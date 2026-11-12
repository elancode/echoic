import XCTest
@testable import Echoic

final class MicrophoneActivityMonitorTests: XCTestCase {
    func test_isIgnoredSystemProcess_screenCaptureDaemon_returnsTrue() {
        XCTAssertTrue(MicrophoneActivityMonitor.isIgnoredSystemProcess("com.apple.replayd"))
    }

    func test_isIgnoredSystemProcess_siriAndDictation_returnsTrue() {
        XCTAssertTrue(MicrophoneActivityMonitor.isIgnoredSystemProcess("com.apple.corespeechd"))
        XCTAssertTrue(MicrophoneActivityMonitor.isIgnoredSystemProcess("com.apple.assistantd"))
    }

    func test_isIgnoredSystemProcess_appleCallApps_returnsFalse() {
        XCTAssertFalse(MicrophoneActivityMonitor.isIgnoredSystemProcess("com.apple.FaceTime"))
        XCTAssertFalse(MicrophoneActivityMonitor.isIgnoredSystemProcess("com.apple.Safari"))
        XCTAssertFalse(MicrophoneActivityMonitor.isIgnoredSystemProcess("com.apple.WebKit.GPU"))
    }

    func test_isIgnoredSystemProcess_thirdPartyMeetingApps_returnsFalse() {
        XCTAssertFalse(MicrophoneActivityMonitor.isIgnoredSystemProcess("us.zoom.xos"))
        XCTAssertFalse(MicrophoneActivityMonitor.isIgnoredSystemProcess("com.amazon.Amazon-Chime"))
        XCTAssertFalse(MicrophoneActivityMonitor.isIgnoredSystemProcess("com.google.Chrome.helper"))
        XCTAssertFalse(MicrophoneActivityMonitor.isIgnoredSystemProcess(""))
    }
}
