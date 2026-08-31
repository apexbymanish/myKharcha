import SwiftUI
import UIKit
import KharchaKit

struct HistoryView: View {
    let store: ExpenseStore
    @StateObject private var vm: HistoryViewModel
    @EnvironmentObject private var privacy: PrivacyManager
    @State private var editingRow: TxnRow?
    @State private var period: ActivityPeriod = .month
    @State private var searchText = ""
    @State private var selectedBarDate: Date?
    // Month navigation (client-side filter on top of VM filters)
    @State private var selectedMonth: Date? = nil
    // Sections the user has explicitly collapsed; empty = all expanded
    @State private var collapsedSections: Set<String> = []
    @State private var analyticsExpanded = false
    // Local calendar day selection — shown inline below heatmap, does NOT filter the main list
    @State private var selectedCalendarDay: Date? = nil
    @State private var showReports = false
    @State private var selectedYear: Int? = nil
    @State private var showFiltersSheet = false

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: HistoryViewModel(store: store))
    }

    // MARK: - Computed

    private var bars: [ActivityBar] {
        ActivitySeries.bars(vm.state.allRows, period: period, now: Date(), calendar: .current)
    }
    private var prevBars: [ActivityBar] {
        ActivitySeries.barsPrior(vm.state.allRows, period: period, now: Date(), calendar: .current)
    }
    private var monthBars: [ActivityBar] {
        ActivitySeries.daysInMonth(vm.state.allRows, monthOf: vm.state.calendarMonth, calendar: .current)
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

                // ── 2. Expandable transaction sections ────────────────────
                ForEach(visibleSections, id: \.title) { section in
                    let isExpanded = !collapsedSections.contains(section.title)
                    Section {
                        if isExpanded {
                            ForEach(section.rows, id: \.id) { row in
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
                        }
                    } header: {
                        ExpandableSectionHeader(
                            title: section.title,
                            totalExpenses: section.totalExpenses,
                            totalIncome: section.totalIncome,
                            filterKind: vm.state.filterKind,
                            isExpanded: isExpanded,
                            isRevealed: privacy.isRevealed
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded {
                                    collapsedSections.insert(section.title)
                                } else {
                                    collapsedSections.remove(section.title)
                                }
                            }
                        }
                    }
                }

                // ── 3. No-results when filters match nothing ──────────────
                if visibleSections.isEmpty && !vm.state.allRows.isEmpty && vm.state.errorMessage == nil {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No matching transactions",
                        message: "Try adjusting your search, month, or filters."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // ── 4. Analytics — collapsed by default ───────────────────
                analyticsSection
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
            ReportsView(allRows: vm.state.allRows, categories: vm.state.categories)
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
        .onChange(of: period) { _, _ in
            selectedBarDate = nil
            Task { await vm.setDayFilter(nil) }
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
        .onChange(of: selectedCalendarDay) { _, newDay in
            guard newDay != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("calendarDayDetail", anchor: .top)
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
                ActivitySummaryHeader(bars: bars, prevBars: prevBars, isRevealed: privacy.isRevealed)
                ActivityBarChart(
                    bars: bars,
                    unit: period == .year ? .month : .day,
                    selectedDate: $selectedBarDate
                )
                if let date = selectedBarDate {
                    BarSelectionBreakdown(allRows: vm.state.allRows, date: date, period: period) {
                        selectedBarDate = nil
                    }
                    .id("barSelectionBreakdown")
                }
                calendarContent
            } label: {
                HStack {
                    Label("Analytics & Calendar", systemImage: "chart.bar.xaxis")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Picker("Period", selection: $period) {
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

    @ViewBuilder private var calendarContent: some View {
        HStack {
            Button {
                let prev = Calendar.current.date(byAdding: .month, value: -1, to: vm.state.calendarMonth)!
                selectedCalendarDay = nil
                Task { await vm.setCalendarMonth(prev) }
            } label: {
                Image(systemName: "chevron.left").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()
            Text(vm.state.calendarMonth.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.medium))
            Spacer()

            Button {
                let next = Calendar.current.date(byAdding: .month, value: 1, to: vm.state.calendarMonth)!
                selectedCalendarDay = nil
                Task { await vm.setCalendarMonth(next) }
            } label: {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }

        MonthHeatGrid(
            bars: monthBars,
            calendar: .current,
            selectedDay: selectedCalendarDay,
            isRevealed: privacy.isRevealed
        ) { day in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                let alreadySelected = selectedCalendarDay.map {
                    Calendar.current.isDate($0, inSameDayAs: day)
                } ?? false
                selectedCalendarDay = alreadySelected ? nil : day
            }
        }

        // Inline day detail — appears immediately below the heatmap on tap.
        if let day = selectedCalendarDay {
            DayDetailExpansion(
                day: day,
                allRows: vm.state.allRows,
                categories: vm.state.categories,
                isRevealed: privacy.isRevealed,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedCalendarDay = nil }
                },
                onEdit: { row in
                    editingRow = row
                }
            )
            .id("calendarDayDetail")
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Inline day detail (shown below heatmap on tap)

private struct DayDetailExpansion: View {
    let day: Date
    let allRows: [TxnRow]
    let categories: [CategorySnapshot]
    let isRevealed: Bool
    let onDismiss: () -> Void
    let onEdit: (TxnRow) -> Void

    private var dayRows: [TxnRow] {
        allRows.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    private var totalExpense: Decimal { dayRows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    private var totalIncome:  Decimal { dayRows.filter { $0.kind == .income  }.reduce(0) { $0 + $1.amount } }

    // Show category breakdown only when 2+ transactions span 2+ distinct categories.
    private var distinctCategoryCount: Int {
        Set(dayRows.map { $0.categoryName.isEmpty ? "Other" : $0.categoryName }).count
    }
    private var showBreakdown: Bool { dayRows.count >= 2 && distinctCategoryCount >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        if totalExpense > 0 {
                            Text(isRevealed ? "−\(AmountFormatter.money(totalExpense))" : "−••••")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.moneyOut)
                        }
                        if totalIncome > 0 {
                            Text(isRevealed ? "+\(AmountFormatter.money(totalIncome))" : "+••••")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.moneyIn)
                        }
                        if dayRows.isEmpty {
                            Text("No transactions")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close day detail")
            }
            .padding(.bottom, dayRows.isEmpty ? 0 : 10)

            // Transaction rows
            ForEach(Array(dayRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.vertical, 4) }
                Button { onEdit(row) } label: { TxnRowView(row: row, categories: categories) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edits this transaction")
            }

            // Category breakdown bars — only when 2+ categories
            if showBreakdown {
                DayCategoryBars(rows: dayRows, categories: categories, isRevealed: isRevealed)
                    .padding(.top, 10)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 6)
    }
}

// MARK: - Day category breakdown bars

private struct DayCategoryBars: View {
    let rows: [TxnRow]
    let categories: [CategorySnapshot]
    let isRevealed: Bool

    private struct Bar: Identifiable {
        let id: String; let name: String; let amount: Decimal; let color: Color; let fraction: Double
    }

    private func bars(for kind: TxnKind) -> [Bar] {
        let kindRows = rows.filter { $0.kind == kind }
        guard !kindRows.isEmpty else { return [] }
        let total = kindRows.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        let grouped = Dictionary(grouping: kindRows, by: { $0.categoryName.isEmpty ? "Other" : $0.categoryName })
        let sorted = grouped
            .map { name, txns in (name, txns.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }

        let top  = sorted.prefix(4)
        let rest = sorted.dropFirst(4)

        var result: [Bar] = top.map { name, amount in
            let color = categories.first(where: { $0.name == name }).map { Color(hex: $0.colorHex) } ?? Color.brandPrimary
            let frac  = min(max(NSDecimalNumber(decimal: amount / total).doubleValue, 0), 1)
            return Bar(id: name, name: name, amount: amount, color: color, fraction: frac)
        }
        if !rest.isEmpty {
            let amt  = rest.reduce(Decimal(0)) { $0 + $1.1 }
            let frac = min(max(NSDecimalNumber(decimal: amt / total).doubleValue, 0), 1)
            result.append(Bar(id: "Others", name: "Others", amount: amt, color: .secondary, fraction: frac))
        }
        return result
    }

    var body: some View {
        let expBars = bars(for: .expense)
        let incBars = bars(for: .income)

        if !expBars.isEmpty || !incBars.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                ForEach(expBars) { bar in barRow(bar, tint: bar.color) }
                if !incBars.isEmpty && !expBars.isEmpty { Divider() }
                ForEach(incBars) { bar in barRow(bar, tint: Color.moneyIn) }
            }
        }
    }

    private func barRow(_ bar: Bar, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(bar.name).font(.caption2).lineLimit(1)
                Spacer()
                Text(isRevealed ? AmountFormatter.money(bar.amount) : "••••")
                    .font(.caption2.monospacedDigit())
                Text("\(Int((bar.fraction * 100).rounded()))%")
                    .font(.caption2).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule().fill(tint).frame(width: geo.size.width * bar.fraction)
                }
            }.frame(height: 4)
        }
    }
}

// MARK: - Expandable section header

private struct ExpandableSectionHeader: View {
    let title: String
    let totalExpenses: Decimal
    let totalIncome: Decimal
    let filterKind: TxnKind?
    let isExpanded: Bool
    let isRevealed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 10)
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

