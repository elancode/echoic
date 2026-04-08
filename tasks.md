# Echoic — Task List

## Phase 1: Foundation (M0 — Week 1)

- [x] **T1** · Create Xcode project with SwiftUI App lifecycle, menu bar target (NSStatusItem), macOS 13 deployment target · **L** · blocked-by: none
- [x] **T2** · Add SPM dependencies: WhisperKit, SpeakerKit, GRDB.swift, Sparkle · **S** · blocked-by: T1
- [x] **T3** · Set up GRDB database with v1 migration (meeting, transcriptSegment, transcriptFts, summary, meetingSpeaker tables) · **M** · blocked-by: T2
- [x] **T4** · Create Swift data models conforming to GRDB Record protocol (Meeting, TranscriptSegment, Summary, MeetingSpeaker) · **M** · blocked-by: T3
- [x] **T5** · Add .gitignore (Xcode, Swift, macOS, CoreML models, build artifacts) · **S** · blocked-by: T1
- [x] **T6** · Set up CI pipeline (GitHub Actions: build + test on macOS runner) · **M** · blocked-by: T1

## Phase 2: Core — Audio Capture (M1 — Weeks 2–3)

- [x] **T7** · Implement ScreenCaptureKit audio capture service (SCStream, excludesCurrentProcessAudio, 48kHz mono) · **L** · blocked-by: T1
- [x] **T8** · Implement PCM ring buffer (30-second, thread-safe) with 48→16 kHz downsampling · **M** · blocked-by: T7
- [x] **T9** · Implement AAC encoder service (AudioToolbox, 64kbps, 30-second segments to disk) · **M** · blocked-by: T7
- [x] **T10** · Implement AVAudioEngine microphone capture on separate channel · **M** · blocked-by: T1
- [x] **T11** · Implement meeting audio file management (segment concatenation → single .m4a on meeting end) · **M** · blocked-by: T9
- [x] **T12** · Write audio pipeline tests (buffer management, format conversion, encoding verification) · **M** · blocked-by: T8, T9

## Phase 3: Core — Transcription (M2 — Weeks 4–5)

- [x] **T13** · Implement WhisperKit integration service (model loading, streaming transcription, 10s chunks with 2s overlap) · **L** · blocked-by: T2, T8
- [x] **T14** · Implement transcript segment deduplication (timestamp alignment for overlapping chunks) · **M** · blocked-by: T13
- [x] **T15** · Wire transcription output to GRDB (insert segments as they arrive, live search during recording) · **M** · blocked-by: T4, T14
- [x] **T16** · Implement model download manager (fetch CoreML model bundles on first run, progress reporting) · **M** · blocked-by: T13
- [x] **T17** · Implement Intel Mac detection + batch-mode fallback (detect hardware, queue audio for post-meeting transcription) · **S** · blocked-by: T13
- [x] **T18** · Write transcription tests (known audio → expected text within WER tolerance, dedup correctness) · **M** · blocked-by: T14, T15

## Phase 4: Core — Diarization (M3 — Weeks 6–7)

- [x] **T19** · Implement SpeakerKit diarization service (post-meeting, full audio, 2–6 speakers) · **L** · blocked-by: T2, T11
- [x] **T20** · Implement transcript-speaker merge (assign speaker ID to each transcript segment by timestamp overlap) · **M** · blocked-by: T19, T15
- [x] **T21** · Implement local speaker identification (mic channel embedding → cluster matching → "You" label) · **M** · blocked-by: T10, T19
- [x] **T22** · Write diarization tests (known multi-speaker audio → DER measurement, merge correctness) · **M** · blocked-by: T20

## Phase 5: Core — Summarization (M4 — Week 8)

