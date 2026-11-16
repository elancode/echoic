import XCTest
import GRDB
@testable import Echoic

final class SpeakerNamingTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private let meetingId = "01HTEST_NAMING_001"

    override func setUpWithError() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.migrate(dbQueue)

        try dbQueue.write { db in
            try Meeting(id: meetingId, title: "Test", startedAt: 0, status: .ready).insert(db)
            for (speakerId, label) in [("speaker_1", "Speaker 1"), ("speaker_2", "Speaker 2"),
                                       ("speaker_3", "Bob (edited)"), ("you", "You")] {
                try MeetingSpeaker(meetingId: meetingId, speakerId: speakerId, label: label).insert(db)
            }
        }
    }

    override func tearDown() {
        dbQueue = nil
    }

    private func labels() throws -> [String: String] {
        try dbQueue.read { db in try SpeakerNaming.labels(meetingId: meetingId, db: db) }
    }

    func test_apply_defaultLabels_renamesSpeakers() throws {
        try dbQueue.write { db in
            try SpeakerNaming.apply(names: ["speaker_1": "John", "speaker_2": "Pranita"], meetingId: meetingId, db: db)
        }

        let result = try labels()
        XCTAssertEqual(result["speaker_1"], "John")
        XCTAssertEqual(result["speaker_2"], "Pranita")
    }

    func test_apply_editedLabelOrYou_keepsLabel() throws {
        try dbQueue.write { db in
            try SpeakerNaming.apply(names: ["speaker_3": "Robert", "you": "Elan"], meetingId: meetingId, db: db)
        }

        let result = try labels()
        XCTAssertEqual(result["speaker_3"], "Bob (edited)")
        XCTAssertEqual(result["you"], "You")
    }

    func test_apply_blankOrUnknownSpeaker_isIgnored() throws {
        try dbQueue.write { db in
            try SpeakerNaming.apply(names: ["speaker_1": "  ", "speaker_99": "Ghost"], meetingId: meetingId, db: db)
        }

        let result = try labels()
        XCTAssertEqual(result["speaker_1"], "Speaker 1")
        XCTAssertNil(result["speaker_99"])
    }

    func test_resolve_speakerIdOrOtherText_mapsOnlySpeakerIds() {
        let labels = ["speaker_1": "John"]

        XCTAssertEqual(SpeakerNaming.resolve("speaker_1", labels: labels), "John")
        XCTAssertEqual(SpeakerNaming.resolve("TBD", labels: labels), "TBD")
        XCTAssertNil(SpeakerNaming.resolve(nil, labels: labels))
    }

    func test_buildTranscriptText_withLabels_groupsBySpeakerName() {
        let segments = [
            TranscriptSegment(meetingId: meetingId, startMs: 0, endMs: 1000, speakerId: "speaker_1", text: "Hi", confidence: 1),
            TranscriptSegment(meetingId: meetingId, startMs: 1000, endMs: 2000, speakerId: "speaker_5", text: "there", confidence: 1),
            TranscriptSegment(meetingId: meetingId, startMs: 2000, endMs: 3000, speakerId: "you", text: "Hello", confidence: 1),
        ]

        let text = MeetingDetailView.buildTranscriptText(
            from: segments,
            labels: ["speaker_1": "John", "speaker_5": "John", "you": "You"]
        )

        XCTAssertEqual(text, "John:\nHi there\n\nYou:\nHello")
    }

    func test_decode_speakerNamesPresentOrMissing_decodesOptionally() throws {
        let base = """
            "title": "T", "executive_summary": "E", "decisions": [], "action_items": []
            """
        let withNames = try JSONDecoder().decode(
            SummaryResponse.self,
            from: Data("{\(base), \"speaker_names\": {\"speaker_1\": \"John\"}}".utf8)
        )
        let without = try JSONDecoder().decode(SummaryResponse.self, from: Data("{\(base)}".utf8))

        XCTAssertEqual(withNames.speakerNames, ["speaker_1": "John"])
        XCTAssertNil(without.speakerNames)
    }

    func test_systemPrompt_schema_requestsSpeakerNames() {
        XCTAssertTrue(SummaryPromptTemplate.systemPrompt.contains("\"speaker_names\""))
    }
}
