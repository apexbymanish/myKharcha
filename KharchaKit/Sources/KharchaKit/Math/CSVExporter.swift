import Foundation

public struct TxnRow: Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let kind: TxnKind
    public let amount: Decimal
    public let categoryName: String
    public let note: String?
    public let source: TxnSource

    public init(id: UUID, date: Date, kind: TxnKind, amount: Decimal, categoryName: String, note: String?, source: TxnSource) {
        self.id = id
        self.date = date
        self.kind = kind
        self.amount = amount
        self.categoryName = categoryName
        self.note = note
        self.source = source
    }
}

public enum CSVExporter {

    public static func export(_ rows: [TxnRow], timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines = ["date,kind,amount,category,note"]
        for row in rows {
            lines.append([
                formatter.string(from: row.date),
                row.kind.rawValue,
                "\(row.amount)",
                escape(row.categoryName),
                escape(row.note ?? "")
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
