import AppKit
import CoreAudio
import Foundation

/// Snapshot of microphone usage by *other* apps.
struct MicrophoneUsage: Equatable {
    var isInUse: Bool
    /// Display name of the app using the mic, when it can be identified.
    var appName: String?

    static let idle = MicrophoneUsage(isInUse: false, appName: nil)
}

/// Reads microphone activity from the CoreAudio HAL. Requires no permissions —
/// it only checks whether input is running, never reads audio.
enum MicrophoneActivityMonitor {
    /// Apple bundle IDs that legitimately indicate a call. Every other `com.apple.*`
    /// process (e.g. `replayd` for ScreenCaptureKit, Siri, dictation) is ignored.
    private static let allowedApplePrefixes = [
        "com.apple.FaceTime",
        "com.apple.Safari",
        "com.apple.WebKit",
    ]

    /// Returns current mic usage by processes other than Echoic.
    /// Synchronous HAL query — call off the main thread.
    static func currentUsage() -> MicrophoneUsage {
        if #available(macOS 14.0, *) {
            return processLevelUsage()
        }
        // macOS 13 has no per-process API: fall back to "is the default input
        // device running at all". Callers must ignore this while Echoic records.
        return MicrophoneUsage(isInUse: defaultInputDeviceIsRunning(), appName: nil)
    }

    // MARK: - macOS 14+: per-process

    @available(macOS 14.0, *)
    private static func processLevelUsage() -> MicrophoneUsage {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleId = Bundle.main.bundleIdentifier ?? ""

        for process in objectList(kAudioHardwarePropertyProcessObjectList) {
            guard uint32Property(process, kAudioProcessPropertyIsRunningInput) == 1 else { continue }

            let pid = pid_t(bitPattern: uint32Property(process, kAudioProcessPropertyPID) ?? 0)
            let bundleId = stringProperty(process, kAudioProcessPropertyBundleID) ?? ""
            guard pid != ownPID, bundleId != ownBundleId, !isIgnoredSystemProcess(bundleId) else { continue }

            return MicrophoneUsage(isInUse: true, appName: displayName(pid: pid))
        }
        return .idle
    }

    static func isIgnoredSystemProcess(_ bundleId: String) -> Bool {
        guard bundleId.hasPrefix("com.apple.") else { return false }
        return !allowedApplePrefixes.contains { bundleId.hasPrefix($0) }
    }

    /// Only name regular (Dock) apps; helper processes like "Google Chrome Helper" get no name.
    private static func displayName(pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else { return nil }
        return app.localizedName
    }

    // MARK: - macOS 13: device-level

    private static func defaultInputDeviceIsRunning() -> Bool {
        guard let device = uint32Property(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultInputDevice
        ), device != kAudioObjectUnknown else { return false }
        return uint32Property(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
    }

    // MARK: - HAL helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func uint32Property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}
