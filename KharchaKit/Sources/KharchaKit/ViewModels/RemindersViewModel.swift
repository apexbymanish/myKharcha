import Foundation
import Observation

@MainActor
public final class RemindersViewModel: ObservableObject {
    public struct State: Sendable {
        public var rules: [RecurringRuleSnapshot] = []
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load() async {
        do {
            let rules = try await store.recurringRules()
            state.rules = rules
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func add(name: String, amountText: String, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool, categoryID: UUID?) async {
        state.errorMessage = nil

        guard let amount = TxnFormViewModel.parsedAmount(amountText) else {
            state.errorMessage = "Enter a valid amount."
            return
        }

        do {
            _ = try await store.addRecurringRule(
                name: name,
                amount: amount,
                categoryID: categoryID,
                dayOfMonth: dayOfMonth,
                remindDaysBefore: remindDaysBefore,
                autoLog: autoLog
            )
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func delete(_ ruleID: UUID) async {
        do {
            try await store.deleteRecurringRule(ruleID: ruleID)
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func nextDueText(for rule: RecurringRuleSnapshot, now: Date = Date(), calendar: Calendar = .current) -> String {
        let nextDue = RecurringMath.nextDueDate(dayOfMonth: rule.dayOfMonth, after: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: nextDue)
    }
}
