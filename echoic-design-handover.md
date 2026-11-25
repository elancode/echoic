# Echoic redesign: design handover

Date: 24 Nov 2026
Owner: Elan
Design canvas: https://claude.ai/artifact/LDbzkTVqEwLmU5p52Xvn4L
Source material: `echoic_vision_doc.md` (Draft v1.0), three screenshots of the current macOS build (menu bar popover, Meeting Library, Settings > Audio)

This document is for whoever implements the redesign. It covers what was designed, the exact values to build from, what is placeholder, and what is still undecided.

## 1. Status

| Screen | Artboard | State |
|---|---|---|
| Library, Summary tab | `Main` | Designed, first pass |
| Menu bar popover, ready | `Popover` | Designed, first pass |
| Menu bar popover, recording | `PopoverRecording` | Designed, first pass |
| Settings > Audio | `Settings` | Designed, first pass |
| Library, Transcript tab | none | Not designed |
| Settings > General, API key, Models | none | Not designed |
| Dark mode for Library and Settings | none | Not designed |
| Empty, error, permission-denied and first-run states | none | Not designed |
| Windows tray variant | none | Not designed |

Nothing has been reviewed against a rendered build yet, and Elan has not signed off on the direction. Treat spacing as approximate until that happens.

## 2. Direction

Name: "ink and signal".

- Near-white ground, black ink for every control and for primary buttons.
- One vermilion accent, reserved for things that are live: the recording dot, the level meter peak, a "Summarizing" row, and timestamps that jump into the transcript.
- The summary is laid out as a document, not as a panel of text. Chrome is kept quiet so the note reads first.
- Reference point was Granola (no bot, calm notepad feel). Nothing was copied from it; the look is Echoic's own.

## 3. Design tokens

### Colour

| Token | Value | Use |
|---|---|---|
| ground | `#F6F7F5` | Sidebar, settings nav, action item rows |
| surface | `#FFFFFF` | Content pane, cards, popover |
| ink | `#15171A` | Text, primary buttons, selected nav item, recording popover background |
| ink-2 | `#24272B` | Lead paragraph |
| text-secondary | `#4A4F54` | Unselected tabs and filters |
| text-muted | `#5C6166` | Metadata, captions, shortcuts |
| border | `#D5D9D2` | Inputs, secondary buttons |
| border-soft | `#E1E4DF` | Pane dividers, cards |
| hairline | `#ECEEEA` | Row separators |
| chip | `#F0F2EE` | Speaker chips, tab track |
| backdrop | `#E4E7E2` | Behind popover and settings in the mockups only |
| accent-text | `#B93A14` | Accent used as text or links on light backgrounds |
| accent-fill | `#E5532A` | Accent used as a fill on light surfaces |
| accent-on-dark | `#FF6A3D` | Accent on the dark recording popover |
| success | `#1E6B4A` | "Granted" status |
| dark-surface-2 | `#1F2226` | Live transcript box in the recording popover |
| dark-border | `#3A3F45` / `#2A2E33` | Secondary button border / divider on dark |
| dark-text-muted | `#A9AEA8` | Labels on dark |
| dark-text-2 | `#C8CCC6` | Older transcript line on dark |

Speaker dot colours used so far: You `#15171A`, Sarah `#2F6F8F`, Speaker 3 `#C9A227`. A full speaker palette has not been defined.

The three accent values exist for contrast reasons. `#E5532A` fails 4.5:1 as small text on white, so text uses `#B93A14`.

### Type

| Role | Face | Size / weight |
|---|---|---|
| Meeting title (h1) | Space Grotesk | 36px, 600, line-height 1.12, tracking -0.02em |
| Section heading | Space Grotesk | 15px, 600 |
| App name | Space Grotesk | 18px (library), 16px (popover), 600 |
| Lead summary paragraph | Inter | 18px, line-height 1.6 |
| Body, list items | Inter | 15px, line-height 1.5 |
| UI default | Inter | 14px, line-height 1.45 |
| Buttons, tabs | Inter | 13px, 500 to 600 |
| Captions | Inter | 12 to 13px |
| Metadata, timestamps, shortcuts | JetBrains Mono | 11 to 12px |
| Group labels ("Today", "Permissions") | JetBrains Mono | 11px, 500, uppercase, tracking 0.06em |
| Recording timer | JetBrains Mono | 44px, 500, tracking -0.03em |

