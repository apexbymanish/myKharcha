import SwiftUI
import UIKit
import KharchaKit

struct HistoryView: View {
    let store: ExpenseStore
    @StateObject private var vm: HistoryViewModel
    @State private var editingRow: TxnRow?
    @State private var showEditSheet = false
    @State private var period: ActivityPeriod = .month
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
        ActivitySeries.daysInMonth(vm.state.allRows, monthOf: Date(), calendar: .current)
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
            ForEach(vm.state.sections, id: \.title) { section in
                Section(section.title) {
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
            }
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Kind") {
                        Button("All Kinds") { Task { await vm.setKindFilter(nil) } }
                        Button("Expense") { Task { await vm.setKindFilter(.expense) } }
                        Button("Income") { Task { await vm.setKindFilter(.income) } }
                    }
                    Section("Category") {
                        Button("All Categories") { Task { await vm.setCategoryFilter(nil) } }
                        ForEach(vm.state.categories, id: \.id) { category in
                            Button(category.name) { Task { await vm.setCategoryFilter(category.name) } }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter transactions")
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
        .task { await vm.load() }
        .refreshable { await vm.load() }
        // Reset bar selection when the user switches periods.
        .onChange(of: period) { _, _ in selectedBarDate = nil }
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
            ActivitySummaryHeader(bars: bars, prevBars: prevBars)
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
            MonthHeatGrid(bars: monthBars, calendar: .current, selectedDay: vm.state.dayFilter) { day in
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
