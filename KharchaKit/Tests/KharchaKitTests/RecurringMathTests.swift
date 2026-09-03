import Testing
import Foundation
@testable import KharchaKit

@Test func nextDueLaterThisMonth() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 25, after: d(2026, 8, 14), calendar: testCal)
    #expect(due == d(2026, 8, 25, 0))
}

@Test func nextDueRollsToNextMonthWhenPassed() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 10, after: d(2026, 8, 14), calendar: testCal)
    #expect(due == d(2026, 9, 10, 0))
}

@Test func nextDueOnSameDayRollsForward() {
    // "after" is strict: on the 25th at noon, day-25 rule points at next month
    let due = RecurringMath.nextDueDate(dayOfMonth: 25, after: d(2026, 8, 25), calendar: testCal)
    #expect(due == d(2026, 9, 25, 0))
}

@Test func day31ClampsToShortMonths() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 31, after: d(2026, 9, 1), calendar: testCal)
    #expect(due == d(2026, 9, 30, 0))
}

@Test func day31ClampsToFebruary() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 31, after: d(2027, 2, 1), calendar: testCal)
    #expect(due == d(2027, 2, 28, 0))
}

@Test func day31ClampsToLeapFebruary() {
    let due = RecurringMath.nextDueDate(dayOfMonth: 31, after: d(2028, 2, 1), calendar: testCal)
    #expect(due == d(2028, 2, 29, 0))
}

@Test func reminderDateSubtractsDays() {
    let reminder = RecurringMath.reminderDate(for: d(2026, 8, 25, 0), daysBefore: 3, calendar: testCal)
    #expect(reminder == d(2026, 8, 22, 0))
}

@Test func dayOfMonthZeroClampsToFirstOfMonthNotPreviousMonth() {
    // dayOfMonth 0 is bogus input; it must still clamp to a valid day (>= 1)
    // rather than underflowing into the previous month.
    let due = RecurringMath.nextDueDate(dayOfMonth: 0, after: d(2026, 8, 31), calendar: testCal)
    #expect(due > d(2026, 8, 31))
    #expect(due == d(2026, 9, 1, 0))
}
