# Echoic — Phase 1 Design Document

**Foundation: Audio Capture, Transcription, Diarization & Summarization**

Author: Elan
Date: March 2026
Status: Draft v2
Classification: Confidential

---

## 1. Overview

Phase 1 delivers the core loop: capture system audio from any meeting on macOS, transcribe it locally, identify speakers, generate a structured summary, and store everything in a searchable local library. The output is a menu bar app that a user can install, configure with an Anthropic API key, and immediately use with zero per-platform setup.

### 1.1 Scope

| In Scope | Out of Scope (Phase 2+) |
|---|---|
| macOS only (Apple Silicon primary, Intel stretch) | Windows / Linux support |
| System audio capture via ScreenCaptureKit | Live transcript overlay |
| Local transcription via WhisperKit (CoreML, English) | Speaker enrollment / persistent voiceprints |
| Speaker diarization via SpeakerKit (CoreML) | Custom vocabulary / domain tuning |
| Post-meeting summarization via Anthropic API | Multi-LLM provider support |
| SQLite meeting library with full-text search | Export integrations (Notion, Obsidian, etc.) |
| Menu bar app with minimal UI | Semantic search, knowledge graph |
| Microphone capture (optional, separate channel) | Multilingual transcription |
| Manual start/stop recording | Auto-detection of meeting audio |

### 1.2 Success Criteria

- User installs the app, grants permissions, enters an API key, and captures their first meeting in under 3 minutes.
- Transcription word error rate (WER) < 15% on native English meeting audio.
- Diarization error rate (DER) < 20% for 2–6 speaker calls.
- Summary generated within 60 seconds of meeting end.
- App idles at < 50MB RAM; active capture + transcription < 300MB RAM, < 10% CPU on Apple Silicon.

---

## 2. System Architecture

### 2.1 Architecture Decision: Native Swift

Phase 1 is **macOS-only** and the core ML pipeline (WhisperKit, SpeakerKit) is Swift-native. This makes a fully native Swift app the cleanest architecture:

