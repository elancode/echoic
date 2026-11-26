# Echoic live transcript window: design handover

Date: 25 Nov 2026
Owner: Elan
Design canvas: https://claude.ai/artifact/LDbzkTVqEwLmU5p52Xvn4L
Artboard: `LiveTranscript`
Companion docs: `echoic-design-handover.md` (tokens, other screens), `echoic-call-detection-handover.md`

This covers the window that opens from "Open live transcript" while a recording is running. It has not been checked against a rendered build yet, so treat spacing as approximate. Only one state is drawn: mid-call, following live, insights populated.

## 1. What changes from the current build

| Current | Redesign | Why |
|---|---|---|
| One line per recognized fragment ("this made", "codecs") | Fragments merged into one paragraph per speaker turn | Fragments are unreadable at a glance |
| Only "You" is labelled; other speech has no speaker | Every turn has a speaker and a start time in a left gutter | You can't tell who said what today |
| Red dot, "Recording", red timer, nothing else in the header | Same status plus source app, speaker count, Bookmark and "Stop and summarize" | Saves a trip back to the menu bar |
| "Auto-scroll" checkbox in the header | "Following live" pill at the bottom of the transcript | The control sits where the scrolling happens |
| Insights: goal field, a spinner and a refresh icon, placeholder text | Insights: goal field, "Updated 20 s ago", and four sections matching the final summary | The panel had no defined content |
| No bookmarks visible | Bookmarks appear as a marker line in the transcript | Confirms the bookmark landed |

## 2. Layout

Window drawn at 1200 x 780. It is fluid: three stacked regions, and the middle one splits in two.

1. **Header:** full width, 12px by 20px padding, hairline below.
2. **Body:** transcript on the left (takes the remaining width, minimum about 480px), Insights on the right (about 340px). Each scrolls independently. Below roughly 820px wide, Insights drops beneath the transcript.
3. **Transcript footer:** pinned to the bottom of the transcript column only.

Colours, type and radii are the tokens in `echoic-design-handover.md`. Values below are the ones specific to this window.

## 3. Header

Left group, 12px gaps:

| Element | Spec |
|---|---|
| Recording dot | 10px, accent, pulsing (1.6s ease-in-out opacity) |
| "Recording" | Space Grotesk 16px, 600 |
| Timer | JetBrains Mono 16px, 500, accent (`#B93A14`) |
| Context | "Zoom · 3 speakers", Inter 13px, `#5C6166` |

Right group, 8px gaps, all 34px tall:

| Element | Spec |
|---|---|
| Bookmark | Secondary button (white, `#D5D9D2` border, radius 8), bookmark icon, label, shortcut hint |
| Stop and summarize | Primary button (ink background, white text, 600), white square icon |
| Insights toggle | 34px icon button, `#F0F2EE` background when the panel is open; accessible label "Hide insights" / "Show insights" |

## 4. Transcript

Scroll area padding: 28px top, 32px sides, 20px bottom. 22px between turns.

### A turn

Two-column grid: 104px gutter, 20px gap, text column takes the rest.

- **Gutter:** speaker name (Inter 13px, 600) with an 8px colour dot before it; start time beneath (JetBrains Mono 11px, `#5C6166`).
- **Text:** Inter 16px, line-height 1.6, one paragraph per turn.

A new turn starts when the speaker changes. A long monologue needs a rule for breaking into further paragraphs; that rule is not decided (see section 7).

### Emphasis by recency

| Text | Colour |
|---|---|
| Earlier turns | `#4A4F54` |
| Current turn, confirmed words | `#15171A` |
| Current turn, words still being recognized | `#6B7075` |

A 2px by 16px accent cursor pulses at the end of the current turn.

### Unnamed speakers

Shown as "Speaker 3" with a small accent "Name" action under the timestamp. Naming a speaker should relabel all of that speaker's turns, here and in the saved meeting.

### Bookmark marker

A single row between turns, indented to the text column (124px): filled bookmark icon, "Bookmark · 08:31" in JetBrains Mono 11px accent, then a 1px `#F1D5CB` rule filling the rest of the row.

### Footer

Left: active sources in mono 11px ("Meeting audio + My microphone"). Right: the "Following live" pill (30px tall, fully rounded, white, `#D5D9D2` border, down-arrow icon).

Intended behaviour, of which only the first state is drawn:

- **Following:** new text keeps the view pinned to the bottom. Pill reads "Following live".
- **Paused:** scrolling up pauses following. The pill should change to a clear call to return, such as "Jump to live", and clicking it resumes.

## 5. Insights panel

Background `#F6F7F5`, left border `#E1E4DF`, padding 24px by 22px, 24px between blocks.

1. **Title row:** "Insights" (Space Grotesk 16px, 600). On the right, "Updated 20 s ago" in mono 11px and a 28px refresh icon button.
2. **Goal for this meeting:** labelled text field, 36px tall, optional. Placeholder "Optional, e.g. Decide the launch date". Replaces "What's this meeting about?".
3. **So far:** one short paragraph, Inter 15px, line-height 1.55.
4. **Decisions · n**
5. **Open questions · n**
6. **Action items · n**

Section labels are mono 11px uppercase with the count after a middle dot. Each decision, question or action is a white card (radius 10, `#E1E4DF` border, 12px padding) with the statement in Inter 14px and, beneath it, the speaker and a timestamp link in accent mono. An empty section shows "None yet." in `#5C6166`.

Clicking a timestamp scrolls the transcript to that turn and pauses following.

The four sections deliberately match the final summary (lead paragraph, decisions, action items, open questions) so the live view is a preview of what the meeting will produce.

## 6. Accessibility

- The transcript scroll area is a polite live region. Announce completed turns, not every interim word.
- Bookmark, Stop, the Insights toggle, refresh, "Name" and the following pill are real buttons. The toggle and pill carry a pressed state.
- The goal field has a visible label tied to it.
- Disable the dot and cursor pulse under reduced-motion settings.
- Speaker identity is carried by the name, not the dot colour alone.

## 7. Assumptions and open decisions

1. **What Insights generates.** The four sections are an assumption; the current panel's real output was not available when this was designed. Confirm or replace.
2. **Live speaker labels.** The design assumes other speakers can be told apart during the call. If diarization only runs afterwards, remote turns need a single generic label (for example "Others") until the meeting ends, and the speaker count in the header goes away.
3. **Insights refresh.** How often it updates on its own, and what the panel shows while updating (the current build has a spinner; none is drawn).
4. **Insights before there is enough speech.** The current build says "Insights appear after a minute or two of discussion." That empty state is not drawn.
5. **Privacy copy.** Live insights mean transcript text is sent to the API during the meeting, not only at the end. The menu's line "Only the transcript text is sent for the summary" may need rewording, and users without an API key need a state for this panel.
6. **Paragraph breaks in long turns.** By pause length, by sentence count, or by elapsed time; not decided.
7. **Paused-following state.** Described in section 4 but not drawn.
8. **Bookmark feedback.** Whether pressing Bookmark also shows a brief confirmation, and whether a bookmark can be labelled or removed.
9. **Editing during the call.** Whether transcript text can be corrected live or only after the meeting.
10. **Shortcut.** The Bookmark shortcut hint is a proposal carried over from the recording menu, not confirmed.
11. **Dark variant.** The recording menu is ink; this window is light for long reading. No dark version exists.

## 8. Placeholder content

The transcript, speakers and insights are the invented pricing meeting used on the other screens. Timer, timestamps, speaker count and "Zoom" are sample values.
