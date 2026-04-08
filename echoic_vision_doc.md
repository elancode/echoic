# Echoic — Vision Document

**Intelligent Meeting Companion for Desktop**

Author: Elan
Date: March 2026
Status: Draft v1.0
Classification: Confidential

---

## 1. Executive Summary

**Echoic** is a lightweight, always-on desktop companion that captures audio from any online meeting—Zoom, Google Meet, Microsoft Teams, Webex, or any browser-based call—and produces real-time transcription, speaker diarization, and intelligent post-meeting summaries. It works by capturing system audio at the OS level, requiring no plugins, calendar integrations, or meeting bot participants. The result is a private, local-first experience where your meeting data never leaves your machine unless you choose to share it.

Knowledge workers spend an average of 15–20 hours per week in meetings, yet the majority of decisions, action items, and context discussed in those meetings is lost within 48 hours. Echoic solves this by turning every meeting into a searchable, structured artifact without changing how people work.

---

## 2. Problem Statement

Despite the proliferation of video conferencing tools, the post-meeting experience remains fundamentally broken:

- **Meeting amnesia:** Critical decisions, context, and nuance are lost because note-taking during a live conversation is both cognitively expensive and incomplete.
- **Bot fatigue:** Existing transcription services (Otter, Fireflies, Fathom) inject a bot participant into the meeting, creating social friction, triggering security concerns, and requiring per-platform integrations.
- **Context fragmentation:** Action items, decisions, and follow-ups are scattered across chat, email, and memory—there is no canonical record of what was discussed and agreed upon.
- **Privacy anxiety:** Cloud-first transcription services upload raw audio to third-party servers, creating compliance and trust issues—especially in enterprise environments and regulated industries.
- **Platform lock-in:** Most solutions only work with one or two meeting platforms, forcing users to manage multiple tools or go without coverage for certain calls.

---

## 3. Vision & Product Principles

### 3.1 Product Vision

> *Echoic makes every meeting effortlessly memorable. Open the app, join your call, and walk away with a perfect record—no bots, no plugins, no cloud dependency.*

### 3.2 Core Principles

| Principle | Description |
|---|---|
| Invisible by default | Echoic should never disrupt a meeting. No bots joining, no consent pop-ups from the tool, no participant list clutter. It captures system audio silently in the background. |
| Local-first privacy | All audio capture, transcription, and diarization happen on-device. Raw audio is never uploaded. Summaries can optionally be synced to a user's own cloud storage. |
| Platform-agnostic | By capturing system audio at the OS level, Echoic works with any meeting tool—Zoom, Meet, Teams, Webex, Discord, phone calls routed through desktop—without per-platform integration. |
| Zero-config start | First-time experience: install, grant audio permission, paste your Anthropic API key, done. No calendar OAuth, no meeting link parsing, no onboarding wizard. Start a meeting and Echoic works. |
| Structured output | Every meeting produces a consistent artifact: timestamped transcript with speaker labels, a structured summary (decisions, action items, open questions), and a searchable index. |

---

## 4. Target User

The primary user is a knowledge worker—product managers, engineers, designers, founders, consultants—who spends 3 or more hours per day in virtual meetings and needs to retain and act on what was discussed. Secondary users include executives who need meeting intelligence across their organization, and teams in regulated industries (healthcare, finance, legal) who need compliant, on-premise transcription.

### 4.1 User Personas

- **The IC Multitasker:** An engineer or PM in 5–8 meetings/day who can't take notes and participate simultaneously. Needs searchable records and auto-extracted action items.
- **The Manager:** Runs 1:1s, standups, and cross-functional syncs. Needs to track commitments across meetings and share summaries with their team.
- **The Compliance Officer:** Requires transcription for audit trails and regulatory compliance but cannot allow audio to leave the corporate network.
- **The Founder:** Investor calls, customer discovery, hiring panels—every conversation matters and there's no support staff to take notes.

