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
