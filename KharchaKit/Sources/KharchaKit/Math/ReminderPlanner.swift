import Foundation

public struct ReminderSpec: Sendable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
    public init(id: String, title: String, body: String, fireDate: Date) {
        self.id = id; self.title = title; self.body = body; self.fireDate = fireDate
    }
}

public enum ReminderPlanner {

    /// Every returned fireDate is strictly in the future relative to `now` — NotificationScheduler relies on this invariant.
    public static func plan(rules: [RecurringRuleSnapshot], debts: [DebtSnapshot], installments: [InstallmentSnapshot] = [], now: Date, calendar: Calendar, hour: Int = 9) -> [ReminderSpec] {
        var specs: [ReminderSpec] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone

        for rule in rules {
            var due = RecurringMath.nextDueDate(dayOfMonth: rule.dayOfMonth, after: now, calendar: calendar)
            var remind = at(hour: hour, of: RecurringMath.reminderDate(for: due, daysBefore: rule.remindDaysBefore, calendar: calendar), calendar: calendar)
            while remind <= now {
                due = RecurringMath.nextDueDate(dayOfMonth: rule.dayOfMonth, after: due, calendar: calendar)
                remind = at(hour: hour, of: RecurringMath.reminderDate(for: due, daysBefore: rule.remindDaysBefore, calendar: calendar), calendar: calendar)
            }
            specs.append(ReminderSpec(
                id: "rule-\(rule.id.uuidString)",
                title: rule.name,
                body: "\(rule.name) (\(AmountFormatter.money(rule.amount))) is due on \(formatter.string(from: due)).",
                fireDate: remind
            ))
        }

        for debt in debts where !debt.settled {
            guard let dueDate = debt.dueDate else { continue }
            let fire = at(hour: hour, of: calendar.date(byAdding: .day, value: -1, to: dueDate)!, calendar: calendar)
            guard fire > now else { continue }
            specs.append(ReminderSpec(
                id: "debt-\(debt.id.uuidString)",
                title: debt.friendName,
                body: "\(debt.friendName)'s \(AmountFormatter.money(debt.remaining)) is due on \(formatter.string(from: dueDate)).",
                fireDate: fire
            ))
        }

        // Active installments/loans: remind `remindDaysBefore` the monthly due day,
        // rolling forward to the next unfired occurrence (same shape as rules).
        for inst in installments {
            var due = RecurringMath.nextDueDate(dayOfMonth: inst.dayOfMonth, after: now, calendar: calendar)
            var remind = at(hour: hour, of: RecurringMath.reminderDate(for: due, daysBefore: inst.remindDaysBefore, calendar: calendar), calendar: calendar)
            while remind <= now {
                due = RecurringMath.nextDueDate(dayOfMonth: inst.dayOfMonth, after: due, calendar: calendar)
                remind = at(hour: hour, of: RecurringMath.reminderDate(for: due, daysBefore: inst.remindDaysBefore, calendar: calendar), calendar: calendar)
            }
            specs.append(ReminderSpec(
                id: "installment-\(inst.id.uuidString)",
                title: inst.name,
                body: String(localized: "\(inst.name) payment (\(AmountFormatter.money(inst.monthlyAmount))) is due on \(formatter.string(from: due)).", bundle: .module),
                fireDate: remind
            ))
        }

        return specs.sorted { $0.fireDate < $1.fireDate }
    }

    private static func at(hour: Int, of day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: day))!
    }
}

public enum AutoLogCatchUp {
    /// Due dates (start-of-day) strictly after `since` and ≤ `now`, ascending.
    public static func dueOccurrences(dayOfMonth: Int, since: Date, now: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = since
        while true {
            let due = RecurringMath.nextDueDate(dayOfMonth: dayOfMonth, after: cursor, calendar: calendar)
            guard due <= now else { break }
            result.append(due)
            cursor = due
        }
        return result
    }
}
