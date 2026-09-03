import SwiftUI
import Charts
import KharchaKit

/// How much of the ledger a report covers. This is where the W/M/Y control
/// lives now — History is the graph and scrolls freely through it, so choosing
/// a span is an analysis job and belongs on the analysis screen.
enum ReportScope: String, CaseIterable, Identifiable {
    case week, month, year
    var id: String { rawValue }

    var component: Calendar.Component {
        switch self {
        case .week:  return .weekOfYear
        case .month: return .month
        case .year:  return .year
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        }
    }

    /// Names one period for a chip or an axis tick — "Aug 17", "Aug 26", "2026".
    func label(for date: Date) -> String {
        let f = DateFormatter()
        switch self {
        case .week:  f.setLocalizedDateFormatFromTemplate("MMMd")
        case .month: f.setLocalizedDateFormatFromTemplate("MMMyy")
        case .year:  f.setLocalizedDateFormatFromTemplate("yyyy")
        }
        return f.string(from: date)
    }

    /// Names one period in full, for a card's heading.
    func fullLabel(for date: Date) -> String {
        let f = DateFormatter()
        switch self {
        case .week:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date
            let iv = DateIntervalFormatter()
            iv.dateStyle = .medium
            iv.timeStyle = .none
            return iv.string(from: date, to: end)
        case .month: f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        case .year:  f.setLocalizedDateFormatFromTemplate("yyyy")
        }
        return f.string(from: date)
    }
}

struct ReportsView: View {
    let allRows: [TxnRow]
    let categories: [CategorySnapshot]
    /// Month History was showing when Reports was opened, so the sheet starts on
    /// the same period the user was already looking at rather than its own default.
    var initialMonth: Date? = nil

    /// The ledger, which lives here rather than under the History graph. History
    /// is the graph; reading back through transactions is an analysis job.
    var sections: [HistoryViewModel.Section] = []
    var onEditRow: ((TxnRow) -> Void)? = nil

    @EnvironmentObject private var privacy: PrivacyManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod: Date? = nil
    @State private var scope: ReportScope = .month
    @State private var showExport = false


