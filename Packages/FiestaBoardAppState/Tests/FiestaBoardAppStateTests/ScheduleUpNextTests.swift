import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

final class ScheduleUpNextTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c
    }()

    private func entry(_ id: String, _ page: String, _ start: String, pattern: String = "all", days: [String]? = nil,
                       enabled: Bool = true, resolved: String? = nil) throws -> ScheduleEntry {
        var object: [String: Any] = ["id": id, "page_id": page, "start_time": start, "day_pattern": pattern,
                                     "enabled": enabled, "recurrence_type": "weekly"]
        if let days { object["custom_days"] = days }
        if let resolved { object["resolved_start_time"] = resolved }
        return try JSONDecoder().decode(ScheduleEntry.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// Saturday 31 Oct 2026, 08:15 Pacific.
    private var saturdayMorning: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 8, minute: 15))! }

    func testPicksTheNextStartToday() throws {
        let entries = [try entry("a", "morning", "06:00"), try entry("b", "hello", "10:00"), try entry("c", "lower", "20:00")]
        let next = try XCTUnwrap(ScheduleUpNext.next(entries, now: saturdayMorning, calendar: calendar))
        XCTAssertEqual(next.pageID, "hello")
        XCTAssertEqual(next.daysAhead, 0)
        XCTAssertEqual(next.whenText(now: saturdayMorning, calendar: calendar), "today at 10:00 AM")
    }

    func testWrapsToTomorrowAndSkipsDisabledAndWrongDays() throws {
        let entries = [try entry("a", "morning", "06:00"), try entry("w", "work", "07:00", pattern: "weekdays"),
                       try entry("off", "off", "09:00", enabled: false)]
        let late = calendar.date(byAdding: .hour, value: 14, to: saturdayMorning)!  // 22:15 Saturday
        let next = try XCTUnwrap(ScheduleUpNext.next(entries, now: late, calendar: calendar))
        XCTAssertEqual(next.pageID, "morning")
        XCTAssertEqual(next.whenText(now: late, calendar: calendar), "tomorrow at 6:00 AM")
    }

    func testCustomDaysAndResolvedStartWin() throws {
        let entries = [try entry("m", "monday", "05:00", pattern: "custom", days: ["Monday"]),
                       try entry("sun", "sunset", "18:00", pattern: "weekends", resolved: "17:02")]
        let next = try XCTUnwrap(ScheduleUpNext.next(entries, now: saturdayMorning, calendar: calendar))
        XCTAssertEqual(next.pageID, "sunset")
        XCTAssertEqual(next.startTime, "17:02")
        let sundayNight = calendar.date(byAdding: .hour, value: 38, to: saturdayMorning)!  // Sunday 22:15
        let monday = try XCTUnwrap(ScheduleUpNext.next(entries, now: sundayNight, calendar: calendar))
        XCTAssertEqual(monday.pageID, "monday")
        XCTAssertEqual(monday.whenText(now: sundayNight, calendar: calendar), "tomorrow at 5:00 AM")
    }

    func testNothingScheduledIsNil() throws {
        XCTAssertNil(ScheduleUpNext.next([], now: saturdayMorning, calendar: calendar))
        XCTAssertNil(ScheduleUpNext.next([try entry("x", "p", "bogus")], now: saturdayMorning, calendar: calendar))
    }
}
