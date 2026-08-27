import SwiftUI
import UIKit
import KharchaKit

struct HistoryView: View {
    let store: ExpenseStore
    @StateObject private var vm: HistoryViewModel
    @EnvironmentObject private var privacy: PrivacyManager
    @State private var editingRow: TxnRow?
    @State private var showEditSheet = false
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

    private var activeFilterSummary: String {
        var parts: [String] = []
        if let month = selectedMonth {
            parts.append(month.formatted(.dateTime.month(.wide).year()))
        } else if let year = selectedYear {
            parts.append("\(year)")
        }
        if let kind = vm.state.filterKind {
            parts.append(kind == .expense ? String(localized: "Expenses") : String(localized: "Income"))
        }
        if let cat = vm.state.filterCategoryName { parts.append(cat) }
        if let day = vm.state.dayFilter {
            parts.append(day.formatted(.dateTime.month(.abbreviated).day()))
        }
        if !vm.state.searchText.isEmpty { parts.append("\"\(vm.state.searchText)\"") }
        return parts.joined(separator: " · ")
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

    // Aggregate totals for the currently visible (filtered) sections.
    private var filteredTxnCount: Int    { visibleSections.reduce(0) { $0 + $1.rows.count } }
    private var filteredTotalExpense: Decimal { visibleSections.reduce(0) { $0 + $1.totalExpenses } }
    private var filteredTotalIncome:  Decimal { visibleSections.reduce(0) { $0 + $1.totalIncome } }

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
                // ── 1. Kind + category filter chips ──────────────────────
                filterChipsSection

                // ── 2. Month jump strip ───────────────────────────────────
                monthSelectorSection

                // ── 3. Active filter banner ───────────────────────────────
                if hasActiveFilter {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(Color.brandPrimary)
                                .font(.callout)
                            Text(activeFilterSummary)
                                .font(.subheadline)
                                .foregroundStyle(Color.brandPrimary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                Task {
                                    searchText = ""
                                    selectedMonth = nil
                                    selectedYear = nil
                                    await vm.clearAllFilters()
                                }
                            } label: {
                                Text("Clear all")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.brandPrimary)
                            }
                        }
                    }
                }
                // ── 3b. Aggregate totals for the filtered set ─────────────
                if hasActiveFilter && !visibleSections.isEmpty {
                    Section {
                        FilterSummaryRow(
                            count: filteredTxnCount,
                            totalExpense: filteredTotalExpense,
                            totalIncome: filteredTotalIncome,
                            filterKind: vm.state.filterKind,
                            isRevealed: privacy.isRevealed
                        )
                    }
                }

                // ── 4. Expandable transaction sections ────────────────────
                ForEach(visibleSections, id: \.title) { section in
                    let isExpanded = !collapsedSections.contains(section.title)
                    Section {
                        if isExpanded {
                            ForEach(section.rows, id: \.id) { row in
                                Button {
                                    editingRow = row
                                    showEditSheet = true
                                } label: {
                                    TxnRowView(row: row)
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

                // ── 5. No-results when filters match nothing ──────────────
                if visibleSections.isEmpty && !vm.state.allRows.isEmpty && vm.state.errorMessage == nil {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No matching transactions",
                        message: "Try adjusting your search, month, or filters."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // ── 6. Analytics — collapsed by default ───────────────────
                analyticsSection
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("History")
        .toolbar {
            // Period picker — controls the analytics chart period.
            ToolbarItem(placement: .topBarLeading) {
                Picker("Period", selection: $period) {
                    Text("Week").tag(ActivityPeriod.week)
                    Text("Month").tag(ActivityPeriod.month)
                    Text("Year").tag(ActivityPeriod.year)
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showReports = true } label: {
                    Image(systemName: "chart.pie.fill")
                }
                .accessibilityLabel("Reports")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if hasActiveFilter {
                        Button("Reset All Filters", role: .destructive) {
                            Task { searchText = ""; selectedMonth = nil; selectedYear = nil; await vm.clearAllFilters() }
                        }
                    }
                    Section("Kind") {
                        Button { Task { await vm.setKindFilter(nil) } } label: {
                            if vm.state.filterKind == nil { Label("All Kinds", systemImage: "checkmark") }
                            else { Text("All Kinds") }
                        }
                        Button { Task { await vm.setKindFilter(.expense) } } label: {
                            if vm.state.filterKind == .expense { Label("Expenses", systemImage: "checkmark") }
                            else { Text("Expenses") }
                        }
                        Button { Task { await vm.setKindFilter(.income) } } label: {
                            if vm.state.filterKind == .income { Label("Income", systemImage: "checkmark") }
                            else { Text("Income") }
                        }
                    }
                    Section("Category") {
                        Button { Task { await vm.setCategoryFilter(nil) } } label: {
                            if vm.state.filterCategoryName == nil { Label("All Categories", systemImage: "checkmark") }
                            else { Text("All Categories") }
                        }
                        ForEach(vm.state.categories, id: \.id) { cat in
                            Button { Task { await vm.setCategoryFilter(cat.name) } } label: {
                                if vm.state.filterCategoryName == cat.name { Label(cat.name, systemImage: "checkmark") }
                                else { Text(cat.name) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: hasActiveFilter
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(hasActiveFilter ? "Filters active" : "Filter transactions")
            }
        }
        .sheet(isPresented: $showReports) {
            ReportsView(allRows: vm.state.allRows, categories: vm.state.categories)
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            editingRow = nil
            Task { await vm.load() }
        }) {
            NavigationStack { TxnFormView(store: store, editing: editingRow) }
        }
        .searchable(text: $searchText, prompt: "Search transactions")
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

    // MARK: - Filter chips (kind + category)

    @ViewBuilder private var filterChipsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let allActive = vm.state.filterKind == nil
                        && vm.state.filterCategoryName == nil
                        && vm.state.searchText.isEmpty
                        && vm.state.dayFilter == nil
                        && selectedMonth == nil
                        && selectedYear == nil

                    FilterChip(String(localized: "All"), icon: nil, isActive: allActive) {
                        Task { searchText = ""; selectedMonth = nil; selectedYear = nil; await vm.clearAllFilters() }
                    }
                    FilterChip(String(localized: "Expenses"), icon: "arrow.down.circle.fill",
                               isActive: vm.state.filterKind == .expense) {
                        Task { await vm.setKindFilter(vm.state.filterKind == .expense ? nil : .expense) }
                    }
                    FilterChip(String(localized: "Income"), icon: "arrow.up.circle.fill",
                               isActive: vm.state.filterKind == .income) {
                        Task { await vm.setKindFilter(vm.state.filterKind == .income ? nil : .income) }
                    }
                    if !vm.state.categories.isEmpty {
                        Divider().frame(height: 20)
                        ForEach(vm.state.categories, id: \.id) { cat in
                            FilterChip(cat.name, icon: cat.symbol,
                                       isActive: vm.state.filterCategoryName == cat.name) {
                                Task {
                                    await vm.setCategoryFilter(
                                        vm.state.filterCategoryName == cat.name ? nil : cat.name
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Year + Month jump strip

    @ViewBuilder private var monthSelectorSection: some View {
        if !vm.state.allRows.isEmpty {
            Section {
                VStack(spacing: 4) {
                    // Year row — only when data spans multiple years
                    if availableYears.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                MonthChip(label: String(localized: "All"), isActive: selectedYear == nil) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedYear = nil; selectedMonth = nil
                                    }
                                }
                                Divider().frame(height: 18)
                                ForEach(availableYears, id: \.self) { year in
                                    let active = selectedYear == year
                                    MonthChip(label: "\(year)", isActive: active) {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            if active { selectedYear = nil; selectedMonth = nil }
                                            else      { selectedYear = year; selectedMonth = nil }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 4).padding(.vertical, 2)
                        }
                    }

                    // Month row (narrows to selected year when one is active)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            let allLabel = selectedYear != nil
                                ? String(localized: "All months")
                                : String(localized: "All time")
                            MonthChip(label: allLabel, isActive: selectedMonth == nil) {
                                withAnimation(.easeInOut(duration: 0.18)) { selectedMonth = nil }
                            }
                            if !availableMonths.isEmpty {
                                Divider().frame(height: 18)
                                ForEach(availableMonths, id: \.self) { month in
                                    let isActive = selectedMonth.map {
                                        Calendar.current.isDate($0, equalTo: month, toGranularity: .month)
                                    } ?? false
                                    // Drop year suffix from chip label when year row is already selected
                                    let chipLabel = (selectedYear != nil || availableYears.count == 1)
                                        ? month.formatted(.dateTime.month(.abbreviated))
                                        : month.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                                    MonthChip(label: chipLabel, isActive: isActive) {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            if isActive {
                                                selectedMonth = nil
                                            } else {
                                                selectedMonth = month
                                                selectedYear = Calendar.current.component(.year, from: month)
                                                Task { await vm.setCalendarMonth(month) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 4).padding(.vertical, 2)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                Text("Browse by date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                Label("Analytics & Calendar", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
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
                    showEditSheet = true
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
                Button { onEdit(row) } label: { TxnRowView(row: row) }
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

// MARK: - Filter summary row (shows aggregate totals when filters are active)

private struct FilterSummaryRow: View {
    let count: Int
    let totalExpense: Decimal
    let totalIncome: Decimal
    let filterKind: TxnKind?
    let isRevealed: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Transaction count
            VStack(alignment: .leading, spacing: 1) {
                Text(count == 1 ? "1 transaction" : "\(count) transactions")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Expense total — omit when income-only filter active
            if filterKind != .income && totalExpense > 0 {
                Text(isRevealed ? "−\(AmountFormatter.money(totalExpense))" : "−••••")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.moneyOut)
            }
            // Income total — omit when expense-only filter active
            if filterKind != .expense && totalIncome > 0 {
                if filterKind != .income && totalExpense > 0 {
                    Text("  ").font(.caption) // spacer between two amounts
                }
                Text(isRevealed ? "+\(AmountFormatter.money(totalIncome))" : "+••••")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.moneyIn)
            }
        }
        .padding(.vertical, 2)
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

// MARK: - Filter chip (kind / category)

private struct FilterChip: View {
    let label: String
    let icon: String?
    let isActive: Bool
    let action: () -> Void

    init(_ label: String, icon: String?, isActive: Bool, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.isActive = isActive; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption2) }
                Text(label).font(.subheadline).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.brandPrimary : Color.secondary.opacity(0.12))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Month chip (time navigation, distinct style from filter chips)

private struct MonthChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? Color.brandPrimary : Color.secondary.opacity(0.1))
                .foregroundStyle(isActive ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(.easeInOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
