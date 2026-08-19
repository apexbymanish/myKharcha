import Testing
import Foundation
@testable import KharchaKit

@Suite
struct HistoryViewModelTests {
    @Test
    @MainActor
    func groupsTransactionsByMonthNewestFirst() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)

        // Add transactions in July and August
        _ = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 7, 15), source: .manual)
        _ = try await store.addTxn(amount: 3_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 7, 10), source: .manual)
        _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 20), source: .manual)
        _ = try await store.addTxn(amount: 8_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 5), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)

        #expect(vm.state.sections.count == 2)
        #expect(vm.state.sections[0].title == "August 2026")
        #expect(vm.state.sections[0].rows.count == 2)
        #expect(vm.state.sections[0].rows.first?.amount == 12_000)  // August newest first
        #expect(vm.state.sections[1].title == "July 2026")
        #expect(vm.state.sections[1].rows.first?.amount == 5_000)   // July newest first
    }

    @Test
    @MainActor
    func kindFilterHidesIncome() async throws {
        let store = try makeStore()
        _ = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10), source: .manual)
        _ = try await store.addTxn(amount: 3_000_000, kind: .income, categoryID: nil, note: nil, date: d(2026, 8, 5), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        #expect(vm.state.sections[0].rows.count == 2)

        await vm.setKindFilter(.expense, calendar: testCal)
        #expect(vm.state.filterKind == .expense)
        #expect(vm.state.sections[0].rows.count == 1)
        #expect(vm.state.sections[0].rows.first?.amount == 5_000)
    }

    @Test
    @MainActor
    func categoryFilterByName() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
        let transport = try await store.addCategory(name: "Transport", symbol: "bus", colorHex: "#3D405B", monthlyBudget: nil)

        _ = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 10), source: .manual)
        _ = try await store.addTxn(amount: 3_000, kind: .expense, categoryID: transport.id, note: nil, date: d(2026, 8, 5), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        #expect(vm.state.sections[0].rows.count == 2)

        await vm.setCategoryFilter("Food", calendar: testCal)
        #expect(vm.state.filterCategoryName == "Food")
        #expect(vm.state.sections[0].rows.count == 1)
        #expect(vm.state.sections[0].rows.first?.categoryName == "Food")
    }

    @Test
    @MainActor
    func deleteRemovesRow() async throws {
        let store = try makeStore()
        let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        #expect(vm.state.sections[0].rows.count == 1)

        await vm.delete(id, calendar: testCal)
        #expect(vm.state.sections.isEmpty)
    }
}
