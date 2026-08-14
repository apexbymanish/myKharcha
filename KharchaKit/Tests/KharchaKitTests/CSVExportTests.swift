import Testing
import Foundation
@testable import KharchaKit

@Test func exportProducesHeaderAndEscapedRows() {
    let rows = [
        TxnRow(date: d(2026, 8, 14), kind: .expense, amount: 12_000, categoryName: "Food", note: "lunch, with Ram"),
        TxnRow(date: d(2026, 8, 15), kind: .income, amount: 3_000_000, categoryName: "", note: nil)
    ]
    let csv = CSVExporter.export(rows, timeZone: testCal.timeZone)
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines[0] == "date,kind,amount,category,note")
    #expect(lines[1] == #"2026-08-14,expense,12000,Food,"lunch, with Ram""#)
    #expect(lines[2] == "2026-08-15,income,3000000,,")
}

@Test func quotesInsideFieldsAreDoubled() {
    let rows = [TxnRow(date: d(2026, 8, 14), kind: .expense, amount: 1, categoryName: "Food", note: #"say "hi""#)]
    let csv = CSVExporter.export(rows, timeZone: testCal.timeZone)
    #expect(csv.contains(#""say ""hi""""#))
}

@Test func storeExportsAllTxnsOldestFirst() async throws {
    let store = try makeStore()
    let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
    _ = try await store.addTxn(amount: 2_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 14), source: .manual)
    _ = try await store.addTxn(amount: 1_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 1), source: .siri)

    let rows = try await store.txnRows()
    #expect(rows.map(\.amount) == [1_000, 2_000])
    #expect(rows[1].categoryName == "Food")
    #expect(rows[0].categoryName == "")
}
