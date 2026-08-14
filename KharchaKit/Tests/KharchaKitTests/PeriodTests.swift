import Testing
import Foundation
@testable import KharchaKit

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.firstWeekday = 2 // Monday
    return c
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(timeZone: cal.timeZone, year: y, month: m, day: d, hour: h))!
}

@Test func todayRangeCoversMidnightToMidnight() {
    let range = Period.today.dateRange(now: date(2026, 8, 14, 15), calendar: cal)
    #expect(range.lowerBound == date(2026, 8, 14, 0))
    #expect(range.upperBound == date(2026, 8, 15, 0))
}

@Test func weekRangeStartsMonday() {
    // 2026-08-14 is a Friday; week = Mon 08-10 ..< Mon 08-17
    let range = Period.week.dateRange(now: date(2026, 8, 14), calendar: cal)
    #expect(range.lowerBound == date(2026, 8, 10, 0))
    #expect(range.upperBound == date(2026, 8, 17, 0))
}

@Test func monthRangeCoversWholeMonth() {
    let range = Period.month.dateRange(now: date(2026, 8, 14), calendar: cal)
    #expect(range.lowerBound == date(2026, 8, 1, 0))
    #expect(range.upperBound == date(2026, 9, 1, 0))
}
