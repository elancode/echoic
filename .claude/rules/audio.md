---
paths:
  - "Echoic/Audio/**"
  - "Echoic/Capture/**"
  - "Echoic/Transcription/**"
  - "Echoic/Diarization/**"
  - "*Audio*.swift"
  - "*Capture*.swift"
---

# Audio Pipeline Rules

## Capture
- System audio: **ScreenCaptureKit** only. No virtual audio drivers, no BlackHole.
- Always set `excludesCurrentProcessAudio = true` to prevent feedback loops.
- Microphone: **AVAudioEngine**. Separate channel from system audio.
- Capture at 48 kHz (ScreenCaptureKit native), downsample to 16 kHz for WhisperKit.

## Buffers & Threading
- Ring buffer must be **thread-safe** (lock-free or mutex-protected).
- Audio callback runs on a dedicated serial queue — never the main thread.
- Ring buffer size: 30 seconds of PCM at 16 kHz mono.

## Storage
- Encode to **AAC** (64 kbps) via AudioToolbox. Write 30-second segments.
- Flush to disk every 30 seconds. A crash must not lose more than 30 seconds.
- On meeting end, concatenate segments into a single `.m4a` file.
- Store in `~/Library/Application Support/Echoic/meetings/{ulid}/`.

## ML Inference
- WhisperKit: 10-second chunks, 2-second overlap. Deduplicate by timestamp.
- SpeakerKit: post-processing only (after meeting end). Not real-time.
- Both run **in-process** via CoreML. No sidecar processes.
- Models lazy-loaded on first recording, unloaded when idle.

## Error Handling
- ScreenCaptureKit permission denied: surface a clear user message, never silently fail.
- Audio format mismatches: log and convert. Never pass mismatched formats to WhisperKit.
- WhisperKit crash: catch, log, and offer batch transcription as fallback.
