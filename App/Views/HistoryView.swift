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
    /// Bar tapped in the chart — drives the BarSelectionBreakdown panel.
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

    /// True when any filter (kind, category, day, search) is active.
    private var hasActiveFilter: Bool {
        vm.state.hasActiveFilters || vm.state.dayFilter != nil || !vm.state.searchText.isEmpty
    }

    /// Human-readable summary of all active filters, e.g. "Expenses · Food · Oct 15".
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
                chartsSection
                calendarSection
            }
            // Active filter banner — tells the user exactly what is being filtered.
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
                                await vm.clearAllFilters()
                            }
                        } label: {
                            Text("Clear")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
            }

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
                        // Adapt the section summary to the active kind filter.
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
            // No-results state: history exists but filters matched nothing.
            if vm.state.sections.isEmpty && !vm.state.allRows.isEmpty && vm.state.errorMessage == nil {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No matching transactions",
                    message: "Try adjusting your search or filters."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Reset all is shown first whenever any filter is active.
                    if hasActiveFilter {
                        Button("Reset All Filters", role: .destructive) {
                            Task {
                                searchText = ""
                                await vm.clearAllFilters()
                            }
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
                    // Filled icon signals that at least one filter is active.
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
        // Reset chart selection AND day filter when the user switches chart periods.
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

    @ViewBuilder private var chartsSection: some View {
        Section {
            Picker("Period", selection: $period) {
                Text("Week").tag(ActivityPeriod.week)
                Text("Month").tag(ActivityPeriod.month)
                Text("Year").tag(ActivityPeriod.year)
            }
            .pickerStyle(.segmented)
            // Summary header with "vs prior period" deltas.
            ActivitySummaryHeader(bars: bars, prevBars: prevBars, isRevealed: privacy.isRevealed)
            // Bar chart — tap a bar to open its category breakdown.
            ActivityBarChart(
                bars: bars,
                unit: period == .year ? .month : .day,
                selectedDate: $selectedBarDate
            )
            // Category breakdown panel — appears when a bar is selected.
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
            Text("Spending & income")
        }
    }

    @ViewBuilder private var calendarSection: some View {
        Section {
            // Month navigation — allows browsing any month's heat grid.
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
                let alreadySelected = vm.state.dayFilter.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
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
