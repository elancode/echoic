import XCTest
import GRDB
@testable import Echoic

final class SpeakerMergeTests: XCTestCase {
    private var dbQueue: DatabaseQueue!

    override func setUp() async throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)

        try DatabaseManager.migrate(dbQueue)
    }

    func testMergeAssignsSpeakers() throws {
        let meetingId = "01HTEST_MERGE_001"

        // Insert meeting and segments
        try dbQueue.write { db in
            try Meeting(id: meetingId, title: "Merge Test", startedAt: 0, status: .ready).insert(db)
            var s1 = TranscriptSegment(meetingId: meetingId, startMs: 0, endMs: 5000, text: "Hello everyone", confidence: 0.9)
            try s1.insert(db)
            var s2 = TranscriptSegment(meetingId: meetingId, startMs: 5000, endMs: 10000, text: "Thanks for joining", confidence: 0.85)
            try s2.insert(db)
            var s3 = TranscriptSegment(meetingId: meetingId, startMs: 10000, endMs: 15000, text: "Let us begin", confidence: 0.9)
            try s3.insert(db)
        }

        // Speaker diarization results
        let speakerSegments = [
            DiarizationService.DiarizationSegment(startMs: 0, endMs: 6000, speakerId: "speaker_1"),
            DiarizationService.DiarizationSegment(startMs: 6000, endMs: 15000, speakerId: "speaker_2")
        ]

        try SpeakerMerge.merge(meetingId: meetingId, speakerSegments: speakerSegments, databaseWriter: dbQueue)

        // Verify speakers assigned
        let segments = try dbQueue.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingId)
                .order(TranscriptSegment.Columns.startMs)
                .fetchAll(db)
        }

        XCTAssertEqual(segments[0].speakerId, "speaker_1")
        XCTAssertEqual(segments[1].speakerId, "speaker_2")
        XCTAssertEqual(segments[2].speakerId, "speaker_2")

        // Verify meetingSpeaker entries created
        let speakers = try dbQueue.read { db in
            try MeetingSpeaker.fetchAll(db)
        }
        XCTAssertEqual(speakers.count, 2)
    }

    func test_merge_micSegments_keepLocalSpeaker() throws {
        let meetingId = "01HTEST_MERGE_YOU"
        try dbQueue.write { db in
            try Meeting(id: meetingId, title: "Merge You", startedAt: 0, status: .processing).insert(db)
            var remote = TranscriptSegment(meetingId: meetingId, startMs: 0, endMs: 5000, text: "How was the trip", confidence: 0.9)
            try remote.insert(db)
            var mine = TranscriptSegment(meetingId: meetingId, startMs: 5000, endMs: 9000,
                                         speakerId: TranscriptSegment.localSpeakerId, text: "It was great thanks", confidence: 0.9)
            try mine.insert(db)
        }
        // Diarization of system audio only knows remote speakers; it may still cover the mic segment's time range.
        let speakerSegments = [DiarizationService.DiarizationSegment(startMs: 0, endMs: 10_000, speakerId: "speaker_1")]

        try SpeakerMerge.merge(meetingId: meetingId, speakerSegments: speakerSegments, databaseWriter: dbQueue)

        let speakerIds = try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT speakerId FROM transcriptSegment WHERE meetingId = ? ORDER BY startMs", arguments: [meetingId])
        }
        XCTAssertEqual(speakerIds, ["speaker_1", TranscriptSegment.localSpeakerId])
    }

    func test_merge_withMicSegments_createsYouMeetingSpeaker() throws {
        let meetingId = "01HTEST_MERGE_YOU_LABEL"
        try dbQueue.write { db in
            try Meeting(id: meetingId, title: "Merge You Label", startedAt: 0, status: .processing).insert(db)
            var mine = TranscriptSegment(meetingId: meetingId, startMs: 0, endMs: 3000,
                                         speakerId: TranscriptSegment.localSpeakerId, text: "Morning all", confidence: 0.9)
            try mine.insert(db)
        }

        try SpeakerMerge.merge(meetingId: meetingId, speakerSegments: [], databaseWriter: dbQueue)

        let labels = try dbQueue.read { db in
            try MeetingSpeaker.filter(MeetingSpeaker.Columns.meetingId == meetingId).fetchAll(db).map(\.label)
        }
        XCTAssertEqual(labels, ["You"])
    }
}
