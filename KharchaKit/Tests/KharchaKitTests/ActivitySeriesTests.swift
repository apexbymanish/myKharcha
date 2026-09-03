import Testing
import Foundation
@testable import KharchaKit

private func row(_ amount: Decimal, _ kind: TxnKind, _ date: Date) -> TxnRow {
    TxnRow(id: UUID(), date: date, kind: kind, amount: amount, categoryName: "", note: nil, source: .manual)
}

@Test func monthBarsBucketByDay() {
    let txns = [
        row(100, .expense, d(2026, 8, 3)),
        row(500, .income, d(2026, 8, 3)),
        row(50, .expense, d(2026, 8, 10)),
        row(9999, .expense, d(2026, 9, 1))   // different month → excluded
    ]
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    let totalExpense = bars.reduce(Decimal(0)) { $0 + $1.expense }
    #expect(bars.count == 31)          // August has 31 days
    #expect(bars[2].expense == 100)    // Aug 3 → index 2
    #expect(bars[2].income == 500)
    #expect(bars[9].expense == 50)     // Aug 10 → index 9
    #expect(totalExpense == 150)       // Sept txn not counted
}

@Test func yearBarsBucketByMonth() {
    let txns = [
        row(100, .expense, d(2026, 3, 10)),
        row(200, .income, d(2026, 3, 20)),
        row(70, .expense, d(2026, 12, 25))
    ]
    let bars = ActivitySeries.bars(txns, period: .year, now: d(2026, 8, 1), calendar: testCal)
    #expect(bars.count == 12)
    #expect(bars[2].expense == 100)    // March → index 2
    #expect(bars[2].income == 200)
    #expect(bars[11].expense == 70)    // December → index 11
}

@Test func weekBarsHaveSevenDaysAndPlaceToday() {
    let now = d(2026, 8, 5)
    let bars = ActivitySeries.bars([row(300, .expense, now), row(1000, .income, now)],
                                   period: .week, now: now, calendar: testCal)
    let today = testCal.startOfDay(for: now)
    let todayBar = bars.first { $0.date == today }
    #expect(bars.count == 7)
    #expect(todayBar?.expense == 300)
    #expect(todayBar?.income == 1000)
    #expect(todayBar?.net == 700)
}

@Test func emptyBucketsAreZeroNotMissing() {
    let bars = ActivitySeries.bars([], period: .week, now: d(2026, 8, 5), calendar: testCal)
    let allZero = bars.allSatisfy(\.isEmpty)
    #expect(bars.count == 7)
    #expect(allZero)
}

@Test func weekBarsAlwaysStartOnSundayEvenWhenTheCalendarSaysMonday() {
    // Kharcha always runs Sunday→Saturday weeks. testCal is deliberately
    // Monday-first (firstWeekday = 2), standing in for a device in a
    // Monday-first locale — the bars must ignore that and start on Sunday.
    let bars = ActivitySeries.bars([], period: .week, now: d(2026, 8, 5), calendar: testCal)
    let firstWeekday = testCal.component(.weekday, from: bars[0].date)
    let lastWeekday = testCal.component(.weekday, from: bars[6].date)
    #expect(bars.count == 7)
    #expect(firstWeekday == 1)   // 1 == Sunday
    #expect(lastWeekday == 7)    // 7 == Saturday
}

// MARK: - Period-over-period change (chart header sentence)

@Test func changeRatioIsNegativeWhenSpendingFell() {
    // Drives "Spending in August 2026 is down 8%…" in the chart header.
    let ratio = ActivitySeries.changeRatio(current: 9_200, prior: 10_000)
    #expect(ratio == Decimal(string: "-0.08"))
}

@Test func changeRatioIsNilWhenPriorPeriodHadNothingToCompareAgainst() {
    // A user's first-ever month has no prior spend. There is no meaningful
    // percentage against zero, so the header must fall back to a plain total
    // rather than render "up ∞%" or crash on a NaN.
    #expect(ActivitySeries.changeRatio(current: 9_200, prior: 0) == nil)
}

