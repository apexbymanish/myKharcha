import Foundation

@MainActor
public final class HistoryViewModel: ObservableObject {
    public struct Section: Sendable, Equatable {
        public let title: String
        public let totalExpenses: Decimal
        public let totalIncome: Decimal
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
        /// Text search across note and category name.
        public var searchText: String = ""
        public var categories: [CategorySnapshot] = []
        public var errorMessage: String?
        /// The month shown in the calendar heat grid — navigable independently.
        public var calendarMonth: Date = Date()

        /// True when any kind or category filter is active.
        public var hasActiveFilters: Bool {
            filterKind != nil || filterCategoryName != nil
        }
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    /// Localized "Month Year" formatter, created once (DateFormatter is expensive).
    private static let sectionTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f
    }()

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

    /// Filter by free-text across note and category name. Empty string clears the filter.
    public func setSearchFilter(_ text: String, calendar: Calendar = .current) async {
        state.searchText = text
        await reloadSections(calendar: calendar)
    }

    /// Clears all active filters (kind, category, day) in one shot.
    public func clearAllFilters(calendar: Calendar = .current) async {
        state.filterKind = nil
        state.filterCategoryName = nil
        state.dayFilter = nil
        await reloadSections(calendar: calendar)
    }

    /// Navigate the calendar heat grid to a different month; also clears the day filter.
    public func setCalendarMonth(_ date: Date, calendar: Calendar = .current) async {
        state.calendarMonth = date
        state.dayFilter = nil
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
            let query = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let rows = all
                .filter { state.filterKind == nil || $0.kind == state.filterKind! }
                .filter { state.filterCategoryName == nil || $0.categoryName == state.filterCategoryName! }
                .filter { state.dayFilter == nil || calendar.isDate($0.date, inSameDayAs: state.dayFilter!) }
                .filter {
                    query.isEmpty
                        || $0.categoryName.localizedCaseInsensitiveContains(query)
                        || $0.note?.localizedCaseInsensitiveContains(query) == true
                }
                .sorted { $0.date > $1.date }

            let grouped = Dictionary(grouping: rows) { row in
                let c = calendar.dateComponents([.year, .month], from: row.date)
                return c.year! * 100 + c.month!
            }

            state.sections = grouped.keys.sorted(by: >).map { key in
                let sectionRows = grouped[key]!
                let expenses = sectionRows
                    .filter { $0.kind == .expense }
                    .reduce(Decimal(0)) { $0 + $1.amount }
                let income = sectionRows
                    .filter { $0.kind == .income }
                    .reduce(Decimal(0)) { $0 + $1.amount }
                return Section(
                    title: Self.sectionTitleFormatter.string(from: sectionRows[0].date),
                    totalExpenses: expenses,
                    totalIncome: income,
                    rows: sectionRows
                )
            }
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
