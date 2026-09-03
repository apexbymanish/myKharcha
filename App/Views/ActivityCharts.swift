import SwiftUI
import Charts
import KharchaKit

/// The sentence above the chart — "Spending in August 2026 is down 8%, totalling
/// ₹8,450." Apple's charts guidance asks that a chart carry text describing its
/// contents that stays informative read on its own, which a bare "Analytics" label
/// does not. It names the period explicitly, so the figure can never be mistaken
/// for today's when the chart is scrolled elsewhere.
struct ChartHeadline: View {
    let summary: ActivitySummary
    let period: ActivityPeriod
    var isRevealed: Bool = true

    private var total: String {
        isRevealed ? AmountFormatter.money(summary.expense) : "••••"
    }

    /// "August 2026" / "Aug 17 – 23, 2026" / "2026", matching the scope on screen.
    private var periodLabel: String {
        switch period {
        case .week:
            // `DateIntervalFormatter` picks the locale's own range separator and
            // collapses repeated parts ("Aug 17 – 23" rather than "Aug 17 – Aug 23").
            // Building the range by hand would bake in an en-dash and comma order
            // that is wrong in several of the twenty languages this app ships.
            let end = Calendar.current.date(byAdding: .day, value: 6, to: summary.start) ?? summary.start
            let f = DateIntervalFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: summary.start, to: end)
        case .month:
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return f.string(from: summary.start)
        case .year:
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("yyyy")
            return f.string(from: summary.start)
        }
    }

    /// One whole sentence per case, never assembled from fragments.
    ///
    /// This used to concatenate `Text(" is ") + Text("down 8%") + Text(",")` so the
    /// percentage could be coloured inline. That hardcodes English word order and
    /// hands translators meaningless pieces — a key of `" is "` cannot be
    /// translated, and the fixed order breaks outright in Arabic and Urdu, both of
    /// which this app ships. The trend colour moved to its own badge below instead.
    private var sentence: Text {
        guard let pct = summary.changePercent, summary.trend != .unknown else {
            return Text("Spending in \(periodLabel) totalled \(total).")
        }
        switch summary.trend {
        case .flat:
            return Text("Spending in \(periodLabel) is unchanged, totalling \(total).")
        case .up:
            return Text("Spending in \(periodLabel) is up \(pct)%, totalling \(total).")
        case .down:
            return Text("Spending in \(periodLabel) is down \(pct)%, totalling \(total).")
        case .unknown:
            return Text("Spending in \(periodLabel) totalled \(total).")
        }
    }

    /// Colour for the trend, carried by the sentence's own tint rather than by a
    /// span inside it — locating a word inside a translated sentence would mean
    /// knowing where it lands in twenty languages.
    private var trendTint: Color {
        switch summary.trend {
        case .up:      return .moneyOut
        case .down:    return .moneyIn
        case .flat,
             .unknown: return .primary
        }
    }

    var body: some View {
        sentence
            .font(.subheadline)
            .foregroundStyle(trendTint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(isRevealed
                ? Text("Spending in \(periodLabel), \(AmountFormatter.money(summary.expense))")
                : Text("Amounts hidden"))
    }
}


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
    /// Budget one bar is measured against, for colouring. Zero disables colouring.
    var allowance: Decimal = 0
    /// Leading edge of the visible window, bound to the view model's chart anchor.
    /// Writing to it is how scrolling moves the period the header describes.
    @Binding var scrollPosition: Date

    /// About nine bars on screen at a time, scrolling freely through the rest.
    /// Nine is the ceiling for keeping an amount on every bar legible, and it is
    /// roughly what Pedometer++ shows.
    private var visibleDomain: TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        switch period {
        case .week, .month: return 9 * day
        case .year:         return 9 * 30 * day
        }
    }

    /// Bars are only labelled while the labels can be read. A month is 31 bars and
    /// a label on each collides into noise, so past this count the amounts drop out
    /// and the bars carry the shape on their own.
    private var labelsFit: Bool { bars.count <= 14 }

    /// Bar colour by how the day sat against its budget, the way Pedometer++
    /// colours a day by whether the step goal was met. Income keeps its own tint.
    private func barColor(for p: Point) -> Color {
        guard p.series == spentLabel else { return .moneyIn }
        switch ActivitySeries.spendLevel(expense: Decimal(p.amount), allowance: allowance) {
        case .under:   return Color(hex: "#0B7167")
        case .near:    return Color(hex: "#E8A33D")
        case .over:    return Color(hex: "#ba1a1a")
        case .unknown: return .moneyOut
        }
    }

    /// Top of the y-scale. Not the maximum: one rent-sized day would take the whole
    /// height and flatten every ordinary day into a stub. `chartCeiling` returns the
    /// 90th percentile so the outlier clips and the rest of the period stays
    /// readable. See its tests for the two cases.
    private var peak: Double {
        let ceiling = ActivitySeries.chartCeiling(points.map { Decimal($0.amount) })
        return (ceiling as NSDecimalNumber).doubleValue
    }

    /// The bucket the user tapped, if it has spending.
    private var selectedPoint: Point? {
        guard let sel = selectedDate.wrappedValue else { return nil }
        let cal = Calendar.current
        return points.first { cal.isDate($0.date, equalTo: sel, toGranularity: unit) }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let series: String
        let amount: Double
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
    private var points: [Point] {
        bars.compactMap { bar in
            let spent = (bar.expense as NSDecimalNumber).doubleValue
            guard spent > 0 else { return nil }
            return Point(date: bar.date, series: spentLabel, amount: spent)
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                BarMark(
                    x: .value("Date", p.date, unit: unit),
                    y: .value("Amount", p.amount),
                    // Fat bars. Every column used to reserve a second slot for an
                    // income bar that was usually zero, so even the spend bar only
                    // got half a column.
                    width: .fixed(34)
                )
                .foregroundStyle(barColor(for: p))
                .cornerRadius(4)
                // Every spend bar carries its own amount, so a value never needs
                // to be uncovered by tapping or scrubbing.
                .annotation(position: .top, spacing: 2) {
                    if labelsFit, p.series == spentLabel, p.amount > 0 {
                        Text(AmountFormatter.money(Decimal(p.amount)))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Selection highlights the whole column behind the bar rather than
            // drawing a line through it — the bar stays readable and the tap
            // clearly belongs to that day.
            if let sel = selectedDate.wrappedValue {
                RectangleMark(x: .value("Selected", sel, unit: unit))
                    .foregroundStyle(Color.primary.opacity(0.06))
                    .zIndex(-1)
            }
        }
        .chartLegend(.hidden)   // colour now encodes budget, not series
        // No Y axis and no gridlines. Every bar already carries its own amount, so
        // an axis would be the same information twice — and the axis furniture is
        // most of what makes a chart look busy. Pedometer++ draws neither.
        .chartYAxis(.hidden)
        // X axis keeps the dates but drops the gridlines and the axis rule.
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel().font(.system(size: 9))
            }
        }
        // `chartCeiling` already includes its headroom, so no second helping here.
        .chartYScale(domain: 0...(peak > 0 ? peak : 1))
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
        // Scrolling into a period with a different peak rescales the bars. Without
        // this they jump to their new heights; with it they grow into them.
        .animation(.smooth(duration: 0.35), value: peak)
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