---

## 5. Key Capabilities

### 5.1 System Audio Capture

Echoic captures audio at the OS level using platform-native APIs (CoreAudio on macOS, WASAPI on Windows). This approach captures all system audio output, meaning any application producing meeting audio is automatically captured. The app provides a simple toggle to start/stop capture, with optional auto-detection of meeting audio patterns to begin recording automatically.

- **macOS:** Leverages a lightweight virtual audio driver (similar to BlackHole/Loopback) to tap the system audio bus without modifying the output stream.
- **Windows:** Uses WASAPI loopback capture to mirror the default audio output device with zero latency impact.
- **Microphone capture** (user's own voice) is optionally mixed or captured on a separate channel for improved diarization of the local speaker.

### 5.2 Real-Time Transcription

Transcription runs entirely on-device using a local speech-to-text model. The baseline engine is a fine-tuned Whisper variant optimized for real-time streaming, with chunked inference to maintain low latency (~2–3 second delay). Users see a live transcript scrolling as the meeting progresses.

- **Model options:** Ship with a compact model (~500MB) for broad hardware support. Allow users to download a larger, higher-accuracy model (~1.5GB) for Apple Silicon / NVIDIA GPU acceleration.
- **Language support:** English at launch, with a clear path to multilingual support via Whisper's existing language coverage.
- **Custom vocabulary:** Users can add company-specific terms, product names, and acronyms to improve transcription accuracy.

### 5.3 Speaker Diarization

Echoic identifies and labels distinct speakers throughout the meeting. Diarization uses a combination of embedding-based speaker clustering and optional enrollment (the user can label speakers after a meeting, and Echoic learns their voiceprint for future calls).

- On single-channel system audio, diarization uses spectral embedding clustering (e.g., pyannote-style pipeline) to separate speakers.
- When mic capture is enabled, the local user's voice is identified with high confidence via the separate audio channel, improving overall accuracy.
- Speaker labels persist across meetings—once you identify "Sarah from Product," she's labeled automatically in future calls.

### 5.4 Meeting Summarization

After a meeting ends (or on-demand), Echoic generates a structured summary by sending the transcript to a cloud-hosted LLM via API. The default model is Claude Sonnet 4.6 (Anthropic), chosen for its strong performance on long-context summarization, structured extraction, and instruction-following. Users provide their own Anthropic API key during setup, and the transcript is sent as a single request to the `/v1/messages` endpoint. The API key is stored locally in the system keychain (macOS Keychain / Windows Credential Manager) and never transmitted anywhere other than Anthropic's API. In the future, additional model providers (OpenAI, AWS Bedrock) may be supported as alternatives.

Every summary follows a consistent structure:

1. **Meeting metadata:** Date, time, duration, detected participants.
2. **Executive summary:** A 2–3 sentence overview of what the meeting was about.
3. **Key decisions:** Explicit decisions made during the call, attributed to speakers.
4. **Action items:** Tasks and owners extracted from the conversation, with due dates when mentioned.
5. **Open questions:** Unresolved topics or questions that were raised but not answered.
6. **Topic outline:** A hierarchical breakdown of subjects discussed, with timestamps for quick navigation.

### 5.5 Search & Knowledge Base

All transcripts and summaries are indexed locally in a full-text search engine (SQLite FTS5). Users can search across all historical meetings by keyword, speaker, date range, or topic. Semantic search (embedding-based) is available as an optional enhancement for natural-language queries like "when did we decide on the pricing model?"

---

## 6. Architecture Overview

Echoic is built as a native desktop application using Tauri (Rust backend + web frontend). This provides a small binary footprint (~15MB), native OS integration for audio capture, and a modern React-based UI.

| Layer | Technology |
|---|---|
| Shell / UI | Tauri v2 + React + TailwindCSS. Cross-platform (macOS, Windows, Linux). |
| Audio Capture | Rust-native: cpal + custom virtual audio driver (macOS), WASAPI loopback (Windows). |
| Transcription | whisper.cpp running in a sidecar process. GPU-accelerated on Apple Silicon (CoreML) and NVIDIA (CUDA). |
| Diarization | pyannote.audio speaker embedding pipeline, running in a bundled Python sidecar. |
| Summarization | Cloud: Anthropic API (Claude Sonnet 4.6) via user-provided API key. API key stored in OS keychain. Future support for OpenAI / Bedrock. |
| Storage | SQLite for metadata + FTS5 for search. Audio segments stored as compressed Opus files on disk. |
| Sync (optional) | Export to Notion, Obsidian, Google Docs, or S3 via user-configured integrations. |

---

## 7. User Experience

### 7.1 First-Time Setup

Install the app. Grant microphone and system audio permission. Enter your Anthropic API key in settings. Done. No account creation required—the API key is stored securely in your OS keychain and is only used to call the Anthropic API for meeting summaries. The app sits in the menu bar (macOS) or system tray (Windows) and is always available with a single click.

### 7.2 During a Meeting

When audio is detected (or the user clicks "Start"), Echoic begins capturing. A subtle, non-intrusive indicator shows that recording is active. The user can optionally open a live transcript panel that floats alongside their meeting window. Bookmarks can be dropped at any moment with a keyboard shortcut to flag important moments.

### 7.3 After a Meeting

When audio stops (or the user clicks "Stop"), summarization kicks off automatically. Within 30–60 seconds, the meeting card appears in Echoic's dashboard with the full transcript, speaker timeline, and structured summary. The user can edit speaker names, correct transcript errors, and share the summary via their preferred channel.

### 7.4 Dashboard & Search

The main app window is a searchable timeline of all past meetings. Each meeting card shows the date, duration, participants, and summary preview. Clicking into a meeting reveals the full transcript with speaker colors, a topic outline with timestamp links, and the structured summary. A global search bar lets users query across all meetings.

---

## 8. Competitive Landscape

| Feature | Echoic | Otter.ai | Fireflies | Granola | Fathom |
|---|---|---|---|---|---|
| No bot required | ✓ | ✗ | ✗ | ✓ | ✗ |
| Local-first | ✓ | ✗ | ✗ | Partial | ✗ |
| Platform agnostic | ✓ | Limited | Limited | ✓ | Zoom only |
| Diarization | ✓ | ✓ | ✓ | ✗ | ✓ |
| Offline capable | Partial (capture + transcription offline; summarization requires internet) | ✗ | ✗ | ✗ | ✗ |
| Free tier | Free app + BYOK API costs | Limited | Limited | Limited | ✓ |

Echoic's differentiation is rooted in the intersection of local-first privacy and platform-agnostic capture. No existing solution offers both without a meeting bot. Granola is the closest analog but lacks diarization and deep summarization. Echoic combines the best transcription quality of dedicated services with the privacy guarantees of a fully local tool.

---

## 9. Phased Roadmap

### Phase 1: Foundation (Months 1–3)

- System audio capture working on macOS and Windows.
- Local transcription with whisper.cpp (English).
- Basic speaker diarization (2–6 speakers).
- Post-meeting summary via Anthropic API (Claude Sonnet 4.6), user-provided API key.
- SQLite-based meeting library with full-text search.
- Menu bar / tray app with minimal UI.

### Phase 2: Polish & Power (Months 4–6)

- Live transcript overlay during meetings.
- Speaker enrollment and persistent voiceprints.
- Custom vocabulary and domain-specific tuning.
- Support for alternative LLM providers (OpenAI, AWS Bedrock) alongside Anthropic.
- Export integrations: Notion, Obsidian, Google Docs, Markdown.
- Keyboard shortcuts for bookmarks, start/stop, quick search.

### Phase 3: Intelligence (Months 7–12)

- Semantic search across meeting history.
- Cross-meeting knowledge graph: track decisions, action items, and topics over time.
- Meeting prep assistant: before a recurring meeting, surface unresolved items from prior sessions.
- Team features: shared meeting library with access controls.
- Calendar integration for auto-labeling meetings.
- Multilingual transcription and translation.

---

## 10. Privacy & Compliance

Privacy is not a feature of Echoic—it is the architecture. The system is designed so that a privacy-conscious user never needs to trust a third party with their meeting content.

- **Audio stays local:** Raw audio is captured, processed, and stored entirely on the user's machine. No audio is ever transmitted over the network in the default configuration.
- **Transcript sent for summarization only:** When a meeting ends, the transcript text (never raw audio) is sent to the Anthropic API for summarization. The request is stateless—Anthropic does not retain inputs or outputs on API calls. The API key is stored in the OS keychain and never exposed in plaintext on disk.
- **Data sovereignty:** Users own their data. Meeting files are standard formats (JSON transcripts, Opus audio, Markdown summaries) stored in a user-accessible directory.
- **Consent:** Echoic does not interact with other meeting participants. However, the app provides a configurable reminder to inform participants that the meeting is being recorded, supporting compliance with two-party consent laws.
- **Enterprise-ready:** For enterprise deployments, Echoic can be configured to disable all network access, enforce local-only mode, and integrate with corporate DLP policies.

---

## 11. Business Model

Echoic follows a freemium model. Summarization uses the user's own Anthropic API key (bring-your-own-key), so API costs are paid directly to Anthropic. Echoic itself layers value on top:

| Tier | Includes | Price |
|---|---|---|
| Free | Unlimited transcription + diarization + summaries via your own API key. Full meeting library and search. | $0 / forever (+ your API costs) |
| Pro | Speaker enrollment, semantic search, export integrations (Notion, Obsidian, Google Docs), custom vocabulary, priority model updates. | $12/month (+ your API costs) |
| Team | Shared meeting library, team search, admin controls, SSO, usage analytics. | $20/user/month (+ your API costs) |
| Enterprise | On-prem deployment, custom model fine-tuning, DLP integration, dedicated support, SLA. | Custom pricing |

---

## 12. Success Metrics

| Metric | Target (6 months) | Target (12 months) |
|---|---|---|
| Daily active users | 5,000 | 25,000 |
| Meetings captured / week | 20,000 | 150,000 |
| Transcription WER | < 12% | < 8% |
| Diarization DER | < 18% | < 12% |
| Free → Pro conversion | 5% | 10% |
| NPS | > 50 | > 65 |

---

## 13. Risks & Mitigations

- **OS audio permission changes:** Apple and Microsoft periodically tighten audio capture APIs. Mitigation: maintain close parity with OS betas; offer a fallback browser extension that captures tab audio as a secondary capture path.
- **On-device model quality:** Local models may produce lower-quality transcription than cloud alternatives. Mitigation: invest in model optimization (quantization, distillation) and offer cloud as an upgrade path rather than a requirement.
- **Legal and consent complexity:** Recording laws vary by jurisdiction. Mitigation: provide clear user education, configurable consent notifications, and legal guidance in the app.
- **Competitive response:** Zoom, Google, and Microsoft could build native transcription and summarization into their platforms. Mitigation: Echoic's cross-platform, local-first positioning is a moat that single-platform vendors cannot replicate.

---

## 14. Open Questions

1. Should Echoic support in-person meeting capture (room microphone mode) in v1 or defer to v2?
2. What is the right default behavior for auto-detection of meeting audio vs. requiring manual start?
3. How should Echoic handle meetings where the user is a passive listener vs. an active participant for diarization accuracy?
4. Should the free tier include a limited number of cloud summaries per month as a taste of Pro?
5. What is the right licensing model for the virtual audio driver on macOS—bundle a custom driver or require the user to install an open-source one?

---

*End of Document*
