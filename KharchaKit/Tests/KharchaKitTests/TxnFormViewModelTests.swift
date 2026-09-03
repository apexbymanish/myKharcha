import Testing
import Foundation
@testable import KharchaKit

@Suite
struct TxnFormViewModelTests {
    @Test
    @MainActor
    func parsedAmountHandlesFormatting() {
        #expect(TxnFormViewModel.parsedAmount("12,000") == 12_000)
        #expect(TxnFormViewModel.parsedAmount("₩12,000.50") == Decimal(string: "12000.50")!)
        #expect(TxnFormViewModel.parsedAmount("0") == nil)
        #expect(TxnFormViewModel.parsedAmount("-5") == nil)
        #expect(TxnFormViewModel.parsedAmount("abc") == nil)
    }

    @Test
    @MainActor
    func saveAddsTxn() async throws {
        let store = try makeStore()
        try await store.seedDefaultCategoriesIfNeeded()
        let vm = TxnFormViewModel(store: store)
        await vm.load()
        vm.setAmountText("12,000")
        vm.setNote("lunch")
        vm.setCategory(vm.state.categories.first { $0.name == "Food" }?.id)
        await vm.save()
        #expect(vm.state.didSave == true)
        let rows = try await store.txnRows()
        #expect(rows.first?.amount == 12_000)
    }

    @Test
    @MainActor
    func saveRejectsBadAmountWithMessage() async throws {
        let vm = TxnFormViewModel(store: try makeStore())
        vm.setAmountText("nope")
        await vm.save()
        #expect(vm.state.didSave == false)
        #expect(vm.state.errorMessage != nil)
    }

    @Test
    @MainActor
    func editingUpdatesExistingTxn() async throws {
        let store = try makeStore()
        let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10), source: .manual)
        let row = try await store.txnRows().first { $0.id == id }!
        let vm = TxnFormViewModel(store: store)
        vm.beginEditing(row)
        vm.setAmountText("7,500")
        await vm.save()
        let updated = try await store.txnRows().first { $0.id == id }!
        #expect(updated.amount == 7_500)
    }
}
