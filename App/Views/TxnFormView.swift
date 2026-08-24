import SwiftUI
import KharchaKit

/// Shared add/edit form. Home's ➕ presents it with `editingRow: nil`; History's
/// row tap presents it with the tapped `TxnRow`. The screen leads with the amount
/// (the reason you opened it); "Split into monthly installments" reveals the
/// installment flow via progressive disclosure so the common one-time path stays
/// effortless. The category grid is filtered to the chosen kind.
struct TxnFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var vm: TxnFormViewModel
    let editingRow: TxnRow?

    @FocusState private var amountFocused: Bool

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
            if vm.state.mode == .oneTime {
                oneTimeFields
            } else {
                installmentFields
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .inline : .automatic)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
        }
        .task {
            await vm.load()
            if let editingRow {
                vm.beginEditing(editingRow)
            } else {
                amountFocused = true   // jump straight to the amount for a new entry
            }
        }
        .onChange(of: vm.state.didSave) { _, saved in
            if saved { dismiss() }
        }
    }

    private var navTitle: LocalizedStringKey {
        if editingRow != nil { return "Edit Transaction" }
        return vm.state.mode == .installment ? "New Installment" : "Add Transaction"
    }

    // MARK: One-time

    @ViewBuilder private var oneTimeFields: some View {
        Section {
            // Amount is the hero: large, right-aligned, auto-focused.
            TextField("0", text: amountBinding)
                .keyboardType(.decimalPad)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .focused($amountFocused)
                .padding(.vertical, 4)
            Picker("Kind", selection: kindBinding) {
                Text("Expense").tag(TxnKind.expense)
                Text("Income").tag(TxnKind.income)
            }
            .pickerStyle(.segmented)
        }

        categorySection

        Section {
            DatePicker("Date", selection: dateBinding, displayedComponents: .date)
            TextField("Note", text: noteBinding)
        }

        // Progressive disclosure: the installment path lives one tap away, only
        // when creating (you can't convert an existing transaction).
        if editingRow == nil {
            Section {
                Button {
                    amountFocused = false
                    vm.setMode(.installment)
                } label: {
                    Label("Split into monthly installments", systemImage: "calendar.badge.clock")
                }
            } footer: {
                Text("For a purchase paid over months, or a loan you repay monthly.")
            }
        }
    }

    // MARK: Installment

    @ViewBuilder private var installmentFields: some View {
        Section {
            Button {
                vm.setMode(.oneTime)
            } label: {
                Label("One-time transaction", systemImage: "chevron.left")
                    .font(.callout)
            }
        }

        Section {
            TextField("Name (e.g. iPhone, Car loan)", text: Binding(get: { vm.state.instName }, set: vm.setInstName))
            Picker("Kind", selection: Binding(get: { vm.state.instKind }, set: vm.setInstKind)) {
                Text("Purchase").tag(InstallmentKind.purchase)
                Text("Loan taken").tag(InstallmentKind.loan)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(vm.state.instKind == .loan
                 ? "Money you borrowed and repay monthly."
                 : "Something you're paying off over several months.")
        }

        Section {
            TextField("Total amount", text: Binding(get: { vm.state.instTotalText }, set: vm.setInstTotal))
                .keyboardType(.decimalPad)
            Stepper("Months: \(vm.state.instMonths)", value: Binding(get: { vm.state.instMonths }, set: vm.setInstMonths), in: 1...120)
            HStack {
                Text("Monthly")
                Spacer()
                TextField("0", text: Binding(get: { vm.state.instMonthlyText }, set: vm.setInstMonthly))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
            }
        } footer: {
            Text("The monthly amount is total ÷ months — edit it if your actual payment differs.")
        }

        categorySection

        Section {
            Picker("Due day", selection: Binding(get: { vm.state.instDay }, set: vm.setInstDay)) {
                ForEach(1...31, id: \.self) { day in Text("Day \(day)").tag(day) }
            }
            DatePicker("Starts", selection: dateBinding, displayedComponents: .date)
            Toggle("Auto-record each month", isOn: Binding(get: { vm.state.instAutoLog }, set: vm.setInstAutoLog))
            if vm.state.instKind == .loan {
                Toggle("Record borrowed cash as income", isOn: Binding(get: { vm.state.instAsIncome }, set: vm.setInstAsIncome))
            }
        } footer: {
            Text(vm.state.instAutoLog
                 ? "The monthly payment is logged automatically on the due day."
                 : "You'll record each monthly payment yourself; we'll remind you before it's due.")
        }

        Section {
            TextField("Note", text: noteBinding)
        }
    }

    // MARK: Shared

    // At normal sizes: adaptive columns (min 64pt → 4–5 per row).
    // At AX sizes: exactly 2 columns so long category names like "Entertainment"
    // can wrap to 2 lines without truncating.
    private var categoryGridColumns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 64))]
    }

    @ViewBuilder private var categorySection: some View {
        if !vm.visibleCategories.isEmpty {
            Section("Category") {
                LazyVGrid(columns: categoryGridColumns, spacing: 12) {
                    ForEach(vm.visibleCategories, id: \.id) { category in
                    Button {
                        vm.setCategory(vm.state.categoryID == category.id ? nil : category.id)
                    } label: {
                        CategoryChip(category: category, isSelected: vm.state.categoryID == category.id)
                    }
                    .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
