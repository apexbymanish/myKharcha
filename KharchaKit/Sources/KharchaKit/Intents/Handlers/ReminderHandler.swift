import Foundation

public enum AddReminderHandler {
    public static func run(store: ExpenseStore, name: String, amount: Decimal, dayOfMonth: Int, remindDaysBefore: Int, now: Date, calendar: Calendar) async throws -> LogResult {
        let rule = try await store.addRecurringRule(name: name, amount: amount, categoryID: nil, dayOfMonth: dayOfMonth, remindDaysBefore: remindDaysBefore, autoLog: false)
        let due = RecurringMath.nextDueDate(dayOfMonth: dayOfMonth, after: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        return LogResult(
            txnID: rule.id,
            needsDuplicateConfirmation: false,
            message: "I'll remind you about \(name) (\(AmountFormatter.krw(amount))) on \(formatter.string(from: due))."
        )
    }
}
