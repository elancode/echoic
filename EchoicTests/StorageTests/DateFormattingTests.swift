import XCTest
@testable import Echoic

final class DateFormattingTests: XCTestCase {
    func test_formatTimestamp_zero_returnsBracketedZeroClock() {
        XCTAssertEqual(Date.formatTimestamp(ms: 0), "[00:00:00]")
    }

    func test_formatTimestamp_underAnHour_returnsBracketedHoursMinutesSeconds() {
        XCTAssertEqual(Date.formatTimestamp(ms: 65_000), "[00:01:05]")
        XCTAssertEqual(Date.formatTimestamp(ms: 3_599_999), "[00:59:59]")
    }

    func test_formatTimestamp_overAnHour_returnsBracketedHoursMinutesSeconds() {
        XCTAssertEqual(Date.formatTimestamp(ms: 3_725_000), "[01:02:05]")
    }

    func test_formatTimestamp_negative_clampsToZero() {
        XCTAssertEqual(Date.formatTimestamp(ms: -500), "[00:00:00]")
    }
}
