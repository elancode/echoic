import XCTest
@testable import Echoic

final class MeetingDetectorTests: XCTestCase {
    func test_notificationText_startWithAppName_asksIfEchoicShouldStart() {
        let text = MeetingDetector.notificationText(for: .start(MicrophoneUsage(isInUse: true, appName: "Zoom")))

        XCTAssertEqual(text.title, "Meeting detected")
        XCTAssertEqual(text.body, "Zoom is using your microphone. Should Echoic start recording?")
    }

    func test_notificationText_startWithoutAppName_mentionsEchoic() {
        let text = MeetingDetector.notificationText(for: .start(MicrophoneUsage(isInUse: true, appName: nil)))

        XCTAssertEqual(text.body, "Your microphone is in use. Should Echoic start recording?")
    }

    func test_notificationText_stopWithAppName_asksIfEchoicShouldStop() {
        let text = MeetingDetector.notificationText(for: .stop(appName: "Zoom"))

        XCTAssertEqual(text.title, "Meeting ended?")
        XCTAssertEqual(text.body, "Zoom stopped using your microphone. Should Echoic stop recording?")
    }

    func test_notificationText_stopWithoutAppName_mentionsEchoic() {
        let text = MeetingDetector.notificationText(for: .stop(appName: nil))

        XCTAssertEqual(text.body, "Your microphone is no longer in use. Should Echoic stop recording?")
    }
}
