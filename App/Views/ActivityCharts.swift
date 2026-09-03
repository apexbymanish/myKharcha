import SwiftUI
import Charts
import KharchaKit

/// The snap-up detail for a tapped bar. Sits on the chart, next to the bar it
/// describes, rather than at the bottom of the screen.
private struct TooltipCard: View {
    let date: Date
    let amount: Decimal
    let unit: Calendar.Component

    private var label: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(unit == .month ? "MMMMyyyy" : "MMMd")
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(AmountFormatter.money(amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

/// The figure written against a bar: neutral ink, with a small tinted sign
/// carrying the direction — minus in red for money spent, plus in green for
/// money received.
///
/// Amounts used to be tinted to the day's leading category, which made the text
/// a competing colour above the bands it labelled — and on a pale category it
/// fell below contrast against the chart's own background. Neutral ink reads at
/// any size in either theme, and the sign says which way the money went in the
/// notation a ledger already uses.
private struct AmountTag: View {
    enum Direction { case spent, received }

    let amount: Decimal
    let direction: Direction

    private var symbol: String { direction == .spent ? "minus" : "plus" }
    private var tint: Color { direction == .spent ? .moneyOut : .moneyIn }

    var body: some View {
        HStack(spacing: 2) {
            // `imageScale` rather than a fixed point size, so the sign grows
            // with the amount under Dynamic Type instead of shrinking beside it.
            Image(systemName: symbol)
                .imageScale(.small)
                .fontWeight(.bold)
                .foregroundStyle(tint)
            Text(AmountFormatter.money(amount))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.caption2.weight(.semibold))
        .minimumScaleFactor(0.75)
        .lineLimit(1)
    }
}

/// Grouped spend-vs-income bar chart over a set of `ActivityBar` buckets.
/// `unit` is `.day` for week/month periods and `.month` for the year period.
/// Bind `selectedDate` to track which bar the user tapped; the binding is
/// updated by `.chartXSelection` and cleared by `onClearSelection`.
struct ActivityBarChart: View {
    let bars: [ActivityBar]
    let unit: Calendar.Component
    /// Two-way binding — updated live as the user taps/drags across the chart.
    var selectedDate: Binding<Date?> = .constant(nil)
    /// Scope of the chart — sets how much timeline is visible at once and what
    /// the horizontal scroll snaps to (a week, a month, or a year per page).
    var period: ActivityPeriod = .month
    /// Category name → colour hex, so bands wear the same colours their categories
    /// do elsewhere. Colour is presentation, so the model does not carry it.
    var categoryColors: [String: String] = [:]
    /// Leading edge of the visible window, bound to the view model's chart anchor.
    /// Writing to it is how scrolling moves the period the header describes.
    @Binding var scrollPosition: Date

    /// About nine bars on screen at a time, scrolling freely through the rest.
    /// Nine is the ceiling for keeping an amount on every bar legible, and it is
    /// roughly what Pedometer++ shows.
    ///
    /// Static because the hero above the chart has to total the same window the
    /// bars draw. When each side worked this out for itself the figure described
    /// the whole month while the bars showed nine days of it, so scrolling to an
    /// empty week still showed a large number with nothing under it.
    static func visibleDomain(for period: ActivityPeriod) -> TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        switch period {
        case .week, .month: return 9 * day
        case .year:         return 9 * 30 * day
        }
    }

    private var visibleDomain: TimeInterval { Self.visibleDomain(for: period) }

    /// The buckets actually on screen — from the scroll position forward by one
    /// visible domain. Everything that scales with "what you can see" derives from
    /// this rather than from the whole series.
    private var visibleBars: [ActivityBar] {
        let end = scrollPosition.addingTimeInterval(visibleDomain)
        return bars.filter { $0.date >= scrollPosition && $0.date < end }
    }

    /// Non-empty buckets on screen. Drives how fat the bars are drawn.
    private var populatedCount: Int { visibleBars.filter { $0.expense > 0 }.count }

    /// Bar width as a share of its column.
    ///
    /// Two bars in a nine-column grid look lost at a fixed ratio, so the fewer
    /// bars a window holds the fatter they are drawn. Varying the ratio rather
    /// than the visible domain is deliberate: pushing `chartXVisibleDomain` low
    /// enough to fatten bars makes Swift Charts stop honouring bar width at all.
    private var barRatio: Double {
        switch populatedCount {
        case 0, 1, 2: return 0.98
        case 3, 4:    return 0.9
        case 5, 6:    return 0.82
        default:      return 0.72
        }
    }

    /// Ceiling for the income half of the chart, from the visible window only.
    private var incomePeak: Double {
        let totals = visibleBars.map(\.income).filter { $0 > 0 }
        let ceiling = ActivitySeries.chartCeiling(totals)
        return (ceiling as NSDecimalNumber).doubleValue
    }

    /// Share of the chart's height given to income, below the zero line.
    ///
    /// Income and spending cannot share a scale: one salary is twenty times a day's
    /// spending, and on a shared axis it flattens every expense bar to nothing —
    /// which is why income was pulled from the chart in the first place. So the two
    /// halves are scaled independently, income into the lower quarter.
    ///
    /// The cost is that heights are not comparable across the zero line: a green bar
    /// twice a red one does not mean twice the money. The zero rule and the colour
    /// split are what tell the reader these are two different measures.
    private static let incomeShare = 0.25

    /// Bottom of the y-domain. Zero when nothing was received in view, so an
    /// income-free window keeps the whole frame for spending.
    ///
    /// Measured against the spending ceiling, never against the income itself. It
    /// used to return `-incomePeak * 3`, mixing two scales that share no unit: a
    /// ₩3,000,000 salary beside ₩130,000 of spending gave a domain of
    /// -9,000,000…130,000, so the entire expense half rendered in the top 1.4% of
    /// the plot as hairlines with their labels stacked on one another. Deriving
    /// the floor from `spendTop` pins the zero rule at three quarters of the
    /// height whatever was received, and `depth` below normalises income into
    /// the quarter that leaves.
    private var floorValue: Double {
        guard incomePeak > 0 else { return 0 }
        return -spendTop * (Self.incomeShare / (1 - Self.incomeShare))
    }

    /// Labels always fit, because the visible window is fixed at roughly nine bars
    /// by `visibleDomain` however long the series is.
    ///
    /// This used to test `bars.count`, which is the whole scrollable series — up to
    /// 800 buckets — rather than the handful on screen. It was therefore always
    /// false, and every amount and category name was silently suppressed.
    private var labelsFit: Bool { true }

    /// Colour of a band, taken from the category's own swatch so a bar matches the
    /// chips and icons that category wears everywhere else in the app.
    ///
    /// This replaces the budget-status colouring. A fill can encode category or
    /// budget, not both, and knowing what the money went on beats knowing whether
    /// the day beat its allowance — which the hero and Reports already say.
    private func barColor(for p: Point) -> Color {
        if let hex = categoryColors[p.series] { return Color(hex: hex) }
        // Dimmed on purpose. At full strength systemGray is the brightest band on
        // a dark chart, which puts the loudest colour on the one bucket that means
        // "nothing in particular" and lets it out-shout the named categories.
        if p.series == ActivityBar.otherSegmentName {
            return Color(hex: "#8E8E93").opacity(0.5)
        }
        return .moneyOut
    }

    /// Top of the y-scale. Not the maximum: one rent-sized day would take the whole
    /// height and flatten every ordinary day into a stub. `chartCeiling` returns the
    /// 90th percentile so the outlier clips and the rest of the period stays
    /// readable. See its tests for the two cases.
    private var peak: Double {
        // Only what is on screen. This used to scale against the entire series, so
        // a window holding one ₩11,180 day was measured against a ceiling drawn
        // from months of history — the bar rendered correctly, at 1.6% of a height
        // it had no business being compared to.
        let totals = visibleBars.map(\.expense).filter { $0 > 0 }
        let ceiling = ActivitySeries.chartCeiling(totals)
        return (ceiling as NSDecimalNumber).doubleValue
    }

    /// Top of the y-domain, never zero.
    ///
    /// A window where nothing was spent still needs a scale: with `peak` at zero
    /// the grey stubs were drawn `0 * 0.012` tall, so a run of no-spend days showed
    /// as an empty black half rather than as a row of days with nothing on them.
    private var spendTop: Double { peak > 0 ? peak : 1 }

    /// Whether a band is deep enough to hold its category name. Below this it is a
    /// colour stripe and the legend has to carry the meaning instead.
    private func bandHoldsItsName(_ p: Point) -> Bool {
        peak > 0 && p.amount / peak > 0.22
    }

    /// The bucket the user tapped, if it has spending.
    private var selectedPoint: Point? {
        guard let sel = selectedDate.wrappedValue else { return nil }
        let cal = Calendar.current
        return points.first { cal.isDate($0.date, equalTo: sel, toGranularity: unit) }
    }

    /// One category's band within one day's bar.
    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        /// Category name — the stacking key, and the label on the largest band.
        let series: String
        let amount: Double
        /// This day's whole spend, so the amount above the bar can be drawn once
        /// on the topmost band rather than once per band.
        let dayTotal: Double
        /// True for the biggest band of the day: the one that carries the name.
        let isLead: Bool
        /// True for the last band in the stack — the one whose top edge is the
        /// top of the whole bar, and so the only place the day's total can sit
        /// without floating somewhere down the side of it.
        let isTop: Bool
    }

    private var spentLabel: String { String(localized: "Spent") }
    private var receivedLabel: String { String(localized: "Received") }

    /// Spending only, and only days that have some.
    ///
    /// Income used to be a second series here. A ₩3,000,000 salary against days of
    /// ₩12k–₩128k set the shared y-scale, so every expense bar rendered a few
    /// pixels tall and the chart showed nothing. Income belongs in the hero, where
    /// it is a number rather than a bar that flattens the ones around it.
    ///
    /// Zero days are dropped rather than drawn: a spend tracker has many of them,
    /// and each one was eating a column's width to say nothing.
    /// One point per category band, so the bars stack by what the money went on.
    private var points: [Point] {
        bars.flatMap { bar -> [Point] in
            let total = (bar.expense as NSDecimalNumber).doubleValue
            guard total > 0 else { return [] }
            return bar.segments.enumerated().map { index, seg in
                Point(date: bar.date,
                      series: seg.categoryName,
                      amount: (seg.amount as NSDecimalNumber).doubleValue,
                      dayTotal: total,
                      isLead: index == 0,
                      isTop: index == bar.segments.count - 1)
            }
        }
    }

    /// Days with nothing spent. They keep their column and show a flat grey stub,
    /// so a no-spend day reads as a day you spent nothing rather than a hole.
    private var emptyBars: [ActivityBar] { bars.filter { $0.expense == 0 } }

    /// Income bars, pre-scaled to their own half of the axis.
    ///
    /// Computed here rather than inline: `let` bindings inside a
    /// `ChartContentBuilder` closure defeat its type inference, and the failure
    /// surfaces as a misleading "cannot convert [ActivityBar] to Binding<C>".
    private struct IncomePoint: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Decimal
        let plotted: Double
    }

