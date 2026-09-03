import Foundation

@MainActor
public final class SettingsViewModel: ObservableObject {
    public struct State: Sendable {
        public var categories: [CategorySnapshot] = []
        public var exportDocument: String?
        public var backupData: Data?
        public var importedCount: Int?
        public var importWasReplace: Bool = false
        public var isWorking: Bool = false
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load() async {
        state.errorMessage = nil
        do {
            let categories = try await store.categories()
            state.categories = categories
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func addCategory(name: String, symbol: String = "tag", colorHex: String = "#9A9A9A") async {
        state.errorMessage = nil

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            state.errorMessage = "Enter a category name."
            return
        }

        // Check for duplicate
        if state.categories.contains(where: { $0.name == trimmed }) {
            state.errorMessage = "That category already exists."
            return
        }

        do {
            _ = try await store.addCategory(name: trimmed, symbol: symbol, colorHex: colorHex, monthlyBudget: nil)
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func deleteCategory(_ id: UUID) async {
        do {
            try await store.deleteCategory(categoryID: id)
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func makeExport(calendar: Calendar = .current) async {
        do {
            let rows = try await store.txnRows()
            let document = CSVDocumentBuilder.document(rows, timeZone: calendar.timeZone)
            state.exportDocument = document
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func makeBackup() async {
        state.errorMessage = nil
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            let backup = try await store.exportBackup()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            state.backupData = try encoder.encode(backup)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Backup failed."
        }
    }

    /// Additive import — adds only records whose UUID isn't already on this device.
    public func mergeBackup(data: Data) async {
        state.errorMessage = nil
        state.importedCount = nil
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(KharchaBackup.self, from: data)
            let count = try await store.importBackup(backup)
            await load()
            state.importWasReplace = false
            state.importedCount = count
        } catch {
            state.errorMessage = "Could not read backup file. Make sure it's a valid Kharcha backup."
        }
    }

    /// Erases all local data first, then imports the backup. Decodes the backup before
    /// deleting anything — if the file is invalid, existing data is left untouched.
    public func replaceAndImportBackup(data: Data) async {
        state.errorMessage = nil
        state.importedCount = nil
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // Validate before erasing — bail here if the file is corrupt.
            let backup = try decoder.decode(KharchaBackup.self, from: data)
            try await store.deleteAllData()
            let count = try await store.importBackup(backup)
            await load()
            state.importWasReplace = true
            state.importedCount = count
        } catch {
            await load()
            state.errorMessage = "Restore failed. Your data may be in an inconsistent state. Please try again."
        }
    }

    public func clearImportResult() {
        state.importedCount = nil
    }

    public func deleteAllData() async {
        state.errorMessage = nil
        state.isWorking = true
        defer { state.isWorking = false }
        do {
            try await store.deleteAllData()
            await load()
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
