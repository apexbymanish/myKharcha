import Foundation

/// A snapshot of the user's current pay cycle, used by Home to show how many days
/// remain until payday and how much is safe to spend per day. Pure value type —
/// all monetary decisions live here so they can be unit-tested without a store.
public struct PayCyclePlan: Sendable, Equatable {
    /// The user's declared monthly salary (the money available for the cycle).
    public let salary: Decimal
    /// Expenses already logged within the current cycle (cycleStart ..< nextPayday).
    public let spentThisCycle: Decimal
    /// The most recent payday on or before "now" — the start of the current cycle.
    public let cycleStart: Date
    /// The next payday — the end of the current cycle.
    public let nextPayday: Date
    /// Whole days from the start of today until the next payday (never below 1, so
    /// the per-day figure stays finite on payday itself).
    public let daysUntilPayday: Int

    public init(salary: Decimal, spentThisCycle: Decimal, cycleStart: Date, nextPayday: Date, daysUntilPayday: Int) {
        self.salary = salary
        self.spentThisCycle = spentThisCycle
        self.cycleStart = cycleStart
        self.nextPayday = nextPayday
        self.daysUntilPayday = daysUntilPayday
    }

    /// Money left for the rest of the cycle, floored at zero (you can't "un-spend").
    public var remaining: Decimal { max(0, salary - spentThisCycle) }

    /// A steady daily allowance that spends the remaining balance exactly by payday.
    public var safeToSpendPerDay: Decimal {
        guard daysUntilPayday > 0 else { return remaining }
        return remaining / Decimal(daysUntilPayday)
    }

    /// True when the cycle's spending has already exceeded the salary.
    public var isOverspent: Bool { spentThisCycle > salary }
}

public enum PayCyclePlanner {
    /// The payday date within the calendar month containing `date`, clamping the
    /// requested day-of-month to the month's length (so "31" lands on Feb 28/29).
    public static func payday(inMonthOf date: Date, day: Int, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let firstOfMonth = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count
        let clampedDay = min(max(day, 1), daysInMonth)
        return calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: clampedDay))!
    }

    /// Resolve the current cycle boundaries relative to `now`. If this month's
    /// payday hasn't happened yet, the cycle started last month; otherwise it
    /// started this month and the next payday is next month.
    public static func cycle(now: Date, dayOfMonth: Int, calendar: Calendar) -> (start: Date, next: Date, daysUntilNext: Int) {
        let today = calendar.startOfDay(for: now)
        let thisMonthsPayday = payday(inMonthOf: today, day: dayOfMonth, calendar: calendar)

        let start: Date
        let next: Date
        if thisMonthsPayday <= today {
            start = thisMonthsPayday
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: today)!
            next = payday(inMonthOf: nextMonth, day: dayOfMonth, calendar: calendar)
        } else {
            let prevMonth = calendar.date(byAdding: .month, value: -1, to: today)!
            start = payday(inMonthOf: prevMonth, day: dayOfMonth, calendar: calendar)
            next = thisMonthsPayday
        }

        let days = max(1, calendar.dateComponents([.day], from: today, to: next).day ?? 1)
        return (start, next, days)
    }

    /// Build a plan given the money already spent this cycle (the caller sums it
    /// from the store over `cycleStart ..< nextPayday`).
    public static func plan(now: Date, dayOfMonth: Int, salary: Decimal, spentThisCycle: Decimal, calendar: Calendar) -> PayCyclePlan {
        let c = cycle(now: now, dayOfMonth: dayOfMonth, calendar: calendar)
        return PayCyclePlan(
            salary: salary,
            spentThisCycle: spentThisCycle,
            cycleStart: c.start,
            nextPayday: c.next,
            daysUntilPayday: c.daysUntilNext
        )
    }
}
