import SwiftUI
import UIKit
import KharchaKit

struct HistoryView: View {
    let store: ExpenseStore
    @StateObject private var vm: HistoryViewModel
    @EnvironmentObject private var privacy: PrivacyManager
    @State private var editingRow: TxnRow?
    @State private var selectedBarDate: Date?
    @State private var showReports = false

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

    /// Where the chart is actually scrolled to, written synchronously by the
    /// scroll binding.
    ///
    /// This used to live in the view model, written as `Task { await
    /// vm.setChartAnchor(...) }` from a callback that fires every frame of a
    /// fling. Each frame spawned a task, the tasks had no ordering guarantee
    /// between them, and the binding's getter kept returning the old value until
    /// one landed — so the anchor drifted behind the scroll and sometimes
    /// settled on a position the user had passed through pages ago. The header
    /// then described a window the bars were not drawing. It is `@State` now:
    /// one synchronous write per frame, in order, and the view model hears about
    /// it once when the scroll stops.
    @State private var liveAnchor: Date?

    /// Whether the user has actually dragged the chart.
    ///
    /// `chartScrollPosition` reports a position during the chart's first layout,
    /// before it has applied the position we asked for — and that report is the
    /// start of the scrollable content, not where the chart ends up drawing.
    /// Taking it at face value overwrote the opening anchor with the oldest
    /// bucket in the ledger, so the header read "Jul 1 – 10, ₩0, No spend" while
    /// the chart drew the end of August correctly. A layout pass is not a scroll;
    /// only a finger on the chart is.
    @State private var userHasScrolled = false

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            // The view model learns where the scroll ended once, at rest, rather
            // than once per frame. The chart itself no longer waits for this —
            // it follows the quantised position live.
            await vm.setChartAnchor(liveAnchor ?? vm.state.chartAnchor)
            await vm.settleChartAnchor()
        }
    }


    /// The buckets currently on screen — the same window `ActivityBarChart`
    /// draws, taken from the same function so the two cannot drift apart.
    /// The window the hero and the bar scale are measured over: the live scroll
    /// position, snapped to the start of its bucket.
    ///
    /// Snapping is what makes this cheap to follow live. The set of bars in view
    /// is a function of the quantised position, so between two positions inside
    /// the same day nothing it feeds — the ceiling, the bar width, the totals —
    /// can change, and a fling recomputes once per day crossed rather than once
    /// per frame. The earlier attempt deferred all of this until the scroll came
    /// to rest, which stopped the churn but left the scale describing wherever
    /// you had last stopped: income had no room and tall bars clipped until you
    /// let go.
    private var effectiveScaleAnchor: Date {
        let live = liveAnchor ?? vm.state.chartAnchor
        let cal = Calendar.current
        return period == .year
            ? (cal.dateInterval(of: .month, for: live)?.start ?? live)
            : cal.startOfDay(for: live)
    }

    /// The buckets on screen, the boundary one included.
    ///
    /// Inclusive of the far edge on purpose. `chartXVisibleDomain` is a length,
    /// not a bar count, so the bucket sitting on the far boundary is drawn — as a
    /// sliver or a full bar depending on where the scroll rests. Excluding it
    /// meant the header could read "₩0, No spend" with a bar plainly on screen,
    /// and worse, the ceiling was measured without it: `spendTop` fell back to 1
    /// and that bar overflowed to full height, clipped square at the top.
    private var visibleBars: [ActivityBar] {
        // The settled anchor, not the live one. Reading the scroll position as it
        // moves made the hero's figures and its date range churn through every
        // intermediate window during a fling; they now change once, when the
        // scroll stops, on the same beat as the bars rescaling.
        let start = effectiveScaleAnchor
        let end = start.addingTimeInterval(ActivityBarChart.visibleDomain(for: period))
        return vm.state.chartBars.filter { $0.date >= start && $0.date <= end }
    }

    /// Totals for what you can actually see.
    ///
    /// This used to read `vm.state.chartSummary`, which totals the whole period
    /// containing the anchor — a month. The bars show nine days of that month,
    /// so scrolling to an empty week left ₩107,055 sitting above a chart with
    /// nothing in it, and the figure never moved as you scrolled within a month.
    /// A number that does not answer to the picture under it is worse than no
    /// number: there is no way to tell what it is counting.
    private struct VisibleTotals {
        let expense: Decimal
        let income: Decimal
        var isEmpty: Bool { expense == 0 && income == 0 }
    }

    private var visibleTotals: VisibleTotals {
        let bars = visibleBars
        return VisibleTotals(
            expense: bars.reduce(Decimal(0)) { $0 + $1.expense },
            income: bars.reduce(Decimal(0)) { $0 + $1.income }
        )
    }

    /// The tapped day's transactions, newest-largest first.
    ///
    /// Resolved here rather than in the chart: the chart is handed buckets, and
    /// a bucket carries category totals with no note on them. History already
    /// holds every row, so the lookup belongs on this side.
    private var selectedEntries: [TxnRow] {
        guard let date = selectedBarDate else { return [] }
        let cal = Calendar.current
        let granularity: Calendar.Component = period == .year ? .month : .day
        return vm.state.allRows
            .filter { cal.isDate($0.date, equalTo: date, toGranularity: granularity) }
            .sorted { $0.amount > $1.amount }
    }

    /// Names the span the figure covers — "Sep 23 – 29". Without it the hero is
    /// an unattributed number, which is what made it unreadable.
    private var visibleRangeLabel: String {
        guard let first = visibleBars.first?.date, let last = visibleBars.last?.date else { return "" }
        let f = DateIntervalFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: first, to: last)
    }

    /// Spent, received and net for whatever the chart is showing — the Pedometer++
    /// hero, where one figure dominates and the others qualify it. Income used to
    /// exist only as a second bar colour, which was easy to miss entirely.
    @ViewBuilder private var heroBlock: some View {
        let s = visibleTotals
        let net = s.income - s.expense
        VStack(spacing: 3) {
            // The span the figure covers, named. The hero used to be a number
            // with nothing attached to it.
            Text(visibleRangeLabel)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Text(privacy.isRevealed ? AmountFormatter.money(s.expense) : "••••")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.moneyOut)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Both qualifier lines stay laid out even with nothing received,
            // and fade instead of being removed.
            //
            // They used to be behind `if s.income > 0`, so scrolling from a
            // month with a salary to one without collapsed the hero by two
            // lines and yanked the chart up under it mid-scroll. Holding the
            // space costs a little air on income-free windows and buys a
            // block that never changes height.
            VStack(spacing: 2) {
                Text(privacy.isRevealed
                     ? "\(AmountFormatter.money(s.income)) received"
                     : "•••• received")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.moneyIn)

                // Two whole strings rather than one with the arrow interpolated.
                // The interpolated form extracted as "%@ %@ net" — two opaque
                // slots a translator cannot place, and no way to move the arrow
                // to the other side of the figure where a right-to-left script
                // needs it.
                Text(privacy.isRevealed
                     ? (net >= 0
                        ? "↑ \(AmountFormatter.money(net)) net"
                        : "↓ \(AmountFormatter.money(abs(net))) net")
                     : "•••• net")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(net >= 0 ? Color.moneyIn : Color.moneyOut)
            }
            .opacity(s.income > 0 ? 1 : 0)
            .accessibilityHidden(s.income == 0)
        }
        .frame(maxWidth: .infinity)
        // Digits roll to their new values as you scroll to another period,
        // rather than the whole figure being swapped out. This is what Apple
        // uses for changing numbers — timers, rings, Weather.
        .contentTransition(.numericText())
        // Slower than the chart's own spring on purpose: the figure settles
        // after the bars do, so the eye follows the bars and then reads the
        // number, rather than both changing at once and neither registering.
        .animation(.smooth(duration: 0.45), value: s.expense)
        .animation(.smooth(duration: 0.45), value: s.income)
        .animation(.smooth(duration: 0.45), value: s.income > 0)
        .accessibilityElement(children: .combine)
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
                    isRevealed: privacy.isRevealed,
                    selectedEntries: selectedEntries,
                    scaleAnchor: effectiveScaleAnchor,
                    scrollPosition: Binding(
                        get: { liveAnchor ?? vm.state.chartAnchor },
                        set: { newAnchor in
                            guard userHasScrolled else { return }
                            selectedBarDate = nil
                            liveAnchor = newAnchor
                            scheduleSettle()
                        }
                    )
                )
                // Minimum distance rather than zero, so a tap that selects a bar
                // is not mistaken for a scroll. Simultaneous, so the chart's own
                // pan still does the scrolling — this only observes.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in
                            if !userHasScrolled { userHasScrolled = true }
                        }
                )
                // Roughly two fifths of the screen. Full-bleed only works when the
                // chart is reliably full; spending has empty days and outliers, so
                // a screen of pure chart is mostly a screen of nothing.
                .frame(height: 300)
                // Edge to edge. The 8pt inset made it read as a component sitting
                // on the screen; running to the edges makes the graph the surface
                // the screen is built on, which is what Pedometer++ does.
                .padding(.bottom, 8)

                if visibleTotals.isEmpty {
                    // Sits over the chart rather than in place of it, and lets
                    // touches through so the scroll underneath still works.
                    //
                    // Sits just above the date axis, in the space the missing
                    // bars would have filled, rather than floating at the top of
                    // an empty frame away from the thing it is describing.
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle)
                            .foregroundStyle(Color.moneyIn)
                            .symbolEffect(.bounce, options: .nonRepeating)
                        Text("No spend")
                            .font(.title.weight(.semibold))
                        Text("Swipe to another period")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 44)
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
        .animation(.smooth(duration: 0.3), value: visibleTotals.isEmpty)
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
                sections: vm.state.sections,
                onEditRow: { editingRow = $0 }
            )
        }
        .sheet(item: $editingRow, onDismiss: {
            Task { await vm.load() }
        }) { row in
            NavigationStack { TxnFormView(store: store, editing: row) }
        }
        .task {
            await vm.load()
            // Seed both, so a screen that is never scrolled still measures the
            // bars it is actually drawing.
            liveAnchor = vm.state.chartAnchor
        }
        // Covers anchor moves that arrive without a scroll — a reload, or the
        // period being switched underneath.
        .onChange(of: vm.state.chartBars.count) { _, _ in
            if liveAnchor == nil { liveAnchor = vm.state.chartAnchor }
        }
        // No `.refreshable`: the screen is a fixed layout with no scroll container,
        // so pull-to-refresh had nothing to attach to and never fired. Reloads come
        // from `.task` on appear, foregrounding, and remote changes below — the
        // ledger moved to Reports, so there is nothing here to pull down on.
        .onChange(of: vm.state.chartPeriod) { _, _ in
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
}
