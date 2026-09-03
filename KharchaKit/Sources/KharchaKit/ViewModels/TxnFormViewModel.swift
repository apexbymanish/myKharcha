import Foundation

@MainActor
public final class TxnFormViewModel: ObservableObject {
    /// One-time transaction vs a multi-month installment/loan.
    public enum Mode: Sendable, Equatable { case oneTime, installment }

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

        // Installment mode (only offered when creating, not editing).
        public var mode: Mode = .oneTime
        public var instName = ""
        public var instKind: InstallmentKind = .purchase
        public var instTotalText = ""
        public var instMonths = 12
        public var instMonthlyText = ""
        public var instDay = 1
        public var instAutoLog = false
        public var instAsIncome = false
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load() async {
        state.errorMessage = nil
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
        clearCategoryIfNotApplicable()
    }

    /// Categories relevant to what's being logged: the current kind for a one-time
    /// txn, always expense categories for an installment (its payments are expenses).
    public var visibleCategories: [CategorySnapshot] {
        let target: TxnKind = state.mode == .installment ? .expense : state.kind
        return state.categories.filter { $0.kind.applies(to: target) }
    }

    /// Drop a selected category that no longer applies after switching kind/mode.
    private func clearCategoryIfNotApplicable() {
        let target: TxnKind = state.mode == .installment ? .expense : state.kind
        if let id = state.categoryID,
           let cat = state.categories.first(where: { $0.id == id }),
           !cat.kind.applies(to: target) {
            state.categoryID = nil
        }
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

    // MARK: Installment mode

    public func setMode(_ m: Mode) {
        state.mode = m
        state.errorMessage = nil
        clearCategoryIfNotApplicable()
    }
    public func setInstName(_ s: String) { state.instName = s; state.errorMessage = nil }
    public func setInstKind(_ k: InstallmentKind) { state.instKind = k }
    public func setInstDay(_ d: Int) { state.instDay = d }
    public func setInstAutoLog(_ v: Bool) { state.instAutoLog = v }
    public func setInstAsIncome(_ v: Bool) { state.instAsIncome = v }

    public func setInstTotal(_ s: String) {
        state.instTotalText = s
        state.errorMessage = nil
        recomputeMonthly()
    }
    public func setInstMonths(_ n: Int) {
        state.instMonths = max(1, n)
        recomputeMonthly()
    }
    /// User override of the auto-computed monthly amount.
    public func setInstMonthly(_ s: String) {
        state.instMonthlyText = s
        state.errorMessage = nil
    }

    /// Recompute the per-month amount from total ÷ months (rounded to the currency).
    private func recomputeMonthly() {
        guard let total = Self.parsedAmount(state.instTotalText), state.instMonths > 0 else { return }
        let monthly = InstallmentMath.monthlyFromTotal(total, termCount: state.instMonths)
        state.instMonthlyText = NSDecimalNumber(decimal: monthly).stringValue
    }

    public func save() async {
        if state.mode == .installment {
            await saveInstallment()
            return
        }
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

    private func saveInstallment() async {
        state.errorMessage = nil
        state.didSave = false

        let name = state.instName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            state.errorMessage = "Enter a name."
            return
        }
        guard let monthly = Self.parsedAmount(state.instMonthlyText) else {
            state.errorMessage = "Enter a valid amount."
            return
        }
        do {
            _ = try await store.addInstallment(
                name: name,
                kind: state.instKind,
                monthlyAmount: monthly,
                termCount: state.instMonths,
                dayOfMonth: state.instDay,
                startDate: state.date,
                categoryID: state.categoryID,
                remindDaysBefore: 3,
                autoLog: state.instAutoLog,
                recordPrincipalAsIncome: state.instKind == .loan && state.instAsIncome,
                note: state.note.isEmpty ? nil : state.note
            )
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
