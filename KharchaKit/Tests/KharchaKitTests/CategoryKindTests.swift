import Testing
import Foundation
@testable import KharchaKit

@MainActor
struct CategoryKindTests {

    @Test func seededDefaultsCarryKinds() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()
        let cats = try await store.categories()
        #expect(cats.first { $0.name == "Food" }?.kind == .expense)
        #expect(cats.first { $0.name == "Salary" }?.kind == .income)
        #expect(cats.first { $0.name == "Other" }?.kind == .any)
    }

    @Test func reconcileMergesDuplicateCategories() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()   // fallback "Other"
        let dupe = try await store.addCategory(name: "Other", symbol: "tag", colorHex: "#999999", monthlyBudget: nil, kind: .expense)
        _ = try await store.addTxn(amount: 5000, kind: .expense, categoryID: dupe.id, note: "x", date: d(2026, 8, 1), source: .manual)

        let merged = try await store.reconcileCategories(applyIncomeHeuristic: false)
        #expect(merged == 1)
        let others = try await store.categories().filter { $0.name == "Other" }
        #expect(others.count == 1)
        #expect(others.first?.isFallback == true)   // the fallback was kept
        // The transaction survived (was reassigned to the keeper, not deleted).
        #expect(try await store.txnRows().count == 1)
    }

    @Test func incomeHeuristicTagsKnownIncomeNames() async throws {
        let store = try makeStore()
        _ = try await store.addCategory(name: "Salary", symbol: "dollarsign.circle", colorHex: "#2A9D8F", monthlyBudget: nil, kind: .expense)
        _ = try await store.reconcileCategories(applyIncomeHeuristic: true)
        #expect(try await store.categories().first { $0.name == "Salary" }?.kind == .income)
    }

    @Test func visibleCategoriesFilterByKind() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()
        let vm = TxnFormViewModel(store: store)
        await vm.load()

        vm.setKind(.expense)
        #expect(vm.visibleCategories.contains { $0.name == "Food" })
        #expect(!vm.visibleCategories.contains { $0.name == "Salary" })
        #expect(vm.visibleCategories.contains { $0.name == "Other" })   // .any shows for both

        vm.setKind(.income)
        #expect(vm.visibleCategories.contains { $0.name == "Salary" })
        #expect(!vm.visibleCategories.contains { $0.name == "Food" })
        #expect(vm.visibleCategories.contains { $0.name == "Other" })
    }

    @Test func switchingToIncomeClearsAnExpenseOnlySelection() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()
        let vm = TxnFormViewModel(store: store)
        await vm.load()
        let food = try #require(try await store.categories().first { $0.name == "Food" })
        vm.setKind(.expense)
        vm.setCategory(food.id)
        #expect(vm.state.categoryID == food.id)
        vm.setKind(.income)   // Food doesn't apply to income → selection cleared
        #expect(vm.state.categoryID == nil)
    }
}
