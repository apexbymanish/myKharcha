import Testing
import Foundation
@testable import KharchaKit

@Suite
struct BudgetsViewModelTests {
    @Test
    @MainActor
    func loadPopulatesStatuses() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 100_000)
        _ = try await store.addTxn(amount: 30_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 10), source: .manual)

        let vm = BudgetsViewModel(store: store)
        await vm.load(now: d(2026, 8, 19), calendar: testCal)

        #expect(vm.state.categories.count == 1)
        #expect(vm.state.statuses.count == 1)
        #expect(vm.state.statuses[0].categoryName == "Food")
        #expect(vm.state.statuses[0].spent == 30_000)
    }

    @Test
    @MainActor
    func setBudgetWithAmount() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)

        let vm = BudgetsViewModel(store: store)
        await vm.load(now: d(2026, 8, 19), calendar: testCal)

        await vm.setBudget(categoryID: food.id, amountText: "150,000", now: d(2026, 8, 19), calendar: testCal)

        let statuses = try await store.budgetStatuses(now: d(2026, 8, 19), calendar: testCal)
        #expect(statuses[0].budget == 150_000)
    }

    @Test
    @MainActor
    func setBudgetWithEmptyTextClearsIt() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 100_000)

        let vm = BudgetsViewModel(store: store)
        await vm.load(now: d(2026, 8, 19), calendar: testCal)

        await vm.setBudget(categoryID: food.id, amountText: "", now: d(2026, 8, 19), calendar: testCal)

        let statuses = try await store.budgetStatuses(now: d(2026, 8, 19), calendar: testCal)
        #expect(statuses.isEmpty)
    }

    @Test
    @MainActor
    func setBudgetWithJunkSetsErrorMessage() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)

        let vm = BudgetsViewModel(store: store)
        await vm.load(now: d(2026, 8, 19), calendar: testCal)

        await vm.setBudget(categoryID: food.id, amountText: "junk", now: d(2026, 8, 19), calendar: testCal)

        #expect(vm.state.errorMessage != nil)
    }
}
