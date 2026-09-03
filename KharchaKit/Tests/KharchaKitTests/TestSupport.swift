import Foundation
import SwiftData
@testable import KharchaKit

var testCal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.firstWeekday = 2
    return c
}

func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
    testCal.date(from: DateComponents(timeZone: testCal.timeZone, year: y, month: m, day: day, hour: h))!
}

func makeStore() throws -> ExpenseStore {
    // Pin the display currency so spoken/notification message assertions are
    // deterministic regardless of the test machine's region (AmountFormatter
    // now defaults to the device's locale currency).
    AmountFormatter.currencyCode = "KRW"
    let container = try ModelContainer(
        for: Schema(KharchaSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ExpenseStore(modelContainer: container)
}

/// Pin KRW for tests that assert formatted amounts but don't build a store
/// (e.g. the pure ReminderPlanner tests).
func pinTestCurrency() {
    AmountFormatter.currencyCode = "KRW"
}

/// An expense row in a named category, for the stacked-bar tests.
func rowIn(_ category: String, _ amount: Decimal, _ date: Date) -> TxnRow {
    TxnRow(id: UUID(), date: date, kind: .expense, amount: amount,
           categoryName: category, note: nil, source: .manual)
}
