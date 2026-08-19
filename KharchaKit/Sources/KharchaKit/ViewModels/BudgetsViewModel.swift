import Foundation
import Observation

@MainActor
public final class BudgetsViewModel: ObservableObject {
    public struct State: Sendable {
        public var categories: [CategorySnapshot] = []
        public var statuses: [BudgetStatus] = []
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load(now: Date = Date(), calendar: Calendar = .current) async {
        do {
            let categories = try await store.categories()
            state.categories = categories

            let statuses = try await store.budgetStatuses(now: now, calendar: calendar)
            state.statuses = statuses
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func setBudget(categoryID: UUID, amountText: String, now: Date = Date(), calendar: Calendar = .current) async {
        state.errorMessage = nil

        let amount: Decimal?
        if amountText.isEmpty {
            amount = nil
        } else {
            guard let parsed = TxnFormViewModel.parsedAmount(amountText) else {
                state.errorMessage = "Enter a valid amount."
                return
            }
            amount = parsed
        }

        do {
            try await store.setBudget(categoryID: categoryID, amount: amount)
            await load(now: now, calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
