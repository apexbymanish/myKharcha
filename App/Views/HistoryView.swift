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
    }

    private var activeFilterSummary: String {
        var parts: [String] = []
        if let month = selectedMonth {
            parts.append(month.formatted(.dateTime.month(.wide).year()))
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

    // Unique months derived from all transactions, newest first.
    private var availableMonths: [Date] {
        let cal = Calendar.current
        let months = Set(vm.state.allRows.compactMap { row -> Date? in
            var comps = cal.dateComponents([.year, .month], from: row.date)
            comps.day = 1
            return cal.date(from: comps)
        })
        return months.sorted(by: >)
    }

    // Sections after applying the client-side month filter.
    private var visibleSections: [HistoryViewModel.Section] {
        guard let month = selectedMonth else { return vm.state.sections }
        let cal = Calendar.current
        return vm.state.sections.filter { section in
            section.rows.contains { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        }
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
                Menu {
                    if hasActiveFilter {
                        Button("Reset All Filters", role: .destructive) {
                            Task { searchText = ""; selectedMonth = nil; await vm.clearAllFilters() }
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
        .onChange(of: selectedCalendarDay) { _, newDay in
            guard newDay != nil else { return }
            Task { @MainActor in
                // Wait one frame so DayDetailExpansion is in the hierarchy before scrolling.
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

                    FilterChip(String(localized: "All"), icon: nil, isActive: allActive) {
                        Task { searchText = ""; selectedMonth = nil; await vm.clearAllFilters() }
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

    // MARK: - Month jump strip

    @ViewBuilder private var monthSelectorSection: some View {
        if !availableMonths.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        MonthChip(label: String(localized: "All time"), isActive: selectedMonth == nil) {
                            withAnimation(.easeInOut(duration: 0.18)) { selectedMonth = nil }
                        }
                        Divider().frame(height: 18)
                        ForEach(availableMonths, id: \.self) { month in
                            let isActive = selectedMonth.map {
                                Calendar.current.isDate($0, equalTo: month, toGranularity: .month)
                            } ?? false
                            MonthChip(
                                label: month.formatted(.dateTime.month(.abbreviated).year(.twoDigits)),
                                isActive: isActive
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedMonth = isActive ? nil : month
                                    if !isActive {
                                        Task { await vm.setCalendarMonth(month) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                Text("Month")
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
                }
                calendarContent
            } label: {
                Label("Analytics & Calendar", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .onChange(of: period) { _, _ in
            selectedBarDate = nil
            Task { await vm.setDayFilter(nil) }
        }
    }

    @ViewBuilder private var calendarContent: some View {
        HStack {
            Button {
                let prev = Calendar.current.date(byAdding: .month, value: -1, to: vm.state.calendarMonth)!
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
    let isRevealed: Bool
    let onDismiss: () -> Void
    let onEdit: (TxnRow) -> Void

    private var dayRows: [TxnRow] {
        allRows.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    private var totalExpense: Decimal { dayRows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    private var totalIncome: Decimal  { dayRows.filter { $0.kind == .income  }.reduce(0) { $0 + $1.amount } }

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
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                if index > 0 {
                    Divider().padding(.vertical, 4)
                }
                Button { onEdit(row) } label: {
                    TxnRowView(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edits this transaction")
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 6)
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
