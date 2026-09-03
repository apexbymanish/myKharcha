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

    /// "August 2026" / "Aug 17–23, 2026" / "2026", matching the scope on screen.
    private var periodLabel: String {
        let f = DateFormatter()
        switch period {
        case .week:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: summary.start) ?? summary.start
            f.setLocalizedDateFormatFromTemplate("MMMd")
            let range = "\(f.string(from: summary.start)) – \(f.string(from: end))"
            f.setLocalizedDateFormatFromTemplate("yyyy")
            return "\(range), \(f.string(from: summary.start))"
        case .month:
            f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return f.string(from: summary.start)
        case .year:
            f.setLocalizedDateFormatFromTemplate("yyyy")
            return f.string(from: summary.start)
        }
    }

    private var trendPhrase: Text? {
        // No prior period to compare against — drop the clause rather than
        // claiming a change from nothing.
        guard let pct = summary.changePercent, summary.trend != .unknown else { return nil }
        switch summary.trend {
        case .flat:
            return Text(" is ") + Text("unchanged").foregroundStyle(.secondary) + Text(",")
        case .up:
            return Text(" is ") + Text("up \(pct)%").foregroundStyle(Color.moneyOut) + Text(",")
        case .down:
            return Text(" is ") + Text("down \(pct)%").foregroundStyle(Color.moneyIn) + Text(",")
        case .unknown:
            return nil
        }
    }

    var body: some View {
        Group {
            if let trend = trendPhrase {
                Text("Spending in \(periodLabel)") + trend + Text(" totalling \(total).")
            } else {
                Text("Spending in \(periodLabel) totalled \(total).")
            }
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(isRevealed
            ? "Spending in \(periodLabel), \(AmountFormatter.money(summary.expense))"
            : "Amounts hidden")
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

    /// One whole period fills the screen, so the scope control decides both what a
    /// bar means and how far one swipe travels: a week, a month, or a year.
    private var visibleDomain: TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        switch period {
        case .week:  return 7 * day
        case .month: return 31 * day     // the longest month, so none is clipped
        case .year:  return 365 * day
        }
    }

    /// Where a swipe comes to rest — the start of a week, a month, or a year, to
    /// match the scope. Without this the chart halts mid-period and the header
    /// ends up describing a window straddling two months.
    private var snapTo: DateComponents {
        switch period {
        case .week:  return DateComponents(hour: 0, weekday: 1)   // 1 == Sunday
        case .month: return DateComponents(day: 1)
        case .year:  return DateComponents(month: 1, day: 1)
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

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let series: String
        let amount: Double
    }

    private var spentLabel: String { String(localized: "Spent") }
    private var receivedLabel: String { String(localized: "Received") }

    private var points: [Point] {
        bars.flatMap { bar in
            [
                Point(date: bar.date, series: spentLabel, amount: (bar.expense as NSDecimalNumber).doubleValue),
                Point(date: bar.date, series: receivedLabel, amount: (bar.income as NSDecimalNumber).doubleValue)
            ]
        }
    }

    /// Buckets where nothing was spent or received. A zero-height bar draws
    /// nothing, so without their own mark these are indistinguishable from days
    /// with no data at all — and from the empty space past the end of the ledger.
    private var emptyBars: [ActivityBar] { bars.filter(\.isEmpty) }

    var body: some View {
        Chart {
            // A no-spend day is a real, and good, outcome in a spend tracker —
            // not missing data. It gets a baseline dot rather than a stub bar,
            // because a bar would imply an amount that was not spent.
            ForEach(emptyBars) { bar in
                PointMark(
                    x: .value("Date", bar.date, unit: unit),
                    y: .value("Amount", 0)
                )
                .symbol(.circle)
                .symbolSize(14)
                .foregroundStyle(Color.secondary.opacity(0.35))
            }
            ForEach(points) { p in
                BarMark(
                    x: .value("Date", p.date, unit: unit),
                    y: .value("Amount", p.amount),
                    // Chunky bars with tight gutters. A thin bar reads as
                    // decoration; a wide one reads as data.
                    width: .fixed(22)
                )
                .foregroundStyle(barColor(for: p))
                .cornerRadius(3)
                .position(by: .value("Series", p.series))
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
            // Selection indicator — a faint vertical rule at the chosen bucket.
            if let sel = selectedDate.wrappedValue {
                RuleMark(x: .value("Selected", sel, unit: unit))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
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
        .chartXSelection(value: selectedDate)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomain)
        // Scrolling pages by whichever unit the scope control names: pick Month and
        // one swipe moves one month, landing on the 1st rather than part-way in.
        .chartScrollTargetBehavior(.valueAligned(matching: snapTo))
        .chartScrollPosition(x: $scrollPosition)
        // Long-press scrubbing is deliberately absent. With every bar labelled
        // there is no hidden value to uncover, so the gesture would only compete
        // with the scroll pan for no gain. Tap-to-select still filters the list.
        .frame(height: 200)
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
    private var points: [Point] {
        bars.flatMap { bar in
            [
                Point(date: bar.date, series: "e", amount: (bar.expense as NSDecimalNumber).doubleValue),
                Point(date: bar.date, series: "i", amount: (bar.income as NSDecimalNumber).doubleValue)
            ]
        }
    }

    var body: some View {
        Chart(points) { p in
            BarMark(x: .value("Date", p.date, unit: .day), y: .value("Amount", p.amount))
                .foregroundStyle(p.series == "e" ? Color.moneyOut : Color.moneyIn)
                .position(by: .value("Series", p.series))
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

