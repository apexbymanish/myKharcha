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

        /// Time scope of the History chart (week/month/year), set by the W|M|Y control.
        public var chartPeriod: ActivityPeriod = .month
        /// The period the chart is currently scrolled to. This is the single source
        /// of truth for what the chart and its header describe — never `Date()`.
        public var chartAnchor: Date = Date()
        /// Bars spanning the whole timeline, so the chart can be scrolled through it.
        /// Cached here rather than recomputed on every SwiftUI body pass.
        public var chartBars: [ActivityBar] = []
        /// Totals and period-over-period change for `chartAnchor`'s window.
        public var chartSummary: ActivitySummary?
        /// Budget one bar is measured against, for the bar colours. Zero when the
        /// user has set no category budgets, which renders bars in a neutral tint.
        public var chartAllowance: Decimal = 0
        /// The period the chart came to rest on. `chartAnchor` moves continuously
        /// under the finger so the headline can track it; this only catches up once
        /// scrolling stops, so the transaction list is not rebuilt every frame.
        public var settledAnchor: Date = Date()

        /// True when any kind or category filter is active.
        public var hasActiveFilters: Bool {
            filterKind != nil || filterCategoryName != nil
        }
    }

    @Published public private(set) var state = State()

    /// How many buckets the chart shows at once. Lives here rather than only in
    /// the view because the opening anchor has to be chosen against the same
    /// window the chart will draw — pick a different number in either place and
    /// the header describes a span the bars do not.
    public static let chartVisibleBuckets = 9

    /// Set once the opening window has been chosen. Later reloads — a foreground,
    /// a remote change, returning from an edit — must not drag the chart back to
    /// the newest data while the user is reading an older month.
    private var hasChosenOpeningAnchor = false
    private let store: ExpenseStore
    /// "Today" as far as the scrollable domain is concerned, captured once per load
    /// so the domain stays put while the user scrolls around inside it.
    private var seriesNow = Date()

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

    /// Move the chart to the period containing `date` — driven by the chart's scroll
    /// position, so the header and totals follow whatever is on screen.
    ///
    /// Only the summary is recomputed. The scrollable domain must stay fixed while
    /// scrolling, or the anchor would feed back into it and the timeline would keep
    /// growing under the user's finger. It is also the expensive half.
    public func setChartAnchor(_ date: Date, calendar: Calendar = .current) async {
        state.chartAnchor = date
        recomputeSummary(calendar: calendar)
    }

    /// Switch the chart's time scope. `chartAnchor` is deliberately left alone, so
    /// month→week lands in a week of the month being viewed instead of snapping
    /// back to today and discarding where the user had navigated to.
    public func setChartPeriod(_ period: ActivityPeriod, calendar: Calendar = .current) async {
        state.chartPeriod = period
        recomputeChart(calendar: calendar)
    }

    /// Called when the chart's scroll comes to rest. Brings the list's period up to
    /// where the chart actually stopped — deferred until now so a fling costs one
    /// list rebuild rather than one per frame.
    public func settleChartAnchor(calendar: Calendar = .current) async {
        guard state.settledAnchor != state.chartAnchor else { return }
        state.settledAnchor = state.chartAnchor
        await reloadSections(calendar: calendar)
    }

    /// Rebuilds both halves — the scrollable domain and the summary on top of it.
    private func recomputeChart(calendar: Calendar) {
        recomputeSeries(calendar: calendar)
        recomputeSummary(calendar: calendar)
    }

    /// The scrollable domain, spanning the data plus today. Deliberately independent
    /// of `chartAnchor` so scrolling can never extend it.
    private func recomputeSeries(calendar: Calendar) {
        state.chartBars = ActivitySeries.continuousBars(
            state.allRows, period: state.chartPeriod, now: seriesNow, calendar: calendar
        )
        chooseOpeningAnchorIfNeeded()
    }

    /// Open on the newest bucket that actually holds something, rather than on
    /// today.
    ///
    /// `continuousBars` runs the domain out to `now`, so a ledger whose last row
    /// is weeks old ends in a run of empty buckets. Anchoring at `Date()` opened
    /// the chart inside that run: the header totalled an empty window and said
    /// "No spend" while the bars the user could see held six figures, and the
    /// y-ceiling — measured over the same empty window — collapsed to its
    /// fallback, so those bars overflowed the domain, clipped square at the top
    /// and took the income scale down with them.
    ///
    /// Choosing the window here, before the view is built, means the anchor and
    /// the drawn window agree on the first frame rather than after a scroll.
    private func chooseOpeningAnchorIfNeeded() {
        // Latch only once the series actually holds activity. It used to latch on
        // the first non-empty *array*, which a series built before the rows had
        // loaded satisfies — every bucket zero. The anchor was then chosen from
        // nothing and never revisited, and the header spent the session
        // describing a window the chart was not drawing.
        guard !hasChosenOpeningAnchor,
              let newest = state.chartBars.lastIndex(where: { $0.expense > 0 || $0.income > 0 })
        else { return }
        hasChosenOpeningAnchor = true

        let start = max(0, newest - (Self.chartVisibleBuckets - 1))
        let date = state.chartBars[start].date
        state.chartAnchor = date
        state.settledAnchor = date
        ChartDiagnostics.log("openingAnchor bars=\(state.chartBars.count) newest=\(newest) start=\(start) date=\(date)")
    }

    /// Totals and change for whichever window the chart is scrolled to, plus the
    /// per-bar budget allowance those bars are coloured against.
    private func recomputeSummary(calendar: Calendar) {
        state.chartSummary = ActivitySeries.summary(
            state.allRows, period: state.chartPeriod, containing: state.chartAnchor, calendar: calendar
        )
        let budgetTotal = state.categories.compactMap(\.monthlyBudget).reduce(Decimal(0), +)
        let days = calendar.range(of: .day, in: .month, for: state.chartAnchor)?.count ?? 30
        state.chartAllowance = ActivitySeries.allowancePerBucket(
            monthlyBudgetTotal: budgetTotal, period: state.chartPeriod, daysInMonth: days
        )
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

            // Chart reads from the unfiltered ledger, so it refreshes whenever rows do.
            recomputeChart(calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