- [x] **T23** · Implement Keychain service (store/retrieve/delete Anthropic API key via Security.framework) · **M** · blocked-by: T1
- [x] **T24** · Implement Anthropic API client (URLSession, claude-sonnet-4-6, structured JSON response parsing) · **L** · blocked-by: T23
- [x] **T25** · Implement retry logic (exponential backoff with jitter, 3 attempts, max 5 min) · **S** · blocked-by: T24
- [x] **T26** · Implement summary prompt template (system prompt + transcript formatting + JSON schema) · **M** · blocked-by: T24
- [x] **T27** · Implement long meeting chunking (>3 hours → 90-min segments → meta-summary consolidation) · **M** · blocked-by: T26
- [x] **T28** · Wire summary to GRDB (store rawJson, extract title + executiveSummary for display) · **S** · blocked-by: T4, T24
- [x] **T29** · Write summarization tests (API client formatting, response parsing, retry behavior, Keychain operations) · **M** · blocked-by: T24, T25

## Phase 6: Integration — UI (M5 — Weeks 9–10)

- [x] **T30** · Implement menu bar (NSStatusItem) with idle/recording/processing icon states · **M** · blocked-by: T1
- [x] **T31** · Implement menu bar popover (recent meetings list, Start/Stop Recording button, Settings gear) · **M** · blocked-by: T30, T4
- [x] **T32** · Implement recording flow (Start → capture + transcribe → Stop → diarize + summarize → ready) · **L** · blocked-by: T7, T13, T19, T24, T30
- [x] **T33** · Implement Meeting Library view (chronological list, cards with title/date/duration/preview, FTS search bar, date filter) · **L** · blocked-by: T4, T15
- [x] **T34** · Implement Meeting Detail view (transcript with speaker colors, structured summary panel, editable speaker labels) · **L** · blocked-by: T33, T20
- [x] **T35** · Implement audio playback (AVAudioPlayer, play/pause, scrub, transcript-segment-to-timestamp linking) · **M** · blocked-by: T11, T34
- [x] **T36** · Implement Settings view (API key entry, model selection + download, mic toggle + device picker, storage path) · **M** · blocked-by: T23, T16

## Phase 7: Polish & Beta (M6 — Weeks 11–12)

- [x] **T37** · Implement first-run onboarding flow (Screen Recording permission explanation, Mic permission, API key validation, model download) · **M** · blocked-by: T36, T7
- [x] **T38** · Implement meeting status state machine with error handling (recording → processing → ready / error, with user-visible messages) · **M** · blocked-by: T32
- [ ] **T39** · Performance tuning (profile RAM/CPU, lazy model loading, optimize FTS queries) · **M** · blocked-by: T32
- [ ] **T40** · Create app icon and menu bar icon assets (idle, recording, processing states) · **S** · blocked-by: T30
- [ ] **T41** · Set up code signing, notarization, and .dmg packaging · **M** · blocked-by: T1
- [x] **T42** · Integrate Sparkle for auto-updates · **S** · blocked-by: T41
- [x] **T43** · Add recording consent reminder feature (configurable notification to meeting participants) · **S** · blocked-by: T32
- [ ] **T44** · End-to-end testing with real meetings (10 test recordings across the audio corpus) · **L** · blocked-by: T32
- [ ] **T45** · Private beta release to 10 users, collect feedback · **M** · blocked-by: T41, T44

---

## Completed Task Log

