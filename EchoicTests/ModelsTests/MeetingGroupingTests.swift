import XCTest
@testable import Echoic

final class MeetingGroupingTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        // Wednesday 25 Nov 2026, 10:00 local
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 10))
    }

    private func meeting(_ id: String, daysAgo: Int, hour: Int = 9) -> Meeting {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now!
        let date = calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        var meeting = Meeting.create(title: id)
        meeting.id = id
        meeting.startedAt = Int64(date.timeIntervalSince1970 * 1000)
        return meeting
    }

    func test_groups_meetingsAcrossDays_labelsTodayYesterdayLastWeekAndMonth() {
        let meetings = [
            meeting("a", daysAgo: 0), meeting("b", daysAgo: 1),
            meeting("c", daysAgo: 4), meeting("d", daysAgo: 30),
        ]

        let groups = MeetingGrouping.groups(for: meetings, now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "Last week", "October 2026"])
        XCTAssertEqual(groups.map { $0.meetings.map(\.id) }, [["a"], ["b"], ["c"], ["d"]])
    }

    func test_groups_unsortedInput_keepsNewestFirstWithinGroup() {
        let meetings = [meeting("early", daysAgo: 0, hour: 8), meeting("late", daysAgo: 0, hour: 9)]

        let groups = MeetingGrouping.groups(for: meetings, now: now, calendar: calendar)

        XCTAssertEqual(groups.first?.meetings.map(\.id), ["late", "early"])
    }

    func test_groups_noMeetings_returnsEmpty() {
        XCTAssertTrue(MeetingGrouping.groups(for: [], now: now, calendar: calendar).isEmpty)
    }
}
