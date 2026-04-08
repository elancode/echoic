# Echoic — Product Specification

## Overview

Echoic is a native macOS menu bar app that captures audio from any online meeting, transcribes it locally using on-device ML, identifies speakers, and generates structured summaries via the Anthropic API. It works by capturing system audio at the OS level through ScreenCaptureKit — no meeting bots, no plugins, no cloud audio upload. All audio processing happens on-device; only the transcript text is sent to the Anthropic API for summarization.

**Phase 1 goal:** Ship a working macOS app that a user can install, grant permissions, enter an Anthropic API key, and immediately start capturing meetings with transcription, diarization, and summarization.

## User Personas

### The IC Multitasker
Engineer or PM in 5–8 meetings/day. Can't take notes and participate simultaneously. Needs searchable records and auto-extracted action items. Values speed and low friction.

### The Manager
Runs 1:1s, standups, and cross-functional syncs. Needs to track commitments across meetings and share summaries with their team. Values structured output and speaker attribution.

### The Compliance Officer
Requires transcription for audit trails and regulatory compliance. Cannot allow audio to leave the corporate network. Values local-first architecture and data sovereignty.

### The Founder
Investor calls, customer discovery, hiring panels — every conversation matters, no support staff to take notes. Values zero-config setup and reliable capture across all meeting platforms.

## Core Features

### F1: System Audio Capture
Capture all system audio output (any meeting app) via ScreenCaptureKit with optional microphone input via AVAudioEngine.

**Acceptance criteria:**
- [ ] Captures audio from Zoom, Google Meet, Teams, and browser-based calls without app-specific integration
- [ ] `excludesCurrentProcessAudio = true` prevents feedback loops
- [ ] Audio buffered in 30-second ring buffer, encoded to AAC, flushed to disk every 30 seconds
- [ ] Recording survives app crash with at most 30 seconds of audio loss
- [ ] Optional mic capture on separate channel for local speaker identification
- [ ] CPU usage < 8% during capture on Apple Silicon

### F2: Real-Time Transcription
Transcribe captured audio in real-time using WhisperKit (CoreML, on-device).

**Acceptance criteria:**
- [ ] Transcription runs in-process via WhisperKit — no sidecar
- [ ] 10-second chunks with 2-second overlap, deduplicated by timestamp
- [ ] Segments written to SQLite as they arrive (searchable during recording)
- [ ] WER < 15% on native English meeting audio
- [ ] RTF < 0.1x on Apple Silicon with small.en model
- [ ] Intel Macs fall back to batch transcription after meeting end
- [ ] Model downloaded on first run (~150 MB for small.en, ~600 MB for large-v3)

### F3: Speaker Diarization
Identify and label 2–6 distinct speakers using SpeakerKit (CoreML, post-processing).

**Acceptance criteria:**
- [ ] Runs post-meeting on full audio file — not real-time
- [ ] DER < 20% for 2–6 speaker calls
- [ ] Each transcript segment assigned a speaker ID by timestamp overlap
- [ ] When mic is enabled, local user identified as "You" via speaker embedding comparison
- [ ] Other speakers labeled "Speaker 1", "Speaker 2", etc.
- [ ] Processing time < 30 seconds for a 1-hour meeting on Apple Silicon

### F4: Meeting Summarization
Generate structured summaries by sending the speaker-labeled transcript to the Anthropic API.

**Acceptance criteria:**
- [ ] Uses Claude Sonnet 4.6 (`claude-sonnet-4-6-20260320`)
- [ ] API key stored in macOS Keychain, never on disk
- [ ] Summary returned as structured JSON: title, executive_summary, decisions (with speaker + timestamp), action_items (with owner + due), open_questions, topics (with timestamps)
- [ ] Meetings > 3 hours chunked into 90-minute segments with meta-summary consolidation
- [ ] Summary generated within 60 seconds of meeting end (including diarization)
- [ ] Retry with exponential backoff + jitter on failure (3 attempts, max 5 min between)
- [ ] Meeting fully usable without summary (transcript + diarization are local-only)

### F5: Meeting Library & Search
SQLite-based local storage with full-text search across all meeting transcripts.

**Acceptance criteria:**
- [ ] Meetings listed chronologically with title, date, duration, participant count, 1-line preview
- [ ] Full-text search via FTS5 with Porter stemming across all transcript text
- [ ] Date range filtering
- [ ] Meeting detail view: transcript with speaker labels + color coding, structured summary, audio playback with timestamp-linked scrubbing
- [ ] Speaker labels editable by user (persisted per meeting)
- [ ] Data stored in `~/Library/Application Support/Echoic/`

### F6: Menu Bar App & Onboarding
Minimal, always-available menu bar interface with guided first-run setup.

**Acceptance criteria:**
- [ ] Menu bar icon (NSStatusItem) with idle, recording, and processing states
- [ ] Popover shows: recent meetings, Start/Stop Recording, Open Library, Settings
- [ ] First-run onboarding: Screen Recording permission (with explanation), Microphone permission (optional), API key entry (validated), model download (with progress)
- [ ] User goes from install to first recording in < 3 minutes
- [ ] App idles at < 30 MB RAM
- [ ] App launches in < 1 second
- [ ] No dock icon (menu bar only by default)

## Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| App framework | Native Swift + SwiftUI | All core deps (WhisperKit, SpeakerKit, ScreenCaptureKit) are Swift. No bridging needed. |
| Audio capture | ScreenCaptureKit | Zero-install, Apple-supported API. No virtual audio driver. Requires macOS 13+. |
| Transcription | WhisperKit (CoreML) | In-process, ANE-optimized, Swift-native. Eliminates whisper.cpp sidecar. |
| Diarization | SpeakerKit (CoreML) | In-process, companion to WhisperKit. Eliminates pyannote Python sidecar. |
| Process model | Single process | No sidecars, no IPC. CoreML manages hardware dispatch. |
| Database | GRDB.swift + SQLite + FTS5 | Type-safe Swift wrapper, SwiftUI observation via @Query, built-in FTS5. |
| Audio storage | AAC in .m4a | Native macOS codec, small size (~5 MB/hour). No third-party codec. |
| Meeting IDs | ULID | Time-sortable, globally unique, string-sortable in SQLite. |
| Secrets | macOS Keychain | OS-level encryption. Never stored in files or UserDefaults. |
| Distribution | .dmg (signed + notarized) | Faster iteration than App Store. Sparkle for auto-updates. |
| Platform | macOS only (Phase 1) | No cross-platform benefit needed. Tauri/Rust deferred to Phase 2 if Windows added. |

## Data Model

### SQLite Schema (GRDB.swift)

**meeting**
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | ULID |
| title | TEXT | From summary or "Meeting on {date}" |
| startedAt | INTEGER | Unix timestamp (ms) |
| endedAt | INTEGER | |
| durationMs | INTEGER | |
| audioPath | TEXT | Relative path to .m4a |
| status | TEXT | `recording` → `processing` → `ready` / `error` |

**transcriptSegment**
| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | Auto-increment |
| meetingId | TEXT FK | → meeting.id, CASCADE delete |
| startMs | INTEGER | |
| endMs | INTEGER | |
| speakerId | TEXT | `you`, `speaker_1`, etc. |
| text | TEXT | Transcribed text |
| confidence | REAL | WhisperKit confidence score |

**transcriptFts** — FTS5 virtual table synchronized with transcriptSegment, Porter tokenizer.

**summary**
| Column | Type | Notes |
|---|---|---|
| meetingId | TEXT PK FK | → meeting.id |
| rawJson | TEXT | Full Claude response JSON |
| executiveSummary | TEXT | Extracted for display |
| title | TEXT | Extracted for meeting card |
| createdAt | INTEGER | |

**meetingSpeaker**
| Column | Type | Notes |
|---|---|---|
| meetingId | TEXT | Composite PK |
| speakerId | TEXT | Composite PK |
| label | TEXT | User-assigned name |

### API Contract — Anthropic Summary Response

```json
{
  "title": "Q2 Roadmap Planning",
  "executive_summary": "The team aligned on prioritizing the API migration...",
  "decisions": [
    {"decision": "Prioritize API migration over new features", "speaker": "Speaker 1", "timestamp_ms": 32000}
  ],
  "action_items": [
    {"task": "Draft API migration plan", "owner": "Speaker 1", "due": "next Friday"}
  ],
  "open_questions": [
    "Should we deprecate the v1 endpoints immediately or maintain them for 6 months?"
  ],
  "topics": [
    {"title": "Q2 Roadmap", "start_ms": 0, "end_ms": 900000, "summary": "Discussion of priorities..."}
  ]
}
```

## Non-Functional Requirements

| Requirement | Target |
|---|---|
| Idle RAM | < 30 MB |
| Active RAM (recording + transcription) | < 250 MB |
| CPU during recording (Apple Silicon) | < 8% |
| CPU during recording (Intel) | < 20% |
| Disk per hour of audio | ~8 MB |
| Time to summary (post meeting end) | < 60 seconds |
| App launch time | < 1 second |
| Minimum OS | macOS 13 (Ventura) |
| Minimum hardware | Apple Silicon recommended; Intel supported with degraded perf |
| Minimum RAM | 8 GB (16 GB for large model) |
| Transcription WER | < 15% (English) |
| Diarization DER | < 20% (2–6 speakers) |
| Audio loss on crash | ≤ 30 seconds |
| API cost per 1-hour meeting | ~$0.05 |

## Out of Scope (Phase 2+)

- Windows / Linux support
- Live transcript overlay during meetings
- Speaker enrollment / persistent voiceprints across meetings
- Custom vocabulary / domain-specific tuning
- Multi-LLM provider support (OpenAI, Bedrock)
- Export integrations (Notion, Obsidian, Google Docs)
- Semantic search / knowledge graph
- Multilingual transcription
- Auto-detection of meeting audio (auto-start recording)
- Calendar integration
- Team features / shared meeting library
- In-person meeting capture (room mic mode)

## Open Questions

1. **Intel Mac support level:** Official support with batch-mode transcription, or drop Intel entirely? WhisperKit runs at ~1.0x RTF on Intel (barely real-time). Design doc recommends: support with documented limitations.
2. **ScreenCaptureKit app-level filtering:** Capture all system audio (default) or let user select which app? Risk: captures Spotify alongside Zoom. Design doc recommends: all audio by default, advanced setting for app filtering.
3. **Audio storage format:** AAC (small, native) vs. WAV (lossless, better for re-processing). Design doc recommends: AAC for storage, temporary WAV for diarization pass.
4. **App Store distribution timeline:** Ship .dmg first for speed, or target App Store from day one? ScreenCaptureKit apps have been approved but review is unpredictable. Design doc recommends: .dmg first, App Store in parallel.
5. **SpeakerKit maturity:** SpeakerKit is newer than pyannote. What's the fallback if diarization quality is insufficient? Design doc recommends: benchmark against pyannote on test corpus before committing.
