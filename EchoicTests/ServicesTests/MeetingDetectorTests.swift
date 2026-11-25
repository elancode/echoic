import XCTest
@testable import Echoic

final class MeetingDetectorTests: XCTestCase {
    func test_stopNotificationText_withAppName_asksIfEchoicShouldStop() {
        let text = MeetingDetector.stopNotificationText(appName: "Zoom")

        XCTAssertEqual(text.title, "Meeting ended?")
        XCTAssertEqual(text.body, "Zoom stopped using your microphone. Should Echoic stop recording?")
    }

    func test_stopNotificationText_withoutAppName_mentionsEchoic() {
        let text = MeetingDetector.stopNotificationText(appName: nil)

        XCTAssertEqual(text.body, "Your microphone is no longer in use. Should Echoic stop recording?")
    }

    func test_autoStopNotificationText_withAppName_saysRecordingStopped() {
        let text = MeetingDetector.autoStopNotificationText(appName: "Zoom")

        XCTAssertEqual(text.title, "Recording stopped")
        XCTAssertEqual(text.body, "Zoom stopped using your microphone, so Echoic stopped recording.")
    }

    func test_autoStopNotificationText_withoutAppName_saysCallEnded() {
        let text = MeetingDetector.autoStopNotificationText(appName: nil)

        XCTAssertEqual(text.body, "Your call ended, so Echoic stopped recording.")
    }

    func test_isAutoStopEnabled_unset_defaultsToTrue() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        XCTAssertTrue(MeetingDetector.isAutoStopEnabled(defaults: defaults))
        defaults.set(false, forKey: MeetingDetector.autoStopSettingsKey)
        XCTAssertFalse(MeetingDetector.isAutoStopEnabled(defaults: defaults))
    }
}
