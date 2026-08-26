import SwiftUI
import KharchaKit
import UserNotifications

/// Monthly Plan: enter (or paste) your income, and the app evaluates the month —
/// commitments, subscriptions, recommended savings, safe-to-spend, a suggested
/// target income, where to put the savings, and what's due soon. Every figure is
/// computed by the tested engine; Apple Intelligence only rephrases the summary
/// and can schedule a plain-language pre-alert on payday.
struct PlanView: View {
    let store: ExpenseStore
    @StateObject private var vm: MonthlyPlanViewModel

    @AppStorage(PayPreference.dayKey, store: PayPreference.defaults) private var paydayDay = 1
    @AppStorage(PayPreference.salaryKey, store: PayPreference.defaults) private var monthlySalary = 0.0
    @AppStorage("plan.savingsRatePercent", store: PayPreference.defaults) private var savingsRate = 20

    @State private var incomeText = ""
    @State private var pasteText = ""
    @State private var showPaste = false
    @State private var alertScheduled = false
    @FocusState private var pasteFocused: Bool

    @AppStorage(CurrencyPreference.defaultsKey, store: PayPreference.defaults)
    private var currencyCode = AmountFormatter.currencyCode

    private var currencySymbol: String {
        Locale(identifier: "en_US@currency=\(currencyCode)").currencySymbol ?? currencyCode
    }

