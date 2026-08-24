import Testing
import Foundation
@testable import KharchaKit

struct PayCyclePlanTests {
    /// UTC Gregorian calendar so the date arithmetic is deterministic across machines.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func paydayClampsToShortMonth() {
        // Asking for the 31st in February lands on the last real day.
        let payday = PayCyclePlanner.payday(inMonthOf: date(2026, 2, 10), day: 31, calendar: cal)
        #expect(payday == date(2026, 2, 28))
    }

    @Test func cycleBeforeThisMonthsPayday() {
        // Payday is the 25th, today is the 2nd → cycle started last month's 25th.
        let c = PayCyclePlanner.cycle(now: date(2026, 3, 2), dayOfMonth: 25, calendar: cal)
        #expect(c.start == date(2026, 2, 25))
        #expect(c.next == date(2026, 3, 25))
        #expect(c.daysUntilNext == 23)
    }

    @Test func cycleAfterThisMonthsPayday() {
        // Payday is the 5th, today is the 20th → cycle started this month's 5th.
        let c = PayCyclePlanner.cycle(now: date(2026, 3, 20), dayOfMonth: 5, calendar: cal)
        #expect(c.start == date(2026, 3, 5))
        #expect(c.next == date(2026, 4, 5))
        #expect(c.daysUntilNext == 16)
    }

    @Test func safeToSpendPerDay() {
        let plan = PayCyclePlanner.plan(
            now: date(2026, 3, 20), dayOfMonth: 5,
            salary: 30_000, spentThisCycle: 6_000, calendar: cal
        )
        #expect(plan.remaining == 24_000)
        #expect(plan.daysUntilPayday == 16)
        #expect(plan.safeToSpendPerDay == 1_500)  // 24000 / 16
        #expect(plan.isOverspent == false)
    }

    @Test func overspentFloorsRemainingAtZero() {
        let plan = PayCyclePlanner.plan(
            now: date(2026, 3, 20), dayOfMonth: 5,
            salary: 30_000, spentThisCycle: 35_000, calendar: cal
        )
        #expect(plan.remaining == 0)
        #expect(plan.isOverspent == true)
        #expect(plan.safeToSpendPerDay == 0)
    }
}