    private var incomePoints: [IncomePoint] {
        guard incomePeak > 0 else { return [] }
        // Four fifths of the income half, not all of it. The last fifth is the
        // gutter the amount is written in: the figure sits under its bar on the
        // chart's own background rather than on the green fill, so the tinted
        // arrow beside it stays visible. Without the gutter the tallest bar
        // reaches the floor and the label has nowhere to go but the date axis.
        let depth = abs(floorValue) * 0.8
        return bars.compactMap { bar in
            guard bar.income > 0 else { return nil }
            let value = (bar.income as NSDecimalNumber).doubleValue
            return IncomePoint(date: bar.date,
                               amount: bar.income,
                               plotted: -(value / incomePeak) * depth)
        }
    }

    // MARK: - Chart content
    //
    // Split out of `body`: with all of it inline the type-checker gave up on
    // the whole Chart expression, the same way it did on HistoryView's List.

    @ChartContentBuilder private var incomeMarks: some ChartContent {
        // Income hangs below the zero line, scaled to its own side. Days you
        // were paid read instantly without a salary crushing the spending above.
        ForEach(incomePoints) { p in
            BarMark(
                x: .value("Date", p.date, unit: unit),
                yStart: .value("Amount", 0),
                yEnd: .value("Amount", p.plotted),
                width: .ratio(barRatio)
            )
            .foregroundStyle(Color.moneyIn)
            .cornerRadius(4)
            // Under the bar, in the gutter `incomePoints` leaves for it, so the
            // tag sits on the chart's background and its green arrow reads.
            //
            // `.fit(to: .plot)`, not `.fit(to: .chart)`: the chart includes the
            // date axis, so fitting to it is what allowed the figure to land on
            // top of the dates in the first place.
            .annotation(position: .bottom,
                        spacing: 3,
                        overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .fit(to: .plot))) {
                AmountTag(amount: p.amount, direction: .received)
            }
        }
    }

    @ChartContentBuilder private var zeroRuleMark: some ChartContent {
        // The line the two measures meet at. Without it the split reads as one
        // scale and the income bars look like negative spending.
        if incomePeak > 0 {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
    }

    @ChartContentBuilder private var emptyDayMarks: some ChartContent {
        // Empty days keep their column: a flat grey stub on the baseline, so a
        // no-spend day is visibly a day rather than a gap in the data.
        ForEach(emptyBars) { bar in
            BarMark(
                x: .value("Date", bar.date, unit: unit),
                yStart: .value("Amount", 0),
                yEnd: .value("Amount", spendTop * 0.018),
                width: .ratio(barRatio)
            )
            .foregroundStyle(Color.secondary.opacity(0.28))
            .cornerRadius(2)
        }
    }

    @ChartContentBuilder private var spendMarks: some ChartContent {
        ForEach(points) { p in
            BarMark(
                x: .value("Date", p.date, unit: unit),
                y: .value("Amount", p.amount),
                // A share of the column, and that share grows when few bars
                // are on screen — see `barRatio`.
                width: .ratio(barRatio)
            )
            .foregroundStyle(barColor(for: p))
            .cornerRadius(4)
            // Every spend bar carries its own amount, so a value never needs
            // to be uncovered by tapping or scrubbing.
            // Amount always above the bar, tinted to match it. Fixed placement
            // beats adaptive — your eye learns one place to look.
            // The biggest band carries its category name, written into the
            // band itself. Dynamic Type sized, so it grows with the user's
            // text setting instead of staying 9pt forever.
            .annotation(position: .overlay, alignment: .center, spacing: 0) {
                if labelsFit, p.isLead, bandHoldsItsName(p) {
                    Text(p.series)
                        .font(.caption2.weight(.bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(.black.opacity(0.72))
                        .padding(.horizontal, 2)
                }
            }
            // The day's total, written once above the whole stack.
            //
            // Keyed on `isTop`, not `isLead`. An annotation attaches to its own
            // mark, and the lead band is the *biggest* one, which stacks at the
            // bottom — so on any bar with more than one category the total was
            // drawn just above that bottom band, floating down beside the bar it
            // was meant to be labelling instead of sitting on top of it.
            //
            // `overflowResolution` keeps it on screen for a bar that clips at
            // the percentile ceiling. Without it the label is positioned above
            // the bar's true top, which is outside the plot area — so the
            // biggest days, the ones you most want labelled, showed nothing.
            .annotation(position: .top,
                        spacing: 3,
                        overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .fit(to: .chart))) {
                if labelsFit, p.isTop {
                    AmountTag(amount: Decimal(p.dayTotal), direction: .spent)
                }
            }
        }
    }

    @ChartContentBuilder private var selectionMark: some ChartContent {
        // Selection highlights the whole column behind the bar rather than
        // drawing a line through it — the bar stays readable and the tap
        // clearly belongs to that day.
        if let sel = selectedDate.wrappedValue {
            RectangleMark(x: .value("Selected", sel, unit: unit))
                .foregroundStyle(Color.primary.opacity(0.06))
                .zIndex(-1)
        }
    }

    var body: some View {
        Chart {
            incomeMarks
            zeroRuleMark
            emptyDayMarks
            spendMarks
            selectionMark
        }
        .chartLegend(.hidden)   // colour now encodes budget, not series
        // No Y axis and no gridlines. Every bar already carries its own amount, so
        // an axis would be the same information twice — and the axis furniture is
        // most of what makes a chart look busy. Pedometer++ draws neither.
        .chartYAxis(.hidden)
        // X axis keeps the dates but drops the gridlines and the axis rule.
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                // Horizontal inset lives here rather than on the whole chart, so
                // the bars can run to the screen edges while the dates stay clear
                // of them.
                AxisValueLabel(horizontalSpacing: 8).font(.system(size: 9))
            }
        }
        // `chartCeiling` already includes its headroom, so no second helping here.
        // The floor drops below zero only when the window actually holds income.
        .chartYScale(domain: floorValue...spendTop)
        .chartXSelection(value: selectedDate)
        // The detail rides on the bar you tapped. It used to appear at the foot of
        // the screen, far from the thing it described.
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let p = selectedPoint,
                   let plot = proxy.plotFrame,
                   let x = proxy.position(forX: p.date) {
                    let originX = geo[plot].origin.x
                    TooltipCard(date: p.date, amount: Decimal(p.amount), unit: unit)
                        .position(x: min(max(originX + x, 70), geo.size.width - 70), y: 28)
                        // Scales up from the bar rather than appearing, and slides
                        // between bars instead of jumping when the selection moves.
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .animation(.spring(response: 0.32, dampingFraction: 0.72),
                                   value: p.date)
                }
            }
        }
        // The selection highlight and tooltip arrive together, on one spring.
        .animation(.spring(response: 0.32, dampingFraction: 0.72),
                   value: selectedDate.wrappedValue)
        // Height and width both change as the window moves — the ceiling rescales
        // and sparse windows fatten. One spring drives both, so they move together
        // rather than as two easings finishing at different moments, which reads as
        // jitter. Slightly under-damped so it settles rather than stopping dead.
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: peak)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: incomePeak)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: barRatio)
        // A tap on a bar should feel like it landed.
        .sensoryFeedback(.selection, trigger: selectedDate.wrappedValue)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomain)
        // Plain momentum scrolling, nothing catching it — Pedometer++ glides
        // because it never snaps to a boundary.
        .chartScrollPosition(x: $scrollPosition)
        // Long-press scrubbing is deliberately absent. With every bar labelled
        // there is no hidden value to uncover, so the gesture would only compete
        // with the scroll pan for no gain. Tap-to-select still filters the list.
        //
        // No fixed height. It used to be pinned at 200pt, so however much room the
        // caller gave it the chart stayed small and got centred — bars floating
        // mid-screen with white above and below. It fills what it is handed, and
        // the bars sit on the bottom of that.
    }
}

