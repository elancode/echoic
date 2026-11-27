import Foundation
import AVFoundation
import os.log

private let micLogger = Logger(subsystem: "com.echoic.app", category: "MicCapture")

/// Captures microphone audio via AVAudioEngine on a separate channel.
/// Used for local speaker identification ("You" label) and as primary input for in-person meetings.
final class MicrophoneCaptureService {
    /// Recreated for every capture session. A long-lived engine caches the input
    /// format from when it was first used, which goes stale when the device
    /// changes rate (e.g. a Bluetooth headset switching to 24 kHz call mode).
    private var engine = AVAudioEngine()
    private(set) var isCapturing = false
    private var ringBuffer: RingBuffer

    /// AAC encoder for writing segments to disk (when used as primary input).
    private var encoder: AACEncoder?

    /// The meeting ID currently being recorded (when used as primary input).
    private(set) var currentMeetingId: String?

    /// Callback invoked with mic audio samples.
    var onAudioSamples: (([Float]) -> Void)?

    init(ringBuffer: RingBuffer? = nil) {
        self.ringBuffer = ringBuffer ?? RingBuffer(durationSeconds: 30, sourceSampleRate: 48000, targetSampleRate: 16000)
    }

    /// Requests microphone permission.
    /// Tries multiple APIs since macOS permission behavior varies by version and sandbox state.
    static func requestPermission() async -> Bool {
        // First check AVCaptureDevice (works for mic specifically)
        let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        micLogger.info("AVCaptureDevice mic auth status: \(captureStatus.rawValue)")

        if captureStatus == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if granted { return true }
        } else if captureStatus == .authorized {
            return true
        }

        // Try AVAudioApplication (macOS 14+)
        if #available(macOS 14.0, *) {
            let appStatus = AVAudioApplication.shared.recordPermission
            micLogger.info("AVAudioApplication record permission: \(appStatus.rawValue)")

