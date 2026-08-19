import SwiftUI
import KharchaKit

struct SettingsView: View {
    @StateObject private var vm: SettingsViewModel
    @State private var showAddCategoryAlert = false

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
                if let document = vm.state.exportDocument {
                    ShareLink(item: document, preview: SharePreview("Kharcha Export.csv"))
                } else {
                    Button("Export as CSV") {
                        Task { await vm.makeExport() }
                    }
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
    }
}
