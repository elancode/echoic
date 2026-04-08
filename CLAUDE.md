# Echoic

Native macOS meeting companion — captures system audio via ScreenCaptureKit, transcribes with WhisperKit (CoreML), diarizes with SpeakerKit, summarizes via Anthropic API. Swift + SwiftUI, single-process, menu bar app.

## Architecture

```
Echoic/
├── App/                    # App entry point, AppDelegate, menu bar (NSStatusItem)
├── Audio/                  # ScreenCaptureKit capture, AVAudioEngine mic, ring buffer, AAC encoding
├── Transcription/          # WhisperKit integration, chunked inference, VAD, dedup
├── Diarization/            # SpeakerKit integration, speaker merge, local speaker ID
├── Summarization/          # Anthropic API client, prompt templates, retry logic
├── Storage/                # GRDB.swift database, migrations, FTS5 search, file management
├── Models/                 # Swift data models (Meeting, TranscriptSegment, Summary, Speaker)
├── Views/                  # SwiftUI views — Library, MeetingDetail, Settings, Onboarding
├── Services/               # Keychain, model download manager, audio playback
└── Utilities/              # ULID generation, date formatting, audio format conversion

EchoicTests/
├── AudioTests/             # Buffer, encoding, format conversion
├── TranscriptionTests/     # WhisperKit pipeline, segment dedup
├── StorageTests/           # GRDB operations, FTS queries, migrations
├── SummarizationTests/     # API client, response parsing, retry
└── IntegrationTests/       # End-to-end meeting lifecycle

Resources/
├── Assets.xcassets         # App icon, menu bar icons (idle/recording/processing)
└── Localizable.strings     # UI strings (English only for Phase 1)
```

**Data directory (runtime):** `~/Library/Application Support/Echoic/`
- `echoic.db` — SQLite database
- `meetings/{ulid}/audio.m4a` — meeting audio (AAC)
- `meetings/{ulid}/segments/` — 30s AAC chunks during recording
- `models/` — WhisperKit CoreML model bundles

## Commands

> **Note:** These commands require the Xcode project (task T1). They will fail until project setup is complete.

```bash
# Build
xcodebuild -scheme Echoic -configuration Debug build

# Test
xcodebuild -scheme Echoic -configuration Debug test
# or: swift test (for SPM-only targets)

# Lint
swiftlint lint --strict
# or: swift-format lint -r Echoic/

# Format
swiftlint --fix
# or: swift-format format -i -r Echoic/

# Clean build
xcodebuild -scheme Echoic clean

# Archive for distribution
xcodebuild -scheme Echoic -configuration Release archive -archivePath build/Echoic.xcarchive

# Run a single test
xcodebuild test -scheme Echoic -only-testing EchoicTests/StorageTests/testInsertMeeting
```

## Code Style

- **Swift 5.9+**, target macOS 13 (Ventura)
- **SwiftUI** for all views; **AppKit** only for NSStatusItem menu bar integration
- **GRDB.swift** for all database access — use `Record` protocol, `@Query` for SwiftUI observation
- **Naming:** Swift API Design Guidelines — clear at point of use, no abbreviations
  - Types: `UpperCamelCase` (e.g., `MeetingLibraryView`, `AudioCaptureService`)
  - Functions/properties: `lowerCamelCase` (e.g., `startCapture()`, `currentMeeting`)
  - Protocols: noun for capabilities (`Identifiable`), `-able`/`-ible` for behaviors
- **Error handling:** typed errors with enums (`enum AudioError: Error`), never force unwrap in production code
- **Concurrency:** Swift structured concurrency (`async/await`, `Task`, `AsyncStream`). No raw GCD unless interfacing with C APIs.
- **Dependencies:** Swift Package Manager only. Current packages:
  - `WhisperKit` (argmaxinc) — transcription
  - `SpeakerKit` (argmaxinc) — diarization
  - `GRDB.swift` (groue) — SQLite + FTS5
  - `Sparkle` — auto-update
- **IDs:** ULIDs for all meeting IDs (time-sortable, string-sortable in SQLite)
- **Audio format:** 48 kHz capture → 16 kHz mono for WhisperKit. Storage as AAC in .m4a container.
- **Secrets:** macOS Keychain via `Security.framework` only. Never store API keys in UserDefaults, plists, or files.

## Critical Rules

1. **Never upload raw audio.** Only transcript text is sent to the Anthropic API. Audio stays local always.
2. **Single-process architecture.** No sidecars, no XPC services, no helper processes. WhisperKit and SpeakerKit run in-process.
3. **Keychain-only secrets.** API keys go in macOS Keychain. Never write secrets to disk, logs, or UserDefaults.
4. **No force unwraps** (`!`) in production code. Use `guard let`, `if let`, or `try?` with fallback.
5. **No blocking the main thread.** All audio capture, transcription, diarization, and API calls run on background tasks via `async/await`.
6. **Screen Recording permission** is for audio capture only. Never capture video/screen content.
7. **GRDB migrations are append-only.** Never modify an existing migration. Add a new one.
8. **AAC audio segments** must be flushed to disk every 30 seconds during recording. A crash must not lose more than 30 seconds of audio.
9. **Anthropic API retries** use exponential backoff with jitter (max 5 min between retries, 3 attempts). Never retry without backoff.
10. **Meeting data belongs to the user.** Files are standard formats (SQLite, AAC, JSON) in a user-accessible directory.

## Task Workflow

1. **Start of session:** Read `tasks.md` and `SPEC.md`. Identify the next unblocked task.
2. **Before coding:** Write a failing test (XCTest) that defines the expected behavior.
3. **Implementation:** Write the minimum code to pass the test. Follow code style above.
4. **After passing:** Run full test suite. Lint. Fix any issues.
5. **Update tasks.md:** Check off completed task. Move to Completed Task Log with date. Note any new tasks discovered.
6. **Commits:** Conventional commits (`feat:`, `fix:`, `test:`, `refactor:`, `docs:`, `chore:`). One logical change per commit.

## Compaction Rules

When context is compacted, always preserve:
- List of all files modified in this session
- Current task ID and status from tasks.md
- Any failing tests and their error messages
- Architecture decisions made during this session
- The current working branch and any uncommitted changes