All three are Google Fonts. Fallbacks: `system-ui` for the sans faces, `ui-monospace` for mono.

### Shape and spacing

- Radius: 6 (filter pills, tab), 8 (buttons, inputs, nav items), 10 (list rows), 12 (cards, primary popover buttons), 14 to 16 (windows, popover), fully round for speaker chips.
- Control heights: 28 (filter pill, chip), 30 (tab), 32 (toolbar button), 36 (search, menu row), 44 to 48 (popover primary actions).
- Shadows: selected list row `0 1px 2px rgba(21,23,26,0.06)`; popover and settings window `0 12px 32px rgba(21,23,26,0.18)` plus a 1px `rgba(21,23,26,0.08)` ring.
- Focus ring: 2px solid ink, 2px offset (white on the dark popover).

## 4. Screens

### 4.1 Library (`Main`)

Layout: two panes. Sidebar is about 300px; the content pane takes the rest and scrolls independently. The reading column is capped at 760px and centred. Below roughly 860px wide the sidebar stacks above the content.

Sidebar, top to bottom:
1. App mark and name, with a "Record" button on the right (accent dot).
2. Search field, "Search every meeting", with a shortcut hint.
3. Filters: All, Today, This week, This month (kept from the current build).
4. Meetings grouped under mono day labels: Today, Yesterday, Last week.

Meeting row: title (wraps, never truncated) over a mono line of time, duration and speaker count. Selected row is a white card with a border and a light shadow.

Content pane:
1. Toolbar: Summary / Transcript segmented tabs on the left; "Copy summary" (secondary) and "Export" (primary, ink) on the right.
2. Mono metadata line: date, time, duration, meeting type.
3. Title.
4. Speaker chips.
5. Lead paragraph (the 2 to 3 sentence executive summary from the vision doc).
6. Decisions: one row per decision, with the speaker and a timestamp link on the right.
7. Action items: real checkboxes, with owner and due date on the right.
8. Open questions: plain list.
9. Topics: two-column grid of timestamp and topic.

This maps one-to-one onto the summary structure in section 5.4 of the vision doc. "Meeting metadata" is items 2 to 4.

Changes from the current build:

| Current | Redesign | Why |
|---|---|---|
| Summary shows literal `**bold**` markers | Structured sections rendered as real headings and lists | The Markdown is not being rendered today; this is a bug as well as a design issue |
| Speakers labelled "Unknown" and "You" in prose | "Speaker 3" chip with a dashed border and a "Name" action | Entry point for speaker enrollment (vision doc 5.3) |
| Green "ready" badge on every row | No badge when ready; an accent "Summarizing" line only while in progress | Status that is always the same carries no information |
| Titles truncated with an ellipsis | Titles wrap | Several current titles are unreadable in the list |
| Flat list | Grouped by day | Easier to scan |
| Delete "x" on every row | Not shown | Not yet placed; see open decisions |
| Search in the window title bar | Search at the top of the sidebar | Sits with the list it filters |

### 4.2 Popover, ready (`Popover`)

Card width 340px.

1. Header: mark, "Echoic", "Ready" status, settings button.
2. "Listening to": two checkbox rows, each with a live level meter.
   - Meeting audio: "Everyone else on the call"
   - My microphone: "Default input, labelled as You"
3. Primary button: "Start recording" with an accent dot and shortcut hint.
4. Privacy line: "Audio stays on this Mac. Only the transcript text is sent for the summary."
5. Menu rows: Open library, Quit Echoic.

Change from the current build: the System Audio / Microphone segmented control is replaced by two independent checkboxes. The current Settings screen already describes the microphone as an addition to system audio, so an either-or control contradicts it. The level meters let someone confirm Echoic can hear the call before they press record.

### 4.3 Popover, recording (`PopoverRecording`)

Same footprint, inverted to ink so the state is unmistakable at a glance.

