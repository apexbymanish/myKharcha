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

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: HistoryViewModel(store: store))
    }

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
        vm.state.hasActiveFilters || vm.state.dayFilter != nil || !vm.state.searchText.isEmpty
    }

    private var activeFilterSummary: String {
        var parts: [String] = []
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

    var body: some View {
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
                // ── Filter chips ─────────────────────────────────────────
                filterChipsSection

                // ── Active filter banner ──────────────────────────────────
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
                                Task { searchText = ""; await vm.clearAllFilters() }
                            } label: {
                                Text("Clear")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.brandPrimary)
                            }
                        }
                    }
                }

                // ── Transaction list (primary — shown first) ──────────────
                ForEach(vm.state.sections, id: \.title) { section in
                    Section {
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
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            if vm.state.filterKind == .income {
                                Text(privacy.isRevealed
                                     ? "+\(AmountFormatter.money(section.totalIncome))"
                                     : "+••••")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.moneyIn.opacity(0.8))
                            } else {
                                Text(privacy.isRevealed
                                     ? "−\(AmountFormatter.money(section.totalExpenses))"
                                     : "−••••")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // No-results: history exists but filters matched nothing.
                if vm.state.sections.isEmpty && !vm.state.allRows.isEmpty && vm.state.errorMessage == nil {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No matching transactions",
                        message: "Try adjusting your search or filters."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // ── Analytics (scroll down to see charts) ─────────────────
                chartsSection
                calendarSection
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("History")
        .toolbar {
            // Period picker in toolbar — always accessible without scrolling.
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
                            Task { searchText = ""; await vm.clearAllFilters() }
                        }
                    }
                    Section("Kind") {
                        Button {
                            Task { await vm.setKindFilter(nil) }
                        } label: {
                            if vm.state.filterKind == nil {
                                Label("All Kinds", systemImage: "checkmark")
                            } else {
                                Text("All Kinds")
                            }
                        }
                        Button {
                            Task { await vm.setKindFilter(.expense) }
                        } label: {
                            if vm.state.filterKind == .expense {
                                Label("Expense", systemImage: "checkmark")
                            } else {
                                Text("Expense")
                            }
                        }
                        Button {
                            Task { await vm.setKindFilter(.income) }
                        } label: {
                            if vm.state.filterKind == .income {
                                Label("Income", systemImage: "checkmark")
                            } else {
                                Text("Income")
                            }
                        }
                    }
                    Section("Category") {
                        Button {
                            Task { await vm.setCategoryFilter(nil) }
                        } label: {
                            if vm.state.filterCategoryName == nil {
                                Label("All Categories", systemImage: "checkmark")
                            } else {
                                Text("All Categories")
                            }
                        }
                        ForEach(vm.state.categories, id: \.id) { category in
                            Button {
                                Task { await vm.setCategoryFilter(category.name) }
                            } label: {
                                if vm.state.filterCategoryName == category.name {
                                    Label(category.name, systemImage: "checkmark")
                                } else {
                                    Text(category.name)
                                }
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
            NavigationStack {
                TxnFormView(store: store, editing: editingRow)
            }
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
    }

    // MARK: - Filter chips

    @ViewBuilder private var filterChipsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let allActive = vm.state.filterKind == nil
                        && vm.state.filterCategoryName == nil
                        && vm.state.searchText.isEmpty
                        && vm.state.dayFilter == nil

                    FilterChip(
                        String(localized: "All"),
                        icon: nil,
                        isActive: allActive
                    ) {
                        Task { searchText = ""; await vm.clearAllFilters() }
                    }

                    FilterChip(
                        String(localized: "Expenses"),
                        icon: "arrow.down.circle.fill",
                        isActive: vm.state.filterKind == .expense
                    ) {
                        Task { await vm.setKindFilter(vm.state.filterKind == .expense ? nil : .expense) }
                    }

                    FilterChip(
                        String(localized: "Income"),
                        icon: "arrow.up.circle.fill",
                        isActive: vm.state.filterKind == .income
                    ) {
                        Task { await vm.setKindFilter(vm.state.filterKind == .income ? nil : .income) }
                    }

                    if !vm.state.categories.isEmpty {
                        Divider().frame(height: 20)
                        ForEach(vm.state.categories, id: \.id) { cat in
                            FilterChip(
                                cat.name,
                                icon: cat.symbol,
                                isActive: vm.state.filterCategoryName == cat.name
                            ) {
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

    // MARK: - Analytics

    @ViewBuilder private var chartsSection: some View {
        Section {
            // Summary header with "vs prior period" deltas.
            ActivitySummaryHeader(bars: bars, prevBars: prevBars, isRevealed: privacy.isRevealed)
            // Bar chart — tap a bar to open its category breakdown.
            ActivityBarChart(
                bars: bars,
                unit: period == .year ? .month : .day,
                selectedDate: $selectedBarDate
            )
            if let date = selectedBarDate {
                BarSelectionBreakdown(
                    allRows: vm.state.allRows,
                    date: date,
                    period: period
                ) {
                    selectedBarDate = nil
                }
            }
        } header: {
            Text("Analytics")
        }
    }

    @ViewBuilder private var calendarSection: some View {
        Section {
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
                selectedDay: vm.state.dayFilter,
                isRevealed: privacy.isRevealed
            ) { day in
                let alreadySelected = vm.state.dayFilter.map {
                    Calendar.current.isDate($0, inSameDayAs: day)
                } ?? false
                Task { await vm.setDayFilter(alreadySelected ? nil : day) }
            }
            if let day = vm.state.dayFilter {
                Button {
                    Task { await vm.setDayFilter(nil) }
                } label: {
                    Label("Showing \(day.formatted(.dateTime.month().day())) — tap to show all",
                          systemImage: "xmark.circle.fill")
                        .font(.caption)
                }
            }
        } header: {
            Text("Calendar")
        }
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let icon: String?
    let isActive: Bool
    let action: () -> Void

    init(_ label: String, icon: String?, isActive: Bool, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.caption2)
                }
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)
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
