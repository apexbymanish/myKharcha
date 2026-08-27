import SwiftUI
import UIKit
import KharchaKit

struct HomeView: View {
    let store: ExpenseStore
    @StateObject private var vm: HomeViewModel
    @EnvironmentObject private var signIn: SignInManager
    @EnvironmentObject private var privacy: PrivacyManager
    @State private var showAddSheet = false
    @State private var showImportSheet = false
    @State private var editingRow: TxnRow?
    @State private var showBackupSheet = false
    @State private var showPlanNav = false
    @State private var showProfileNav = false
    @State private var showRemindersNav = false
    @State private var showHistoryNav = false
    @AppStorage(PayPreference.dayKey, store: PayPreference.defaults) private var paydayDay = 1
    @AppStorage(PayPreference.salaryKey, store: PayPreference.defaults) private var monthlySalary = 0.0
    @AppStorage("plan.savingsRatePercent", store: PayPreference.defaults) private var savingsRate = 20

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: HomeViewModel(store: store))
    }

    private var salaryDecimal: Decimal? { monthlySalary > 0 ? Decimal(monthlySalary) : nil }

    private func reload() async {
        await vm.load(payday: paydayDay, monthlySalary: salaryDecimal, savingsRatePercent: savingsRate)
    }

    private var incomeTitle: String {
        vm.state.monthIncomeIsFromSalary ? "Monthly salary" : "Income this month"
    }

    private func masked(_ amount: String) -> String {
        privacy.isRevealed ? amount : "••••••"
    }

    // MARK: - Greeting

    private var firstName: String? {
        guard let full = signIn.displayName, !full.isEmpty else { return nil }
        let first = full.components(separatedBy: " ").first ?? ""
        return first.isEmpty ? nil : first
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let phrase: String
        switch hour {
        case 5..<12:  phrase = String(localized: "Good morning")
        case 12..<17: phrase = String(localized: "Good afternoon")
        case 17..<21: phrase = String(localized: "Good evening")
        default:      phrase = String(localized: "Good night")
        }
        if let name = firstName { return "\(phrase), \(name)" }
        return phrase
    }

    private var greetingSubline: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return String(localized: "Start the day in control.")
        case 12..<17: return String(localized: "How's spending looking today?")
        case 17..<21: return String(localized: "Good time to log today's expenses.")
        default:      return String(localized: "Rest well — review tomorrow.")
        }
    }

    // MARK: - Next upcoming row

    private func dueLabel(for days: Int) -> String {
        switch days {
        case 0:    return String(localized: "today")
        case 1:    return String(localized: "tomorrow")
        case 2..<14: return "in \(days) days"
        default:
            // Concrete date is clearer than "in N weeks" for anything 2+ weeks out.
            let date = Calendar.current.date(
                byAdding: .day, value: days,
                to: Calendar.current.startOfDay(for: Date())
            ) ?? Date()
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    @ViewBuilder
    private func nextUpcomingRow(_ item: HomeViewModel.State.NextUpcomingItem) -> some View {
        // Auto-pay: never urgent, show calm confirmation. Manual: urgent only if due today.
        let isAuto = item.autoLog
        let isUrgent = item.daysUntil == 0 && !isAuto
        let amountText: String? = item.amount > 0
            ? (privacy.isRevealed ? AmountFormatter.money(item.amount) : "••••••")
            : nil
        let dueLabelText = isAuto && item.daysUntil == 0
            ? String(localized: "auto-logging today")
            : dueLabel(for: item.daysUntil)
        let subtitleText = [amountText, dueLabelText]
            .compactMap { $0 }.joined(separator: " · ")
        let a11yAmount = item.amount > 0
            ? (privacy.isRevealed ? ", \(AmountFormatter.money(item.amount))" : ", amount hidden")
            : ""
        let rowIcon = isAuto ? "bolt.circle" : (isUrgent ? "calendar.badge.exclamationmark" : "calendar")
        let rowColor: Color = isAuto ? .moneyIn : (isUrgent ? .moneyOut : .secondary)
        let titlePrefix = isAuto ? "Auto: " : "Next: "

        HStack(spacing: 12) {
            Image(systemName: rowIcon)
                .font(.callout)
                .foregroundStyle(rowColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(titlePrefix)\(item.name)")
                    .font(.subheadline)
                    .foregroundStyle(isUrgent ? Color.moneyOut : .primary)
                    .lineLimit(1)
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(isUrgent ? Color.moneyOut.opacity(0.8) : .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isAuto ? "Auto-pay" : "Next bill"): \(item.name)\(a11yAmount), \(dueLabelText)")
        .accessibilityHint("Opens Reminders")
    }

    // MARK: - Grouped recent

    private var groupedRecent: [(title: String, rows: [TxnRow])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: vm.state.recent) { row -> String in
            if cal.isDateInToday(row.date) { return String(localized: "Today") }
            if cal.isDateInYesterday(row.date) { return String(localized: "Yesterday") }
            return row.date.formatted(.dateTime.month(.abbreviated).day())
        }
        let sortedKeys = grouped.keys.sorted { a, b in
            (grouped[a]!.first!.date) > (grouped[b]!.first!.date)
        }
        return sortedKeys.map { (title: $0, rows: grouped[$0]!) }
    }

    private var hasLoggedToday: Bool {
        vm.state.recent.contains { Calendar.current.isDateInToday($0.date) }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Greeting
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(greetingText)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(greetingSubline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
            }

            // Balance hero — tappable → History.
            // HIG: primary status first, before any action.
            Section {
                Button { showHistoryNav = true } label: {
                    BalanceHeroCard(
                        spentTitle: "Spent this month",
                        spent: masked(AmountFormatter.money(vm.state.monthSpent)),
                        incomeTitle: LocalizedStringKey(incomeTitle),
                        income: masked(AmountFormatter.money(vm.state.monthIncome))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens transaction history")
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Alerts: budget health + due-soon strip.
            // HIG: surfaced immediately after status so urgent items never hide below actions.
            if !vm.state.budgets.isEmpty || !vm.state.dueSoonItems.isEmpty {
                Section {
                    MonthGlanceCard(budgets: vm.state.budgets, dueSoonItems: vm.state.dueSoonItems)
                }
            }

            // Quiet upcoming hint — next bill when nothing is urgently due.
            if vm.state.dueSoonItems.isEmpty, let item = vm.state.nextUpcomingItem {
                Section {
                    Button { showRemindersNav = true } label: {
                        nextUpcomingRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }

            // (Quick actions moved to sticky safeAreaInset — always visible, no scroll needed)

            if vm.state.weekBars.contains(where: { !$0.isEmpty }) {
                Section("This Week") {
                    MiniTrendChart(bars: vm.state.weekBars)
                }
            }

            Section("Plan") {
                Button { showPlanNav = true } label: {
                    if let plan = vm.state.payPlan {
                        PayCycleCard(plan: plan)
                    } else {
                        PlanSetupNudge()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Monthly Plan")
            }

            if vm.state.breakdown.total > 0 {
                Section("This Month") {
                    SpendingDonutChart(
                        breakdown: vm.state.breakdown,
                        colors: vm.state.categoryColors
                    )
                }
            }

            if !vm.state.budgets.isEmpty {
                Section("Budgets") {
                    ForEach(vm.state.budgets, id: \.categoryID) { status in
                        BudgetBar(status: status)
                    }
                }
            }

            if !vm.state.friendRows.isEmpty {
                Section("Friends") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(vm.state.friendRows, id: \.friendID) { row in
                                FriendDebtChip(row: row)
                            }
                        }
                    }
                }
            }

            // Recent — empty state or date-grouped sections
            if vm.state.recent.isEmpty {
                Section("Recent") {
                    VStack(spacing: 12) {
                        EmptyStateView(
                            icon: "tray",
                            title: "No transactions yet",
                            message: "Log your first expense or income — tap ➕ above."
                        )
                        Button {
                            showAddSheet = true
                        } label: {
                            Text("Add your first transaction")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.brandPrimary.opacity(0.12))
                                .foregroundStyle(Color.brandPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowSeparator(.hidden)
                }
            } else {
                // "Nothing logged today" nudge — shown when there's history but nothing today
                if !hasLoggedToday {
                    Section("Today") {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Nothing logged today — add one?", systemImage: "plus.circle")
                                .font(.subheadline)
                                .foregroundStyle(Color.brandPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Date-grouped rows: Today / Yesterday / "Aug 20" …
                ForEach(groupedRecent, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.rows, id: \.id) { row in
                            Button {
                                editingRow = row
                            } label: {
                                TxnRowView(row: row)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edits this transaction")
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    Task { await vm.deleteTxn(row.id, payday: paydayDay, monthlySalary: salaryDecimal, savingsRatePercent: savingsRate) }
                                }
                            }
                        }
                    }
                }
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Sticky quick actions — always above the tab bar, never scrolls away.
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    Button { showAddSheet = true } label: {
                        QuickActionLabel(icon: "plus", title: "Add")
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    Button { showImportSheet = true } label: {
                        QuickActionLabel(icon: "doc.text.magnifyingglass", title: "Import")
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    Button { showPlanNav = true } label: {
                        QuickActionLabel(icon: "chart.line.uptrend.xyaxis", title: "Plan")
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    if signIn.isSignedIn {
                        Button { showProfileNav = true } label: {
                            QuickActionLabel(
                                icon: "person.crop.circle.fill.badge.checkmark",
                                title: "Synced",
                                tint: .moneyIn
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button { showBackupSheet = true } label: {
                            QuickActionLabel(icon: "icloud.and.arrow.up", title: "Back up")
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(.regularMaterial)
            }
        }
        .navigationTitle("Paisa Khoi?")
        .navigationDestination(isPresented: $showHistoryNav) { HistoryView(store: store) }
        .navigationDestination(isPresented: $showPlanNav) { PlanView(store: store) }
        .navigationDestination(isPresented: $showProfileNav) { ProfileView(store: store) }
        .navigationDestination(isPresented: $showRemindersNav) { RemindersView(store: store) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showImportSheet = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("Import from text")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 20) {
                    Button {
                        privacy.toggle()
                    } label: {
                        Image(systemName: privacy.isRevealed ? "eye" : "eye.slash")
                    }
                    .accessibilityLabel(privacy.isRevealed ? "Hide amounts" : "Show amounts")

                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add transaction")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { Task { await reload() } }) {
            NavigationStack {
                TxnFormView(store: store)
            }
        }
        .sheet(item: $editingRow, onDismiss: {
            Task { await reload() }
        }) { row in
            NavigationStack {
                TxnFormView(store: store, editing: row)
            }
        }
        .sheet(isPresented: $showImportSheet, onDismiss: { Task { await reload() } }) {
            NavigationStack {
                ImportView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showImportSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showBackupSheet) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                BackupPromptCard(signIn: signIn) { showBackupSheet = false }
                    .padding(.top, 12)
                Spacer()
            }
            .padding(.horizontal, 16)
            .presentationDetents([.medium])
            .onChange(of: signIn.isSignedIn) { _, signed in
                if signed { showBackupSheet = false }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: paydayDay) { _, _ in Task { await reload() } }
        .onChange(of: monthlySalary) { _, _ in Task { await reload() } }
        .onChange(of: savingsRate) { _, _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kharchaRemoteDidChange)) { _ in
            Task { await reload() }
        }
    }
}

/// Shown in the Plan section when no salary/payday is configured yet.
private struct PlanSetupNudge: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 40, height: 40)
                .background(Color.brandPrimary.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up your pay cycle")
                    .font(.subheadline.weight(.semibold))
                Text("Add your salary and payday to see daily spend limits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// One Home quick-action tile: tinted icon circle + caption, fills its column equally.
private struct QuickActionLabel: View {
    let icon: String
    let title: LocalizedStringKey
    var tint: Color = .brandPrimary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
