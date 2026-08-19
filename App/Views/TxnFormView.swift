import SwiftUI
import KharchaKit

/// Shared add/edit form. Home's ➕ presents it with `editingRow: nil`; History's
/// row tap presents it with the tapped `TxnRow` (TxnFormViewModel.beginEditing
/// maps the row back onto editable state).
struct TxnFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: TxnFormViewModel
    let editingRow: TxnRow?

    init(store: ExpenseStore, editing row: TxnRow? = nil) {
        _vm = StateObject(wrappedValue: TxnFormViewModel(store: store))
        self.editingRow = row
    }

    private var amountBinding: Binding<String> {
        Binding(get: { vm.state.amountText }, set: vm.setAmountText)
    }
    private var kindBinding: Binding<TxnKind> {
        Binding(get: { vm.state.kind }, set: vm.setKind)
    }
    private var noteBinding: Binding<String> {
        Binding(get: { vm.state.note }, set: vm.setNote)
    }
    private var dateBinding: Binding<Date> {
        Binding(get: { vm.state.date }, set: vm.setDate)
    }

    var body: some View {
        Form {
            Section {
                TextField("Amount", text: amountBinding)
                    .keyboardType(.decimalPad)
                Picker("Kind", selection: kindBinding) {
                    Text("Expense").tag(TxnKind.expense)
                    Text("Income").tag(TxnKind.income)
                }
                .pickerStyle(.segmented)
            }

            Section("Category") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                    ForEach(vm.state.categories, id: \.id) { category in
                        Button {
                            vm.setCategory(category.id)
                        } label: {
                            CategoryChip(category: category, isSelected: vm.state.categoryID == category.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                TextField("Note", text: noteBinding)
            }

            if let error = vm.state.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle(editingRow == nil ? "Add Transaction" : "Edit Transaction")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
            }
        }
        .task {
            await vm.load()
            if let editingRow {
                vm.beginEditing(editingRow)
            }
        }
        .onChange(of: vm.state.didSave) { _, saved in
            if saved { dismiss() }
        }
    }
}
