import Foundation

/// Excel-openable CSV file content: BOM so Korean text decodes, trailing newline per RFC 4180.
public enum CSVDocumentBuilder {
    public static func document(_ rows: [TxnRow], timeZone: TimeZone) -> String {
        "\u{FEFF}" + CSVExporter.export(rows, timeZone: timeZone) + "\n"
    }
}
