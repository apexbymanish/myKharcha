import SwiftUI
import UIKit
import KharchaKit

struct SettingsView: View {
    @StateObject private var vm: SettingsViewModel
    @State private var showAddCategoryAlert = false
    @State private var exportURL: URL?

    init(store: ExpenseStore) {
        _vm = StateObject(wrappedValue: SettingsViewModel(store: store))
    }

    var body: some View {
        List {
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

            Section("Export") {
                // Button stays visible always — tapping regenerates the file, so
                // re-exporting after new transactions doesn't require anything
                // special from the user.
                Button("Export as CSV") {
                    Task { await vm.makeExport() }
                }
                if let exportURL {
                    ShareLink(item: exportURL, preview: SharePreview("Kharcha Export.csv"))
                }
            }

            if let error = vm.state.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("Settings")
        .textFieldAlert(isPresented: $showAddCategoryAlert, title: "Add Category", placeholder: "Name") { text in
            Task { await vm.addCategory(name: text) }
        }
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
        .onChange(of: vm.state.exportDocument) { _, newValue in
            exportURL = newValue.flatMap { CSVFileWriter.write($0) }
        }
    }
}
