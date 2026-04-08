import Foundation
import GRDB

/// Manages the SQLite database and migrations.
final class DatabaseManager {
    static let shared = DatabaseManager()

    private(set) var dbPool: DatabasePool?

    private init() {}

    /// Opens (or creates) the database at the standard application support location.
    func setup() throws {
        let url = try databaseURL()
        let directory = url.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbPool = try DatabasePool(path: url.path, configuration: config)

        try runMigrations()
    }

    /// Opens a database at a custom path (used for testing).
    func setup(at path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true

        dbPool = try DatabasePool(path: path, configuration: config)

        try runMigrations()
    }

    /// Opens an in-memory database (used for testing).
    func setupInMemory() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true

        let queue = try DatabaseQueue(configuration: config)
        // For in-memory testing, use DatabaseQueue directly
        // We store it as a DatabaseWriter
        try migrate(queue)
        // Store a reference for testing
        _inMemoryQueue = queue
    }

    private var _inMemoryQueue: DatabaseQueue?

    /// Returns the appropriate database writer.
    var databaseWriter: (any DatabaseWriter)? {
        dbPool ?? _inMemoryQueue
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        guard let dbPool else { return }
        try migrate(dbPool)
    }

    private func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        // GRDB migrations are append-only (Critical Rule #7)
        migrator.registerMigration("v1") { db in
            // meeting table
            try db.create(table: "meeting") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("startedAt", .integer).notNull()
                t.column("endedAt", .integer)
                t.column("durationMs", .integer)
                t.column("audioPath", .text)
                t.column("status", .text).notNull().defaults(to: "recording")
            }

            // transcriptSegment table
            try db.create(table: "transcriptSegment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .text)
                    .notNull()
                    .references("meeting", onDelete: .cascade)
                t.column("startMs", .integer).notNull()
                t.column("endMs", .integer).notNull()
                t.column("speakerId", .text)
                t.column("text", .text).notNull()
                t.column("confidence", .double)
            }

            // transcriptFts — FTS5 virtual table with Porter tokenizer
            try db.execute(sql: """
                CREATE VIRTUAL TABLE transcriptFts USING fts5(
                    text,
                    content='transcriptSegment',
                    content_rowid='id',
                    tokenize='porter'
                )
                """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER transcriptSegment_ai AFTER INSERT ON transcriptSegment BEGIN
                    INSERT INTO transcriptFts(rowid, text) VALUES (new.id, new.text);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER transcriptSegment_ad AFTER DELETE ON transcriptSegment BEGIN
                    INSERT INTO transcriptFts(transcriptFts, rowid, text) VALUES('delete', old.id, old.text);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER transcriptSegment_au AFTER UPDATE ON transcriptSegment BEGIN
                    INSERT INTO transcriptFts(transcriptFts, rowid, text) VALUES('delete', old.id, old.text);
                    INSERT INTO transcriptFts(rowid, text) VALUES (new.id, new.text);
                END
                """)

            // summary table
            try db.create(table: "summary") { t in
                t.column("meetingId", .text).primaryKey()
                    .references("meeting", onDelete: .cascade)
                t.column("rawJson", .text).notNull()
                t.column("executiveSummary", .text)
                t.column("title", .text)
                t.column("createdAt", .integer).notNull()
            }

            // meetingSpeaker table
            try db.create(table: "meetingSpeaker") { t in
                t.column("meetingId", .text)
                    .notNull()
                    .references("meeting", onDelete: .cascade)
                t.column("speakerId", .text).notNull()
                t.column("label", .text).notNull()
                t.primaryKey(["meetingId", "speakerId"])
            }
        }

        migrator.registerMigration("v2_processed_flag") { db in
            try db.alter(table: "meeting") { t in
                t.add(column: "processed", .boolean).notNull().defaults(to: false)
            }
            // Mark all existing "ready" meetings as processed
            try db.execute(sql: "UPDATE meeting SET processed = 1 WHERE status = 'ready'")
        }

        try migrator.migrate(writer)
    }

    // MARK: - Paths

    private func databaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Echoic", isDirectory: true)
            .appendingPathComponent("echoic.db")
    }
}
