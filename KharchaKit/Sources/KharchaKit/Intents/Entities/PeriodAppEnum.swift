import AppIntents

public enum PeriodAppEnum: String, AppEnum {
    case today, week, month
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    public static let caseDisplayRepresentations: [PeriodAppEnum: DisplayRepresentation] = [
        .today: "today", .week: "this week", .month: "this month"
    ]
    public var period: Period { Period(rawValue: rawValue) ?? .today }
}
