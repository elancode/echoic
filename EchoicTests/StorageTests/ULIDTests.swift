import XCTest
@testable import Echoic

final class ULIDTests: XCTestCase {
    func testULIDLength() {
        let ulid = ULID.generate()
        XCTAssertEqual(ulid.count, 26)
    }

    func testULIDUniqueness() {
        let ulids = (0..<100).map { _ in ULID.generate() }
        let uniqueSet = Set(ulids)
        XCTAssertEqual(uniqueSet.count, 100)
    }

    func testULIDChronologicalOrder() {
        let first = ULID.generate()
        // Small delay to ensure different timestamp
        Thread.sleep(forTimeInterval: 0.002)
        let second = ULID.generate()

        // ULIDs should be string-sortable in chronological order
        XCTAssertTrue(first < second, "ULIDs should sort chronologically: \(first) < \(second)")
    }

    func testULIDValidCharacters() {
        let ulid = ULID.generate()
        let validChars = CharacterSet(charactersIn: "0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        for char in ulid.unicodeScalars {
            XCTAssertTrue(validChars.contains(char), "Invalid character in ULID: \(char)")
        }
    }
}
