import SwiftUI
import KharchaKit

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

    @State private var pasteText = ""
    @State private var showPaste = false
    @State private var alertScheduled = false
    @FocusState private var focusedField: Field?

    /// The text inputs that raise the keyboard, so a toolbar "Done" can dismiss it.
    private enum Field { case income, paste }

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: MonthlyPlanViewModel(store: store, rates: FrankfurterRateService()))
    }

    // Optional-Double binding so an income of 0 shows an empty field (placeholder
    // "0") rather than a literal "0" that new digits append to — typing 3000000
    // into a "0" field otherwise reads as 30000000.
    private var incomeBinding: Binding<Double?> {
        Binding(
            get: { vm.state.income == 0 ? nil : NSDecimalNumber(decimal: vm.state.income).doubleValue },
            set: { vm.setIncome(Decimal($0 ?? 0)) }
        )
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
        .navigationTitle("Monthly Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { clearAll() }
                    .disabled(pasteText.isEmpty && !vm.state.adviceFromModel)
            }
            // decimalPad has no return key, so give the keyboard an explicit Done.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .task {
            await vm.load(income: Decimal(monthlySalary), savingsRatePercent: savingsRate)
        }
        .onChange(of: savingsRate) { _, newValue in
            vm.setSavingsRate(newValue)
        }
    }

    /// Reset the screen: drop any pasted text, dismiss the keyboard, and reload the
    /// plan from the Settings salary (which also reverts an AI-reworded summary to
    /// the exact engine text).
    private func clearAll() {
        pasteText = ""
        showPaste = false
        focusedField = nil
        alertScheduled = false
        Task { await vm.load(income: Decimal(monthlySalary), savingsRatePercent: savingsRate) }
    }

    // MARK: Income

    private var incomeSection: some View {
        Section {
            HStack {
                Label("Monthly income", systemImage: "banknote")
                Spacer()
                TextField("0", value: incomeBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
                    .focused($focusedField, equals: .income)
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
                    .focused($focusedField, equals: .paste)
                Button {
                    focusedField = nil
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
                    focusedField = nil
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
            Text("Pre-filled from your salary in Settings. Paste a payslip or message to detect it automatically — foreign amounts are converted to your currency.")
        }
    }

    // MARK: Summary

    private func summarySection(_ plan: MonthlyPlan) -> some View {
        Section {
            if plan.isOverCommitted {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.moneyOut)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Over-committed by \(AmountFormatter.money(plan.shortfall))")
                            .font(.subheadline.weight(.semibold))
                        Text("Your commitments exceed your income.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            planRow("Commitments", AmountFormatter.money(plan.commitmentsTotal), "list.bullet.rectangle")
            if plan.subscriptionsTotal > 0 {
                planRow("of which subscriptions", AmountFormatter.money(plan.subscriptionsTotal), "arrow.triangle.2.circlepath")
            }
            planRow("Recommended savings", AmountFormatter.money(plan.recommendedSavings), "arrow.down.to.line", tint: .moneyIn)
            planRow("Safe to spend", AmountFormatter.money(plan.safeToSpend), "checkmark.seal",
                    tint: plan.safeToSpend < 0 ? .moneyOut : .moneyIn, bold: true)
        } header: {
            Text("This month")
        }
    }

    private func planRow(_ title: LocalizedStringKey, _ value: String, _ icon: String, tint: Color? = nil, bold: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(tint == nil ? .primary : tint!)
            Spacer()
            Text(value)
                .font(bold ? .body.monospacedDigit().weight(.semibold) : .body.monospacedDigit())
                .foregroundStyle(tint == nil ? .primary : tint!)
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
            Text("To cover your commitments and usual spending while still saving \(savingsRate)%, aim to earn about this per month.")
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
