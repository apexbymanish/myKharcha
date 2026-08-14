import Foundation

public enum RecurringMath {

    /// First occurrence of `dayOfMonth` strictly after `date`, clamped to the
    /// target month's length (31 → Feb 28/29), at start-of-day.
    public static func nextDueDate(dayOfMonth: Int, after date: Date, calendar: Calendar) -> Date {
        let startOfMonth = calendar.dateInterval(of: .month, for: date)!.start
        var candidate = clamped(dayOfMonth: dayOfMonth, inMonthOf: startOfMonth, calendar: calendar)
        if candidate <= calendar.startOfDay(for: date) {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            candidate = clamped(dayOfMonth: dayOfMonth, inMonthOf: nextMonth, calendar: calendar)
        }
        return candidate
    }

    public static func reminderDate(for due: Date, daysBefore: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -daysBefore, to: due)!
    }

    private static func clamped(dayOfMonth: Int, inMonthOf monthStart: Date, calendar: Calendar) -> Date {
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)!.count
        let day = min(dayOfMonth, dayCount)
        return calendar.date(byAdding: .day, value: day - 1, to: calendar.startOfDay(for: monthStart))!
    }
}
