import SwiftUI
import Charts
import KharchaKit

/// The snap-up detail for a tapped bar. Sits on the chart, next to the bar it
/// describes, rather than at the bottom of the screen.
///
/// Carries the day's breakdown, not just its total. The bands already say what
/// the money went on, but only the biggest one is wide enough to hold its name —
/// everything below that is a colour with no label. Tapping is where the rest of
/// the answer lives.
private struct TooltipCard: View {
    let bar: ActivityBar
    /// That day's transactions, in the order they should be read. Passed in
    /// rather than derived from `bar`, because an `ActivityBar` carries category
    /// totals and a category total has no note attached to it — and the note is
    /// what tells you which ₩900,000 this was.
    let entries: [TxnRow]
    let unit: Calendar.Component
    /// Resolved by the chart, so the dot beside an entry matches its band.
    let colorFor: (String) -> Color
    var isRevealed: Bool = true

    /// Four fits without the card growing taller than the chart it sits on. The
    /// rest are counted rather than listed; the ledger in Reports is where you
    /// go to read them all.
    private static let maxRows = 4

    private var shown: ArraySlice<TxnRow> { entries.prefix(Self.maxRows) }
    private var overflow: Int { max(0, entries.count - Self.maxRows) }

    private var label: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(unit == .month ? "MMMMyyyy" : "MMMd")
        return f.string(from: bar.date)
    }

    private func money(_ amount: Decimal) -> String {
        isRevealed ? AmountFormatter.money(amount) : "••••"
    }

    private func category(_ row: TxnRow) -> String {
        row.categoryName.isEmpty ? String(localized: "Uncategorized") : row.categoryName
    }

    private func note(_ row: TxnRow) -> String? {
        guard let n = row.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !n.isEmpty else { return nil }
        return n
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                // Counts are not amounts, so they stay visible when amounts hide.
                if bar.count > 0 {
                    Text("\(bar.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            if bar.expense > 0 {
                Text("−" + money(bar.expense))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.moneyOut)
            }
            if bar.income > 0 {
                Text("+" + money(bar.income))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.moneyIn)
            }

            if !shown.isEmpty {
                Divider().padding(.vertical, 1)
                ForEach(shown, id: \.id) { row in
                    HStack(alignment: .top, spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(colorFor(category(row)))
                            .frame(width: 7, height: 7)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 0) {
                            // The note leads when there is one — "Loan payed"
                            // identifies the entry, "Other" only bins it. The
                            // category drops to the line beneath so both are
                            // there without either crowding the other.
                            Text(note(row) ?? category(row))
                                .font(.caption2)
                                .lineLimit(1)
                            if note(row) != nil {
                                Text(category(row))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Text((row.kind == .expense ? "−" : "+") + money(row.amount))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(row.kind == .expense ? .secondary : Color.moneyIn)
                    }
                }
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: 110, maxWidth: 210, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
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
    var isRevealed: Bool = true

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
            Text(isRevealed ? AmountFormatter.money(amount) : "••••")
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.caption2.weight(.semibold))
        .minimumScaleFactor(0.75)
        .lineLimit(1)
    }
}

