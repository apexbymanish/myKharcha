import SwiftUI
import UIKit
import KharchaKit

struct HistoryView: View {
    let store: ExpenseStore
    @StateObject private var vm: HistoryViewModel
    @EnvironmentObject private var privacy: PrivacyManager
    @State private var editingRow: TxnRow?
    @State private var selectedBarDate: Date?
    // Month navigation (client-side filter on top of VM filters)
    @State private var selectedMonth: Date? = nil
    @State private var showReports = false
    @State private var selectedYear: Int? = nil

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

    /// Spent, received and net for whatever the chart is showing — the Pedometer++
    /// hero, where one figure dominates and the others qualify it. Income used to
    /// exist only as a second bar colour, which was easy to miss entirely.
    @ViewBuilder private var heroBlock: some View {
        if let s = vm.state.chartSummary {
            VStack(spacing: 2) {
                Text(privacy.isRevealed ? AmountFormatter.money(s.expense) : "••••")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.moneyOut)

                if s.income > 0 {
                    Text(privacy.isRevealed
                         ? "\(AmountFormatter.money(s.income)) received"
                         : "•••• received")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.moneyIn)
                }

                let net = s.income - s.expense
                if s.income > 0 {
                    Text(privacy.isRevealed
                         ? "\(net >= 0 ? "↑" : "↓") \(AmountFormatter.money(abs(net))) net"
                         : "•••• net")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(net >= 0 ? Color.moneyIn : Color.moneyOut)
                }
            }
            .frame(maxWidth: .infinity)
            // Digits roll to their new values as you scroll to another period,
            // rather than the whole figure being swapped out. This is what Apple
            // uses for changing numbers — timers, rings, Weather.
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.3), value: s.expense)
            .animation(.smooth(duration: 0.3), value: s.income)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let error = vm.state.errorMessage {
                InlineError(message: error)
                    .padding(.horizontal)
            }

            heroBlock
                .padding(.horizontal)
                .padding(.top, 8)

            // The chart sits on the bottom of the screen, above the tab bar, with
            // the breathing room between it and the hero rather than beneath it.
            Spacer(minLength: 12)

            // The chart is always present, even with nothing in view. It used to be
            // *replaced* by the empty state, which removed the only way to scroll
            // back to a period that has data — the user was stranded.
            ZStack {
                ActivityBarChart(
                    bars: vm.state.chartBars,
                    unit: period == .year ? .month : .day,
                    selectedDate: $selectedBarDate,
                    period: period,
                    // Bands wear their category's own colour, resolved here —
                    // KharchaKit stays free of presentation.
                    categoryColors: Dictionary(
                        vm.state.categories.map { ($0.name, $0.colorHex) },
                        uniquingKeysWith: { first, _ in first }
                    ),
                    scrollPosition: Binding(
                        get: { vm.state.chartAnchor },
                        set: { newAnchor in
                            selectedBarDate = nil
                            selectedMonth = nil
                            Task { await vm.setChartAnchor(newAnchor) }
                            scheduleSettle()
                        }
                    )
                )
                // Roughly two fifths of the screen. Full-bleed only works when the
                // chart is reliably full; spending has empty days and outliers, so
                // a screen of pure chart is mostly a screen of nothing.
                .frame(height: 300)
                // Edge to edge. The 8pt inset made it read as a component sitting
                // on the screen; running to the edges makes the graph the surface
                // the screen is built on, which is what Pedometer++ does.
                .padding(.bottom, 8)

                if let summary = vm.state.chartSummary, summary.isEmpty {
                    // Sits over the chart rather than in place of it, and lets
                    // touches through so the scroll underneath still works.
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.title)
                            .foregroundStyle(Color.moneyIn)
                            .symbolEffect(.bounce, options: .nonRepeating)
                        Text("No spend")
                            .font(.title3.weight(.semibold))
                        Text("Swipe to another period")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Flat white left the bars floating on nothing. A soft vertical wash —
        // barely-there at the top, grounding under the bars — gives them a surface
        // to sit on without adding a card or a border.
        .background {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        // Crossing between the chart and the empty state is a change of content,
        // not a jump cut.
        .animation(.smooth(duration: 0.3), value: vm.state.chartSummary?.isEmpty)
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showReports = true } label: {
                    Image(systemName: "chart.pie.fill")
                }
                .accessibilityLabel("Reports")
            }
        }
        .sheet(isPresented: $showReports) {
            ReportsView(
                allRows: vm.state.allRows,
                categories: vm.state.categories,
                initialMonth: vm.state.chartAnchor,
                // Filters are presented from Reports but still drive the ledger,
                // so the state stays here and Reports gets the bindings.
                filterHost: .init(
                    vm: vm,
                    selectedYear: $selectedYear,
                    selectedMonth: $selectedMonth,
                    availableYears: availableYears,
                    availableMonths: availableMonths,
                    resultsCount: filteredTxnCount,
                    onReset: {
                        selectedMonth = nil
                        selectedYear = nil
                        Task { await vm.clearAllFilters() }
                    }
                ),
                sections: visibleSections,
                onEditRow: { editingRow = $0 }
            )
        }
        .sheet(item: $editingRow, onDismiss: {
            Task { await vm.load() }
        }) { row in
            NavigationStack { TxnFormView(store: store, editing: row) }
        }
        .task { await vm.load() }
        // No `.refreshable`: the screen is a fixed layout with no scroll container,
        // so pull-to-refresh had nothing to attach to and never fired. Reloads come
        // from `.task` on appear, foregrounding, and remote changes below — the
        // ledger moved to Reports, so there is nothing here to pull down on.
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
    }

    /// Maps the VM's optional `filterKind` to/from the 3-way segment. Only the
    /// Filters sheet uses it now — filtering belongs on Reports, not here.
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