            if appStatus == .undetermined {
                do {
                    return try await AVAudioApplication.requestRecordPermission()
                } catch {
                    micLogger.error("AVAudioApplication permission request failed: \(error)")
                }
            } else if appStatus == .granted {
                return true
            }
        }

        micLogger.error("Microphone permission denied — user must enable in System Settings")
        return false
    }

    /// Starts capturing microphone audio.
    /// - Parameters:
    ///   - deviceID: Optional audio device ID. Uses default input if nil.
    ///   - meetingId: If provided, enables AAC recording for this meeting (primary input mode).
    func startCapture(deviceID: AudioDeviceID? = nil, meetingId: String? = nil) throws {
        guard !isCapturing else { return }

        engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Set device if specified
        if let deviceID {
            guard let audioUnit = inputNode.audioUnit else {
                throw MicrophoneError.deviceNotAvailable
            }
            var id = deviceID
            let size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                size
            )
            guard status == noErr else {
                throw MicrophoneError.deviceNotAvailable
            }
        }

        // installTap raises an Objective-C exception (which Swift can't catch, and
        // which corrupts the concurrency runtime as it unwinds) when the tap format
        // doesn't match the hardware. Validate first and fail with a Swift error.
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw MicrophoneError.deviceNotAvailable
        }
        guard let format = Self.tapFormat(hardware: hardwareFormat, output: inputNode.outputFormat(forBus: 0)) else {
            micLogger.error(
                "Mic format mismatch: hardware \(hardwareFormat.sampleRate) Hz / \(hardwareFormat.channelCount) ch, engine \(inputNode.outputFormat(forBus: 0).sampleRate) Hz"
            )
            throw MicrophoneError.formatMismatch
        }
        let sampleRate = format.sampleRate

        micLogger.notice("Mic format: \(sampleRate) Hz, \(format.channelCount) ch")

        // Fresh 16 kHz buffer per session. Samples are converted with AVAudioConverter
        // because device rates (e.g. 24 kHz Bluetooth headsets, 44.1 kHz USB mics)
        // aren't integer multiples of 16 kHz.
        self.ringBuffer = RingBuffer(durationSeconds: 30, sourceSampleRate: 16000, targetSampleRate: 16000)
        guard let resampler = MicrophoneResampler(inputFormat: format) else {
            micLogger.error("Cannot convert mic format \(sampleRate) Hz / \(format.channelCount) ch to 16 kHz mono")
            throw MicrophoneError.deviceNotAvailable
        }

        // Set up AAC encoder if this is primary input mode
        if let meetingId {
            self.currentMeetingId = meetingId
            let segmentsDir = try AudioFileManager.segmentsDirectory(meetingId: meetingId)
            let enc = AACEncoder(outputDirectory: segmentsDir, sampleRate: sampleRate)
            try enc.start()
            self.encoder = enc
            micLogger.info("AAC encoder started for mic at \(sampleRate) Hz")
        }

        var tapCallCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            let channelData = buffer.floatChannelData?[0]
            let frameCount = Int(buffer.frameLength)

            guard let data = channelData, frameCount > 0 else { return }

            let samples = Array(UnsafeBufferPointer(start: data, count: frameCount))

            // Log audio levels periodically to diagnose silent-mic issues
            tapCallCount += 1
            if tapCallCount % 100 == 1 {
                let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
                let peak = samples.map { abs($0) }.max() ?? 0
                micLogger.notice("Mic tap #\(tapCallCount): \(frameCount) frames, RMS=\(rms), peak=\(peak)")
            }

            self.ringBuffer.writeDownsampled(resampler.resample(buffer))
            try? self.encoder?.encode(samples: samples)
            self.onAudioSamples?(samples)
        }

        do {
            try engine.start()
        } catch {
            // Clean up tap if engine fails to start (e.g. permission denied)
            inputNode.removeTap(onBus: 0)
            encoder = nil
            currentMeetingId = nil
            micLogger.error("AVAudioEngine failed to start: \(error)")
            throw MicrophoneError.permissionDenied
        }
        isCapturing = true
    }

    /// The format to install the input tap with, or nil if the engine's output
    /// format no longer matches the hardware (installing it would raise an
    /// uncatchable Objective-C exception).
    static func tapFormat(hardware: AVAudioFormat, output: AVAudioFormat) -> AVAudioFormat? {
        guard hardware.sampleRate > 0, hardware.channelCount > 0,
              output.sampleRate == hardware.sampleRate,
              output.channelCount == hardware.channelCount else {
            return nil
        }
        return output
    }

    /// Stops capturing microphone audio and finalizes any recording.
    func stopCapture() async throws {
        guard isCapturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        // Finalize encoder if we were recording
        try await encoder?.finish()

        if let meetingId = currentMeetingId, let encoder {
            micLogger.info("Mic encoder has \(encoder.completedSegments.count) segments")
            if !encoder.completedSegments.isEmpty {
                let outputURL = try AudioFileManager.finalAudioURL(meetingId: meetingId)
                try await AudioFileManager.concatenateSegments(encoder.completedSegments, to: outputURL)
                micLogger.info("Mic audio concatenated to \(outputURL.path)")
                try AudioFileManager.cleanupSegments(meetingId: meetingId)
            }
        }

        encoder = nil
        currentMeetingId = nil
        ringBuffer.reset()
    }

    /// Stops capturing without async (for non-primary use).
    func stopCaptureSync() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }

    /// Returns the microphone ring buffer for speaker embedding extraction.
    var micBuffer: RingBuffer {
        ringBuffer
    }

    /// Lists available audio input devices.
    static func availableInputDevices() -> [(id: AudioDeviceID, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &devices)

        return devices.compactMap { deviceID -> (id: AudioDeviceID, name: String)? in
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var size: UInt32 = 0
            AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &size)

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }
            AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &size, bufferListPointer)

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }

            guard inputChannels > 0 else { return nil }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)

            return (id: deviceID, name: name as String)
        }
    }
}

enum MicrophoneError: Error, LocalizedError {
    case permissionDenied
    case deviceNotAvailable
    case engineStartFailed
    case formatMismatch

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied. Open System Settings → Privacy & Security → Microphone, and enable Echoic."
        case .deviceNotAvailable:
            return "No microphone input device is available."
        case .engineStartFailed:
            return "Failed to start the audio engine for microphone capture."
        case .formatMismatch:
            return "The microphone changed format (for example, a headset switching to call mode). Try starting the recording again."
        }
    }
}
