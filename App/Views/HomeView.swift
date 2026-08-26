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
    @State private var showEditSheet = false
    @State private var showBackupSheet = false
    @State private var showPlanNav = false
    @State private var showProfileNav = false
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
            // Balance hero
            Section {
                BalanceHeroCard(
                    spentTitle: "Spent this month",
                    spent: masked(AmountFormatter.money(vm.state.monthSpent)),
                    incomeTitle: LocalizedStringKey(incomeTitle),
                    income: masked(AmountFormatter.money(vm.state.monthIncome))
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Quick actions — 4 fixed tiles, no horizontal scroll.
            // Each Button carries .frame(maxWidth: .infinity) so the HStack distributes
            // width equally even across the if/else conditional fourth tile.
            Section {
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
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Quick actions")
            }

            // Month at a glance — budget health + due-soon strip
            if !vm.state.budgets.isEmpty || !vm.state.dueSoonItems.isEmpty {
                Section {
                    MonthGlanceCard(budgets: vm.state.budgets, dueSoonItems: vm.state.dueSoonItems)
                }
            }

            if vm.state.weekBars.contains(where: { !$0.isEmpty }) {
                Section("This Week") {
                    MiniTrendChart(bars: vm.state.weekBars)
                }
            }

            if let plan = vm.state.payPlan {
                Section("Plan") {
                    Button { showPlanNav = true } label: {
                        PayCycleCard(plan: plan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Monthly Plan")
                }
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
                                showEditSheet = true
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
        .navigationTitle("Jeb Kharcha")
        .navigationDestination(isPresented: $showPlanNav) { PlanView(store: store) }
        .navigationDestination(isPresented: $showProfileNav) { ProfileView(store: store) }
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
                Button {
                    privacy.toggle()
                } label: {
                    Image(systemName: privacy.isRevealed ? "eye" : "eye.slash")
                }
                .accessibilityLabel(privacy.isRevealed ? "Hide amounts" : "Show amounts")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add transaction")
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { Task { await reload() } }) {
            NavigationStack {
                TxnFormView(store: store)
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            editingRow = nil
            Task { await reload() }
        }) {
            NavigationStack {
                TxnFormView(store: store, editing: editingRow)
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
