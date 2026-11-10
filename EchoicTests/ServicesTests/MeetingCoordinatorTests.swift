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
}
