import SwiftUI
import UIKit
import AuthenticationServices
import KharchaKit

struct SettingsView: View {
    let store: ExpenseStore
    @StateObject private var vm: SettingsViewModel
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var signIn: SignInManager
    @State private var showAddCategoryAlert = false
    @State private var exportURL: URL?
    @State private var backupURL: URL?
    @State private var showImportFilePicker = false
    @State private var pendingImportData: Data?
    @State private var showImportModeDialog = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteFinalConfirm = false
    @State private var showImportResult = false
    @State private var showFileReadError = false
    @AppStorage(CurrencyPreference.defaultsKey,
                store: UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard)
    private var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    @AppStorage(PayPreference.dayKey, store: PayPreference.defaults) private var paydayDay = 1
    @AppStorage(PayPreference.salaryKey, store: PayPreference.defaults) private var monthlySalary = 0.0

    private var currentLanguageName: String {
        let code = Locale.current.language.languageCode?.identifier ?? Locale.current.identifier
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: SettingsViewModel(store: store))
    }

    // MARK: - Sections

    private var accountSection: some View {
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
    }

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(vm.state.categories, id: \.id) { category in
                HStack(spacing: 10) {
                    CategoryIconBadge(symbol: category.symbol, colorHex: category.colorHex, size: 28)
                    Text(category.name)
                }
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
    }

    private var currencySection: some View {
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
            Text("All amounts are shown and totalled in this currency. When you paste text with foreign amounts (e.g. $10), they're converted to it automatically.")
        }
    }

    private var payCycleSection: some View {
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
    }

    private var languageSection: some View {
        Section("Language") {
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settingsURL) {
                    HStack {
                        Label("App Language", systemImage: "globe")
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer()
                        Text(currentLanguageName).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private var importSection: some View {
        Section("Import") {
            NavigationLink {
                ImportView(store: store)
            } label: {
                Label("Import from Text", systemImage: "doc.text.magnifyingglass")
            }
            Button { showImportFilePicker = true } label: {
                Label("Restore from Backup", systemImage: "arrow.down.doc")
            }
        }
    }

    private var exportSection: some View {
        Section("Export") {
            Button { Task { await vm.makeExport() } } label: {
                Label("Export as CSV", systemImage: "tablecells")
            }
            if let exportURL {
                ShareLink(item: exportURL, preview: SharePreview("Kharcha-Export.csv"))
            }
            Button { Task { await vm.makeBackup() } } label: {
                Label("Create Full Backup", systemImage: "square.and.arrow.up")
            }
            if let backupURL {
                ShareLink(item: backupURL, preview: SharePreview("Kharcha-Backup.json"))
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Erase All Data", systemImage: "trash")
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Permanently deletes all transactions, friends, debts, savings, and installments. Categories are reset to defaults. This cannot be undone.")
        }
    }

    private var shareSection: some View {
        Section {
            ShareLink(
                item: URL(string: "https://jebkharcha.dnmc.app/kharcha")!,
                subject: Text("Try Kharcha — free expense tracker"),
                message: Text("I track my expenses with Kharcha. It's free!")
            ) {
                Label("Share Kharcha", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Share")
        } footer: {
            Text("Invite friends and family to try Kharcha.")
        }
    }

    // MARK: - Import result message

    private var importResultMessage: String {
        guard let count = vm.state.importedCount else { return "" }
        if vm.state.importWasReplace {
            return count == 0
                ? "Previous data was erased. The backup was empty — no records were restored."
                : "Previous data erased. \(count) records restored from the backup."
        } else {
            return count == 0
                ? "Everything is already up to date — no new records found in this backup."
                : "\(count) new records added from the backup."
        }
    }

    // MARK: - Body

    private var settingsList: some View {
        List {
            accountSection
            categoriesSection
            currencySection
            payCycleSection
            languageSection
            importSection
            exportSection
            dangerSection
            shareSection
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .disabled(vm.state.isWorking)
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
        .onChange(of: vm.state.backupData) { _, newValue in
            backupURL = newValue.flatMap { BackupFileWriter.write($0) }
        }
        .onChange(of: vm.state.importedCount) { _, count in
            if count != nil { showImportResult = true }
        }
        .fileImporter(isPresented: $showImportFilePicker, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                showFileReadError = true
                return
            }
            // Pre-validate before showing the mode dialog — catches corrupt files
            // before the user even sees the Replace/Merge choice.
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard (try? decoder.decode(KharchaBackup.self, from: data)) != nil else {
                showFileReadError = true
                return
            }
            pendingImportData = data
            showImportModeDialog = true
        }
        .confirmationDialog("Import Backup", isPresented: $showImportModeDialog, titleVisibility: .visible) {
            Button("Erase & Replace", role: .destructive) {
                guard let data = pendingImportData else { return }
                pendingImportData = nil
                Task {
                    await vm.replaceAndImportBackup(data: data)
                    services.sync.pushNow()
                }
            }
            Button("Keep & Merge") {
                guard let data = pendingImportData else { return }
                pendingImportData = nil
                Task { await vm.mergeBackup(data: data) }
            }
            Button("Cancel", role: .cancel) { pendingImportData = nil }
        } message: {
            Text("Erase & Replace deletes all your current data, then restores from this backup. Keep & Merge only adds records not already on this device. Erase & Replace cannot be undone.")
        }
        .alert("Backup Restored", isPresented: $showImportResult) {
            Button("OK") { vm.clearImportResult() }
        } message: {
            Text(importResultMessage)
        }
        .alert("Invalid Backup File", isPresented: $showFileReadError) {
            Button("OK") {}
        } message: {
            Text("This file isn't a valid Kharcha backup. Make sure you're selecting a file exported from Kharcha.")
        }
    }

    var body: some View {
        settingsList
            .confirmationDialog("Erase All Data?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Erase All Data", role: .destructive) { showDeleteFinalConfirm = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all your transactions, friends, debts, savings, and installments. Categories are reset to defaults.")
            }
            .confirmationDialog("Erase All Data", isPresented: $showDeleteFinalConfirm, titleVisibility: .visible) {
                Button("Erase Permanently", role: .destructive) {
                    Task {
                        await vm.deleteAllData()
                        // Push tombstones immediately so deleted data doesn't
                        // resurrect from Firestore on the next pull.
                        services.sync.pushNow()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your financial history cannot be recovered once erased. Consider creating a backup first.")
            }
    }
}