/// A compact, axis-light trend (used on Home) — same data, smaller and legend-free.
struct MiniTrendChart: View {
    let bars: [ActivityBar]

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let series: String
        let amount: Double
    }
    /// Spending only, same reason as the full chart: a salary in the window set
    /// the shared y-scale and squashed every spend bar to nothing.
    private var points: [Point] {
        bars.compactMap { bar in
            let spent = (bar.expense as NSDecimalNumber).doubleValue
            guard spent > 0 else { return nil }
            return Point(date: bar.date, series: "e", amount: spent)
        }
    }

    var body: some View {
        Chart(points) { p in
            BarMark(x: .value("Date", p.date, unit: .day), y: .value("Amount", p.amount))
                .foregroundStyle(Color.moneyOut)
                .cornerRadius(2)
        }
        .chartLegend(.hidden)
        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisTick() } }
        .chartYAxis(.hidden)
        .frame(height: 90)
    }
}

/// Per-category spend/income breakdown for a single time bucket (day or month).
/// Shown in History below the bar chart when the user taps a bar.
/// Always shows all transactions for the bucket regardless of active list filters,
/// since it corresponds to the unfiltered chart bars above.
struct BarSelectionBreakdown: View {
    let allRows: [TxnRow]
    let date: Date
    let period: ActivityPeriod
    let onDismiss: () -> Void

