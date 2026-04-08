# Echoic

Native macOS meeting companion that captures audio from any meeting app, transcribes it locally, identifies speakers, and generates structured summaries. No bots, no plugins, no cloud audio upload.

## How it works

Echoic sits in your menu bar. Click record before a call and it captures system audio via ScreenCaptureKit — works with Zoom, Google Meet, Teams, or any browser-based call. Transcription and speaker diarization run on-device using CoreML (WhisperKit + SpeakerKit). Only transcript text is sent to the Anthropic API for summarization. Audio never leaves your machine.

## Features

- **Universal capture** — records system audio at the OS level, no per-app integration needed
- **Real-time transcription** — WhisperKit (CoreML) transcribes as you talk, searchable during recording
- **Speaker diarization** — identifies 2-6 speakers, optional mic input for "You" labeling
- **Structured summaries** — decisions, action items, and open questions via Anthropic API
- **Full-text search** — FTS5-powered search across all meeting transcripts
- **Local-first** — audio stored as standard AAC, transcripts in SQLite, all in `~/Library/Application Support/Echoic/`
- **Crash-safe** — audio flushed to disk every 30 seconds

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon recommended (Intel supported with batch transcription fallback)
- Screen Recording permission (for system audio capture)
- Anthropic API key (for summarization)

## Building

```bash
# Build
xcodebuild -scheme Echoic -configuration Debug build

# Run tests
xcodebuild -scheme Echoic -configuration Debug test
```

## Setup

1. Build and run the app
2. Grant Screen Recording permission when prompted
3. Open Settings from the menu bar icon and enter your Anthropic API key
4. Click **Start Recording** before your next call

## Architecture

```
Echoic/
├── App/            # Entry point, AppDelegate, menu bar
├── Audio/          # ScreenCaptureKit capture, AVAudioEngine mic, ring buffer, AAC encoding
├── Transcription/  # WhisperKit integration, chunked inference, VAD, dedup
├── Diarization/    # SpeakerKit integration, speaker merge, local speaker ID
├── Summarization/  # Anthropic API client, prompt templates, retry logic
├── Storage/        # GRDB.swift database, migrations, FTS5 search
├── Models/         # Data models (Meeting, TranscriptSegment, Summary, Speaker)
├── Views/          # SwiftUI — Library, MeetingDetail, Settings, Onboarding
├── Services/       # Keychain, model download, audio playback
└── Utilities/      # ULID generation, date formatting
```

Single-process architecture — no sidecars, no XPC services. WhisperKit and SpeakerKit run in-process via CoreML.

## Privacy

- Audio is captured and processed entirely on-device
- Only transcript text is sent to the Anthropic API for summarization
- API keys stored in macOS Keychain
- All meeting data lives in user-accessible standard formats (SQLite, AAC, JSON)

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE).
