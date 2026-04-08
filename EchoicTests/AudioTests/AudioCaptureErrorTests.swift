import XCTest
@testable import Echoic

final class AudioCaptureErrorTests: XCTestCase {
    func testPermissionNotGrantedDescription() {
        let error = AudioCaptureError.permissionNotGranted
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Screen Recording"))
        XCTAssertTrue(error.errorDescription!.contains("System Settings"))
    }

    func testAllErrorCasesHaveDescriptions() {
        let cases: [AudioCaptureError] = [
            .noDisplayFound,
            .captureAlreadyRunning,
            .permissionDenied,
            .permissionNotGranted
        ]
        for error in cases {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }

    func testErrorConformsToLocalizedError() {
        let error: Error = AudioCaptureError.permissionNotGranted
        XCTAssertFalse(error.localizedDescription.contains("permissionNotGranted"),
                       "localizedDescription should use errorDescription, not the case name")
    }
}