- **WhisperKit** and **SpeakerKit** are Swift packages with direct CoreML integration — no bridging layer needed.
- **ScreenCaptureKit** is an Apple framework with a Swift-first API.
- **macOS Keychain** and **menu bar APIs** (NSStatusItem) are native AppKit.
- A Tauri (Rust) shell would require a Swift↔Rust FFI bridge for every Apple framework call, adding complexity with no cross-platform benefit (since we're macOS-only in Phase 1).

**Decision:** Build as a native **Swift app** using **SwiftUI** for the UI. This keeps the entire stack in one language, eliminates cross-process communication, and provides the best Apple Silicon performance. If Phase 2+ adds Windows support, the Rust/Tauri layer can be introduced then, with the Swift ML pipeline wrapped as a macOS-specific backend.

| Component | Technology |
|---|---|
| **App Shell** | Swift + SwiftUI, menu bar app (NSStatusItem) |
| **Audio Capture** | ScreenCaptureKit (system audio) + AVAudioEngine (microphone) |
| **Transcription** | WhisperKit (Swift, CoreML, on-device) |
| **Diarization** | SpeakerKit (Swift, CoreML, on-device) |
| **Summarization** | Anthropic API via URLSession, API key in macOS Keychain |
| **Storage** | SQLite (via GRDB.swift) + FTS5 for search, audio as compressed CAF/AAC on disk |
| **Build** | Xcode + Swift Package Manager |
| **Distribution** | `.dmg` signed and notarized, or Mac App Store |

### 2.2 Process Model

The app runs as a **single process**. No sidecars, no cross-process IPC.

WhisperKit and SpeakerKit load CoreML models into memory on recording start and unload on stop. CoreML manages GPU/ANE scheduling automatically — the app doesn't need to manage hardware acceleration explicitly.

### 2.3 Data Flow

```
User clicks "Start Recording"
  │
  ▼
ScreenCaptureKit ──► system audio stream (PCM, 48 kHz)
AVAudioEngine    ──► mic audio stream (PCM, 48 kHz)    [optional]
  │
  ├──► Audio Buffer (ring, 30s) ──► AAC Encoder ──► disk (segments/)
  │
  ▼
Downsampled to 16 kHz mono
  │
  ├──► WhisperKit (streaming, 10s chunks)
  │      │
  │      ▼
  │    Transcript segments [{start, end, text}] ──► SQLite (live)
  │
  └──► [buffered for post-processing]
         │
         ▼ (on meeting end)
       SpeakerKit (full audio)
         │
         ▼
       Speaker segments [{start, end, speaker_id}]
         │
         ▼
       Merge: transcript + speaker labels ──► SQLite
         │
         ▼
       Anthropic API (transcript with speaker labels)
         │
         ▼
       Structured summary ──► SQLite ──► UI
```

---

## 3. Component Design

### 3.1 Audio Capture (ScreenCaptureKit + AVAudioEngine)

**Responsibility:** Capture system audio output and optionally microphone input.

#### System Audio — ScreenCaptureKit

ScreenCaptureKit (macOS 13+) provides app-level and screen-level audio capture without a virtual audio driver. No BlackHole, no custom HAL plugin, no kernel extension.

```swift
// Capture all system audio (excluding Echoic itself)
let config = SCStreamConfiguration()
config.capturesAudio = true
config.excludesCurrentProcessAudio = true
config.sampleRate = 48000
config.channelCount = 1

let filter = SCContentFilter(/* display or app-based filter */)
let stream = SCStream(filter: filter, configuration: config, delegate: self)
stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
try await stream.startCapture()
```

Key behaviors:
- `excludesCurrentProcessAudio = true` prevents feedback loops from the app's own audio playback.
- Audio arrives as `CMSampleBuffer` in the stream output delegate — standard CoreAudio format, easy to feed into WhisperKit.
- **Requires Screen Recording permission** (macOS system dialog). The app must explain this clearly: "Echoic needs Screen Recording permission to capture meeting audio. It does not record your screen."

#### Microphone — AVAudioEngine

```swift
let engine = AVAudioEngine()
let inputNode = engine.inputNode
let format = inputNode.outputFormat(forBus: 0)
inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
    // Feed to ring buffer for diarization (local speaker ID)
}
engine.prepare()
try engine.start()
```

- Mic audio is kept on a separate channel for local speaker identification during diarization.
- Requires Microphone permission (standard macOS dialog).

#### Audio Format

| Parameter | Value | Rationale |
|---|---|---|
| Capture rate | 48 kHz | ScreenCaptureKit native output |
| Processing rate | 16 kHz | WhisperKit's expected input; downsampled in-process |
| Channels | Mono (system) + Mono (mic) | Separate channels improve diarization |
| Bit depth | 32-bit float (CoreAudio native) | Downconverted to 16-bit for WhisperKit |
| Buffer | 30-second ring buffer | Covers WhisperKit chunk window with margin |

#### Storage Format

- During recording, audio is encoded to **AAC** (compressed, ~64 kbps) in 30-second segments written to `~/Library/Application Support/Echoic/meetings/{id}/segments/`.
- On meeting end, segments are concatenated into a single `.m4a` file (~5 MB per hour).
- AAC chosen over Opus because it's natively supported by CoreAudio/AVFoundation — no third-party codec needed.

### 3.2 Transcription (WhisperKit)

**Responsibility:** Convert audio to timestamped text segments in real-time.

#### Why WhisperKit

[WhisperKit](https://github.com/argmaxinc/WhisperKit) is a Swift package that runs Whisper models on Apple Silicon via CoreML + ANE (Apple Neural Engine). Advantages over whisper.cpp:
- **Native Swift API** — no C FFI, no sidecar process.
- **CoreML optimization** — models are compiled to `.mlmodelc` format, automatically dispatched to ANE/GPU/CPU by CoreML.
- **Streaming support** — built-in chunked inference with VAD (voice activity detection).
- **Small footprint** — the framework is a Swift Package; models are separate downloads.

#### Model Selection

| Model | Size | Use Case |
|---|---|---|
| `whisper-small.en` | ~150 MB (CoreML) | Default. Fast, good accuracy on Apple Silicon. |
| `whisper-large-v3` | ~600 MB (CoreML) | Optional download. Best accuracy. Requires M1+ with 8GB+ RAM. |

CoreML-optimized models are smaller than their GGML equivalents because they're quantized and compiled for Apple hardware.

#### Inference Pipeline

```swift
let whisperKit = try await WhisperKit(model: "small.en")

// Streaming transcription during meeting
whisperKit.transcribe(audioBuffer: chunk) { result in
    let segment = TranscriptSegment(
        startMs: result.start,
        endMs: result.end,
        text: result.text,
        confidence: result.confidence
    )
    database.insert(segment)
}
```

1. Audio from ScreenCaptureKit is downsampled to 16 kHz mono and fed to WhisperKit in **10-second chunks with 2-second overlap**.
2. WhisperKit runs VAD to skip silence, then transcribes active speech.
3. Output segments are deduplicated by timestamp alignment and written to SQLite as they arrive.
4. On Apple Silicon (M1+), inference runs primarily on the ANE, leaving GPU free for the user's other work.

#### Performance

| Hardware | Model | Expected RTF |
|---|---|---|
| M1/M2/M3 | small.en | ~0.05x (20x real-time) |
| M1/M2/M3 | large-v3 | ~0.15x (7x real-time) |
| Intel Mac | small.en | ~1.0x (marginal real-time) |

Intel Macs fall back to CPU-only inference. If real-time isn't achievable, the app buffers audio and transcribes in batch after the meeting.

### 3.3 Speaker Diarization (SpeakerKit)

**Responsibility:** Segment audio by speaker and assign stable speaker IDs.

#### Approach

Diarization runs as a **post-processing step** after the meeting ends. Real-time diarization is deferred to Phase 2.

[SpeakerKit](https://github.com/argmaxinc/SpeakerKit) is the companion to WhisperKit — a Swift package for speaker diarization using CoreML. It uses speaker embedding models to cluster audio segments by voice.

```swift
let speakerKit = try await SpeakerKit()
let speakerSegments = try await speakerKit.diarize(
    audioURL: meetingAudioURL,
    minSpeakers: 2,
    maxSpeakers: 6
)
// speakerSegments: [{start_ms, end_ms, speaker_id}, ...]
```

1. On meeting end, the full audio file is passed to SpeakerKit.
2. SpeakerKit produces speaker segments with cluster IDs (`speaker_0`, `speaker_1`, ...).
3. Transcript segments are merged with speaker segments by timestamp overlap — each transcript segment is assigned the speaker with the highest temporal overlap.

#### Local Speaker Identification

When microphone capture is enabled:
- The mic channel audio is processed by SpeakerKit to extract a speaker embedding for the local user.
- This embedding is compared against the diarization clusters to identify which cluster is "You."
- The local user is labeled "You"; others are labeled "Speaker 1", "Speaker 2", etc.

#### Performance

On Apple Silicon, SpeakerKit processes a 1-hour meeting in ~15–30 seconds using the ANE. Combined with the Anthropic API call (~10 seconds), the full post-meeting pipeline completes in under 60 seconds.

### 3.4 Meeting Summarization (Anthropic API)

**Responsibility:** Generate a structured summary from the speaker-labeled transcript.

#### API Integration

- **Model:** Claude Sonnet 4.6 (`claude-sonnet-4-6-20260320`)
- **API Key:** Stored in macOS Keychain via `Security.framework`. Retrieved at runtime.
- **HTTP Client:** `URLSession` (native Foundation). Retry logic: exponential backoff with jitter, 3 retries.

```swift
let keychain = KeychainService()
let apiKey = try keychain.get("anthropic_api_key")

var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
// ... POST with transcript body
```

#### Prompt Design

System prompt instructs Claude to produce a structured summary as JSON:

```
System: You are a meeting summarization assistant. Given a transcript with speaker labels
and timestamps, produce a structured summary. Be precise about attributing statements
to speakers. Extract concrete action items with owners when identifiable.

Output the summary as JSON matching this schema:
{
  "title": "string (short meeting title, 5-10 words)",
  "executive_summary": "string (2-3 sentences)",
  "decisions": [{"decision": "string", "speaker": "string", "timestamp_ms": number}],
  "action_items": [{"task": "string", "owner": "string | null", "due": "string | null"}],
  "open_questions": ["string"],
  "topics": [{"title": "string", "start_ms": number, "end_ms": number, "summary": "string"}]
}
```

User message contains the transcript:

```
[00:00:15] You: Let's start with the Q2 roadmap...
[00:00:32] Speaker 1: I think we should prioritize the API migration.
...
```

#### Context Window & Cost

- Claude Sonnet 4.6 supports 200K tokens. A 1-hour meeting produces ~10K–15K tokens — well within limits.
- For meetings > 3 hours, the transcript is chunked into 90-minute segments, each summarized independently, then a meta-summary pass consolidates them.
- **Cost:** ~$0.05 per 1-hour meeting at current Anthropic pricing. A heavy user (5 meetings/day) spends ~$5/month.

#### Error Handling

- **API unreachable:** Summary queued, retried when connectivity returns. Meeting is fully usable without summary.
- **Invalid API key:** User prompted to re-enter. Meeting saved without summary.
- **Rate limiting (429):** Exponential backoff with jitter, up to 5 minutes between retries.

### 3.5 Storage (SQLite via GRDB.swift)

**Responsibility:** Persist all meeting data locally with full-text search.

[GRDB.swift](https://github.com/groue/GRDB.swift) provides a type-safe Swift wrapper over SQLite with built-in FTS5 support, migrations, and observation (SwiftUI integration via `@Query`).

#### Schema

```swift
// GRDB migration
migrator.registerMigration("v1") { db in
    try db.create(table: "meeting") { t in
        t.primaryKey("id", .text)              // ULID
        t.column("title", .text)
        t.column("startedAt", .integer).notNull()
        t.column("endedAt", .integer)
        t.column("durationMs", .integer)
        t.column("audioPath", .text)
        t.column("status", .text).notNull().defaults(to: "recording")
            .check { ["recording", "processing", "ready", "error"].contains($0) }
    }

    try db.create(table: "transcriptSegment") { t in
        t.autoIncrementedPrimaryKey("id")
        t.belongsTo("meeting", onDelete: .cascade).notNull()
        t.column("startMs", .integer).notNull()
        t.column("endMs", .integer).notNull()
        t.column("speakerId", .text)
        t.column("text", .text).notNull()
        t.column("confidence", .double)
    }

    try db.create(virtualTable: "transcriptFts", using: FTS5()) { t in
        t.synchronize(withTable: "transcriptSegment")
        t.tokenizer = .porter(wrapping: .unicode61())
        t.column("text")
    }

    try db.create(table: "summary") { t in
        t.primaryKey("meetingId", .text).references("meeting", onDelete: .cascade)
        t.column("rawJson", .text).notNull()
        t.column("executiveSummary", .text)
        t.column("title", .text)
        t.column("createdAt", .integer).notNull()
    }

    try db.create(table: "meetingSpeaker") { t in
        t.column("meetingId", .text).notNull().references("meeting", onDelete: .cascade)
        t.column("speakerId", .text).notNull()
        t.column("label", .text)
        t.primaryKey(["meetingId", "speakerId"])
    }
}
```

GRDB's `synchronize(withTable:)` for FTS5 automatically maintains the full-text index via triggers — no manual trigger management.

#### File Layout

```
~/Library/Application Support/Echoic/
├── echoic.db                           # SQLite database
├── meetings/
│   ├── 01JQ7X.../
│   │   ├── audio.m4a                   # Full meeting audio (AAC)
│   │   ├── segments/                   # 30s AAC chunks (during recording)
│   │   └── transcript.json             # Backup export
│   └── 01JQ8Y.../
│       └── ...
└── models/
    ├── whisperkit-small-en/            # CoreML model bundle
    └── whisperkit-large-v3/            # Optional larger model
```

### 3.6 User Interface (SwiftUI)

**Responsibility:** Minimal, non-intrusive interface for controlling capture and browsing meetings.

#### Menu Bar (NSStatusItem)

The primary interaction surface. Always visible, never in the way.

- **Idle state:** Echoic icon in menu bar. Click opens a popover: recent meetings list, "Start Recording" button, Settings gear.
- **Recording state:** Icon pulses subtly (or changes color). Popover shows elapsed time, audio level indicator, and "Stop Recording" button.
- **Processing state:** Icon shows progress. Popover shows "Transcribing..." / "Identifying speakers..." / "Generating summary..." with a progress bar.

#### Main Window

Opened from menu bar or via "Open Library" in the popover.

**Meeting Library (default view)**
- Chronological list, most recent first.
- Each card: title (from summary or "Meeting on {date}"), date, duration, participant count, 1-line summary preview.
- Search bar: queries FTS5 index, highlights matches.
- Date range filter.

**Meeting Detail View**
- Left panel: full transcript with speaker labels and color coding. Timestamps are clickable.
- Right panel: structured summary — executive summary, decisions, action items, open questions, topic outline.
- Speakers section: list of detected speakers with editable labels.
- Audio playback bar at bottom: play/pause, scrub. Clicking a transcript segment jumps playback.

#### Settings

- API key entry (stored in Keychain).
- Model selection (small vs. large, with download button and size indicator).
- Microphone on/off toggle and device selection.
- Storage location (default: `~/Library/Application Support/Echoic/`).

#### SwiftUI + AppKit Integration

- Main window and meeting views: **SwiftUI** for modern declarative UI.
- Menu bar: **NSStatusItem** (AppKit) — SwiftUI doesn't natively support menu bar apps, so the status item is AppKit with a SwiftUI popover attached via `NSHostingView`.
- The app is a menu bar–only app by default (no dock icon). The main window opens as a standard window when requested.

---

## 4. Key Technical Decisions

### 4.1 Why Native Swift Over Tauri?

| | Native Swift | Tauri (Rust + React) |
|---|---|---|
| WhisperKit/SpeakerKit integration | Direct — same language, same runtime | Requires Swift↔Rust FFI bridge |
| ScreenCaptureKit | Native API | Rust bindings via `objc` crate, fragile |
| Menu bar app | NSStatusItem (first-class) | Tauri system tray (abstraction layer) |
| Binary size | ~10 MB | ~15 MB |
| RAM (idle) | ~20 MB | ~30 MB (WebView overhead) |
| Cross-platform | macOS only | macOS + Windows + Linux |

Since Phase 1 is macOS-only, the cross-platform benefit of Tauri is irrelevant. Every core dependency (WhisperKit, SpeakerKit, ScreenCaptureKit, Keychain) is a Swift/Apple framework. Going native eliminates an entire bridging layer.

**Phase 2+ migration path:** If Windows support is added later, the architecture can evolve to: Swift backend (macOS) ↔ shared protocol ↔ Rust backend (Windows), with a shared React or SwiftUI frontend per platform. The SQLite schema and Anthropic API client are portable.

### 4.2 Why ScreenCaptureKit Over Virtual Audio Drivers?

- **Zero-install:** No BlackHole, no custom HAL plugin, no kernel extension. ScreenCaptureKit is a system framework on macOS 13+.
- **App-level filtering:** Can capture audio from specific apps (e.g., only Zoom) instead of all system audio.
- **Apple-supported:** Unlike virtual audio drivers (which Apple has historically broken with OS updates), ScreenCaptureKit is a stable, documented API.
- **Trade-off:** Requires Screen Recording permission, which is a UX friction point. But the virtual audio driver approach also required permissions (and often more confusing ones).

### 4.3 Why WhisperKit + SpeakerKit Over whisper.cpp + pyannote?

| | WhisperKit + SpeakerKit | whisper.cpp + pyannote |
|---|---|---|
| Process model | In-process (single process) | Two sidecar processes |
| Runtime dependencies | None (Swift frameworks) | C++ runtime, Python 3.10+, PyTorch |
| Download size | ~150 MB (CoreML models) | ~700 MB+ (binaries + models + Python env) |
| Apple Silicon optimization | ANE + GPU via CoreML (automatic) | Metal via whisper.cpp (manual), no ANE |
| Build complexity | `swift package resolve` | Cross-compile C++, bundle Python with PyInstaller |

This is the single biggest architectural simplification in Phase 1. Eliminating two sidecar processes removes IPC, crash recovery, process lifecycle management, and ~500 MB of bundled dependencies.

### 4.4 Why Post-Processing Diarization (Not Real-Time)?

Real-time diarization on single-channel audio introduces 5–10 second delay and reduces accuracy — the model lacks future context for speaker turns. Post-processing the full audio produces better results with simpler code. Phase 2 can revisit real-time diarization.

### 4.5 Why ULID for Meeting IDs?

ULIDs are time-sortable, globally unique, and URL-safe. They provide chronological ordering without a sequential counter (important for a local-first app) and sort correctly as strings in SQLite.

---

## 5. Installation & First Run

### 5.1 Distribution

- **`.dmg`** with drag-to-Applications. Signed with Developer ID and notarized.
- Future: Mac App Store (pending review of ScreenCaptureKit usage in App Store guidelines).
- Auto-update via Sparkle framework.

### 5.2 System Requirements

- macOS 13 (Ventura) or later — required for ScreenCaptureKit.
- Apple Silicon (M1+) recommended. Intel supported with degraded transcription performance.
- 8 GB RAM minimum (16 GB recommended for large model).

### 5.3 First Run Flow

```
1. App launches → menu bar icon appears
2. "Welcome to Echoic" popover opens:
   a. Grant Screen Recording permission → system dialog
      (explain: "Echoic captures meeting audio, not your screen")
   b. Grant Microphone permission → system dialog (optional, can skip)
   c. Enter Anthropic API key → validated with a test request → stored in Keychain
   d. Model download begins (small.en, ~150 MB) with progress bar
3. "You're ready. Start a meeting and click Record."
4. Popover closes. App sits in menu bar.
```

### 5.4 Permissions Required

| Permission | Required? | Why |
|---|---|---|
| Screen Recording | Yes | ScreenCaptureKit requires this to capture system audio |
| Microphone | Optional | Improves diarization by identifying local speaker |

---

## 6. Performance Budget

| Metric | Target | Measurement |
|---|---|---|
| Idle RAM | < 30 MB | Menu bar app, no recording, no models loaded |
| Active RAM (recording + transcription) | < 250 MB | Includes WhisperKit with small model |
| CPU during recording | < 8% | On M1; WhisperKit offloads to ANE |
| Disk per hour of audio | ~8 MB | AAC audio (~5 MB) + transcript + metadata (~3 MB) |
| Time to summary after meeting end | < 60 seconds | Diarization (~20s) + API call (~10s) + overhead |
| App launch to ready | < 1 second | Menu bar icon visible, models lazy-loaded on first record |

---

## 7. Testing Strategy

### 7.1 Unit Tests (XCTest)

- Audio buffer management and format conversion.
- SQLite operations via GRDB (insert, query, FTS search).
- Transcript segment merging with speaker labels.
- Anthropic API client: request formatting, response parsing, retry logic.
- Keychain read/write.

### 7.2 Integration Tests

- **Audio pipeline:** Feed a known WAV file through the capture → buffer → WhisperKit pipeline. Assert transcript output matches expected text within WER tolerance.
- **Diarization:** Run SpeakerKit on pre-recorded multi-speaker audio with known ground truth. Assert DER < 20%.
- **Summarization:** Send a known transcript to the Anthropic API and validate the response parses into the expected schema.
- **End-to-end:** Simulate a full meeting lifecycle: start → feed audio → stop → verify transcript, diarization, and summary are stored correctly.

### 7.3 Test Audio Corpus

Assemble 10–15 meeting recordings (with consent) covering:
- 2-person 1:1 conversations
- 4–6 person group meetings
- Crosstalk and interruptions
- Low-quality audio (laptop speakers, background noise)
- Accented English speakers

---

## 8. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| ScreenCaptureKit permission UX confuses users ("Screen Recording" for audio) | Drop-off during onboarding | High | Clear in-app explanation with screenshot. Consider a short onboarding animation. |
| WhisperKit accuracy is insufficient for meeting audio | Poor transcription quality | Medium | Benchmark against whisper.cpp on test corpus before committing. Fall back to whisper.cpp sidecar if needed. |
| SpeakerKit diarization quality for single-channel system audio | Poor speaker attribution | Medium | Benchmark against pyannote on test corpus. Mic channel as secondary signal improves accuracy significantly. |
| macOS 13+ requirement excludes some users | Smaller addressable market | Low | macOS 13 adoption is >85% of active Macs. Acceptable trade-off for ScreenCaptureKit. |
| Intel Mac performance too slow for real-time transcription | Degraded UX on older hardware | Medium | Detect hardware on first run. Offer batch-mode transcription. Show warning for Intel users. |
| Two-party consent legal exposure | Liability risk | Medium | Configurable "this meeting is being recorded" reminder. Legal disclaimer in onboarding. |
| Anthropic API cost surprises for heavy users | User churn | Low | Show estimated cost before summarization. Running cost tracker in settings. |

---

## 9. Open Questions

1. **Intel Mac support:** Should Phase 1 officially support Intel Macs, or declare Apple Silicon as the minimum? WhisperKit works on Intel but at ~1.0x RTF (barely real-time). Recommend: support Intel with batch-mode transcription as a documented limitation.

2. **ScreenCaptureKit app-level filtering:** Should we capture all system audio or let the user select which app to capture? App-level filtering is more precise (captures only Zoom, not Spotify) but requires the user to pick the right app. Recommend: capture all system audio by default, with an advanced setting for app-level filtering.

3. **Meeting title generation:** Extract from the summary response (add `title` field to the prompt schema) vs. a separate lightweight call. Recommend: include in the summary prompt — it's one extra line in the schema and avoids a second API call.

4. **Audio storage format:** AAC (native to macOS, smallest size) vs. WAV (lossless, better for re-processing). Recommend: AAC for storage, keep a temporary WAV for the diarization pass, then delete.

5. **App Store distribution:** ScreenCaptureKit apps have historically been approved on the App Store, but the review process is unpredictable. Should we target App Store from day one or ship direct (`.dmg`) first? Recommend: `.dmg` first for faster iteration, submit to App Store in parallel.

---

## 10. Milestones

| Milestone | Target | Deliverable |
|---|---|---|
| **M0: Project setup** | Week 1 | Xcode project, Swift packages (WhisperKit, SpeakerKit, GRDB), CI pipeline, test harness. |
| **M1: Audio capture** | Week 3 | ScreenCaptureKit capturing system audio + mic. Ring buffer, AAC encoding to disk. Playback verification. |
| **M2: Transcription** | Week 5 | WhisperKit producing real-time transcript segments from captured audio. Segments stored in SQLite. Accuracy benchmarked against test corpus. |
| **M3: Diarization** | Week 7 | SpeakerKit producing speaker segments post-meeting. Merged with transcript. Local speaker ID via mic channel. DER benchmarked. |
| **M4: Summarization** | Week 8 | Anthropic API integration. API key in Keychain. Structured summary generated and stored on meeting end. |
| **M5: UI** | Week 10 | Menu bar app, recording controls, meeting library, meeting detail view, search, settings. Full end-to-end flow. |
| **M6: Polish & Beta** | Week 12 | `.dmg` installer (signed, notarized), first-run onboarding, error handling, performance tuning, 10-user private beta. |

---

*End of Phase 1 Design Document*
