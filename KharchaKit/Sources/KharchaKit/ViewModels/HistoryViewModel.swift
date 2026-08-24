import Foundation

@MainActor
public final class HistoryViewModel: ObservableObject {
    public struct Section: Sendable, Equatable {
        public let title: String
        public let rows: [TxnRow]
    }

    public struct State: Sendable {
        public var sections: [Section] = []
        /// Every transaction, unfiltered — drives the charts and calendar grid.
        public var allRows: [TxnRow] = []
        public var filterKind: TxnKind?
        public var filterCategoryName: String?
        /// When set, the list is limited to this day (tapped in the calendar grid).
        public var dayFilter: Date?
        public var categories: [CategorySnapshot] = []
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    public func load(calendar: Calendar = .current) async {
        state.errorMessage = nil
        do {
            let categories = try await store.categories()
            state.categories = categories
            await reloadSections(calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func setKindFilter(_ k: TxnKind?, calendar: Calendar = .current) async {
        state.filterKind = k
        await reloadSections(calendar: calendar)
    }

    public func setCategoryFilter(_ name: String?, calendar: Calendar = .current) async {
        state.filterCategoryName = name
        await reloadSections(calendar: calendar)
    }

    /// Limit the list to a single day (calendar tap); pass nil to clear.
    public func setDayFilter(_ day: Date?, calendar: Calendar = .current) async {
        state.dayFilter = day
        await reloadSections(calendar: calendar)
    }

    public func delete(_ id: UUID, calendar: Calendar = .current) async {
        do {
            try await store.deleteTxn(txnID: id)
            await reloadSections(calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    private func reloadSections(calendar: Calendar) async {
        state.errorMessage = nil
        do {
            let all = try await store.txnRows()
            state.allRows = all
            let rows = all
                .filter { state.filterKind == nil || $0.kind == state.filterKind! }
                .filter { state.filterCategoryName == nil || $0.categoryName == state.filterCategoryName! }
                .filter { state.dayFilter == nil || calendar.isDate($0.date, inSameDayAs: state.dayFilter!) }
                .sorted { $0.date > $1.date }

            let grouped = Dictionary(grouping: rows) { row in
                let c = calendar.dateComponents([.year, .month], from: row.date)
                return c.year! * 100 + c.month!
            }

            let titleFormatter = DateFormatter()
            titleFormatter.dateFormat = "MMMM yyyy"
            titleFormatter.locale = Locale(identifier: "en_US_POSIX")
            titleFormatter.timeZone = calendar.timeZone

            state.sections = grouped.keys.sorted(by: >).map { key in
                Section(title: titleFormatter.string(from: grouped[key]![0].date), rows: grouped[key]!)
            }
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
