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

/// Everything the History chart header reports about the period the chart is
/// currently scrolled to. Derived from the calendar, so a 28-day February and a
/// 31-day August each describe their own true length.
public struct ActivitySummary: Sendable, Equatable {
    /// First bucket of the window (start-of-day, or start-of-month for `.year`).
    public let start: Date
    /// Number of buckets in the window — 28 for February, 31 for August, 12 for a year.
    public let barCount: Int
    public let expense: Decimal
    public let income: Decimal
    /// Change in expense against the immediately preceding period, or `nil`
    /// when that period had no spending to compare against.
    public let changeRatio: Decimal?

    /// Direction of travel against the prior period, for the header sentence.
    public enum Trend: Sendable, Equatable {
        case up, down, flat
        /// No prior spending to compare against — the header drops the clause
        /// rather than claiming a rise from nothing.
        case unknown
    }

    public var trend: Trend {
        guard let r = changeRatio else { return .unknown }
        if r > 0 { return .up }
        if r < 0 { return .down }
        return .flat
    }

    /// Magnitude of the change as a whole percent — 8 for both −8% and +8%.
    /// `trend` carries the direction. `nil` when there is nothing to compare.
    public var changePercent: Int? {
        guard let r = changeRatio else { return nil }
        let magnitude = (r < 0 ? -r : r) * 100
        return Int((magnitude as NSDecimalNumber).doubleValue.rounded())
    }

    /// True when the window holds no activity of any kind. Distinct from a
    /// no-spend day, which is a real day that happened to cost nothing — this is
    /// a stretch of timeline with nothing in it, and says so on the chart.
    public var isEmpty: Bool { expense == 0 && income == 0 }
}

/// How a single bucket's spending sits against its budget allowance. Drives the
/// bar colour, so a glance at the chart shows which days went over.
public enum SpendLevel: Sendable, Equatable {
    case under, near, over
    /// No budget configured — the bar takes a neutral tint rather than implying
    /// the user did well or badly.
    case unknown
}

/// Buckets transactions into spend/income bars for the History charts and the
/// calendar heat grid. No presentation here — the view renders these with Charts.
public enum ActivitySeries {

    /// Fraction of the allowance at which a bucket stops being comfortably under.
    private static let nearThreshold = Decimal(string: "0.8")!

    /// The budget one bar is measured against. Bars are days in week and month
    /// scope, so the monthly budget is divided by that month's own length — using
    /// a flat 30 would misjudge February and every 31-day month. In year scope a
    /// bar is a whole month, so the monthly budget applies as-is.
    public static func allowancePerBucket(monthlyBudgetTotal: Decimal, period: ActivityPeriod, daysInMonth: Int) -> Decimal {
        switch period {
        case .week, .month:
            guard daysInMonth > 0 else { return 0 }
            return monthlyBudgetTotal / Decimal(daysInMonth)
        case .year:
            return monthlyBudgetTotal
        }
    }

    /// Classifies one bucket's spend against its allowance for colouring.
    /// Spending exactly the allowance counts as `.near`, not `.over` — hitting the
    /// target precisely should not be flagged as a failure.
    public static func spendLevel(expense: Decimal, allowance: Decimal) -> SpendLevel {
        guard allowance > 0 else { return .unknown }
        if expense > allowance { return .over }
        if expense >= allowance * nearThreshold { return .near }
        return .under
    }

    /// Scale beyond which a pinch counts as a deliberate zoom rather than a wobble.
    /// Below it the rung is unchanged, so resting two fingers on the chart does
    /// nothing.
    private static let rungThreshold = 1.5

    /// The rung a pinch lands on when the fingers lift.
    ///
    /// `scale` is the live magnification: greater than 1 means the fingers spread
    /// (zoom in, less time in more detail), less than 1 means they pinched
    /// together. Movement inside the threshold keeps the current rung, and the
    /// ladder clamps at both ends rather than wrapping.
    public static func rung(forScale scale: Double, from current: ActivityPeriod) -> ActivityPeriod {
        let ladder: [ActivityPeriod] = [.week, .month, .year]   // in → out
        guard let index = ladder.firstIndex(of: current) else { return current }
        let step: Int
        if scale >= rungThreshold {
            step = -1                       // zoom in, toward .week
        } else if scale <= 1 / rungThreshold {
            step = 1                        // zoom out, toward .year
        } else {
            step = 0
        }
        let target = min(max(index + step, 0), ladder.count - 1)
        return ladder[target]
    }

