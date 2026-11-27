---
paths:
  - "Echoic/Views/**"
  - "Echoic/UI/**"
  - "*View.swift"
  - "*Popover.swift"
---

# SwiftUI Conventions

- All views use **SwiftUI**. AppKit (NSStatusItem, NSHostingView) only for the menu bar integration.
- Keep view bodies under 40 lines. Extract subviews as separate structs.
- Use `@Query` (GRDB) for database-backed views. No manual observation boilerplate.
- Use `@State` for view-local state, `@Environment` for shared services.
- Light appearance per the "ink and signal" design (`echoic-design-handover.md`); the recording popover is dark. Use `Theme` tokens (`Echoic/Views/Design/Theme.swift`), not system semantic colors or raw hex values. Dark mode for Library and Settings is not designed yet.
- Fonts: Inter (UI), Space Grotesk (titles), JetBrains Mono (metadata) via `Font.inter`, `Font.display`, `Font.mono`.
- No external UI libraries. TailwindCSS does not exist here — this is native SwiftUI.
- Menu bar popover uses `NSHostingView` wrapping a SwiftUI view.
- Speaker colors: `Theme.speakerColor(for:)` (deterministic hash; "You" is ink).
- Timestamps displayed as `[HH:MM:SS]`. Clickable timestamps should trigger audio playback seek.
- Accessibility: all interactive elements must have meaningful labels.
