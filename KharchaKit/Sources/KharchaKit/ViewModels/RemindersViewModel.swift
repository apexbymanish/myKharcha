import Foundation

@MainActor
public final class RemindersViewModel: ObservableObject {
    public struct State: Sendable {
        public var rules: [RecurringRuleSnapshot] = []
        public var paidRuleIDs: Set<UUID> = []
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load(now: Date = Date(), calendar: Calendar = .current) async {
        state.errorMessage = nil
        do {
            let rules = try await store.recurringRules()
            state.rules = rules
            let txns = try await store.txnRows()
            var paid: Set<UUID> = []
            for rule in rules where txns.contains(where: {
                $0.note == rule.name && calendar.isDate($0.date, equalTo: now, toGranularity: .month)
            }) {
                paid.insert(rule.id)
            }
            state.paidRuleIDs = paid
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Logs the rule's amount as an expense for today. Returns the new transaction's UUID
    /// so the caller can present an undo action. Returns nil if already paid this month.
    @discardableResult
    public func markPaid(_ rule: RecurringRuleSnapshot, now: Date = Date(), calendar: Calendar = .current) async -> UUID? {
        let txns = (try? await store.txnRows()) ?? []
        guard !txns.contains(where: {
            $0.note == rule.name && calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }) else { return nil }
        do {
            let txnID = try await store.addTxn(amount: rule.amount, kind: .expense, categoryID: nil, note: rule.name, date: now, source: .manual)
            await load(now: now, calendar: calendar)
            return txnID
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
            return nil
        }
    }

    public func undoMarkPaid(txnID: UUID) async {
        do {
            try await store.deleteTxn(txnID: txnID)
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func daysUntil(rule: RecurringRuleSnapshot, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let next = RecurringMath.nextDueDate(dayOfMonth: rule.dayOfMonth, after: yesterday, calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: next)).day ?? 0
        return max(0, days)
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

    public func update(id: UUID, name: String, amountText: String, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool) async {
        state.errorMessage = nil

        guard let amount = TxnFormViewModel.parsedAmount(amountText) else {
            state.errorMessage = "Enter a valid amount."
            return
        }

        do {
            try await store.updateRecurringRule(
                id: id, name: name, amount: amount, categoryID: nil,
                dayOfMonth: dayOfMonth, remindDaysBefore: remindDaysBefore, autoLog: autoLog
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
