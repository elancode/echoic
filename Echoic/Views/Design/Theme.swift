import CoreText
import os.log
import SwiftUI

private let themeLogger = Logger(subsystem: "com.echoic.app", category: "Theme")

/// Design tokens for the "ink and signal" direction (see echoic-design-handover.md §3).
///
/// Vermilion is reserved for things that are live: the recording dot, a
/// "Summarizing" row, and timestamps that jump into the transcript. Always pair
/// it with text so state never relies on colour alone.
enum Theme {
    // MARK: Colour — light

    static let ground = Color(hex: 0xF6F7F5)
    static let surface = Color(hex: 0xFFFFFF)
    static let ink = Color(hex: 0x15171A)
    static let ink2 = Color(hex: 0x24272B)
    static let textSecondary = Color(hex: 0x4A4F54)
    static let textMuted = Color(hex: 0x5C6166)
    static let border = Color(hex: 0xD5D9D2)
    static let borderSoft = Color(hex: 0xE1E4DF)
    static let hairline = Color(hex: 0xECEEEA)
    static let chip = Color(hex: 0xF0F2EE)
    static let success = Color(hex: 0x1E6B4A)

    /// Accent as text or links on light backgrounds (4.5:1 on white).
    static let accentText = Color(hex: 0xB93A14)
    /// Accent as a fill on light surfaces. Not for small text.
    static let accentFill = Color(hex: 0xE5532A)
    /// Accent on the dark recording popover.
    static let accentOnDark = Color(hex: 0xFF6A3D)

    // MARK: Colour — dark (recording popover)

    static let darkSurface2 = Color(hex: 0x1F2226)
    static let darkBorder = Color(hex: 0x3A3F45)
    static let darkDivider = Color(hex: 0x2A2E33)
    static let darkTextMuted = Color(hex: 0xA9AEA8)
    static let darkText2 = Color(hex: 0xC8CCC6)

    // MARK: Speakers

    /// Dot colour for a speaker. "You" is ink; others come from a fixed palette
    /// chosen by a stable hash of the speaker ID, so a speaker keeps its colour.
    static func speakerColor(for speakerId: String?) -> Color {
        guard let speakerId else { return textMuted }
        if speakerId == TranscriptSegment.localSpeakerId { return ink }
        let palette = speakerPalette
        return palette[Int(stableHash(speakerId) % UInt64(palette.count))]
    }

    /// Palette beyond the two drawn colours (Sarah blue, Speaker 3 ochre) is a
    /// placeholder until a full speaker palette is designed.
    static let speakerPalette: [Color] = [
        Color(hex: 0x2F6F8F), Color(hex: 0xC9A227), Color(hex: 0x6B4E9B),
        Color(hex: 0x2E7D5B), Color(hex: 0x9A4A6B), Color(hex: 0x5A6B2E),
    ]

    /// FNV-1a; `String.hashValue` is randomised per launch.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    // MARK: Shape

    enum Radius {
        static let pill: CGFloat = 6
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let card: CGFloat = 12
        static let window: CGFloat = 14
    }
}

// MARK: - Type

extension Font {
    /// Space Grotesk SemiBold — titles, section headings, app name.
    static func display(_ size: CGFloat) -> Font {
        .custom("SpaceGrotesk-SemiBold", size: size)
    }

    /// Inter at the given weight (400, 500 or 600 are bundled).
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Inter-Medium"
        case .semibold, .bold, .heavy, .black: name = "Inter-SemiBold"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size)
    }

    /// JetBrains Mono — metadata, timestamps, shortcuts, group labels.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .regular ? "JetBrainsMono-Regular" : "JetBrainsMono-Medium", size: size)
    }
}

/// Registers the bundled fonts for this process. If registration fails, SwiftUI
/// falls back to the system font, so the app still works.
enum FontRegistry {
    static func registerBundledFonts(in bundle: Bundle = .main) {
        let urls = (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        guard !urls.isEmpty else {
            themeLogger.error("No bundled fonts found; using system fonts")
            return
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered fonts report an error too; that's harmless.
                themeLogger.debug("Font registration skipped for \(url.lastPathComponent, privacy: .public)")
            }
        }
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