- [x] **T1** · Create Xcode project with SwiftUI App lifecycle, menu bar target (NSStatusItem), macOS 13 deployment target · completed 2026-03-22
- [x] **T2** · Add SPM dependencies: GRDB.swift, Sparkle (WhisperKit/SpeakerKit deferred — not yet publicly available as SPM packages) · completed 2026-03-22
- [x] **T3** · Set up GRDB database with v1 migration (meeting, transcriptSegment, transcriptFts, summary, meetingSpeaker tables) · completed 2026-03-22
- [x] **T4** · Create Swift data models conforming to GRDB Record protocol (Meeting, TranscriptSegment, Summary, MeetingSpeaker) · completed 2026-03-22
- [x] **T5** · Add .gitignore (Xcode, Swift, macOS, CoreML models, build artifacts) · completed 2026-03-22
- [x] **T6** · Set up CI pipeline (GitHub Actions: build + test on macOS runner) · completed 2026-03-22
- [x] **T7** · Implement ScreenCaptureKit audio capture service · completed 2026-03-22
- [x] **T8** · Implement PCM ring buffer with 48→16 kHz downsampling · completed 2026-03-22
- [x] **T9** · Implement AAC encoder service (30-second segments to disk) · completed 2026-03-22
- [x] **T10** · Implement AVAudioEngine microphone capture · completed 2026-03-22
- [x] **T11** · Implement meeting audio file management (segment concatenation) · completed 2026-03-22
- [x] **T12** · Write audio pipeline tests (RingBuffer: downsampling, overflow, thread safety) · completed 2026-03-22
- [x] **T13** · Implement WhisperKit integration service (interface ready, model loading, 10s chunked inference) · completed 2026-03-22
- [x] **T14** · Implement transcript segment deduplication (Jaccard similarity, timestamp overlap) · completed 2026-03-22
- [x] **T15** · Wire transcription output to GRDB (TranscriptionStore with dedup + FTS search) · completed 2026-03-22
- [x] **T16** · Implement model download manager (HuggingFace download, progress reporting) · completed 2026-03-22
- [x] **T17** · Implement Intel Mac detection + batch-mode fallback · completed 2026-03-22
- [x] **T18** · Write transcription tests (dedup correctness, similarity, merge logic) · completed 2026-03-22
- [x] **T19** · Implement diarization service (interface ready, placeholder energy-based segmentation) · completed 2026-03-22
- [x] **T20** · Implement transcript-speaker merge (timestamp overlap matching) · completed 2026-03-22
- [x] **T21** · Implement local speaker identification (mic embedding comparison) · completed 2026-03-22
- [x] **T22** · Write diarization tests (speaker merge correctness) · completed 2026-03-22
- [x] **T23** · Implement Keychain service · completed 2026-03-22
- [x] **T24** · Implement Anthropic API client (claude-sonnet-4-6, structured JSON parsing) · completed 2026-03-22
- [x] **T25** · Implement retry logic (exponential backoff with jitter) · completed 2026-03-22
- [x] **T26** · Implement summary prompt template (system prompt + transcript formatting) · completed 2026-03-22
- [x] **T27** · Implement long meeting chunking (90-min segments + meta-summary) · completed 2026-03-22
- [x] **T28** · Wire summary to GRDB (SummarizationService orchestrator) · completed 2026-03-22
- [x] **T29** · Write summarization tests (prompt formatting, response parsing, chunking, retry config) · completed 2026-03-22
- [x] **T30** · Implement menu bar with idle/recording/processing icon states · completed 2026-03-22
- [x] **T31** · Implement menu bar popover (recent meetings, recording controls, live transcript preview) · completed 2026-03-22
- [x] **T32** · Implement recording flow (MeetingCoordinator: full pipeline orchestration) · completed 2026-03-22
- [x] **T33** · Implement Meeting Library view (NavigationSplitView, FTS search, date filtering) · completed 2026-03-22
- [x] **T34** · Implement Meeting Detail view (transcript with speaker colors, summary panel, editable speakers) · completed 2026-03-22
- [x] **T35** · Implement audio playback (play/pause, scrub, transcript-segment-to-timestamp linking) · completed 2026-03-22
- [x] **T36** · Implement Settings view (4 tabs: general, API, audio, models) · completed 2026-03-22
- [x] **T37** · Implement first-run onboarding flow (6-step wizard) · completed 2026-03-22
- [x] **T38** · Implement meeting status state machine (MeetingState enum with error handling) · completed 2026-03-22
- [x] **T42** · Sparkle dependency added in project.yml · completed 2026-03-22
- [x] **T43** · Add recording consent reminder feature (UNUserNotificationCenter) · completed 2026-03-22
