import Testing
import Foundation
@testable import KharchaKit

@Test func todayRangeCoversMidnightToMidnight() {
    let range = Period.today.dateRange(now: d(2026, 8, 14, 15), calendar: testCal)
    #expect(range.lowerBound == d(2026, 8, 14, 0))
    #expect(range.upperBound == d(2026, 8, 15, 0))
}

@Test func weekRangeStartsMonday() {
    // 2026-08-14 is a Friday; week = Mon 08-10 ..< Mon 08-17
    let range = Period.week.dateRange(now: d(2026, 8, 14), calendar: testCal)
    #expect(range.lowerBound == d(2026, 8, 10, 0))
    #expect(range.upperBound == d(2026, 8, 17, 0))
}

@Test func monthRangeCoversWholeMonth() {
    let range = Period.month.dateRange(now: d(2026, 8, 14), calendar: testCal)
    #expect(range.lowerBound == d(2026, 8, 1, 0))
    #expect(range.upperBound == d(2026, 9, 1, 0))
}
