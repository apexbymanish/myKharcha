import SwiftUI
import UIKit
import AuthenticationServices
import KharchaKit

struct SettingsView: View {
    let store: ExpenseStore
    @StateObject private var vm: SettingsViewModel
    @EnvironmentObject private var signIn: SignInManager
    @State private var showAddCategoryAlert = false
    @State private var exportURL: URL?
    @State private var testNotifSent = false
    @AppStorage(CurrencyPreference.defaultsKey,
                store: UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard)
    private var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    @AppStorage(PayPreference.dayKey, store: PayPreference.defaults) private var paydayDay = 1
    @AppStorage(PayPreference.salaryKey, store: PayPreference.defaults) private var monthlySalary = 0.0

    /// The app's currently-resolved display language, shown next to the Language row.
    private var currentLanguageName: String {
        let code = Locale.current.language.languageCode?.identifier ?? Locale.current.identifier
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: SettingsViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                if signIn.isSignedIn {
                    NavigationLink {
                        ProfileView(store: store)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.brandGradient).frame(width: 32, height: 32)
                                Image(systemName: "person.fill").font(.caption).foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(signIn.displayName ?? "Profile")
                                Text("Signed in with Apple")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        signIn.configure(request)
                    } onCompletion: { result in
                        signIn.handle(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            } header: {
                Text("Account")
            } footer: {
                Text(signIn.isSignedIn
                     ? "Your expenses are backed up and synced across your devices."
                     : "Your data is saved on this device only. Sign in with Apple to back it up and sync it across your devices.")
            }

            Section("Categories") {
                ForEach(vm.state.categories, id: \.id) { category in
                    Label(category.name, systemImage: category.symbol)
                        .swipeActions {
                            if !category.isFallback {
                                Button("Delete", role: .destructive) {
                                    Task { await vm.deleteCategory(category.id) }
                                }
                            }
                        }
                }
                Button {
                    showAddCategoryAlert = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
            }

            Section {
                Picker(selection: $currencyCode) {
                    ForEach(CurrencyPreference.options, id: \.self) { code in
                        Text(CurrencyPreference.label(for: code)).tag(code)
                    }
                } label: {
                    Label("Currency", systemImage: "banknote")
                }
                .onChange(of: currencyCode) { _, newValue in
                    AmountFormatter.currencyCode = newValue
                    Task { await vm.load() }
                }
            } header: {
                Text("Currency")
            } footer: {
                Text("All amounts are shown and totalled in this currency. When you paste text with foreign amounts (e.g. $10), they’re converted to it automatically.")
            }

            Section {
                Picker("Payday", selection: $paydayDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("Day \(day)").tag(day)
                    }
                }
                TextField("Monthly salary", value: $monthlySalary, format: .number)
                    .keyboardType(.decimalPad)
            } header: {
                Text("Pay Cycle")
            } footer: {
                Text("Set your payday and monthly salary to see days until payday and a safe daily spend on Home. Leave salary at 0 to hide it.")
            }

            Section {
                Button {
                    testNotifSent = false
                    Task {
                        await NotificationScheduler.shared.fireTestNow()
                        testNotifSent = true
                    }
                } label: {
                    Label(testNotifSent ? "Scheduled — background the app!" : "Send Test Notification",
                          systemImage: testNotifSent ? "checkmark.circle.fill" : "bell.badge")
                        .foregroundStyle(testNotifSent ? Color.moneyIn : Color.brandPrimary)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Fires a test notification in 5 seconds. Background the app after tapping to see it.")
            }

            Section("Language") {
                // The app follows the system language automatically. iOS exposes a
                // per-app Language screen (because the app is localized); deep-link
                // there rather than overriding AppleLanguages, which needs a relaunch.
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settingsURL) {
                        HStack {
                            Label("App Language", systemImage: "globe")
                            Spacer()
                            Text(currentLanguageName).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Import") {
                NavigationLink {
                    ImportView(store: store)
                } label: {
                    Label("Import from Text", systemImage: "doc.text.magnifyingglass")
                }
            }

            Section("Export") {
                // Button stays visible always — tapping regenerates the file, so
                // re-exporting after new transactions doesn't require anything
                // special from the user.
                Button {
                    Task { await vm.makeExport() }
                } label: {
                    Label("Export as CSV", systemImage: "square.and.arrow.up")
                }
                if let exportURL {
                    ShareLink(item: exportURL, preview: SharePreview("Jeb Kharcha Export.csv"))
                }
            }

            Section {
                ShareLink(
                    item: URL(string: "https://jebkharcha-7e514.web.app/kharcha")!,
                    subject: Text("Try Kharcha — free spending tracker"),
                    message: Text("I track my spending with Kharcha. It's free!")
                ) {
                    Label("Share Kharcha", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Share")
            } footer: {
                Text("Invite friends and family to try Kharcha.")
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("Settings")
        .textFieldAlert(isPresented: $showAddCategoryAlert, title: "Add Category", placeholder: "Name") { text in
            Task { await vm.addCategory(name: text) }
        }
        .task { await vm.load() }
        .onAppear { signIn.refreshCredentialState() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
        .onChange(of: vm.state.exportDocument) { _, newValue in
            exportURL = newValue.flatMap { CSVFileWriter.write($0) }
        }
    }
}
