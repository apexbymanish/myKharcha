import Foundation
import Observation

@MainActor
public final class TxnFormViewModel: ObservableObject {
    public struct State: Sendable {
        public var amountText = ""
        public var kind: TxnKind = .expense
        public var categoryID: UUID?
        public var note = ""
        public var date = Date()
        public var categories: [CategorySnapshot] = []
        public var errorMessage: String?
        public var didSave = false
        public var editingTxnID: UUID?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load() async {
        do {
            let categories = try await store.categories()
            state.categories = categories
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func beginEditing(_ row: TxnRow) {
        state.editingTxnID = row.id
        state.amountText = row.amount.description
        state.kind = row.kind
        state.note = row.note ?? ""
        state.date = row.date

        // Map category name back to ID
        if !row.categoryName.isEmpty {
            state.categoryID = state.categories.first { $0.name == row.categoryName }?.id
        } else {
            state.categoryID = nil
        }
    }

    public func setAmountText(_ s: String) {
        state.amountText = s
        state.errorMessage = nil
    }

    public func setKind(_ k: TxnKind) {
        state.kind = k
    }

    public func setCategory(_ id: UUID?) {
        state.categoryID = id
    }

    public func setNote(_ s: String) {
        state.note = s
    }

    public func setDate(_ d: Date) {
        state.date = d
    }

    public func save() async {
        state.errorMessage = nil
        state.didSave = false

        guard let amount = Self.parsedAmount(state.amountText) else {
            state.errorMessage = "Enter a valid amount."
            return
        }

        do {
            if let editingID = state.editingTxnID {
                try await store.updateTxn(
                    txnID: editingID,
                    amount: amount,
                    kind: state.kind,
                    categoryID: state.categoryID,
                    note: state.note.isEmpty ? nil : state.note,
                    date: state.date
                )
            } else {
                _ = try await store.addTxn(
                    amount: amount,
                    kind: state.kind,
                    categoryID: state.categoryID,
                    note: state.note.isEmpty ? nil : state.note,
                    date: state.date,
                    source: .manual
                )
            }
            state.didSave = true
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    nonisolated public static func parsedAmount(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "₩", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned), value > 0 else { return nil }
        return value
    }
}
