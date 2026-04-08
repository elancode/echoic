import SwiftUI
import os.log

private let appLogger = Logger(subsystem: "com.echoic.app", category: "App")

@main
struct EchoicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingComplete")

    init() {
        // Initialize database on launch
        try? DatabaseManager.shared.setup()

        // Clean up stale data from previous crashes/restarts
        if let db = DatabaseManager.shared.databaseWriter {
            // Get empty meeting IDs before deleting so we can remove their audio files
            let emptyMeetingIds: [String] = (try? db.read { dbConn in
                try String.fetchAll(dbConn, sql: """
                    SELECT id FROM meeting WHERE id NOT IN (
                        SELECT DISTINCT meetingId FROM transcriptSegment
                    )
                    """)
            }) ?? []

            for meetingId in emptyMeetingIds {
                try? AudioFileManager.deleteMeetingFiles(meetingId: meetingId)
            }

            try? db.write { dbConn in
                // Delete empty meetings (no transcript segments)
                if !emptyMeetingIds.isEmpty {
                    try dbConn.execute(sql: """
                        DELETE FROM meeting WHERE id NOT IN (
                            SELECT DISTINCT meetingId FROM transcriptSegment
                        )
                        """)
                }

                // Recover stale "recording" meetings from crashes/lid-close.
                // Meetings with transcript segments are recoverable — mark them
                // as "processing" so PostProcessingService picks them up.
                // Meetings with no segments are truly empty — mark as "error".
                let staleRecordingIds = try String.fetchAll(dbConn, sql:
                    "SELECT id FROM meeting WHERE status = 'recording'"
                )
                for meetingId in staleRecordingIds {
                    let segmentCount = try Int.fetchOne(dbConn, sql:
                        "SELECT COUNT(*) FROM transcriptSegment WHERE meetingId = ?",
                        arguments: [meetingId]
                    ) ?? 0

                    if segmentCount > 0 {
                        // Has transcript data — recover it
                        let lastEndMs = try Int64.fetchOne(dbConn, sql:
                            "SELECT MAX(endMs) FROM transcriptSegment WHERE meetingId = ?",
                            arguments: [meetingId]
                        )
                        let startedAt = try Int64.fetchOne(dbConn, sql:
                            "SELECT startedAt FROM meeting WHERE id = ?",
                            arguments: [meetingId]
                        ) ?? 0

                        let endedAt = lastEndMs.map { startedAt + $0 }
                            ?? Int64(Date().timeIntervalSince1970 * 1000)
                        let durationMs = endedAt - startedAt

                        try dbConn.execute(sql: """
                            UPDATE meeting
                            SET status = 'processing', endedAt = ?, durationMs = ?
                            WHERE id = ?
                            """, arguments: [endedAt, durationMs, meetingId])
                        appLogger.info("Recovering stale recording \(meetingId) with \(segmentCount) segments")
                    } else {
                        try dbConn.execute(sql:
                            "UPDATE meeting SET status = 'error' WHERE id = ?",
                            arguments: [meetingId]
                        )
                    }
                }
            }

            // Resume post-processing for any unfinished meetings
            Task {
                await PostProcessingService.resumeUnfinished(databaseWriter: db)
            }
        }
    }

    var body: some Scene {
        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 500, height: 350)

        Window("Meeting Library", id: "library") {
            MeetingLibraryView()
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView()
                }
        }

        MenuBarExtra {
            MenuBarPopoverView()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "waveform")
                if coordinator.state == .recording {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                        .offset(x: 3, y: -3)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
