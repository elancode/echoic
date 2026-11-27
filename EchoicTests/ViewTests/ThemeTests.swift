import AppKit
import XCTest
@testable import Echoic

final class ThemeTests: XCTestCase {
    func test_registerBundledFonts_appBundle_makesDesignFontsAvailable() {
        FontRegistry.registerBundledFonts()

        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold",
                     "SpaceGrotesk-SemiBold", "JetBrainsMono-Regular", "JetBrainsMono-Medium"] {
            XCTAssertNotNil(NSFont(name: name, size: 12), "\(name) is not available")
        }
    }

    func test_speakerColor_sameSpeaker_isStableAcrossCalls() {
        XCTAssertEqual(Theme.stableHash("speaker_2"), Theme.stableHash("speaker_2"))
        XCTAssertNotEqual(Theme.stableHash("speaker_1"), Theme.stableHash("speaker_2"))
    }

    func test_stableHash_knownInput_matchesFNV1a() {
        // FNV-1a 64-bit of "a"
        XCTAssertEqual(Theme.stableHash("a"), 0xaf63_dc4c_8601_ec8c)
    }
}
