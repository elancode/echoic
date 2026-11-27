import XCTest
@testable import Echoic

final class MeetingCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "MeetingCoordinatorTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func test_transcribesMicrophone_settingNeverChanged_defaultsToTrue() {
        XCTAssertTrue(MeetingCoordinator.transcribesMicrophone(defaults: defaults))
    }

    func test_transcribesMicrophone_settingTurnedOff_returnsFalse() {
        defaults.set(false, forKey: MeetingCoordinator.microphoneSettingKey)

        XCTAssertFalse(MeetingCoordinator.transcribesMicrophone(defaults: defaults))
    }

    // MARK: - Sources ("Listening to" checkboxes)

    func test_capturesMeetingAudio_settingNeverChanged_defaultsToTrue() {
        XCTAssertTrue(MeetingCoordinator.capturesMeetingAudio(defaults: defaults))
    }

    func test_recordingMode_bothSources_isSystemAudio() {
        XCTAssertEqual(MeetingCoordinator.recordingMode(meetingAudio: true, microphone: true), .systemAudio)
    }

    func test_recordingMode_meetingAudioOnly_isSystemAudio() {
        XCTAssertEqual(MeetingCoordinator.recordingMode(meetingAudio: true, microphone: false), .systemAudio)
    }

    func test_recordingMode_microphoneOnly_isMicrophone() {
        XCTAssertEqual(MeetingCoordinator.recordingMode(meetingAudio: false, microphone: true), .microphone)
    }

    func test_recordingMode_noSources_isNil() {
        XCTAssertNil(MeetingCoordinator.recordingMode(meetingAudio: false, microphone: false))
    }
}