// MARK: - Window summary (what the scrolled-to period reports)

@Test func summaryReportsTotalsAndChangeForTheScrolledToMonth() {
    // The header reads off whichever window the chart is scrolled to — not `now`.
    let txns = [
        row(9_200, .expense, d(2026, 8, 10)),
        row(50_000, .income, d(2026, 8, 25)),
        row(10_000, .expense, d(2026, 7, 10))   // prior month, drives the delta
    ]
    let s = ActivitySeries.summary(txns, period: .month,
                                   containing: d(2026, 8, 15), calendar: testCal)
    #expect(s.expense == 9_200)
    #expect(s.income == 50_000)
    #expect(s.changeRatio == Decimal(string: "-0.08"))
    #expect(s.start == testCal.startOfDay(for: d(2026, 8, 1)))
}

@Test func summaryWindowLengthFollowsTheCalendarMonthNotAFixedSpan() {
    // February is 28 days and August is 31. A fixed-length window would smear
    // one into the next; the window must be derived from the calendar.
    let feb = ActivitySeries.summary([], period: .month,
                                     containing: d(2026, 2, 15), calendar: testCal)
    let aug = ActivitySeries.summary([], period: .month,
                                     containing: d(2026, 8, 15), calendar: testCal)
    #expect(feb.barCount == 28)   // 2026 is not a leap year
    #expect(aug.barCount == 31)
}

// MARK: - Headline trend (the "is down 8%" half of the header sentence)

@Test func summaryTrendReadsDownAndRoundsToWholePercent() {
    let txns = [
        row(9_200, .expense, d(2026, 8, 10)),
        row(10_000, .expense, d(2026, 7, 10))
    ]
    let s = ActivitySeries.summary(txns, period: .month,
                                   containing: d(2026, 8, 15), calendar: testCal)
    #expect(s.trend == .down)
    #expect(s.changePercent == 8)
}

@Test func summaryTrendIsUnknownWithNoPriorPeriodToCompareAgainst() {
    // First-ever month: the header must drop the comparison clause entirely
    // rather than claim a rise from nothing.
    let s = ActivitySeries.summary([row(9_200, .expense, d(2026, 8, 10))],
                                   period: .month,
                                   containing: d(2026, 8, 15), calendar: testCal)
    #expect(s.trend == .unknown)
    #expect(s.changePercent == nil)
}

@Test func summaryTrendIsFlatWhenSpendingIsUnchanged() {
    let txns = [
        row(5_000, .expense, d(2026, 8, 10)),
        row(5_000, .expense, d(2026, 7, 10))
    ]
    let s = ActivitySeries.summary(txns, period: .month,
                                   containing: d(2026, 8, 15), calendar: testCal)
    #expect(s.trend == .flat)
    #expect(s.changePercent == 0)
}

// MARK: - Bar colour against budget

@Test func spendLevelClassifiesABarAgainstItsAllowance() {
    // Drives the teal / amber / red bar colours, the way Pedometer++ colours a
    // day by whether the step goal was met.
    #expect(ActivitySeries.spendLevel(expense: 30_000, allowance: 60_000) == .under)
    #expect(ActivitySeries.spendLevel(expense: 55_000, allowance: 60_000) == .near)
    #expect(ActivitySeries.spendLevel(expense: 70_000, allowance: 60_000) == .over)
}

@Test func spendLevelTreatsExactlyOnBudgetAsNearNotOver() {
    // Spending precisely the allowance has not exceeded it — colouring it red
    // would punish the user for hitting the target exactly.
    #expect(ActivitySeries.spendLevel(expense: 60_000, allowance: 60_000) == .near)
}

@Test func spendLevelIsUnknownWithoutABudgetToCompareAgainst() {
    // No budgets configured — bars fall back to a neutral tint rather than
    // implying the user did well or badly.
    #expect(ActivitySeries.spendLevel(expense: 60_000, allowance: 0) == .unknown)
}

