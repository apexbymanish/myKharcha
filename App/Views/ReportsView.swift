import SwiftUI
import Charts
import KharchaKit

struct ReportsView: View {
    let allRows: [TxnRow]
    let categories: [CategorySnapshot]
    /// Month History was showing when Reports was opened, so the sheet starts on
    /// the same period the user was already looking at rather than its own default.
    var initialMonth: Date? = nil

    /// Filtering lives here, not on History. History is the ledger and its graph;
    /// narrowing what it shows is an analysis job, so the control sits with the
    /// other analysis. The state itself stays owned by History, which renders the
    /// list — these are its bindings.
    var filterHost: FilterHost? = nil

    /// Everything Reports needs to present the Filters sheet on History's behalf.
    struct FilterHost {
        let vm: HistoryViewModel
        let selectedYear: Binding<Int?>
        let selectedMonth: Binding<Date?>
        let availableYears: [Int]
        let availableMonths: [Date]
        let resultsCount: Int
        let onReset: () -> Void
    }

    @EnvironmentObject private var privacy: PrivacyManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonth: Date? = nil
    @State private var showFilters = false

    // MARK: - Period helpers

    private var availableMonths: [Date] {
        let cal = Calendar.current
        let months = Set(allRows.compactMap { row -> Date? in
            var comps = cal.dateComponents([.year, .month], from: row.date)
            comps.day = 1
            return cal.date(from: comps)
        })
        return months.sorted(by: >)
    }

    private var reportMonth: Date {
        if let m = selectedMonth { return m }
        if let m = availableMonths.first { return m }
        var comps = Calendar.current.dateComponents([.year, .month], from: Date())
        comps.day = 1
        return Calendar.current.date(from: comps) ?? Date()
    }

    private var periodRows: [TxnRow] {
        let cal = Calendar.current
        return allRows.filter { cal.isDate($0.date, equalTo: reportMonth, toGranularity: .month) }
    }

    private var prevMonthRows: [TxnRow] {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .month, value: -1, to: reportMonth) else { return [] }
        return allRows.filter { cal.isDate($0.date, equalTo: prev, toGranularity: .month) }
    }

    // MARK: - Totals

    private var totalExpense: Decimal { periodRows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    private var totalIncome:  Decimal { periodRows.filter { $0.kind == .income  }.reduce(0) { $0 + $1.amount } }
    private var net:          Decimal { totalIncome - totalExpense }
    private var prevExpense:  Decimal { prevMonthRows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    private var prevIncome:   Decimal { prevMonthRows.filter { $0.kind == .income  }.reduce(0) { $0 + $1.amount } }

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

        let prevGrouped = Dictionary(grouping: prevMonthRows.filter { $0.kind == .expense }, by: { $0.categoryName.isEmpty ? "Other" : $0.categoryName })
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

    var body: some View {
        NavigationStack {
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
                    heroSection
                    categorySection
                    if !prevMonthRows.isEmpty { momSection }
                    if !topExpenses.isEmpty   { topExpensesSection }
                    if let insight = insightText { insightSection(insight) }
                }
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.large)
            // Inherit History's month on open so Reports doesn't silently show a
            // different period than the screen it was opened from.
            .onAppear { if selectedMonth == nil { selectedMonth = initialMonth } }
            .toolbar {
                if filterHost != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showFilters = true } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel("Filter transactions")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showFilters) {
                if let host = filterHost {
                    FiltersSheetView(
                        vm: host.vm,
                        selectedYear: host.selectedYear,
                        selectedMonth: host.selectedMonth,
                        availableYears: host.availableYears,
                        availableMonths: host.availableMonths,
                        resultsCount: host.resultsCount,
                        onReset: host.onReset
                    )
                }
            }
        }
    }

    // MARK: - Month selector

    @ViewBuilder private var monthSelectorSection: some View {
        if !availableMonths.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableMonths, id: \.self) { month in
                            let active = Calendar.current.isDate(reportMonth, equalTo: month, toGranularity: .month)
                            ReportMonthChip(
                                label: month.formatted(.dateTime.month(.abbreviated).year(.twoDigits)),
                                isActive: active
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) { selectedMonth = month }
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

    // MARK: - Hero card

    @ViewBuilder private var heroSection: some View {
        Section {
            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reportMonth.formatted(.dateTime.month(.wide).year()))
                            .font(.caption).foregroundStyle(.secondary)
                        if net >= 0 {
                            Text(privacy.isRevealed ? "Net +" + AmountFormatter.money(net) : "Net +••••")
                                .font(.title2.bold()).foregroundStyle(Color.moneyIn)
                        } else {
                            Text(privacy.isRevealed ? "Net −" + AmountFormatter.money(abs(net)) : "Net −••••")
                                .font(.title2.bold()).foregroundStyle(Color.moneyOut)
                        }
                    }
                    Spacer()
                    Image(systemName: net >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(net >= 0 ? Color.moneyIn : Color.moneyOut)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spent").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(privacy.isRevealed ? AmountFormatter.money(totalExpense) : "••••")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.moneyOut)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 2) {
                        Text("Transactions").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("\(periodRows.count)").font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Received").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(privacy.isRevealed ? AmountFormatter.money(totalIncome) : "••••")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.moneyIn)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                if salary > 0 && totalExpense > 0 {
                    let fraction = min(NSDecimalNumber(decimal: totalExpense / salary).doubleValue, 1.0)
                    VStack(alignment: .leading, spacing: 4) {
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
                }
            }
            .padding(.vertical, 4)
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
