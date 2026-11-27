# Echoic call detection: design handover

Date: 25 Nov 2026
Owner: Elan
Design canvas: https://claude.ai/artifact/LDbzkTVqEwLmU5p52Xvn4L
Artboards: `CallDetected` (prompt), `PopoverDetected` (menu while on a call)
Companion doc: `echoic-design-handover.md` (tokens and the other screens)

This covers only the two screens for when Echoic detects a call. Neither has been checked against a rendered build yet, so treat spacing as approximate.

## 1. The problem being fixed

In the current build a call can be started three ways at the same moment:

1. A system notification: "Meeting detected. Zoom is using your microphone. Should Echoic start recording?" It has a blank icon and no buttons.
2. A banner at the top of the menu: "Zoom is using your mic" with "Start recording" and "Not now".
3. The main "Start recording" button lower in the same menu.

Items 2 and 3 do the same thing and sit a few centimetres apart.

## 2. The rule

One Start button per surface, and only one surface asks at a time.

| Situation | What the user sees | Start control |
|---|---|---|
| No call, menu open | Ready menu (`Popover`, unchanged) | "Start recording" |
| Call detected, menu closed | Prompt panel (`CallDetected`) | "Record" |
| Call detected, menu open | On-a-call menu (`PopoverDetected`) | "Record this call" |

- If the menu is open when a call is detected, do not show the prompt. Switch the menu to its on-a-call state instead.
- If the prompt is showing and the user opens the menu, dismiss the prompt.
- All three controls run the same start action, using whichever sources are ticked under "Listening to".

## 3. Prompt panel (`CallDetected`)

A small floating panel owned by Echoic, not a system notification.

Size: 420 x 84, radius 16, background `#15171A`, shadow `0 12px 32px rgba(21,23,26,0.28)`. Contents sit in one row, vertically centred, 14px gaps, padding 16px left and 12px right.

| Element | Spec |
|---|---|
| Mark | Echoic mark, 26px, white strokes, dot in accent `#FF6A3D` |
| Title | "Zoom call started". Space Grotesk 15px, 600, `#F4F5F2` |
| Subtitle | "Record it with Echoic?" Inter 13px, `#C8CCC6` |
| Record button | 40px tall, 16px side padding, radius 10, white background, ink text, Inter 14px 600, with a 9px `#D9481F` dot before the label |
| Close button | 36 x 40, transparent, 16px "x" icon in `#C8CCC6`, accessible label "Not now" |

Copy: the app name in the title is whichever app triggered detection ("Zoom call started", "Teams call started"). If the app can't be identified, use "Call started".

Behaviour:

- Record: start recording, dismiss the panel, and turn the menu bar icon to its recording state.
- Close: dismiss, and don't ask again for this call.
- Focus ring is 2px white with a 2px offset.
- Announce it to assistive tech as an alert dialog labelled "Call detected".

If you stay with system notifications instead: give the app a real icon (the blank square in the current popup is the missing icon), shorten the text to the title and subtitle above, and add "Record" and "Not now" as notification actions.

## 4. Menu while on a call (`PopoverDetected`)

Identical to the ready menu except for four changes:

| Ready menu | On-a-call menu |
|---|---|
| "Ready" beside the app name | Removed |
| Nothing above "Listening to" | Status line: 8px accent dot (`#E5532A`) and "You're on a Zoom call", Inter 15px 600, with 6px below it |
| Banner with its own buttons | Not present in either state. Delete it from the build |
| Main button reads "Start recording" | Reads "Record this call" |

Everything else is unchanged: the two source checkboxes with level meters, the shortcut hint on the main button, the privacy line, Open library and Quit Echoic.

There is no "Not now" in the menu. Closing the menu is the decline.

## 5. Not decided yet

1. **Prompt position.** Assumed top right under the menu bar, where system notifications appear. Not drawn in context.
2. **Auto-dismiss.** How long the prompt stays if ignored, and whether it also disappears when the call ends. Suggestion: stay until the call ends, since a missed prompt means a missed meeting.
3. **Scope of "Not now".** Assumed to cover the current call only. Whether a second call in the same app five minutes later prompts again is open.
4. **Calls that start while recording.** Assumed no prompt. Not specified.
5. **Recording automatically.** A setting to skip the prompt and start on detection would remove the question entirely for people who record everything. This is open question 2 in the vision doc and is not designed.
6. **Detection signal.** The current copy says "Zoom is using your mic". The new copy says "call", which is wrong if an app opens the mic for something else (dictation, a voice memo). Confirm what detection can actually tell apart.
7. **Light or dark prompt.** Drawn in ink to match the recording state and stand out over any window. No light variant exists.
