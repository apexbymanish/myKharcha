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

@Test func summaryKnowsWhenItsWindowHoldsNothingAtAll() {
    // Scrolling into an unused year must be able to say so, rather than showing
    // a blank plot the user has to interpret.
    let empty = ActivitySeries.summary([], period: .month,
                                       containing: d(2021, 3, 15), calendar: testCal)
    #expect(empty.isEmpty)
}

@Test func summaryIsNotEmptyWhenOnlyIncomeLandsInTheWindow() {
    // Income with no spending is still activity. Only a window with neither
    // counts as empty.
    let txns = [row(3_000_000, .income, d(2026, 8, 25))]
    let s = ActivitySeries.summary(txns, period: .month,
                                   containing: d(2026, 8, 15), calendar: testCal)
    #expect(!s.isEmpty)
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

@Test func continuousBarsAreCappedSoALongHistoryDoesNotBuildThousandsOfBuckets() throws {
    // A ledger spanning years must not turn into one ActivityBar per day across
    // the whole range on every reload. The cap keeps the series bounded; the
    // window stays anchored on `now`, which is where the chart opens.
    let txns = [
        row(100, .expense, d(2018, 1, 5)),
        row(100, .expense, d(2026, 8, 5))
    ]
    let bars = ActivitySeries.continuousBars(txns, period: .month,
                                             now: d(2026, 8, 15),
                                             calendar: testCal, maxBuckets: 100)
    #expect(bars.count <= 100)
    // The window still covers today, so the chart has somewhere to land.
    let last = try #require(bars.last).date
    #expect(last >= testCal.startOfDay(for: d(2026, 8, 1)))
}

// MARK: - Chart scale ceiling

@Test func chartCeilingIgnoresASingleOutlierSoOrdinaryDaysStayReadable() {
    // Rent at 20x a normal day would take the whole chart height and squash every
    // other bar to a stub. The ceiling comes from the 90th percentile instead, so
    // the outlier clips and the rest of the month is legible.
    let ordinary: [Decimal] = [12_000, 20_000, 18_000, 25_000, 15_000,
                               22_000, 19_000, 30_000, 17_000]
    let withRent = ordinary + [1_400_000]
    let ceiling = ActivitySeries.chartCeiling(withRent)
    #expect(ceiling < 100_000)          // nowhere near the outlier
    #expect(ceiling >= 30_000)          // still above every ordinary day
}

@Test func chartCeilingNearlyFillsTheFrameWhenNothingIsAnOutlier() {
    // Evenly-sized days have no outlier to protect against. The tallest bar must
    // not clip, and must not sit halfway up the frame either — it should nearly
    // fill it, with only enough headroom to keep it off the ceiling.
    let even: [Decimal] = [20_000, 22_000, 19_000, 21_000, 20_500]
    let ceiling = ActivitySeries.chartCeiling(even)
    #expect(ceiling >= 22_000)          // the tallest bar is not clipped
    #expect(ceiling <= 22_000 * 1.2)    // and it still reaches near the top
}

@Test func chartCeilingIsZeroForNoSpending() {
    #expect(ActivitySeries.chartCeiling([]) == 0)
}

// MARK: - Transaction count per bucket

@Test func barsCarryHowManyTransactionsMadeUpTheirTotal() {
    // A big bar raises one question: was that one purchase or fifteen? The count
    // rides on the bar so the answer is there without tapping.
    let txns = [
        row(50_000, .expense, d(2026, 8, 3)),
        row(30_000, .expense, d(2026, 8, 3)),
        row(20_000, .expense, d(2026, 8, 3)),
        row(90_000, .expense, d(2026, 8, 10))
    ]
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    #expect(bars[2].count == 3)    // Aug 3 — three purchases
    #expect(bars[9].count == 1)    // Aug 10 — one
    #expect(bars[0].count == 0)    // Aug 1 — nothing
}

@Test func barCountsIncludeIncomeNotJustSpending() {
    // The count describes the bucket's activity, not only its spending.
    let txns = [
        row(50_000, .expense, d(2026, 8, 3)),
        row(3_000_000, .income, d(2026, 8, 3))
    ]
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    #expect(bars[2].count == 2)
}

// MARK: - Category segments per bucket

@Test func barsSplitIntoCategorySegmentsLargestFirst() {
    // Stacked bars need to know what a day was spent on, biggest slice first so
    // the one that carries the label is the one at the bottom of the stack.
    let txns = [
        rowIn("Dining", 20_000, d(2026, 8, 3)),
        rowIn("Groceries", 60_000, d(2026, 8, 3)),
        rowIn("Groceries", 10_000, d(2026, 8, 3)),
        rowIn("Transport", 30_000, d(2026, 8, 3))
    ]
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    let segs = bars[2].segments
    #expect(segs.map(\.categoryName) == ["Groceries", "Transport", "Dining"])
    #expect(segs.first?.amount == 70_000)   // the two Groceries rows combined
}

@Test func tinySegmentsMergeIntoOtherSoTheBarIsNotConfetti() {
    // A ₩2,000 coffee inside a ₩200,000 day is a four-pixel band nobody can
    // identify. Anything under a twelfth of the day is folded into one slice.
    let txns = [
        rowIn("Rent", 200_000, d(2026, 8, 3)),
        rowIn("Coffee", 2_000, d(2026, 8, 3)),
        rowIn("Snacks", 3_000, d(2026, 8, 3))
    ]
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    let segs = bars[2].segments
    #expect(segs.count == 2)
    #expect(segs[0].categoryName == "Rent")
    #expect(segs[1].categoryName == ActivityBar.otherSegmentName)
    #expect(segs[1].amount == 5_000)
}

@Test func anEvenlySpreadDayKeepsItsLargestCategoriesRatherThanMergingAllOfThem() {
    // A day spread thinly across many categories has every slice below the
    // floor, so the floor alone folded the whole day into one "Other" block —
    // a featureless bar that says nothing about where the money went, which is
    // the one thing a stacked bar exists to say.
    //
    // The floor now applies only to the tail: the biggest categories are kept
    // whatever their share.
    let txns = (0..<13).map { rowIn("Cat\($0)", 10_000, d(2026, 8, 3)) }
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    let segs = bars[2].segments

    // Each slice is 1/13 — 7.7%, under the 8.3% floor — yet the bar is not
    // one anonymous block.
    #expect(segs.count > 1)
    #expect(segs.first?.categoryName != ActivityBar.otherSegmentName)
    #expect(segs.filter { $0.categoryName == ActivityBar.otherSegmentName }.count <= 1)
}

@Test func theLargestCategoryIsNeverSweptIntoOther() {
    // The band that carries the label is the biggest one. If it can be merged,
    // the label can read "Other" on a bar whose money plainly went somewhere.
    let txns = (0..<20).map { rowIn("Cat\($0)", $0 == 0 ? 12_000 : 10_000, d(2026, 8, 3)) }
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    #expect(bars[2].segments.first?.categoryName == "Cat0")
}

@Test func segmentsCoverTheWholeBarWithNothingLost() {
    // Whatever the merging does, the slices must still add up to the bar — a
    // stacked bar that does not reach its own total is a lie.
    let txns = [
        rowIn("Rent", 200_000, d(2026, 8, 3)),
        rowIn("Coffee", 2_000, d(2026, 8, 3)),
        rowIn("Dining", 40_000, d(2026, 8, 3))
    ]
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    let total = bars[2].segments.reduce(Decimal(0)) { $0 + $1.amount }
    #expect(total == bars[2].expense)
}

@Test func incomeDoesNotAppearAsASpendingSegment() {
    // Segments describe where money went, so a salary is not one of them.
    let txns = [
        rowIn("Groceries", 40_000, d(2026, 8, 3)),
        TxnRow(id: UUID(), date: d(2026, 8, 3), kind: .income, amount: 3_000_000,
               categoryName: "Salary", note: nil, source: .manual)
    ]
    let bars = ActivitySeries.bars(txns, period: .month, now: d(2026, 8, 15), calendar: testCal)
    #expect(bars[2].segments.map(\.categoryName) == ["Groceries"])
}
