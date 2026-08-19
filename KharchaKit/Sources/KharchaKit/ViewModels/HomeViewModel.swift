import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    public struct State: Sendable {
        public var monthSpent: Decimal = 0
        public var monthIncome: Decimal = 0
        public var budgets: [BudgetStatus] = []
        public var friendRows: [DebtRow] = []
        public var recent: [TxnRow] = []
        public var isLoading = false
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load(now: Date = Date(), calendar: Calendar = .current) async {
        state.errorMessage = nil
        state.isLoading = true
        defer { state.isLoading = false }

        do {
            let spent = try await store.spent(in: .month, categoryID: nil, now: now, calendar: calendar)
            state.monthSpent = spent

            let income = try await store.income(in: .month, now: now, calendar: calendar)
            state.monthIncome = income

            let budgets = try await store.budgetStatuses(now: now, calendar: calendar)
            state.budgets = budgets

            let friends = try await store.friends()
            let balances = try await store.netBalances()
            var friendRows: [DebtRow] = []
            for friend in friends {
                let balance = balances[friend.id] ?? 0
                // Skip zero-net friends; store signed net
                if balance != 0 {
                    friendRows.append(DebtRow(friendID: friend.id, name: friend.name, amount: balance))
                }
            }
            // Sort: positive (they owe me) descending, then negative (I owe) by abs descending
            friendRows.sort { a, b in
                let aNet = a.amount
                let bNet = b.amount
                if (aNet > 0) && (bNet <= 0) { return true }
                if (aNet <= 0) && (bNet > 0) { return false }
                return abs(aNet) > abs(bNet)
            }
            state.friendRows = friendRows

            let rows = try await store.txnRows()
            let sorted = rows.sorted { $0.date > $1.date }
            state.recent = Array(sorted.prefix(10))
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func deleteTxn(_ id: UUID, now: Date = Date(), calendar: Calendar = .current) async {
        do {
            try await store.deleteTxn(txnID: id)
            await load(now: now, calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
