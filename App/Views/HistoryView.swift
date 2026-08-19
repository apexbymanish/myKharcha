import SwiftUI
import UIKit
import KharchaKit

struct HistoryView: View {
    let store: ExpenseStore
    @StateObject private var vm: HistoryViewModel
    @State private var editingRow: TxnRow?
    @State private var showEditSheet = false

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: HistoryViewModel(store: store))
    }

    var body: some View {
        List {
            ForEach(vm.state.sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.rows, id: \.id) { row in
                        TxnRowView(row: row)
                            .onTapGesture {
                                editingRow = row
                                showEditSheet = true
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    Task { await vm.delete(row.id) }
                                }
                            }
                    }
                }
            }
            if let error = vm.state.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Kind") {
                        Button("All Kinds") { Task { await vm.setKindFilter(nil) } }
                        Button("Expense") { Task { await vm.setKindFilter(.expense) } }
                        Button("Income") { Task { await vm.setKindFilter(.income) } }
                    }
                    Section("Category") {
                        Button("All Categories") { Task { await vm.setCategoryFilter(nil) } }
                        ForEach(vm.state.categories, id: \.id) { category in
                            Button(category.name) { Task { await vm.setCategoryFilter(category.name) } }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            editingRow = nil
            Task { await vm.load() }
        }) {
            NavigationStack {
                TxnFormView(store: store, editing: editingRow)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
    }
}
