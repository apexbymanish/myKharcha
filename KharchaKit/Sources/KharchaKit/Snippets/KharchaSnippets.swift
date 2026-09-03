import SwiftUI

public struct LogConfirmationCard: View {
    let message: String
    public init(message: String) { self.message = message }
    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message).font(.callout)
            Spacer(minLength: 0)
        }
        .padding()
    }
}

public struct SpendingCard: View {
    let summary: SpendingSummary
    public init(summary: SpendingSummary) { self.summary = summary }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spent \(summary.periodLabel)").font(.caption).foregroundStyle(.secondary)
            Text(AmountFormatter.money(summary.total)).font(.title2.bold())
            ForEach(summary.top, id: \.categoryName) { row in
                HStack {
                    Text(row.categoryName).font(.callout)
                    Spacer()
                    Text(AmountFormatter.money(row.amount)).font(.callout.monospacedDigit())
                }
            }
        }
        .padding()
    }
}

public struct BudgetCard: View {
    let report: BudgetReport
    public init(report: BudgetReport) { self.report = report }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(report.statuses, id: \.categoryID) { status in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(status.categoryName).font(.callout)
                        Spacer()
                        Text("\(AmountFormatter.money(status.spent)) / \(AmountFormatter.money(status.budget))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(status.isOver ? .red : .secondary)
                    }
                    ProgressView(value: min((status.spent as NSDecimalNumber).doubleValue, (status.budget as NSDecimalNumber).doubleValue),
                                 total: (status.budget as NSDecimalNumber).doubleValue)
                        .tint(status.isOver ? .red : .accentColor)
                }
            }
            if report.statuses.isEmpty { Text(report.message).font(.callout) }
        }
        .padding()
    }
}

public struct DebtCard: View {
    let overview: DebtOverview
    public init(overview: DebtOverview) { self.overview = overview }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !overview.theyOweMe.isEmpty {
                Text("Owed to you").font(.caption).foregroundStyle(.secondary)
                ForEach(overview.theyOweMe, id: \.friendID) { row in
                    HStack { Text(row.name); Spacer(); Text(AmountFormatter.money(row.amount)).monospacedDigit() }
                        .font(.callout)
                }
            }
            if !overview.iOwe.isEmpty {
                Text("You owe").font(.caption).foregroundStyle(.secondary)
                ForEach(overview.iOwe, id: \.friendID) { row in
                    HStack { Text(row.name); Spacer(); Text(AmountFormatter.money(row.amount)).monospacedDigit() }
                        .font(.callout)
                }
            }
            if overview.theyOweMe.isEmpty && overview.iOwe.isEmpty { Text("No open debts").font(.callout) }
        }
        .padding()
    }
}