@Test func allowancePerBucketSpreadsTheMonthlyBudgetAcrossDays() {
    // Bars are days in week/month scope, so a monthly budget has to be divided
    // by the length of the month it belongs to — not a flat 30.
    let daily = ActivitySeries.allowancePerBucket(monthlyBudgetTotal: 1_860_000,
                                                 period: .month, daysInMonth: 31)
    #expect(daily == 60_000)
}

@Test func allowancePerBucketUsesTheWholeMonthlyBudgetForYearScope() {
    // In year scope one bar is a whole month, so the allowance is the monthly
    // budget itself rather than a daily slice of it.
    let monthly = ActivitySeries.allowancePerBucket(monthlyBudgetTotal: 1_860_000,
                                                    period: .year, daysInMonth: 31)
    #expect(monthly == 1_860_000)
}

// MARK: - Continuous series (scrollable chart)

@Test func continuousMonthBarsWithNoTransactionsCoverOnlyCurrentMonth() {
    // With no data there is no range to derive, so the scrollable domain
    // falls back to exactly the period containing `now` — never empty,
    // or the chart would have nothing to lay out against.
    let bars = ActivitySeries.continuousBars([], period: .month,
                                             now: d(2026, 8, 15), calendar: testCal)
    let allZero = bars.allSatisfy(\.isEmpty)
    #expect(bars.count == 31)
    #expect(allZero)
    #expect(bars.first?.date == testCal.startOfDay(for: d(2026, 8, 1)))
}

@Test func continuousMonthBarsSpanGapsBetweenDistantTransactions() {
    // Data in January and December only. The scrollable chart must still be able
    // to reach the empty months between them, so the series runs unbroken from the
    // start of the first month with data to the end of the last.
    let txns = [
        row(100, .expense, d(2026, 1, 5)),
        row(70, .expense, d(2026, 12, 25))
    ]
    let bars = ActivitySeries.continuousBars(txns, period: .month,
                                             now: d(2026, 1, 5), calendar: testCal)
    let june = bars.first { $0.date == testCal.startOfDay(for: d(2026, 6, 15)) }
    #expect(bars.first?.date == testCal.startOfDay(for: d(2026, 1, 1)))
    #expect(bars.last?.date == testCal.startOfDay(for: d(2026, 12, 31)))
    #expect(bars.count == 365)          // 2026 is not a leap year
    #expect(june?.isEmpty == true)      // gap months present, not skipped
}

@Test func continuousMonthBarsAlwaysReachTheCurrentPeriod() {
    // Nothing logged since January, but the chart still opens on "now". If the
    // series stopped at the last transaction the current month would be
    // unreachable by scrolling and the chart would have nowhere to land.
    let txns = [row(100, .expense, d(2026, 1, 5))]
    let bars = ActivitySeries.continuousBars(txns, period: .month,
                                             now: d(2026, 8, 15), calendar: testCal)
    #expect(bars.first?.date == testCal.startOfDay(for: d(2026, 1, 1)))
    #expect(bars.last?.date == testCal.startOfDay(for: d(2026, 8, 31)))
}

@Test func continuousWeekBarsAlsoStartOnSunday() {
    // The scrollable week series must snap to the same Sunday boundaries as
    // `bars(_:period:.week:)`, or paging would land mid-week.
    let txns = [row(100, .expense, d(2026, 8, 5))]
    let bars = ActivitySeries.continuousBars(txns, period: .week,
                                             now: d(2026, 8, 5), calendar: testCal)
    let firstWeekday = testCal.component(.weekday, from: bars[0].date)
    #expect(firstWeekday == 1)          // 1 == Sunday
    #expect(bars.count % 7 == 0)        // whole weeks only
}

@Test func continuousMonthBarsExtendToFutureDatedTransactions() {
    // Scheduled/installment rows can sit in the future; they must be reachable too.
    let txns = [row(100, .expense, d(2026, 8, 5)), row(250, .expense, d(2026, 11, 20))]
    let bars = ActivitySeries.continuousBars(txns, period: .month,
                                             now: d(2026, 8, 15), calendar: testCal)
    #expect(bars.last?.date == testCal.startOfDay(for: d(2026, 11, 30)))
}
