import SwiftUI
import Charts
import KharchaKit

/// A period summary above the chart: total Received, total Spent, and the Net —
/// with an up/down arrow and green/red color so it's instantly clear whether you
/// came out ahead or spent more than you earned.
///
/// Pass `prevBars` to show "+X% vs prior" deltas beneath each figure.
/// Pass `isRevealed: false` to redact amounts (PrivacyManager locked state).
struct ActivitySummaryHeader: View {
    let bars: [ActivityBar]
    var prevBars: [ActivityBar]? = nil
    var isRevealed: Bool = true

    private var received: Decimal { bars.reduce(0) { $0 + $1.income } }
    private var spent: Decimal { bars.reduce(0) { $0 + $1.expense } }
    private var net: Decimal { received - spent }
    private var isLoss: Bool { net < 0 }

    private var prevReceived: Decimal? { prevBars.map { $0.reduce(0) { $0 + $1.income } } }
    private var prevSpent: Decimal? { prevBars.map { $0.reduce(0) { $0 + $1.expense } } }

    var body: some View {
        HStack(alignment: .top) {
            statColumn(title: "Received", amount: received, tint: .moneyIn,
                       prev: prevReceived, alignment: .leading)
            Spacer()
            statColumn(title: "Spent", amount: spent, tint: .moneyOut,
                       prev: prevSpent, alignment: .center)
            Spacer()
            netColumn
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRevealed
            ? "Received \(AmountFormatter.money(received)), spent \(AmountFormatter.money(spent)). "
                + (isLoss ? "Net loss \(AmountFormatter.money(abs(net)))" : "Net gain \(AmountFormatter.money(net))")
            : "Amounts hidden")
    }

    private func masked(_ amount: Decimal) -> String {
        isRevealed ? AmountFormatter.money(amount) : "••••"
    }

    private func statColumn(
        title: LocalizedStringKey, amount: Decimal, tint: Color,
        prev: Decimal?, alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(masked(amount))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(isRevealed ? tint : Color.secondary)
            if let p = prev, isRevealed {
                Text(pctDelta(current: amount, prev: p))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var netColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Net").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Image(systemName: isLoss ? "arrow.down.right" : "arrow.up.right")
                    .font(.caption.weight(.bold))
                Text(masked(abs(net)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(isRevealed
                ? (isLoss ? Color.moneyOut : Color.moneyIn)
                : Color.secondary)
            // Net delta: show only when revealed and prior data exists.
            if isRevealed, let pr = prevReceived, let ps = prevSpent {
                let prevNet = pr - ps
                let delta = net - prevNet
                Text("\(delta >= 0 ? "+" : "")\(AmountFormatter.money(delta)) vs prior")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "+12% vs prior" / "−8% vs prior" / "< +1%" for sub-1% changes / "—" when no prior data.
    private func pctDelta(current: Decimal, prev: Decimal) -> String {
        guard prev != 0 else { return current == 0 ? "—" : "new" }
        let pct = Double(truncating: ((current - prev) / prev * 100) as NSDecimalNumber)
        if pct != 0 && abs(pct) < 1 {
            return (pct > 0 ? "< +1%" : "< −1%") + " vs prior"
        }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(Int(pct.rounded()))% vs prior"
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

    var body: some View {
        Chart {
            ForEach(points) { p in
                BarMark(
                    x: .value("Date", p.date, unit: unit),
                    y: .value("Amount", p.amount)
                )
                .foregroundStyle(by: .value("Series", p.series))
                .position(by: .value("Series", p.series))
            }
            // Selection indicator — a faint vertical rule at the chosen bucket.
            if let sel = selectedDate.wrappedValue {
                RuleMark(x: .value("Selected", sel, unit: unit))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .zIndex(-1)
            }
        }
        .chartForegroundStyleScale([spentLabel: Color.moneyOut, receivedLabel: Color.moneyIn])
        .chartXSelection(value: selectedDate)
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

/// A month calendar where each day is tinted by its net (green = net income,
/// red = net spend) and tappable to filter the list to that day.
/// Pass `isRevealed: false` to neutralize color coding and hide amounts in accessibility.
struct MonthHeatGrid: View {
    let bars: [ActivityBar]
    let calendar: Calendar
    let selectedDay: Date?
    var isRevealed: Bool = true
    let onSelect: (Date) -> Void

    private var leadingBlanks: Int {
        guard let first = bars.first?.date else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let s = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(s[shift...] + s[..<shift])
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(bars) { bar in
                    DayCell(
                        bar: bar,
                        day: calendar.component(.day, from: bar.date),
                        isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: bar.date) } ?? false,
                        isRevealed: isRevealed
                    )
                    .onTapGesture { onSelect(bar.date) }
                }
            }
        }
    }

    private struct DayCell: View {
        let bar: ActivityBar
        let day: Int
        let isSelected: Bool
        var isRevealed: Bool = true

        private var fill: Color {
            guard isRevealed else { return Color.secondary.opacity(0.10) }
            if bar.net > 0 { return .moneyIn.opacity(0.22) }
            if bar.net < 0 { return .moneyOut.opacity(0.22) }
            return Color.secondary.opacity(0.10)
        }

        private var dotColor: Color {
            guard isRevealed else { return .secondary }
            return bar.net >= 0 ? Color.moneyIn : Color.moneyOut
        }

        var body: some View {
            VStack(spacing: 2) {
                Text("\(day)").font(.caption2)
                if !bar.isEmpty {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 5, height: 5)
                } else {
                    Circle().fill(.clear).frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.brandPrimary, lineWidth: isSelected ? 2 : 0)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(bar.date.formatted(.dateTime.month(.wide).day()))
            .accessibilityValue(
                bar.isEmpty ? "No activity"
                    : isRevealed ? "Net \(AmountFormatter.money(bar.net))"
                    : "Amounts hidden"
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
