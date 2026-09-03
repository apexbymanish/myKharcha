import Foundation

@MainActor
public final class FriendDetailViewModel: ObservableObject {
    public struct State: Sendable {
        public var friendID: UUID
        public var friendName: String
        public var net: Decimal = 0
        /// Sum of still-open amounts by direction (for the breakdown UI).
        public var totalGiven: Decimal = 0
        public var totalTaken: Decimal = 0
        public var debts: [DebtSnapshot] = []
        public var errorMessage: String?

        public init(friendID: UUID, friendName: String) {
            self.friendID = friendID
            self.friendName = friendName
        }
    }

    @Published public private(set) var state: State

    private let store: ExpenseStore

    public init(store: ExpenseStore, friendID: UUID, friendName: String) {
        self.store = store
        self.state = State(friendID: friendID, friendName: friendName)
    }

    public func load() async {
        state.errorMessage = nil
        do {
            let debts = try await store.debts(friendID: state.friendID)
            let balances = try await store.netBalances()

            state.debts = debts
            state.net = balances[state.friendID] ?? 0
            state.totalGiven = debts.filter { !$0.settled && $0.direction == .iGave }.reduce(0) { $0 + $1.remaining }
            state.totalTaken = debts.filter { !$0.settled && $0.direction == .iTook }.reduce(0) { $0 + $1.remaining }
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func addDebt(direction: DebtDirection, amountText: String, note: String, dueDate: Date?) async {
        state.errorMessage = nil

        guard let amount = TxnFormViewModel.parsedAmount(amountText) else {
            state.errorMessage = "Enter a valid amount."
            return
        }

        do {
            _ = try await store.addDebt(
                friendID: state.friendID,
                amount: amount,
                direction: direction,
                date: Date(),
                note: note.isEmpty ? nil : note,
                dueDate: dueDate
            )
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func settle(amountText: String?) async {
        state.errorMessage = nil

        guard state.net != 0 else {
            state.errorMessage = "Nothing to settle."
            return
        }
        let direction: DebtDirection = state.net > 0 ? .iGave : .iTook

        let amount: Decimal?
        if let text = amountText, !text.isEmpty {
            guard let parsed = TxnFormViewModel.parsedAmount(text) else {
                state.errorMessage = "Enter a valid amount."
                return
            }
            amount = parsed
        } else {
            amount = nil
        }

        do {
            _ = try await store.settleFriendDebts(friendID: state.friendID, amount: amount, direction: direction)
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Clear the whole balance — fully settle every open debt in both directions.
    public func clearAll() async {
        state.errorMessage = nil
        let hasGave = state.debts.contains { !$0.settled && $0.direction == .iGave }
        let hasTook = state.debts.contains { !$0.settled && $0.direction == .iTook }
        guard hasGave || hasTook else {
            state.errorMessage = "Nothing to clear."
            return
        }
        do {
            if hasGave { _ = try await store.settleFriendDebts(friendID: state.friendID, amount: nil, direction: .iGave) }
            if hasTook { _ = try await store.settleFriendDebts(friendID: state.friendID, amount: nil, direction: .iTook) }
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func writeOff(_ debtID: UUID) async {
        do {
            _ = try await store.convertDebtToExpense(debtID: debtID, date: Date())
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
