import SwiftUI
import KharchaKit

/// Tab root: Home / History / Friends / More. "More" is a List pushing
/// Budgets, Reminders, Settings (Task 9 brief §Interfaces). `AppServices` is
/// read once here (the only place a plain `@EnvironmentObject` is used) and
/// its `store` is threaded explicitly into each screen's initializer — leaf
/// screens never touch `AppServices` or the store directly, only their own
/// ViewModel (see task-9-report.md, "adaptations").
struct RootView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var signIn: SignInManager
    @EnvironmentObject private var updateChecker: AppUpdateChecker
    @EnvironmentObject private var privacy: PrivacyManager
    @ObservedObject private var navigator = AppNavigator.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage(PayPreference.dayKey, store: PayPreference.defaults) private var paydayDay = 1
    @AppStorage(PayPreference.salaryKey, store: PayPreference.defaults) private var monthlySalary = 0.0
    @State private var showOptionalUpdateAlert = false

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(store: services.store)
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                HistoryView(store: services.store)
            }
            .tabItem { Label("History", systemImage: "list.bullet") }

            NavigationStack {
                FriendsView(store: services.store)
            }
            .tabItem { Label("Friends", systemImage: "person.2") }

            NavigationStack {
                MoreView(store: services.store)
            }
            .tabItem { Label("More", systemImage: "ellipsis") }
        }
        // Single brand accent across every screen (HIG: one consistent tint for
        // interactivity), coordinated with the app logo.
        .tint(.brandPrimary)
        // Presented from OpenAddExpenseIntent (Spotlight/Siri "Add Expense"),
        // the Home Screen widget (jebkharcha://add), or the Control Center control
        // — independent of whichever tab is active.
        .sheet(isPresented: $navigator.showAddExpense) {
            NavigationStack {
                TxnFormView(store: services.store)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { onboardingDone = !$0 })) {
            OnboardingView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { if case .mandatory = updateChecker.kind { return true }; return false },
            set: { _ in }
        )) {
            if case .mandatory(let msg) = updateChecker.kind {
                MandatoryUpdateView(message: msg) { updateChecker.openAppStore() }
            }
        }
        .alert("Update Available", isPresented: $showOptionalUpdateAlert) {
            Button("Update") { updateChecker.openAppStore() }
            Button("Not Now", role: .cancel) {}
        } message: {
            if case .optional(let msg) = updateChecker.kind { Text(msg) }
        }
        .onOpenURL { navigator.handle(url: $0) }
        // Start live sync if already signed in at launch, and react to sign-in/out.
        .task {
            if let uid = signIn.firebaseUID { services.sync.start(uid: uid) }
            await updateChecker.check()
            if case .optional = updateChecker.kind { showOptionalUpdateAlert = true }
        }
        .onChange(of: signIn.firebaseUID) { _, uid in
            if let uid { services.sync.start(uid: uid) } else { services.sync.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                navigator.consumePendingAddExpense()
                // Catch up any recurring rules or installments that became due
                // while the app was in the background. Idempotent — the watermark
                // prevents re-inserting already-logged occurrences.
                Task {
                    try? await AutoLogRunner.run(
                        store: services.store,
                        watermark: DefaultsWatermark(),
                        now: Date(),
                        calendar: .current
                    )
                    await NotificationScheduler.shared.resync(store: services.store)
                    if monthlySalary > 0 {
                        await NotificationScheduler.shared.schedulePaydayNudge(paydayDay: paydayDay)
                    }
                }
            } else {
                if phase == .background { privacy.lock() }
                // Leaving the foreground → flush local changes to the cloud.
                services.sync.pushNow()
            }
        }
    }
}

private struct MoreView: View {
    let store: ExpenseStore

    var body: some View {
        List {
            Section("Planning") {
                NavigationLink { PlanView(store: store) } label: {
                    MoreRow(icon: "chart.line.uptrend.xyaxis", tint: .brandPrimary,
                            title: "Monthly Plan", subtitle: "Forecast this month's income and spending")
                }
                NavigationLink { BudgetsView(store: store) } label: {
                    MoreRow(icon: "chart.pie", tint: .brandPrimary,
                            title: "Budgets", subtitle: "Set spending limits per category")
                }
                NavigationLink { SavingsView(store: store) } label: {
                    MoreRow(icon: "banknote", tint: .brandPrimary,
                            title: "Savings", subtitle: "Pots, goals, and where to keep money")
                }
                NavigationLink { InstallmentsView(store: store) } label: {
                    MoreRow(icon: "creditcard", tint: .brandPrimary,
                            title: "Installments & Loans", subtitle: "Track what you pay off over months")
                }
                NavigationLink { RemindersView(store: store) } label: {
                    MoreRow(icon: "bell", tint: .brandPrimary,
                            title: "Reminders", subtitle: "Get alerts before bills are due")
                }
            }
            Section("Account") {
                NavigationLink { SettingsView(store: store) } label: {
                    MoreRow(icon: "gearshape", tint: .secondary,
                            title: "Settings", subtitle: "Currency, language, backup, export")
                }
            }
        }
        .navigationTitle("More")
    }
}

/// A More-list row: tinted SF icon + title + one-line description (Settings-style),
/// so each planning tool explains itself at a glance.
private struct MoreRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