    /// The transaction ledger. It used to sit under History's graph; History is
    /// now the graph alone, so reading back through rows happens here.
    @ViewBuilder private var ledgerSections: some View {
        ForEach(sections, id: \.title) { section in
            Section(section.title) {
                ForEach(section.rows, id: \.id) { row in
                    Button {
                        onEditRow?(row)
                    } label: {
                        TxnRowView(row: row, categories: categories)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Period helpers

    /// Everything below is written against `scope` rather than against months.
    /// One `dateInterval(of:for:)` call decides the boundaries, so a week, a
    /// month and a year are the same code path with a different component —
    /// which is what lets the W/M/Y control drive the whole screen.
    private func periodStart(containing date: Date) -> Date {
        Calendar.current.dateInterval(of: scope.component, for: date)?.start ?? date
    }

    /// Only periods that actually hold transactions, newest first. Empty ones
    /// are not offered: a chip that leads to "no data" is a dead end you can
    /// only find by tapping it.
    private var availablePeriods: [Date] {
        Set(allRows.map { periodStart(containing: $0.date) }).sorted(by: >)
    }

    private var reportPeriod: Date {
        if let p = selectedPeriod { return periodStart(containing: p) }
        if let p = availablePeriods.first { return p }
        return periodStart(containing: Date())
    }

    /// Compares normalised starts rather than calling `isDate(_:equalTo:)` with
    /// `.weekOfYear`, whose behaviour across a year boundary depends on the
    /// calendar's minimum-days-in-first-week rule.
    private func rows(in period: Date) -> [TxnRow] {
        allRows.filter { periodStart(containing: $0.date) == period }
    }

    private var periodRows: [TxnRow] { rows(in: reportPeriod) }

    private var prevPeriodRows: [TxnRow] {
        guard let prev = Calendar.current.date(byAdding: scope.component, value: -1, to: reportPeriod)
        else { return [] }
        return rows(in: periodStart(containing: prev))
    }

    // MARK: - Totals

    private var totalExpense: Decimal { periodRows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    private var totalIncome:  Decimal { periodRows.filter { $0.kind == .income  }.reduce(0) { $0 + $1.amount } }
    private var net:          Decimal { totalIncome - totalExpense }
    private var prevExpense:  Decimal { prevPeriodRows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    private var prevIncome:   Decimal { prevPeriodRows.filter { $0.kind == .income  }.reduce(0) { $0 + $1.amount } }

    private var salary: Decimal {
        let raw = PayPreference.defaults.double(forKey: PayPreference.salaryKey)
        return raw > 0 ? Decimal(raw) : 0
    }

    // MARK: - Category totals

    struct CatTotal: Identifiable {
        let id: String
        let name: String
        let amount: Decimal
        let colorHex: String
        let pct: Double
    }

    private func catTotals(for kind: TxnKind) -> [CatTotal] {
        let kindRows = periodRows.filter { $0.kind == kind }
        let total = kindRows.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else { return [] }

        let grouped = Dictionary(grouping: kindRows, by: { $0.categoryName.isEmpty ? "Other" : $0.categoryName })
        let sorted = grouped
            .map { name, txns in (name, txns.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }

        let top  = sorted.prefix(5)
        let rest = sorted.dropFirst(5)

        var result: [CatTotal] = top.map { name, amount in
            let hex = categories.first(where: { $0.name == name })?.colorHex ?? "#8E8E93"
            let pct = min(max(NSDecimalNumber(decimal: amount / total).doubleValue, 0), 1)
            return CatTotal(id: name, name: name, amount: amount, colorHex: hex, pct: pct)
        }
        if !rest.isEmpty {
            let othersAmt = rest.reduce(Decimal(0)) { $0 + $1.1 }
            let pct = min(max(NSDecimalNumber(decimal: othersAmt / total).doubleValue, 0), 1)
            result.append(CatTotal(id: "Others", name: "Others", amount: othersAmt, colorHex: "#8E8E93", pct: pct))
        }
        return result
    }

    // MARK: - Top expenses

    private var topExpenses: [TxnRow] {
        Array(periodRows.filter { $0.kind == .expense }.sorted { $0.amount > $1.amount }.prefix(5))
    }

    // MARK: - Insight nudge

    private var insightText: String? {
        guard prevExpense > 0, totalExpense > 0 else { return nil }
        let delta = totalExpense - prevExpense
        let pct = Int((NSDecimalNumber(decimal: abs(delta) / prevExpense * 100).doubleValue).rounded())
        guard pct >= 3 else { return nil }

        let prevGrouped = Dictionary(grouping: prevPeriodRows.filter { $0.kind == .expense }, by: { $0.categoryName.isEmpty ? "Other" : $0.categoryName })
        let curGrouped  = Dictionary(grouping: periodRows.filter    { $0.kind == .expense }, by: { $0.categoryName.isEmpty ? "Other" : $0.categoryName })
        var biggestCat: String?
        var biggestPct: Double = 0
        for (catName, curTxns) in curGrouped {
            let cur  = curTxns.reduce(Decimal(0)) { $0 + $1.amount }
            let prev = prevGrouped[catName]?.reduce(Decimal(0)) { $0 + $1.amount } ?? 0
            guard prev > 0 else { continue }
            let catPct = abs(NSDecimalNumber(decimal: (cur - prev) / prev).doubleValue * 100)
            if catPct > biggestPct { biggestPct = catPct; biggestCat = catName }
        }

        let direction = delta > 0 ? "up" : "down"
        if let cat = biggestCat {
            return "\(cat) spending is \(direction) \(pct)% from last month"
        }
        return "Total spending is \(direction) \(pct)% from last month"
    }

    // MARK: - Body

    /// Sheet chrome and the scope control, both pinned above the scrolling
    /// content. The picker does not scroll away: it is the control that decides
    /// what everything below means, so it has to stay reachable while you read.
    @ViewBuilder private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("Reports")
                    .font(.title2.bold())

                HStack(spacing: 8) {
                    RptCircleButton(symbol: "xmark", label: "Close") { dismiss() }
                    Spacer()
                    RptCircleButton(symbol: "square.and.arrow.up", label: "Export") {
                        showExport = true
                    }
                    .disabled(periodRows.isEmpty)
                }
            }

            Picker("Scope", selection: $scope) {
                ForEach(ReportScope.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            header
            List {
                monthSelectorSection
                if periodRows.isEmpty {
                    Section {
                        EmptyStateView(
                            icon: "chart.pie",
                            title: "No data for this period",
                            message: "Add transactions to see your spending report."
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    comparisonSection
                    statsSection
                    salarySection
                    if let day = biggestDay { biggestDaySection(day) }
                    categorySection
                    if !prevPeriodRows.isEmpty { momSection }
                    if !topExpenses.isEmpty   { topExpensesSection }
                    if let insight = insightText { insightSection(insight) }
                    ledgerSections
                }
            }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            // Inherit History's month on open so Reports doesn't silently show a
            // different period than the screen it was opened from.
            .onAppear { if selectedPeriod == nil { selectedPeriod = initialMonth } }
            .sheet(isPresented: $showExport) {
                ExportPreviewSheet(rows: periodRows,
                                   periodLabel: scope.fullLabel(for: reportPeriod))
            }
        }
    }

    // MARK: - Month selector

    @ViewBuilder private var monthSelectorSection: some View {
        if !availablePeriods.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availablePeriods, id: \.self) { period in
                            ReportMonthChip(
                                label: scope.label(for: period),
                                isActive: reportPeriod == period
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) { selectedPeriod = period }
                            }
                        }
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Spend against salary

    /// The one thing the stats grid does not carry: spending measured against
    /// what came in to cover it. A total answers "how much"; this answers
    /// "how much of it", which is the question a salary earner is actually
    /// asking, and it needs a bar rather than a figure to answer.
    @ViewBuilder private var salarySection: some View {
        if salary > 0 && totalExpense > 0 {
            Section {
                let fraction = min(NSDecimalNumber(decimal: totalExpense / salary).doubleValue, 1.0)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("of salary").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(privacy.isRevealed
                             ? AmountFormatter.money(totalExpense) + " / " + AmountFormatter.money(salary)
                             : "•••• / ••••")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule()
                                .fill(fraction >= 1.0 ? Color.moneyOut : Color.brandPrimary)
                                .frame(width: geo.size.width * fraction)
                        }
                    }.frame(height: 6)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Comparison chart

    /// This period against the two before it. Three is the useful number: one
    /// bar is a figure, two is a comparison, three is the first count at which
    /// you can see a direction rather than a single step.
    private struct PeriodTotal: Identifiable {
        let id: Date
        let label: String
        let amount: Decimal
        let isCurrent: Bool
    }

    private var comparisonTotals: [PeriodTotal] {
        let cal = Calendar.current
        return (0..<3).reversed().compactMap { back -> PeriodTotal? in
            guard let date = cal.date(byAdding: scope.component, value: -back, to: reportPeriod)
            else { return nil }
            let start = periodStart(containing: date)
            let spent = rows(in: start).filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
            return PeriodTotal(id: start,
                               label: scope.label(for: start),
                               amount: spent,
                               isCurrent: back == 0)
        }
    }

    @ViewBuilder private var comparisonSection: some View {
        Section {
            Chart(comparisonTotals) { p in
                BarMark(
                    x: .value("Period", p.label),
                    y: .value("Spent", NSDecimalNumber(decimal: p.amount).doubleValue),
                    width: .ratio(0.55)
                )
                // The period you are reading is solid; the ones it is measured
                // against recede, so the comparison has a subject.
                .foregroundStyle(p.isCurrent ? Color.moneyOut : Color.moneyOut.opacity(0.3))
                .cornerRadius(6)
                .annotation(position: .top, spacing: 4) {
                    if p.isCurrent && privacy.isRevealed {
                        Text(AmountFormatter.money(p.amount))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.moneyOut)
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Stats grid

    /// Days the average is divided by. For a period still running that is the
    /// days elapsed, not the days it will hold — dividing August's spending by
    /// 31 on the 3rd reports a daily average three times lower than the truth.
    private var elapsedDays: Int {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: scope.component, for: reportPeriod) else { return 1 }
        let end = min(interval.end, Date())
        let days = cal.dateComponents([.day], from: interval.start, to: end).day ?? 0
        return max(days, 1)
    }

    private var dailyAverage: Decimal { totalExpense / Decimal(elapsedDays) }

    private var categoryCount: Int {
        Set(periodRows.filter { $0.kind == .expense }
            .map { $0.categoryName.isEmpty ? "Other" : $0.categoryName }).count
    }

    @ViewBuilder private var statsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(scope.fullLabel(for: reportPeriod))
                    .font(.title2.bold())

                Grid(horizontalSpacing: 12, verticalSpacing: 16) {
                    GridRow {
                        RptStatTile(value: AmountFormatter.money(totalExpense),
                                    label: "TOTAL SPENT", tint: .moneyOut, isRevealed: privacy.isRevealed)
                        RptStatTile(value: AmountFormatter.money(dailyAverage),
                                    label: "PER DAY", isRevealed: privacy.isRevealed)
                    }
                    GridRow {
                        RptStatTile(value: AmountFormatter.money(totalIncome),
                                    label: "TOTAL RECEIVED", tint: .moneyIn, isRevealed: privacy.isRevealed)
                        RptStatTile(value: (net >= 0 ? "+" : "−") + AmountFormatter.money(abs(net)),
                                    label: "NET", tint: net >= 0 ? .moneyIn : .moneyOut,
                                    isRevealed: privacy.isRevealed)
                    }
                    GridRow {
                        // Counts are not amounts, so the privacy toggle leaves
                        // them alone — hiding "47 transactions" protects nothing.
                        RptStatTile(value: "\(periodRows.count)", label: "TRANSACTIONS", isRevealed: true)
                        RptStatTile(value: "\(categoryCount)", label: "CATEGORIES", isRevealed: true)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Biggest day

    private struct DayTotal {
        let date: Date
        let spent: Decimal
        let received: Decimal
        let count: Int
    }

    private var biggestDay: DayTotal? {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: periodRows) { cal.startOfDay(for: $0.date) }
        let totals = byDay.map { date, rows in
            DayTotal(date: date,
                     spent: rows.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount },
                     received: rows.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount },
                     count: rows.count)
        }
        return totals.filter { $0.spent > 0 }.max { $0.spent < $1.spent }
    }

    @ViewBuilder private func biggestDaySection(_ day: DayTotal) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(day.date.formatted(.dateTime.month(.wide).day().year()))
                    .font(.title3.bold())
                Text("BIGGEST DAY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.moneyOut)

                HStack(alignment: .top, spacing: 0) {
                    RptStatTile(value: AmountFormatter.money(day.spent),
                                label: "SPENT", tint: .moneyOut, isRevealed: privacy.isRevealed)
                    RptStatTile(value: AmountFormatter.money(day.received),
                                label: "RECEIVED", tint: .moneyIn, isRevealed: privacy.isRevealed)
                    RptStatTile(value: "\(day.count)", label: "ENTRIES", isRevealed: true)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Category breakdown

    @ViewBuilder private var categorySection: some View {
        let expTotals = catTotals(for: .expense)
        let incTotals = catTotals(for: .income)

        if !expTotals.isEmpty || !incTotals.isEmpty {
            Section("Where it went") {
                if !expTotals.isEmpty {
                    if privacy.isRevealed {
                        Chart(expTotals) { cat in
                            SectorMark(
                                angle: .value("Amount", NSDecimalNumber(decimal: cat.amount).doubleValue),
                                innerRadius: .ratio(0.58),
                                angularInset: 2
                            )
                            .foregroundStyle(Color(hex: cat.colorHex))
                            .cornerRadius(3)
                        }
                        .frame(height: 160)
                        .chartLegend(.hidden)
                    }
                    ForEach(expTotals) { cat in
                        RptCatBarRow(cat: cat, isRevealed: privacy.isRevealed)
                    }
                }
                if !incTotals.isEmpty {
                    if !expTotals.isEmpty { Divider() }
                    Text("Income sources").font(.caption).foregroundStyle(.secondary)
                    ForEach(incTotals) { cat in
                        HStack {
                            Circle().fill(Color.moneyIn).frame(width: 8, height: 8)
                            Text(cat.name).font(.subheadline)
                            Spacer()
                            Text(privacy.isRevealed ? "+" + AmountFormatter.money(cat.amount) : "+••••")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(Color.moneyIn)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Month-over-month

    @ViewBuilder private var momSection: some View {
        Section("vs Last month") {
            HStack(spacing: 0) {
                RptMoMStat(label: "Spent",    current: totalExpense,        prev: prevExpense,              lowerIsBetter: true,  isRevealed: privacy.isRevealed)
                Divider().frame(height: 44)
                RptMoMStat(label: "Received", current: totalIncome,         prev: prevIncome,               lowerIsBetter: false, isRevealed: privacy.isRevealed)
                Divider().frame(height: 44)
                RptMoMStat(label: "Net",      current: net,                 prev: prevIncome - prevExpense, lowerIsBetter: false, isRevealed: privacy.isRevealed)
            }
        }
    }

    // MARK: - Top expenses

    @ViewBuilder private var topExpensesSection: some View {
        Section("Top expenses") {
            ForEach(Array(topExpenses.enumerated()), id: \.element.id) { idx, row in
                HStack {
                    Text("\(idx + 1)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.categoryName.isEmpty ? "Uncategorized" : row.categoryName).font(.subheadline)
                        if let note = row.note, !note.isEmpty {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(row.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(privacy.isRevealed ? AmountFormatter.money(row.amount) : "••••")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Color.moneyOut)
                }
            }
        }
    }

    // MARK: - Insight

    @ViewBuilder private func insightSection(_ text: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.callout)
                Text(text).font(.subheadline)
            }
        }
    }
}

// MARK: - Supporting views

private struct RptCatBarRow: View {
    let cat: ReportsView.CatTotal
    let isRevealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(Color(hex: cat.colorHex)).frame(width: 8, height: 8)
                Text(cat.name).font(.subheadline)
                Spacer()
                Text(isRevealed ? AmountFormatter.money(cat.amount) : "••••")
                    .font(.subheadline.monospacedDigit())
                Text("\(Int((cat.pct * 100).rounded()))%")
                    .font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule().fill(Color(hex: cat.colorHex)).frame(width: geo.size.width * cat.pct)
                }
            }.frame(height: 4)
        }
        .padding(.vertical, 2)
    }
}

private struct RptMoMStat: View {
    let label: String
    let current: Decimal
    let prev: Decimal
    let lowerIsBetter: Bool
    let isRevealed: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(isRevealed ? AmountFormatter.money(abs(current)) : "••••")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
            if isRevealed && prev != 0 {
                let delta = current - prev
                let pct   = Int((NSDecimalNumber(decimal: abs(delta) / abs(prev) * 100).doubleValue).rounded())
                let up    = delta > 0
                let good  = lowerIsBetter ? !up : up
                HStack(spacing: 2) {
                    Image(systemName: up ? "arrow.up" : "arrow.down").font(.caption2)
                    Text("\(pct)%").font(.caption2)
                }
                .foregroundStyle(pct < 3 ? .secondary : (good ? Color.moneyIn : Color.moneyOut))
            } else {
                Text("—").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// One figure and its caption. The unit of the stats grid and the biggest-day
/// card, so a number means the same thing and is measured the same way wherever
/// it appears on this screen.
private struct RptStatTile: View {
    let value: String
    let label: LocalizedStringKey
    var tint: Color = .primary
    let isRevealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isRevealed ? value : "••••")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A circular glyph button, the sheet-chrome control the reference screens use
/// in place of a navigation bar's text buttons.
private struct RptCircleButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ReportMonthChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isActive ? Color.brandPrimary : Color.secondary.opacity(0.1))
                .foregroundStyle(isActive ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(.easeInOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