    /// Totals and period-over-period change for the window containing `date`.
    /// The chart's scroll position supplies `date`, so the header always describes
    /// what is on screen rather than today.
    public static func summary(_ txns: [TxnRow], period: ActivityPeriod, containing date: Date, calendar: Calendar) -> ActivitySummary {
        let window = bars(txns, period: period, now: date, calendar: calendar)
        let prior = barsPrior(txns, period: period, now: date, calendar: calendar)
        let expense = window.reduce(Decimal(0)) { $0 + $1.expense }
        let priorExpense = prior.reduce(Decimal(0)) { $0 + $1.expense }
        return ActivitySummary(
            start: window.first?.date ?? calendar.startOfDay(for: date),
            barCount: window.count,
            expense: expense,
            income: window.reduce(Decimal(0)) { $0 + $1.income },
            changeRatio: changeRatio(current: expense, prior: priorExpense)
        )
    }

    /// Bars for the period containing `now`:
    /// - `.week`: 7 daily bars (the calendar week containing `now`)
    /// - `.month`: one daily bar per day of `now`'s calendar month
    /// - `.year`: 12 monthly bars for `now`'s calendar year
    /// Empty buckets are included (as zero bars) so the axis is continuous.
    public static func bars(_ txns: [TxnRow], period: ActivityPeriod, now: Date, calendar: Calendar) -> [ActivityBar] {
        switch period {
        case .week:
            let start = sundayFirst(calendar).dateInterval(of: .weekOfYear, for: now)!.start
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

    /// Fractional change from `prior` to `current` — `-0.08` means 8% lower.
    /// Drives the chart header's "…is down 8%, totalling ₹8,450." sentence.
    ///
    /// `nil` when `prior` is zero: there is no percentage change from nothing, and
    /// `Decimal` division by zero yields NaN rather than trapping, so the caller
    /// must fall back to a plain total instead of rendering a bogus figure.
    public static func changeRatio(current: Decimal, prior: Decimal) -> Decimal? {
        guard prior != 0 else { return nil }
        return (current - prior) / prior
    }

    /// One continuous run of bars spanning every period that holds data, for the
    /// horizontally scrollable History chart. Unlike `bars(_:period:now:)` — which
    /// returns a single window — this covers the whole timeline so the chart can be
    /// scrolled through it, with empty buckets filled in so gaps stay visible.
    ///
    /// With no transactions there is no range to derive, so the result is exactly the
    /// period containing `now`.
    public static func continuousBars(_ txns: [TxnRow], period: ActivityPeriod, now: Date, calendar: Calendar, maxBuckets: Int = 800) -> [ActivityBar] {
        let dates = txns.map(\.date)
        // `now` is always inside the domain, so the chart can land on the current
        // period even when the newest transaction is months old (or entirely in the future).
        let earliest = min(dates.min() ?? now, now)
        let latest = max(dates.max() ?? now, now)

        let unit: Calendar.Component
        switch period {
        case .week:  unit = .weekOfYear
        case .month: unit = .month
        case .year:  unit = .year
        }
        // Round out to whole periods so the scroll always snaps to a period boundary.
        let bounding = sundayFirst(calendar)
        let start = bounding.dateInterval(of: unit, for: earliest)!.start
        let end = bounding.dateInterval(of: unit, for: latest)!.end

        // Cap the series so a multi-year ledger does not become one bucket per day
        // across the whole range. The window keeps its most recent end — that is
        // where the chart opens — and drops the oldest buckets beyond the cap.
        let bucket: Calendar.Component = (period == .year) ? .month : .day
        let available = calendar.dateComponents([bucket], from: start, to: end).value(for: bucket) ?? 0
        let clampedStart = available > maxBuckets
            ? calendar.date(byAdding: bucket, value: -maxBuckets, to: end)!
            : start

        switch period {
        case .week, .month:
            let days = calendar.dateComponents([.day], from: clampedStart, to: end).day!
            return dailyBars(txns, from: clampedStart, days: days, calendar: calendar)
        case .year:
            let months = calendar.dateComponents([.month], from: clampedStart, to: end).month!
            return monthlyBars(txns, from: clampedStart, months: months, calendar: calendar)
        }
    }

    // MARK: - Private

    /// Kharcha always runs Sunday→Saturday weeks, whatever the device locale's
    /// `firstWeekday` says, so week buckets stay stable across regions and travel.
    private static func sundayFirst(_ calendar: Calendar) -> Calendar {
        var c = calendar
        c.firstWeekday = 1
        return c
    }

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
