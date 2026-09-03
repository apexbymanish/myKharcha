import Testing
import Foundation
@testable import KharchaKit

@Suite
struct SettingsViewModelTests {
    @Test
    @MainActor
    func loadPopulatesCategories() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()

        let vm = SettingsViewModel(store: store)
        await vm.load()

        #expect(vm.state.categories.count == 10)
    }

    @Test
    @MainActor
    func addCategoryWithValidName() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()

        let vm = SettingsViewModel(store: store)
        await vm.load()
        let initialCount = vm.state.categories.count

        await vm.addCategory(name: "Custom", symbol: "star", colorHex: "#FF0000")

        #expect(vm.state.errorMessage == nil)
        #expect(vm.state.categories.count == initialCount + 1)
        #expect(vm.state.categories.contains { $0.name == "Custom" })
    }

    @Test
    @MainActor
    func addCategoryWithDuplicateNameError() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()

        let vm = SettingsViewModel(store: store)
        await vm.load()

        // Try to add duplicate of an existing category
        await vm.addCategory(name: "Food", symbol: "star", colorHex: "#FF0000")

        #expect(vm.state.errorMessage == "That category already exists.")
    }

    @Test
    @MainActor
    func deleteFallbackCategoryError() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()

        let vm = SettingsViewModel(store: store)
        await vm.load()

        // Find "Other" category (the fallback)
        guard let other = vm.state.categories.first(where: { $0.name == "Other" }) else {
            #expect(false, "Other category not found")
            return
        }

        await vm.deleteCategory(other.id)

        #expect(vm.state.errorMessage == "The Other category can't be deleted.")
    }

    @Test
    @MainActor
    func makeExportProducesCSVDocument() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()
        let food = try await store.categories().first(where: { $0.name == "Food" })!
        _ = try await store.addTxn(amount: 50_000, kind: .expense, categoryID: food.id, note: "Lunch", date: d(2026, 8, 19), source: .manual)

        let vm = SettingsViewModel(store: store)
        await vm.makeExport(calendar: testCal)

        #expect(vm.state.exportDocument != nil)
        #expect(vm.state.exportDocument!.starts(with: "\u{FEFF}"))  // BOM
        #expect(vm.state.exportDocument!.contains("date,kind,amount,category,note"))
        #expect(vm.state.exportDocument!.contains("2026-08-19"))
        #expect(vm.state.exportDocument!.contains("50000"))
    }
}
