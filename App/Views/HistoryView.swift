import SwiftUI
import UIKit
import KharchaKit

struct HistoryView: View {
    let store: ExpenseStore
    @StateObject private var vm: HistoryViewModel
    @EnvironmentObject private var privacy: PrivacyManager
    @State private var editingRow: TxnRow?
    @State private var searchText = ""
    @State private var selectedBarDate: Date?
    // Month navigation (client-side filter on top of VM filters)
    @State private var selectedMonth: Date? = nil
    // Sections the user has opened in full via "Show all"; the rest show a preview.
    @State private var fullyShownSections: Set<String> = []
    // Expanded by default: the chart now sits at the top of the screen, so
    // landing on a collapsed row would hide the thing you came to see.
    @State private var analyticsExpanded = true
    // Local calendar day selection — shown inline below heatmap, does NOT filter the main list
    @State private var showReports = false
    @State private var selectedYear: Int? = nil
    @State private var showFiltersSheet = false

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: HistoryViewModel(store: store))
    }

    // MARK: - Computed

    /// The scope currently shown by the chart. Owned by the view model so the
    /// scroll position, the summary and the bars can never disagree about it.
    private var period: ActivityPeriod { vm.state.chartPeriod }

    /// Debounces the end of a scroll. `chartScrollPosition` fires continuously
    /// while a fling decelerates, so each update cancels the previous pending
    /// settle; whichever one survives the quiet gap is the real stop.
    @State private var settleTask: Task<Void, Never>?

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await vm.settleChartAnchor()
        }
    }


    private var hasActiveFilter: Bool {
        vm.state.hasActiveFilters
            || vm.state.dayFilter != nil
            || !vm.state.searchText.isEmpty
            || selectedMonth != nil
            || selectedYear != nil
    }

    // Unique years derived from all transactions, newest first.
    private var availableYears: [Int] {
        let years = Set(vm.state.allRows.map { Calendar.current.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    // Unique months derived from all transactions (filtered to selectedYear when set), newest first.
    private var availableMonths: [Date] {
        let cal = Calendar.current
        let months = Set(vm.state.allRows.compactMap { row -> Date? in
            if let year = selectedYear, cal.component(.year, from: row.date) != year { return nil }
            var comps = cal.dateComponents([.year, .month], from: row.date)
            comps.day = 1
            return cal.date(from: comps)
        })
        return months.sorted(by: >)
    }

    // Transaction count for the currently visible (filtered) sections — shown
    // as the Filters sheet's live "Show N results" button.
    private var filteredTxnCount: Int { visibleSections.reduce(0) { $0 + $1.rows.count } }

    /// One month's rows plus its "Show all" disclosure.
    ///
    /// Extracted from `body` rather than inlined: with the section built in place
    /// the type-checker gave up on the whole `List` expression.
    @ViewBuilder
    private func transactionSection(_ section: HistoryViewModel.Section) -> some View {
        let shown = visibleRows(of: section)
        Section {
            ForEach(shown, id: \.id) { row in
                Button {
                    editingRow = row
                } label: {
                    TxnRowView(row: row, categories: vm.state.categories)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edits this transaction")
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await vm.delete(row.id) }
                    }
                }
            }

            // The count is the point: four of six is not worth a tap, four of
            // two hundred is. A bare chevron hides that.
            if section.rows.count > shown.count {
                showAllButton(for: section)
            }
        } header: {
            SectionHeader(
                title: section.title,
                totalExpenses: section.totalExpenses,
                totalIncome: section.totalIncome,
                filterKind: vm.state.filterKind,
                isRevealed: privacy.isRevealed
            )
        }
    }

    private func showAllButton(for section: HistoryViewModel.Section) -> some View {
        Button {
            // Discard `insert`'s tuple: as a single-expression closure it would be
            // withAnimation's return value, which collides with the action's Void.
            withAnimation(.easeInOut(duration: 0.2)) {
                _ = fullyShownSections.insert(section.title)
            }
        } label: {
            HStack {
                Text("Show all \(section.rows.count) transactions")
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.brandPrimary)
        }
        .buttonStyle(.plain)
    }

    /// How many rows a month shows before the "Show all" row appears. Enough to
    /// see the shape of a month without any one month filling the screen.
    private static let previewRowCount = 4

    /// The rows a section actually renders. Every section shows a preview; tapping
    /// "Show all" opens that one section fully. There is deliberately no
    /// month-level collapse — the preview already keeps the screen usable, so a
    /// second disclosure governing the same rows would be redundant machinery.
    private func visibleRows(of section: HistoryViewModel.Section) -> [TxnRow] {
        if fullyShownSections.contains(section.title) { return section.rows }
        return Array(section.rows.prefix(Self.previewRowCount))
    }

    // Sections after applying the client-side month/year filter.
    private var visibleSections: [HistoryViewModel.Section] {
        let cal = Calendar.current
        if let month = selectedMonth {
            return vm.state.sections.filter { section in
                section.rows.contains { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
            }
        } else if let year = selectedYear {
            return vm.state.sections.filter { section in
                section.rows.contains { cal.component(.year, from: $0.date) == year }
            }
        }
        return vm.state.sections
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
        List {
            if vm.state.allRows.isEmpty && vm.state.errorMessage == nil {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No history yet",
                    message: "Transactions you log will appear here, grouped by month."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                // ── 1. Type segment (All / Expenses / Income) ─────────────
                controlsRowSection

                // ── 2. Analytics — above the ledger, so the chart is what you
                //      land on rather than a stack of collapsed month rows ───
                analyticsSection

                // ── 3. Transaction sections, previewed ────────────────────
                ForEach(visibleSections, id: \.title) { section in
                    transactionSection(section)
                }

                // ── 4. No-results when filters match nothing ──────────────
                if visibleSections.isEmpty && !vm.state.allRows.isEmpty && vm.state.errorMessage == nil {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No matching transactions",
                        message: "Try adjusting your search, month, or filters."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showReports = true } label: {
                    Image(systemName: "chart.pie.fill")
                }
                .accessibilityLabel("Reports")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFiltersSheet = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filters")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.brandPrimary, in: Capsule())
                    .foregroundStyle(.white)
                    .overlay(alignment: .topTrailing) {
                        if hasActiveFilter {
                            Circle()
                                .fill(Color.moneyIn)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .accessibilityLabel(hasActiveFilter ? "Filters active" : "Filter transactions")
            }
        }
        .sheet(isPresented: $showReports) {
            ReportsView(allRows: vm.state.allRows, categories: vm.state.categories,
                        initialMonth: vm.state.chartAnchor)
        }
        .sheet(item: $editingRow, onDismiss: {
            Task { await vm.load() }
        }) { row in
            NavigationStack { TxnFormView(store: store, editing: row) }
        }
        .sheet(isPresented: $showFiltersSheet) {
            FiltersSheetView(
                vm: vm,
                selectedYear: $selectedYear,
                selectedMonth: $selectedMonth,
                availableYears: availableYears,
                availableMonths: availableMonths,
                resultsCount: filteredTxnCount,
                onReset: {
                    searchText = ""
                    selectedMonth = nil
                    selectedYear = nil
                    Task { await vm.clearAllFilters() }
                }
            )
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search transactions")
        .onChange(of: searchText) { _, text in Task { await vm.setSearchFilter(text) } }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onChange(of: vm.state.chartPeriod) { _, _ in
            selectedBarDate = nil
            Task { await vm.setDayFilter(nil) }
        }
        // Picking a month in Filters moves the chart to it, so the list filter and
        // the chart can't end up describing different months.
        .onChange(of: selectedMonth) { _, month in
            guard let month else { return }
            Task { await vm.setChartAnchor(month) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kharchaRemoteDidChange)) { _ in
            Task { await vm.load() }
        }
        .onChange(of: selectedBarDate) { _, newDate in
            guard newDate != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("barSelectionBreakdown", anchor: .top)
                }
            }
        }
        } // ScrollViewReader
    }

    // MARK: - Controls row (Type segment)

    @ViewBuilder private var controlsRowSection: some View {
        Section {
            Picker("Type", selection: kindFilterBinding) {
                Text("All").tag(TxnKindFilter.all)
                Text("Expenses").tag(TxnKindFilter.expense)
                Text("Income").tag(TxnKindFilter.income)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    /// Maps the VM's optional `filterKind` to/from the 3-way segment, used by
    /// both the controls row above and the Filters sheet's Type section.
    private var kindFilterBinding: Binding<TxnKindFilter> {
        Binding(
            get: {
                switch vm.state.filterKind {
                case .expense: return .expense
                case .income: return .income
                case nil: return .all
                }
            },
            set: { newValue in
                Task {
                    switch newValue {
                    case .all: await vm.setKindFilter(nil)
                    case .expense: await vm.setKindFilter(.expense)
                    case .income: await vm.setKindFilter(.income)
                    }
                }
            }
        )
    }

    // MARK: - Analytics (collapsed by default)

    @ViewBuilder private var analyticsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $analyticsExpanded) {
                if let summary = vm.state.chartSummary {
                    ChartHeadline(summary: summary, period: period, isRevealed: privacy.isRevealed)
                }
                ActivityBarChart(
                    // The whole timeline, so the chart can be scrolled through it —
                    // not just the anchored window the header summarises.
                    bars: vm.state.chartBars,
                    unit: period == .year ? .month : .day,
                    selectedDate: $selectedBarDate,
                    period: period,
                    allowance: vm.state.chartAllowance,
                    scrollPosition: Binding(
                        get: { vm.state.chartAnchor },
                        set: { newAnchor in
                            // Paging away from a selected bar makes the selection
                            // meaningless, so drop it as the window moves.
                            selectedBarDate = nil
                            // The chart is the navigator once the user scrolls it —
                            // release the Filters month so the two can't contradict.
                            selectedMonth = nil
                            // The headline follows the finger; the list waits for
                            // the scroll to stop (see settleTask below).
                            Task { await vm.setChartAnchor(newAnchor) }
                            scheduleSettle()
                        }
                    )
                )
                if let date = selectedBarDate {
                    BarSelectionBreakdown(allRows: vm.state.allRows, date: date, period: period) {
                        selectedBarDate = nil
                    }
                    .id("barSelectionBreakdown")
                }
            } label: {
                HStack {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Picker("Period", selection: Binding(
                        get: { vm.state.chartPeriod },
                        set: { newPeriod in
                            // Selection is meaningless once the buckets change shape.
                            selectedBarDate = nil
                            Task { await vm.setChartPeriod(newPeriod) }
                        }
                    )) {
                        Text("Week").tag(ActivityPeriod.week)
                        Text("Month").tag(ActivityPeriod.month)
                        Text("Year").tag(ActivityPeriod.year)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }
            }
        }
    }

}

// MARK: - Expandable section header

/// A month's title and total. Informational only — the section always shows a
/// preview of its rows, so there is nothing here to collapse. The one disclosure
/// is the "Show all" row at the foot of each section, which keeps a single
/// control governing a single thing rather than nesting two.
private struct SectionHeader: View {
    let title: String
    let totalExpenses: Decimal
    let totalIncome: Decimal
    let filterKind: TxnKind?
    let isRevealed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            if filterKind == .income {
                Text(isRevealed ? "+\(AmountFormatter.money(totalIncome))" : "+••••")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.moneyIn.opacity(0.85))
            } else {
                Text(isRevealed ? "−\(AmountFormatter.money(totalExpenses))" : "−••••")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