1. Header: pulsing accent dot, "Recording", settings button.
2. Timer (mono, 44px) with an accent waveform to its right.
3. Live transcript box: the last two utterances with speaker and time. The newest line is white, the previous one dimmer. Should be an `aria-live="polite"` region.
4. Actions: "Bookmark" (secondary) and "Stop and summarize" (primary, white).
5. Menu row: Open live transcript.

The dot pulse is the only animation (1.6s ease-in-out opacity). Disable it under `prefers-reduced-motion`.

### 4.4 Settings > Audio (`Settings`)

Window 640 x 560. Left nav (168px): General, API key, Audio, Models. Selected item is an ink pill.

Permissions card:
- System audio: "Granted" status, an explanation that macOS lists this under Screen Recording and that only audio is taken, and an "Open System Settings" button.
- Microphone: "Granted" status.

Your voice card:
- "Transcribe my microphone" checkbox with its full explanation (the current build cuts this sentence off).
- Input device select.
- Input level meter (12 segments; the peak segment is accent).

Changes from the current build: top tabs become a sidebar, each permission shows its current state, and the section called "Microphone" is renamed "Your voice".

## 5. Placeholder content to replace

- **Meetings, speakers and summary text** are invented from the vision doc (pricing tiers, Phase 3, the macOS driver question). They are not real meetings.
- **Shortcuts:** only ⌘L (Open library) and ⌘Q (Quit) come from the current app. ⌘R (record), ⌘B (bookmark), ⌘T (live transcript) and ⌘K (search) are proposals. ⌘T and ⌘R in particular would need to be global shortcuts that don't collide with browsers.
- **App mark:** a dot with three fading arcs, drawn as a stand-in. It is not the current waveform icon and is not a finished logo.
- **"Strategy review"** as a meeting type, and **speaker counts** in list rows, assume the summarizer and diarizer expose those fields.
- **"Granted"** is the only permission state drawn.

## 6. Open decisions

1. **Direction sign-off.** Is vermilion on ink the right identity, or should Echoic keep its current blue? Each artboard has an accent tweak to try alternatives.
2. **Where delete goes.** Options: context menu on the row, or a "more" menu in the content toolbar.
3. **Both sources off.** If someone unticks both checkboxes in the popover, "Start recording" should be disabled; the disabled state is not drawn.
4. **Auto-detection of meeting audio** (vision doc open question 2) is not represented anywhere. If it ships, the ready popover needs a prompt state.
5. **Bookmarks.** Capture is in the recording popover, but where bookmarks appear in the Library is not designed.
6. **Export.** The button exists; the destination picker (Markdown, Notion, Obsidian, Google Docs) is not designed.
7. **Editing.** The vision doc says users can correct transcripts and speaker names. Only speaker naming has an entry point so far.
8. **Stack mismatch to confirm.** The vision doc specifies Tauri with React and Tailwind; the screenshots look like a native macOS build. The tokens above work for either, but the fonts are web fonts and would need bundling in a native app, and native popovers will not match the 16px radius and shadow exactly without custom drawing.

## 7. Suggested next steps

1. Review the four artboards and settle item 1 above.
2. Design the Transcript tab (speaker colours, timestamp anchors, search highlighting, bookmarks).
3. Design the missing states: first run, no meetings yet, permission denied, missing or invalid API key, summarization failed, no audio detected.
4. Design Settings > API key and Models.
5. Decide on dark mode for the Library, reusing the dark tokens from the recording popover.
6. Fix the Markdown rendering bug in the current summary view regardless of the redesign schedule.

## 8. Implementation notes

- Use real controls: `button`, `input` with `label`, `select`. Tabs need `role="tablist"` / `role="tab"` with `aria-selected`; the selected meeting row and settings nav item carry `aria-current`.
- Icon-only buttons need an accessible label ("Settings").
- Timestamps are links into the transcript; they should switch to the Transcript tab and scroll to that point.
- Text contrast is at least 4.5:1 everywhere as drawn. Keep to the three accent values in section 3 to preserve that.
- The accent is the only colour signalling "live", so pair it with text ("Recording", "Summarizing") rather than relying on colour alone, as the mockups do.
