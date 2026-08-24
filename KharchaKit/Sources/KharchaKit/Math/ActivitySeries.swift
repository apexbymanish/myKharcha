import Foundation

/// The time window a History chart covers.
public enum ActivityPeriod: String, Sendable, CaseIterable {
    case week, month, year
}

/// One bucket of activity — a day (week/month periods) or a month (year period) —
/// with its expense and income totals. Pure value type; all bucketing is exact.
public struct ActivityBar: Sendable, Equatable, Identifiable {
    /// Bucket start: start-of-day for daily buckets, start-of-month for monthly.
    public let date: Date
    public let expense: Decimal
    public let income: Decimal

    public var id: Date { date }
    /// Income minus expense — positive means you netted money that bucket.
    public var net: Decimal { income - expense }
    public var isEmpty: Bool { expense == 0 && income == 0 }

    public init(date: Date, expense: Decimal, income: Decimal) {
        self.date = date
        self.expense = expense
        self.income = income
    }
}

/// Buckets transactions into spend/income bars for the History charts and the
/// calendar heat grid. No presentation here — the view renders these with Charts.
public enum ActivitySeries {

    /// Bars for the period containing `now`:
    /// - `.week`: 7 daily bars (the calendar week containing `now`)
    /// - `.month`: one daily bar per day of `now`'s calendar month
    /// - `.year`: 12 monthly bars for `now`'s calendar year
    /// Empty buckets are included (as zero bars) so the axis is continuous.
    public static func bars(_ txns: [TxnRow], period: ActivityPeriod, now: Date, calendar: Calendar) -> [ActivityBar] {
        switch period {
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            return dailyBars(txns, from: start, days: 7, calendar: calendar)
        case .month:
            let start = calendar.dateInterval(of: .month, for: now)!.start
            let days = calendar.range(of: .day, in: .month, for: now)!.count
            return dailyBars(txns, from: start, days: days, calendar: calendar)
        case .year:
            let start = calendar.dateInterval(of: .year, for: now)!.start
            return monthlyBars(txns, from: start, months: 12, calendar: calendar)
        }
    }

    /// Bars for the period immediately before the one containing `now` —
    /// same structure as `bars(_:period:now:calendar:)` but offset back by one period.
    /// Used by the History summary header to compute "vs prior" deltas.
    public static func barsPrior(_ txns: [TxnRow], period: ActivityPeriod, now: Date, calendar: Calendar) -> [ActivityBar] {
        let offset: Calendar.Component
        switch period {
        case .week:  offset = .weekOfYear
        case .month: offset = .month
        case .year:  offset = .year
        }
        let prior = calendar.date(byAdding: offset, value: -1, to: now)!
        return bars(txns, period: period, now: prior, calendar: calendar)
    }

    /// Daily bars for `now`'s calendar month — used by the calendar heat grid.
    public static func daysInMonth(_ txns: [TxnRow], monthOf now: Date, calendar: Calendar) -> [ActivityBar] {
        bars(txns, period: .month, now: now, calendar: calendar)
    }

    // MARK: - Private

    private static func dailyBars(_ txns: [TxnRow], from start: Date, days: Int, calendar: Calendar) -> [ActivityBar] {
        var byDay: [Date: (expense: Decimal, income: Decimal)] = [:]
        for t in txns {
            let key = calendar.startOfDay(for: t.date)
            var v = byDay[key] ?? (0, 0)
            if t.kind == .expense { v.expense += t.amount } else { v.income += t.amount }
            byDay[key] = v
        }
        return (0..<days).map { offset in
            let key = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: start)!)
            let v = byDay[key] ?? (0, 0)
            return ActivityBar(date: key, expense: v.expense, income: v.income)
        }
    }

    private static func monthlyBars(_ txns: [TxnRow], from start: Date, months: Int, calendar: Calendar) -> [ActivityBar] {
        var byMonth: [Date: (expense: Decimal, income: Decimal)] = [:]
        for t in txns {
            let key = calendar.dateInterval(of: .month, for: t.date)!.start
            var v = byMonth[key] ?? (0, 0)
            if t.kind == .expense { v.expense += t.amount } else { v.income += t.amount }
            byMonth[key] = v
        }
        return (0..<months).map { offset in
            let key = calendar.dateInterval(of: .month, for: calendar.date(byAdding: .month, value: offset, to: start)!)!.start
            let v = byMonth[key] ?? (0, 0)
            return ActivityBar(date: key, expense: v.expense, income: v.income)
        }
    }
}
