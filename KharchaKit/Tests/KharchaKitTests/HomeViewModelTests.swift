import Testing
import Foundation
@testable import KharchaKit

@Suite
struct HomeViewModelTests {
    @Test
    @MainActor
    func loadPopulatesMonthTotalsAndRecent() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 100_000)
        for i in 1...12 {
            _ = try await store.addTxn(amount: Decimal(i * 1_000), kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, i), source: .manual)
        }
        _ = try await store.addTxn(amount: 3_000_000, kind: .income, categoryID: nil, note: nil, date: d(2026, 8, 5), source: .manual)
        let ram = try await store.addFriend(name: "Ram", phone: nil)
        _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

        let vm = HomeViewModel(store: store)
        await vm.load(now: d(2026, 8, 19), calendar: testCal)
        #expect(vm.state.monthSpent == 78_000)          // 1k+…+12k
        #expect(vm.state.monthIncome == 3_000_000)
        #expect(vm.state.recent.count == 10)
        #expect(vm.state.recent.first?.amount == 12_000) // newest first
        #expect(vm.state.budgets.count == 1)
        #expect(vm.state.friendRows.first?.name == "Ram")
        #expect(vm.state.isLoading == false)
    }

    @Test
    @MainActor
    func deleteTxnReloads() async throws {
        let store = try makeStore()
        let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10), source: .manual)
        let vm = HomeViewModel(store: store)
        await vm.deleteTxn(id, now: d(2026, 8, 19), calendar: testCal)
        #expect(vm.state.monthSpent == 0)
        #expect(vm.state.recent.isEmpty)
    }
}
