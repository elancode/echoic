import Foundation

/// A day group in the Library sidebar ("Today", "Yesterday", "Last week", "October 2026").
struct MeetingGroup: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let meetings: [Meeting]
}

enum MeetingGrouping {
    /// Groups meetings newest first: Today, Yesterday, Last week (2–7 days ago),
    /// then one group per calendar month.
    static func groups(for meetings: [Meeting], now: Date = Date(), calendar: Calendar = .current) -> [MeetingGroup] {
        let sorted = meetings.sorted { $0.startedAt > $1.startedAt }
        let today = calendar.startOfDay(for: now)
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "MMMM yyyy"

        var titles: [String] = []
        var buckets: [String: [Meeting]] = [:]
        for meeting in sorted {
            let date = Date(timeIntervalSince1970: Double(meeting.startedAt) / 1000)
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
            let title: String
            switch days {
            case ...0: title = "Today"
            case 1: title = "Yesterday"
            case 2...7: title = "Last week"
            default: title = monthFormatter.string(from: date)
            }
            if buckets[title] == nil { titles.append(title) }
            buckets[title, default: []].append(meeting)
        }
        return titles.map { MeetingGroup(title: $0, meetings: buckets[$0] ?? []) }
    }
}
