import SwiftUI
import KharchaKit

/// First-run welcome: states the value, then asks the one or two things that make
/// the rest of the app useful (currency + optional monthly salary). Local-first —
/// no account required — and fully skippable. Shown once, gated by `onboardingDone`.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage(CurrencyPreference.defaultsKey,
                store: UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard)
    private var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    @AppStorage(PayPreference.salaryKey, store: PayPreference.defaults) private var monthlySalary = 0.0
    @AppStorage(PayPreference.dayKey, store: PayPreference.defaults) private var paydayDay = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 16) {
                        valueRow(icon: "square.and.pencil", title: "Log in seconds",
                                 detail: "Add expenses and income with a tap — or paste a message and let your iPhone detect them.")
                        valueRow(icon: "chart.line.uptrend.xyaxis", title: "See where it goes",
                                 detail: "Charts, a calendar, budgets, savings and a monthly plan keep you ahead.")
                        valueRow(icon: "lock.shield", title: "Private by default",
                                 detail: "Everything lives on your device. Sign in later only if you want backup and sync.")
                    }

                    setupCard

                    Spacer(minLength: 8)
                }
                .padding(20)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { finish() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    finish()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.heroGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle().fill(Color.brandGradient).frame(width: 64, height: 64)
                Image(systemName: "wallet.bifold")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Text("Welcome to Paisa Khoi?")
                .font(.largeTitle.bold())
            Text("Your calm, private money tracker.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func valueRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up").font(.headline)
            HStack {
                Label("Currency", systemImage: "banknote")
                Spacer()
                Picker("", selection: $currencyCode) {
                    ForEach(CurrencyPreference.options, id: \.self) { code in
                        Text(CurrencyPreference.label(for: code)).tag(code)
                    }
                }
                .labelsHidden()
            }
            Divider()
            HStack {
                Label("Monthly income", systemImage: "calendar")
                Spacer()
                TextField("Optional", value: $monthlySalary, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
            Divider()
            HStack {
                Label("Payday (day of month)", systemImage: "calendar.badge.checkmark")
                Spacer()
                Stepper("\(paydayDay)", value: $paydayDay, in: 1...31)
                    .fixedSize()
            }
            Text("You can change these later in Settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.brandPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func finish() {
        AmountFormatter.currencyCode = currencyCode
        onboardingDone = true
        dismiss()
    }
}
