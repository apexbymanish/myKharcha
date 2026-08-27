import Foundation

/// Writes a CSV export string out to a real file so `ShareLink` shares an actual
/// `.csv` attachment (Files, Mail, Messages, ...) instead of a bare string.
/// App-shell IO only — the CSV content itself still comes from
/// `SettingsViewModel.makeExport()` / `CSVDocumentBuilder` in KharchaKit.
enum CSVFileWriter {
    static func write(_ csv: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kharcha-Export.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Kharcha: failed to write CSV export file: \(error)")
            return nil
        }
    }
}