    private func formatAmountText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let stripped = text.replacingOccurrences(of: ",", with: "")
        let endsWithDot = stripped.hasSuffix(".")
        let parts = stripped.components(separatedBy: ".")
        let intStr = parts[0]
        let fracStr = parts.count > 1 ? parts[1] : nil
        guard !intStr.isEmpty, let intVal = Int64(intStr) else { return text }
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "en_US")
        nf.numberStyle = .decimal
        let formatted = nf.string(from: NSNumber(value: intVal)) ?? intStr
        if let frac = fracStr { return formatted + "." + frac }
        if endsWithDot { return formatted + "." }
        return formatted
    }

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: MonthlyPlanViewModel(store: store, rates: FrankfurterRateService()))
    }

    var body: some View {
        List {
            incomeSection
            if let plan = vm.state.plan {
                summarySection(plan)
                adviceSection
                if plan.targetIncomeExceedsIncome { targetIncomeSection(plan) }
                if !plan.upcoming.isEmpty { upcomingSection(plan) }
                if let allocation = vm.state.allocation { allocationSection(allocation) }
                alertSection
            }
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Monthly Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { clearAll() }
                    .disabled(pasteText.isEmpty && !vm.state.adviceFromModel)
            }
        }
        .task {
            await vm.load(income: Decimal(monthlySalary), savingsRatePercent: savingsRate)
            if monthlySalary > 0 {
                incomeText = formatAmountText((Decimal(monthlySalary) as NSDecimalNumber).stringValue)
            }
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            alertScheduled = pending.contains(where: { $0.identifier == "kharcha.plan.summary" })
        }
        .onChange(of: savingsRate) { _, newValue in
            vm.setSavingsRate(newValue)
        }
    }

    /// Reset the screen: drop any pasted text, dismiss the keyboard, and reload the
    /// plan from the Settings salary (which also reverts an AI-reworded summary to
    /// the exact engine text).
    private func clearAll() {
        let rawSalary = monthlySalary > 0 ? (Decimal(monthlySalary) as NSDecimalNumber).stringValue : ""
        incomeText = rawSalary.isEmpty ? "" : formatAmountText(rawSalary)
        pasteText = ""
        showPaste = false
        pasteFocused = false
        alertScheduled = false
        Task { await vm.load(income: Decimal(monthlySalary), savingsRatePercent: savingsRate) }
    }

    // MARK: Income

    private var incomeSection: some View {
        Section {
            HStack {
                Label("Monthly income", systemImage: "banknote")
                Spacer()
                HStack(spacing: 4) {
                    Text(currencySymbol)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    TextField("0", text: $incomeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130)
                }
                .onChange(of: incomeText) {
                    // First pass: reformat with grouping separators.
                    // Return early so the second onChange (with the already-formatted
                    // string) does the actual parse — avoids double-writing storage.
                    let formatted = formatAmountText(incomeText)
                    if formatted != incomeText { incomeText = formatted; return }
                    let raw = incomeText.replacingOccurrences(of: ",", with: "")
                    let parsed = Decimal(string: raw) ?? 0
                    vm.setIncome(parsed)
                    monthlySalary = (parsed as NSDecimalNumber).doubleValue
                }
            }
            Picker(selection: $savingsRate) {
                ForEach([5, 10, 15, 20, 25, 30, 40, 50, 80], id: \.self) { pct in
                    Text("\(pct)%").tag(pct)
                }
            } label: {
                Label("Save", systemImage: "arrow.down.to.line")
            }

            DisclosureGroup(isExpanded: $showPaste) {
                TextField("Paste payslip or bank message…", text: $pasteText, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($pasteFocused)
                Button {
                    pasteFocused = false
                    Task { await vm.parseIncome(pasteText) }
                } label: {
                    if vm.state.isParsingIncome {
                        HStack { ProgressView(); Text("Detecting…") }
                    } else {
                        Label("Detect income", systemImage: "sparkles")
                    }
                }
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.state.isParsingIncome)
                Button(role: .destructive) {
                    pasteText = ""
                    pasteFocused = false
                } label: {
                    Label("Clear pasted text", systemImage: "xmark.circle")
                }
                .disabled(pasteText.isEmpty)
            } label: {
                Label("Paste income from text", systemImage: "doc.text.magnifyingglass")
            }
        } header: {
            Text("Income")
        } footer: {
            Text("Enter what you earn each month. You can also paste a payslip or bank message and the app will read the amount — even in another currency.")
        }
    }

    // MARK: Summary

    private func summarySection(_ plan: MonthlyPlan) -> some View {
        Section {
            if plan.isOverCommitted {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.moneyOut)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bills exceed income by \(AmountFormatter.money(plan.shortfall))")
                            .font(.subheadline.weight(.semibold))
                        Text("Cut a recurring bill or raise your income to get back on track.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            planNavRow("Fixed monthly bills", AmountFormatter.money(plan.commitmentsTotal), "list.bullet.rectangle") {
                RemindersView(store: store)
            }
            if plan.subscriptionsTotal > 0 {
                planRow("Subscriptions", AmountFormatter.money(plan.subscriptionsTotal), "arrow.triangle.2.circlepath", secondary: true)
            }
            planNavRow("Put aside for savings", AmountFormatter.money(plan.recommendedSavings), "arrow.down.to.line", tint: .moneyIn) {
                SavingsView(store: store)
            }
            planNavRow("Left to spend freely", AmountFormatter.money(plan.safeToSpend), "checkmark.seal",
                    tint: plan.safeToSpend < 0 ? .moneyOut : .moneyIn, bold: true) {
                BudgetsView(store: store)
            }
        } header: {
            Text("Your plan")
        } footer: {
            Text("Fixed bills are read from your Recurring Reminders and Installments. Add or edit them there.")
        }
    }

    private func planRow(_ title: LocalizedStringKey, _ value: String, _ icon: String, tint: Color? = nil, bold: Bool = false, secondary: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint ?? .primary))
                .font(secondary ? .callout : .body)
            Spacer()
            Text(value)
                .font(bold ? .body.monospacedDigit().weight(.semibold) : (secondary ? .callout.monospacedDigit() : .body.monospacedDigit()))
                .foregroundStyle(secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint ?? .primary))
        }
        .padding(.leading, secondary ? 20 : 0)
    }

    private func planNavRow<D: View>(_ title: LocalizedStringKey, _ value: String, _ icon: String, tint: Color? = nil, bold: Bool = false, @ViewBuilder destination: () -> D) -> some View {
        NavigationLink(destination: destination()) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(AnyShapeStyle(tint ?? .primary))
                    .font(.body)
                Spacer()
                Text(value)
                    .font(bold ? .body.monospacedDigit().weight(.semibold) : .body.monospacedDigit())
                    .foregroundStyle(AnyShapeStyle(tint ?? .primary))
            }
        }
    }

    // MARK: Advice (Apple Intelligence)

    @ViewBuilder private var adviceSection: some View {
        if let advice = vm.state.advice {
            Section {
                Text(advice)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if PlanAdvisor.isAvailable && !vm.state.adviceFromModel {
                    Button {
                        Task { await vm.generateAIAdvice() }
                    } label: {
                        Label("Rephrase with Apple Intelligence", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("Summary")
            } footer: {
                if vm.state.adviceFromModel {
                    Text("Reworded on-device with Apple Intelligence. The numbers are computed exactly by the app.")
                }
            }
        }
    }

    // MARK: Target income

    private func targetIncomeSection(_ plan: MonthlyPlan) -> some View {
        Section {
            HStack {
                Label("Suggested target income", systemImage: "target")
                Spacer()
                Text(AmountFormatter.money(plan.suggestedTargetIncome))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
        } footer: {
            Text("To cover all your bills, usual spending, and still save \(savingsRate)% — you'd need to earn at least this much per month.")
        }
    }

    // MARK: Upcoming (pre-alerts)

    private func upcomingSection(_ plan: MonthlyPlan) -> some View {
        Section {
            ForEach(plan.upcoming, id: \.name) { c in
                HStack {
                    Label(c.name, systemImage: c.isSubscription ? "arrow.triangle.2.circlepath" : "calendar")
                    Spacer()
                    Text(AmountFormatter.money(c.amount)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Due soon")
        } footer: {
            Text("These are the commitments due within the next week.")
        }
    }

    // MARK: Where to save

    private func allocationSection(_ allocation: SavingsAllocation) -> some View {
        Section {
            ForEach(allocation.lines, id: \.name) { line in
                HStack {
                    Text(line.name)
                    Spacer()
                    Text(AmountFormatter.money(line.reserved)).font(.body.monospacedDigit())
                    if line.shortfall > 0 {
                        Text("short \(AmountFormatter.money(line.shortfall))")
                            .font(.caption2).foregroundStyle(Color.moneyOut)
                    }
                }
            }
            if allocation.free > 0 {
                HStack {
                    Text("Free savings").foregroundStyle(.secondary)
                    Spacer()
                    Text(AmountFormatter.money(allocation.free)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Where to save")
        } footer: {
            Text("How to split your recommended savings across your goals, highest priority first.")
        }
    }

    // MARK: Pre-alert scheduling

    @ViewBuilder private var alertSection: some View {
        if let plan = vm.state.plan {
            Section {
                Button {
                    let body = plan.summaryText()
                    Task {
                        await NotificationScheduler.shared.schedulePlanSummary(body: body, paydayDay: paydayDay)
                        alertScheduled = true
                    }
                } label: {
                    Label(alertScheduled ? "Pre-alert scheduled for payday" : "Remind me on payday", systemImage: alertScheduled ? "checkmark.circle.fill" : "bell.badge")
                        .foregroundStyle(alertScheduled ? Color.moneyIn : Color.brandPrimary)
                }
                .disabled(alertScheduled)
            } footer: {
                Text("Get this plan as a notification on your next payday. Bills you've set up as reminders already alert you before they're due.")
            }
        }
    }
}
