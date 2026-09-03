import Foundation

enum BackupFileWriter {
    static func write(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kharcha-Backup.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("Kharcha: failed to write backup file: \(error)")
            return nil
        }
    }
}
