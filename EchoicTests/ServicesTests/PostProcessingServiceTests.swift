import XCTest
import GRDB
@testable import Echoic

final class PostProcessingServiceTests: XCTestCase {
    private var dbQueue: DatabaseQueue!

    override func setUp() async throws {
        dbQueue = try DatabaseQueue()
        try DatabaseManager.migrate(dbQueue)
        try await dbQueue.write { db in
            try Meeting(id: "m1", title: "Post Test", startedAt: 0, status: .processing).insert(db)
        }
    }

    override func tearDown() async throws {
        dbQueue = nil
    }

    private func insert(speakerId: String?) throws {
        try dbQueue.write { db in
            var segment = TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 1000, speakerId: speakerId, text: "hello", confidence: 0.9)
            try segment.insert(db)
        }
    }

    func test_needsDiarization_onlyLocalSpeakerSegments_returnsTrue() throws {
        try insert(speakerId: nil)
        try insert(speakerId: TranscriptSegment.localSpeakerId)

        XCTAssertTrue(try dbQueue.read { try PostProcessingService.needsDiarization(meetingId: "m1", db: $0) })
    }

    func test_needsDiarization_hasDiarizedSpeaker_returnsFalse() throws {
        try insert(speakerId: "speaker_1")
        try insert(speakerId: TranscriptSegment.localSpeakerId)

        XCTAssertFalse(try dbQueue.read { try PostProcessingService.needsDiarization(meetingId: "m1", db: $0) })
    }
}
