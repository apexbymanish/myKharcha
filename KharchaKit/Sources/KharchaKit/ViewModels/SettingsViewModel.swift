import Foundation

@MainActor
public final class SettingsViewModel: ObservableObject {
    public struct State: Sendable {
        public var categories: [CategorySnapshot] = []
        public var exportDocument: String?
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
}