private extension Array {
    /// First index whose element satisfies `belongsAfter`, assuming the array is
    /// partitioned by it — the standard lower-bound binary search.
    func partitioningIndex(where belongsAfter: (Element) -> Bool) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = low + (high - low) / 2
            if belongsAfter(self[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
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
    /// Whether amounts are shown. The bars used to print real figures while the
    /// hero above them masked to bullets, so the privacy toggle hid the one
    /// number on screen and left nine.
    var isRevealed: Bool = true
    /// The selected day's transactions, supplied by the owner — the chart is
    /// given buckets, and a bucket does not carry notes.
    var selectedEntries: [TxnRow] = []
    /// The window everything scales against, quantised to whole buckets.
    ///
    /// Three designs were tried here. Scaling off the raw scroll position
    /// recomputed the ceiling dozens of times a second and the bars sheared the
    /// whole way through a fling. Freezing it until the scroll came to rest
    /// fixed that and broke something worse: scroll into a window with income,
    /// or with taller bars, and the domain still belonged to where you left —
    /// so income had no room below the axis and tall bars clipped square until
    /// you stopped.
    ///
    /// This follows the scroll live, but only ever sees whole buckets, and the
    /// ceiling it derives is snapped to a round step. Between them the scale
    /// changes only when the set of visible bars really does and the magnitude
    /// really has, and each change rides the spring at the bottom of `body`.
    /// It is what the Health-style implementations do: rescale on a quantised
    /// offset, animated — not per frame, and not deferred.
    var scaleAnchor: Date = .distantPast
    /// Leading edge of the visible window, bound to the view model's chart anchor.
    /// Writing to it is how scrolling moves the period the header describes.
    @Binding var scrollPosition: Date

    /// Rebuilt only when `marksKey` changes.
    @State private var marks = Marks()

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
        // The same count the view model picks the opening anchor against. Two
        // copies of this number is two windows that can disagree.
        let buckets = Double(HistoryViewModel.chartVisibleBuckets)
        switch period {
        case .week, .month: return buckets * day
        case .year:         return buckets * 30 * day
        }
    }

    private var visibleDomain: TimeInterval { Self.visibleDomain(for: period) }

    /// Start of the bucket a date falls in, so a reported range only changes when
    /// the set of visible bars does.
    static func bucketStart(_ date: Date, unit: Calendar.Component) -> Date {
        let cal = Calendar.current
        return unit == .month
            ? (cal.dateInterval(of: .month, for: date)?.start ?? date)
            : cal.startOfDay(for: date)
    }

    /// The buckets actually on screen — from the scroll position forward by one
    /// visible domain, the boundary bucket included. Everything that scales with
    /// "what you can see" derives from this rather than from the whole series.
    ///
    /// The far edge is inclusive because `chartXVisibleDomain` is a length rather
    /// than a bar count, so the bucket on that boundary is drawn. Leaving it out
    /// measured the ceiling without a bar that was on screen, and that bar then
    /// overflowed the domain it had not been counted in.
    private var visibleBars: [ActivityBar] {
        // `scaleAnchor` is fed back from the range this chart reported through
        // `ChartVisibleRangeKey`, so the marks are scaled against the buckets the
        // chart says it is drawing. One frame behind on first layout, and correct
        // from then on — which beats a scroll position that can be wrong and stay
        // wrong.
        let start = scaleAnchor == .distantPast ? scrollPosition : scaleAnchor
        let end = start.addingTimeInterval(visibleDomain)
        // A slice, not a filter. `bars` is sorted and contiguous, so the window is
        // a range of indices found by two binary searches — and this is read by
        // the ceiling, the income depth and the bar width, each of which used to
        // walk all 800 buckets on every body pass. During a fling that is every
        // frame, several times over.
        let lower = bars.partitioningIndex(where: { $0.date >= start })
        let upper = bars.partitioningIndex(where: { $0.date > end })
        guard lower <= upper else { return [] }
        return Array(bars[lower..<upper])
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
        let ceiling = ActivitySeries.niceCeiling(ActivitySeries.chartCeiling(totals))
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

    /// Nothing hangs below the axis any more, so the domain starts at zero.
    ///
    /// Income used to diverge downward on its own scale. It reads more directly
    /// with both measures growing the same way, at the cost that the axis now
    /// means two different things depending on the colour: a green bar is scaled
    /// against the income seen in the window, a red one against the spending, and
    /// one twice the height of the other does not mean twice the money. They
    /// cannot share a scale — a ₩3,000,000 salary beside ₩30,000 days flattens
    /// every red bar to a line, which is what sent income below the axis in the
    /// first place.
    private var floorValue: Double { 0 }

    private var seriesHasIncome: Bool { bars.contains { $0.income > 0 } }

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
    private func barColor(for p: Point) -> Color { barColor(forCategory: p.series) }

    /// Keyed on the name rather than a `Point`, so the tooltip's dots resolve
    /// through the same function the bands do and cannot drift from them.
    private func barColor(forCategory name: String) -> Color {
        if let hex = categoryColors[name] { return Color(hex: hex) }
        // Dimmed on purpose. At full strength systemGray is the brightest band on
        // a dark chart, which puts the loudest colour on the one bucket that means
        // "nothing in particular" and lets it out-shout the named categories.
        if name == ActivityBar.otherSegmentName {
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
        let ceiling = ActivitySeries.niceCeiling(ActivitySeries.chartCeiling(totals))
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

    /// The bucket the user tapped.
    ///
    /// The whole `ActivityBar`, not a `Point`. A Point is one band, so the
    /// tooltip used to report the leading category's amount as if it were the
    /// day's — right on a single-category day and quietly wrong on every other.
    private var selectedBar: ActivityBar? {
        guard let sel = selectedDate.wrappedValue else { return nil }
        let cal = Calendar.current
        return bars.first { cal.isDate($0.date, equalTo: sel, toGranularity: unit) }
    }

    /// One category's band within one day's bar.
    private struct Point: Identifiable {
        /// Derived, never minted. `UUID()` gave every mark a new identity on every
        /// rebuild, so Swift Charts could not match a bar to its previous self: it
        /// discarded and redrew the lot rather than animating a height, which is
        /// most of what "glitchy on a fast scroll" was.
        var id: String { "\(date.timeIntervalSince1970)|\(series)" }
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
    /// The marks, built once per window instead of once per body pass.
    ///
    /// `points` walks every bucket and every category band inside it, `emptyBars`
    /// and `incomePoints` walk the series again — all three of them on every body
    /// pass, which during a fling is every frame. The whole series has to be
    /// plotted for scrolling to work, so the cost cannot be trimmed by drawing
    /// less; it can only be paid less often. This is what "Pedometer++ has its
    /// data ready" amounts to: prepare, then read.
    private struct Marks {
        var points: [Point] = []
        var emptyBars: [ActivityBar] = []
        var incomePoints: [IncomePoint] = []
    }

    /// What the marks actually depend on. Anything absent here cannot change
    /// their geometry, so it must not cause the work to be redone.
    private struct MarksKey: Equatable {
        let barCount: Int
        let firstBar: Date?
        let cap: Double
        let incomeDepth: Double
    }

    private var marksKey: MarksKey {
        MarksKey(barCount: bars.count,
                 firstBar: bars.first?.date,
                 cap: spendTop,
                 incomeDepth: incomePeak > 0 ? abs(floorValue) : 0)
    }

    private func buildMarks() -> Marks {
        Marks(points: buildPoints(),
              emptyBars: bars.filter { $0.expense == 0 },
              incomePoints: buildIncomePoints())
    }

    private var points: [Point] { marks.points }
    private var emptyBars: [ActivityBar] { marks.emptyBars }
    private var incomePoints: [IncomePoint] { marks.incomePoints }

    private func buildPoints() -> [Point] {
        // A day above the ceiling is drawn just under it rather than through it.
        //
        // `chartCeiling` deliberately lets a rent-sized day clip so the ordinary
        // days stay readable, but a mark drawn past the top of the domain is cut
        // off square and loses its rounded cap — the bars stopped looking like
        // bars and became rectangles. Scaling the day's bands down to sit a hair
        // below the ceiling keeps the cap, keeps the proportions between the
        // bands, and still reads as "off the top of the scale". `dayTotal` stays
        // the true figure, so the label above the bar never lies about it.
        let cap = spendTop * 0.985
        return bars.flatMap { bar -> [Point] in
            let total = (bar.expense as NSDecimalNumber).doubleValue
            guard total > 0 else { return [] }
            let squeeze = total > cap ? cap / total : 1
            return bar.segments.enumerated().map { index, seg in
                Point(date: bar.date,
                      series: seg.categoryName,
                      amount: (seg.amount as NSDecimalNumber).doubleValue * squeeze,
                      dayTotal: total,
                      isLead: index == 0,
                      isTop: index == bar.segments.count - 1)
            }
        }
    }

    // Days with nothing spent keep their column and show a flat grey stub, so a
    // no-spend day reads as a day you spent nothing rather than a hole. Built in
    // `buildMarks`.

    /// Income bars, pre-scaled to their own half of the axis.
    ///
    /// Computed here rather than inline: `let` bindings inside a
    /// `ChartContentBuilder` closure defeat its type inference, and the failure
    /// surfaces as a misleading "cannot convert [ActivityBar] to Binding<C>".
    private struct IncomePoint: Identifiable {
        var id: Date { date }
        let date: Date
        let amount: Decimal
        let plotted: Double
    }

    private func buildIncomePoints() -> [IncomePoint] {
        guard seriesHasIncome, incomePeak > 0 else { return [] }
        // Upward, and normalised to the income seen in the window so the biggest
        // green bar reaches the same height the biggest red one does. Held just
        // under the ceiling for the same reason the spend bars are: a mark drawn
        // past the top of the domain is cut off square and loses its cap.
        let ceiling = spendTop * 0.985
        return bars.compactMap { bar in
            guard bar.income > 0 else { return nil }
            let value = (bar.income as NSDecimalNumber).doubleValue
            return IncomePoint(date: bar.date,
                               amount: bar.income,
                               plotted: (value / incomePeak) * ceiling)
        }
    }

    // MARK: - Chart content
    //
    // Split out of `body`: with all of it inline the type-checker gave up on
    // the whole Chart expression, the same way it did on HistoryView's List.

    @ChartContentBuilder private var incomeMarks: some ChartContent {
        // Income grows upward alongside spending, in green.
        //
        // Same width as a spend bar — one bar spec for both measures, so a green
        // column and a red one are the same object in two colours rather than
        // looking like two different kinds of thing.
        //
        // Drawn after the spend marks, so on a day that both earned and spent the
        // green covers the red entirely. That collision is the open question
        // here, deliberately left plain to look at.
        ForEach(incomePoints) { p in
            BarMark(
                x: .value("Date", p.date, unit: unit),
                yStart: .value("Amount", 0),
                yEnd: .value("Amount", p.plotted),
                width: .ratio(barRatio)
            )
            .foregroundStyle(Color.moneyIn)
            .cornerRadius(4)
            .annotation(position: .top,
                        spacing: 3,
                        overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .fit(to: .chart))) {
                AmountTag(amount: p.amount, direction: .received, isRevealed: isRevealed)
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
                    AmountTag(amount: Decimal(p.dayTotal), direction: .spent, isRevealed: isRevealed)
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
            zeroRuleMark
            emptyDayMarks
            spendMarks
            // Last, so on a day that both earned and spent the green sits over
            // the red. Income was drawn first here and last on Home's week chart,
            // which put the same collision on top on one screen and underneath on
            // the other.
            incomeMarks
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
                if let bar = selectedBar,
                   let plot = proxy.plotFrame,
                   let x = proxy.position(forX: bar.date) {
                    let originX = geo[plot].origin.x
                    TooltipCard(bar: bar,
                                entries: selectedEntries,
                                unit: unit,
                                colorFor: { barColor(forCategory: $0) },
                                isRevealed: isRevealed)
                        // Half the card's widest width, so a tap on the first or
                        // last bar slides the card inside the frame rather than
                        // hanging it off the edge.
                        .position(x: min(max(originX + x, 110), geo.size.width - 110), y: 62)
                        // Scales up from the bar rather than appearing, and slides
                        // between bars instead of jumping when the selection moves.
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .animation(.spring(response: 0.32, dampingFraction: 0.72),
                                   value: bar.date)
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
        .onChange(of: marksKey, initial: true) { _, _ in marks = buildMarks() }
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
    /// Amounts are drawn on the bars, so the privacy toggle has to reach here
    /// too — the same hole the full chart had.
    var isRevealed: Bool = true

    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        /// Where the bar is drawn — held below the ceiling so its cap survives.
        let amount: Double
        /// What the day actually cost. The label reads this, never `amount`,
        /// or a capped bar would report a figure the user never spent.
        let trueAmount: Decimal
    }

    /// Income hangs below a zero rule on its own scale, as on the full chart.
    private struct IncomePoint: Identifiable {
        var id: Date { date }
        let date: Date
        let amount: Decimal
        let plotted: Double
    }

    private var spendPoints: [Point] {
        // Held just under the ceiling for the same reason as the full chart: a
        // mark drawn past the top of the domain is cut off square and loses its
        // rounded cap.
        let cap = spendTop * 0.985
        return bars.compactMap { bar in
            let spent = (bar.expense as NSDecimalNumber).doubleValue
            guard spent > 0 else { return nil }
            return Point(date: bar.date, amount: min(spent, cap), trueAmount: bar.expense)
        }
    }

    private var spendTop: Double {
        let ceiling = ActivitySeries.chartCeiling(bars.map(\.expense).filter { $0 > 0 })
        let value = (ceiling as NSDecimalNumber).doubleValue
        return value > 0 ? value : 1
    }

    private var incomePeak: Double {
        let ceiling = ActivitySeries.chartCeiling(bars.map(\.income).filter { $0 > 0 })
        return (ceiling as NSDecimalNumber).doubleValue
    }

    /// A slightly deeper share than the full chart's quarter. At this height a
    /// quarter of 120pt is 30pt, and a bar that short reads as an artefact
    /// rather than as a measure.
    private static let incomeShare = 0.3

    private var floorValue: Double {
        // Keyed on the whole series, not the visible window. Deriving it from the
        // window meant a window with no income had no room below the axis — so
        // scrolling into a payday drew nothing until the scale caught up, and the
        // green bars appeared out of thin air when it did. The frame is reserved
        // whenever the ledger has any income at all, and stays reserved.
        guard seriesHasIncome else { return 0 }
        return -spendTop * (Self.incomeShare / (1 - Self.incomeShare))
    }

    private var seriesHasIncome: Bool { bars.contains { $0.income > 0 } }

    private var incomePoints: [IncomePoint] {
        guard seriesHasIncome, incomePeak > 0 else { return [] }
        // Four fifths, leaving a gutter for the figure — same reason as the full
        // chart: written under the bar it sits on the background, not on green.
        let depth = abs(floorValue) * 0.8
        return bars.compactMap { bar in
            guard bar.income > 0 else { return nil }
            let value = (bar.income as NSDecimalNumber).doubleValue
            return IncomePoint(date: bar.date,
                               amount: bar.income,
                               plotted: -(value / incomePeak) * depth)
        }
    }

    private func money(_ amount: Decimal) -> String {
        isRevealed ? AmountFormatter.money(amount) : "••••"
    }

    @ChartContentBuilder private var spendMarks: some ChartContent {
        ForEach(spendPoints) { p in
            BarMark(x: .value("Date", p.date, unit: .day), y: .value("Amount", p.amount))
                .foregroundStyle(Color.moneyOut)
                .cornerRadius(2)
                // The figure on the bar, as on the full chart. Without it the
                // week is a shape you can compare against itself and nothing
                // else — you can see Thursday was the big day and not what it
                // cost, which is the one thing worth knowing at a glance.
                .annotation(position: .top, spacing: 2,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    Text(money(p.trueAmount))
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // Seven columns on a phone leave roughly 45pt each, and a
                        // five-figure amount wants more than that.
                        .minimumScaleFactor(0.6)
                }
        }
    }

    @ChartContentBuilder private var incomeMarks: some ChartContent {
        ForEach(incomePoints) { p in
            BarMark(x: .value("Date", p.date, unit: .day),
                    yStart: .value("Amount", 0),
                    yEnd: .value("Amount", p.plotted))
                .foregroundStyle(Color.moneyIn)
                .cornerRadius(2)
                .annotation(position: .top, spacing: 2,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    Text(money(p.amount))
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.moneyIn)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
        }
    }

    var body: some View {
        Chart {
            spendMarks
            // Drawn after the spend bars and narrower, so a day that both earned
            // and spent shows both.
            incomeMarks
        }
        .chartLegend(.hidden)
        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisTick() } }
        .chartYAxis(.hidden)
        .chartYScale(domain: floorValue...spendTop)
        // One height now that nothing hangs below the axis.
        .frame(height: 104)
    }
}

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

