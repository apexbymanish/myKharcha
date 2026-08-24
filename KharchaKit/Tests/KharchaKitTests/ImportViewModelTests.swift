import Testing
import Foundation
@testable import KharchaKit

@MainActor
struct ImportViewModelTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func makeStore() throws -> ExpenseStore {
        ExpenseStore(modelContainer: try KharchaContainerFactory.inMemory())
    }

    @Test func parsesAndImportsSelectedRows() async throws {
        let store = try makeStore()
        let vm = ImportViewModel(store: store)
        await vm.parse("Lunch 500\nTaxi 1200", now: date(2026, 8, 20), calendar: cal, allowModel: false)

        #expect(vm.state.rows.count == 2)
        #expect(vm.selectedCount == 2)

        await vm.importSelected()
        #expect(vm.state.importedCount == 2)

        let rows = try await store.txnRows()
        #expect(rows.count == 2)
        #expect(rows.contains { $0.amount == 500 })
        #expect(rows.contains { $0.amount == 1_200 })
    }

    @Test func flagsRowThatDuplicatesAnExistingTransaction() async throws {
        let store = try makeStore()
        // Pre-existing expense that the paste will repeat.
        _ = try await store.addTxn(amount: 500, kind: .expense, categoryID: nil, note: "Lunch",
                                   date: date(2026, 8, 20), source: .manual)

        let vm = ImportViewModel(store: store)
        await vm.parse("Lunch 500\nTaxi 1200", now: date(2026, 8, 20), calendar: cal, allowModel: false)

        let lunch = try #require(vm.state.rows.first { $0.amount == 500 })
        let taxi = try #require(vm.state.rows.first { $0.amount == 1_200 })
        #expect(lunch.isDuplicate == true)
        #expect(lunch.include == false)   // duplicates default to excluded
        #expect(taxi.isDuplicate == false)
        #expect(taxi.include == true)

        // Only the non-duplicate imports by default.
        await vm.importSelected()
        #expect(vm.state.importedCount == 1)
        let rows = try await store.txnRows()
        #expect(rows.count == 2)   // original + the taxi
    }

    @Test func withinPasteDuplicatesAreFlagged() async throws {
        let store = try makeStore()
        let vm = ImportViewModel(store: store)
        await vm.parse("Lunch 500\nLunch 500", now: date(2026, 8, 20), calendar: cal, allowModel: false)

        #expect(vm.state.rows.count == 2)
        #expect(vm.state.rows[0].isDuplicate == false)
        #expect(vm.state.rows[1].isDuplicate == true)   // second identical row
    }
}
