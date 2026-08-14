import Foundation

public enum Period: String, CaseIterable, Sendable {
    case today, week, month

    public func dateRange(now: Date, calendar: Calendar) -> Range<Date> {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return start..<end
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)!
            return interval.start..<interval.end
        case .month:
            let interval = calendar.dateInterval(of: .month, for: now)!
            return interval.start..<interval.end
        }
    }
}
