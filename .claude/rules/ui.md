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
- Dark mode only for Phase 1. Use system semantic colors (`Color.primary`, `Color.secondary`).
- No external UI libraries. TailwindCSS does not exist here — this is native SwiftUI.
- Menu bar popover uses `NSHostingView` wrapping a SwiftUI view.
- Speaker colors: assign a consistent color per speaker_id using a deterministic hash.
- Timestamps displayed as `[HH:MM:SS]`. Clickable timestamps should trigger audio playback seek.
- Accessibility: all interactive elements must have meaningful labels.