    private var bucketRows: [TxnRow] {
        let cal = Calendar.current
        return allRows.filter {
            period == .year
                ? cal.isDate($0.date, equalTo: date, toGranularity: .month)
                : cal.isDate($0.date, inSameDayAs: date)
        }
    }

    private struct CategoryTotal: Identifiable {
        let id: String
        let name: String
        let spent: Decimal
        let received: Decimal
        var total: Decimal { spent + received }
    }

    private var breakdown: [CategoryTotal] {
        let grouped = Dictionary(grouping: bucketRows) { row -> String in
            row.categoryName.isEmpty ? String(localized: "Uncategorized") : row.categoryName
        }
        return grouped.map { name, txns in
            let spent = txns.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
            let received = txns.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
            return CategoryTotal(id: name, name: name, spent: spent, received: received)
        }
        .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(bucketTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selection")
            }

            if breakdown.isEmpty {
                Text("No transactions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(breakdown) { item in
                    HStack {
                        Text(item.name).font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            if item.spent > 0 {
                                Text("−" + AmountFormatter.money(item.spent))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(Color.moneyOut)
                            }
                            if item.received > 0 {
                                Text("+" + AmountFormatter.money(item.received))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(Color.moneyIn)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var bucketTitle: String {
        switch period {
        case .year:
            return date.formatted(.dateTime.month(.wide).year())
        case .month, .week:
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }
}

