import XCTest
@testable import Echoic

final class CallPromptRouterTests: XCTestCase {
    func test_callDetected_menuClosed_showsPanel() {
        var router = CallPromptRouter()

        XCTAssertEqual(router.callDetected(), [.showPanel])
        XCTAssertTrue(router.isPanelVisible)
    }

    func test_callDetected_menuOpen_doesNotShowPanel() {
        var router = CallPromptRouter()
        _ = router.menuOpened()

        XCTAssertEqual(router.callDetected(), [])
        XCTAssertFalse(router.isPanelVisible)
    }

    func test_menuOpened_panelShowing_hidesPanel() {
        var router = CallPromptRouter()
        _ = router.callDetected()

        XCTAssertEqual(router.menuOpened(), [.hidePanel])
        XCTAssertFalse(router.isPanelVisible)
    }

    func test_menuClosed_callStillUnanswered_declines() {
        var router = CallPromptRouter()
        _ = router.callDetected()
        _ = router.menuOpened()

        XCTAssertEqual(router.menuClosed(), [.decline])
    }

    func test_menuClosed_noCall_doesNothing() {
        var router = CallPromptRouter()
        _ = router.menuOpened()

        XCTAssertEqual(router.menuClosed(), [])
    }

    func test_promptEnded_panelShowing_hidesPanel_andMenuCloseNoLongerDeclines() {
        var router = CallPromptRouter()
        _ = router.callDetected()

        XCTAssertEqual(router.promptEnded(), [.hidePanel])
        _ = router.menuOpened()
        XCTAssertEqual(router.menuClosed(), [])
    }

    func test_promptEnded_noPanel_doesNothing() {
        var router = CallPromptRouter()

        XCTAssertEqual(router.promptEnded(), [])
    }

    // MARK: - Copy

    func test_promptText_knownApp_namesTheApp() {
        let text = CallPromptRouter.promptText(appName: "Zoom")

        XCTAssertEqual(text.title, "Zoom call started")
        XCTAssertEqual(text.subtitle, "Record it with Echoic?")
    }

    func test_promptText_unknownApp_saysCallStarted() {
        XCTAssertEqual(CallPromptRouter.promptText(appName: nil).title, "Call started")
        XCTAssertEqual(CallPromptRouter.promptText(appName: "  ").title, "Call started")
    }

    func test_menuStatus_knownAndUnknownApp() {
        XCTAssertEqual(CallPromptRouter.menuStatus(appName: "Teams"), "You're on a Teams call")
        XCTAssertEqual(CallPromptRouter.menuStatus(appName: nil), "You're on a call")
    }
}
