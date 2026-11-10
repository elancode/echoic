import Foundation

extension Date {
    /// Formats the date for display in meeting cards (e.g., "Mar 22, 2026 at 2:30 PM").
    var meetingDisplayString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Formats a duration in milliseconds to a human-readable string (e.g., "1h 23m").
    static func formatDuration(ms: Int64) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    /// Formats a transcript offset in milliseconds as `[HH:MM:SS]` (e.g., "[00:01:05]").
    static func formatTimestamp(ms: Int64) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "[%02d:%02d:%02d]", hours, minutes, seconds)
    }
}
