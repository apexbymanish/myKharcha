import SwiftUI
import KharchaKit

/// One installment/loan: status header, payment ledger, and the manage actions
/// (record a payment, pay off & close, close without paying).
struct InstallmentDetailView: View {
    let store: ExpenseStore
    @StateObject private var vm: InstallmentDetailViewModel

    @State private var showRecordSheet = false
    @State private var confirmPayoff = false
    @State private var confirmClose = false

    init(store: ExpenseStore, installmentID: UUID) {
        self.store = store
        _vm = StateObject(wrappedValue: InstallmentDetailViewModel(store: store, installmentID: installmentID))
    }

    var body: some View {
        List {
            if let item = vm.state.installment {
                headerSection(item)
                if item.isActive {
                    actionsSection(item)
                }
                paymentsSection
            }
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle(vm.state.installment?.name ?? "Installment")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .sheet(isPresented: $showRecordSheet) {
            NavigationStack {
                RecordPaymentSheet(suggested: vm.suggestedPayment) { amount, date in
                    Task {
                        await vm.recordPayment(amount: amount, date: date)
                        await NotificationScheduler.shared.resync(store: store)
                    }
                }
            }
        }
    }

    private func headerSection(_ item: InstallmentSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(AmountFormatter.money(item.remainingAmount))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(item.isComplete ? Color.moneyIn : .primary)
                Text(item.isComplete ? "Paid off" : (item.isClosed ? "Closed" : "remaining"))
                    .font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: item.progress).tint(.brandPrimary)
                HStack {
                    Text("\(AmountFormatter.money(item.paidAmount)) of \(AmountFormatter.money(item.paidAmount + item.remainingAmount))")
                    Spacer()
                    if item.isActive {
                        Text("Next: \(InstallmentDateText.short(item.nextDueDate))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("\(item.termCount) monthly payments of \(AmountFormatter.money(item.monthlyAmount)), due on day \(item.dayOfMonth).")
        }
    }

    private func actionsSection(_ item: InstallmentSnapshot) -> some View {
        Section {
            Button {
                showRecordSheet = true
            } label: {
                Label("Record payment", systemImage: "plus.circle.fill")
            }
            Button {
                confirmPayoff = true
            } label: {
                Label("Pay off & close", systemImage: "checkmark.seal")
            }
            .confirmationDialog("Pay off the remaining \(AmountFormatter.money(item.remainingAmount))?", isPresented: $confirmPayoff, titleVisibility: .visible) {
                Button("Pay off \(AmountFormatter.money(item.remainingAmount))") {
                    Task {
                        await vm.payOff()
                        await NotificationScheduler.shared.resync(store: store)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            Button(role: .destructive) {
                confirmClose = true
            } label: {
                Label("Close without paying", systemImage: "xmark.circle")
            }
            .confirmationDialog("Close this plan without recording any more payments?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Close", role: .destructive) {
                    Task {
                        await vm.close()
                        await NotificationScheduler.shared.resync(store: store)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } footer: {
            Text("Recording a payment logs a real expense. \u{201C}Close\u{201D} just stops the plan — it logs nothing.")
        }
    }

    @ViewBuilder private var paymentsSection: some View {
        if !vm.state.payments.isEmpty {
            Section {
                ForEach(vm.state.payments) { p in
                    HStack {
                        Text(AmountFormatter.money(p.amount)).font(.body.monospacedDigit())
                        Spacer()
                        Text(p.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task {
                                await vm.deletePayment(p.id)
                                await NotificationScheduler.shared.resync(store: store)
                            }
                        }
                    }
                }
            } header: {
                Text("Payments")
            } footer: {
                Text("Deleting a payment also removes the expense it created.")
            }
        }
    }
}

/// Sheet to record a payment: amount (pre-filled with this month's installment) + date.
private struct RecordPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let suggested: Decimal
    let onSave: (Decimal, Date) -> Void

    @State private var amountText: String = ""
    @State private var date = Date()
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            if let error {
                InlineError(message: error)
            }
        }
        .navigationTitle("Record Payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let amount = TxnFormViewModel.parsedAmount(amountText) else {
                        error = "Enter a valid amount."
                        return
                    }
                    onSave(amount, date)
                    dismiss()
                }
            }
        }
        .onAppear {
            if amountText.isEmpty, suggested > 0 {
                amountText = NSDecimalNumber(decimal: suggested).stringValue
            }
        }
    }
}
