import SwiftUI
import UIKit
import KharchaKit

struct FriendDetailView: View {
    let store: ExpenseStore
    @StateObject private var vm: FriendDetailViewModel
    @State private var showAddDebtSheet = false
    @State private var addDebtDirection: DebtDirection = .iGave
    @State private var showSettleAlert = false
    @State private var showClearConfirm = false

    init(store: ExpenseStore, friendID: UUID, friendName: String) {
        self.store = store
        _vm = StateObject(wrappedValue: FriendDetailViewModel(store: store, friendID: friendID, friendName: friendName))
    }

    private var netPhrase: String {
        if vm.state.net > 0 { return String(localized: "\(vm.state.friendName) owes you \(AmountFormatter.money(vm.state.net))") }
        if vm.state.net < 0 { return String(localized: "You owe \(vm.state.friendName) \(AmountFormatter.money(abs(vm.state.net)))") }
        return String(localized: "Settled up")
    }

    var body: some View {
        List {
            Section {
                Text(netPhrase).font(.title3.bold())

                // Running totals of what's still open, by direction.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You gave").font(.caption).foregroundStyle(.secondary)
                        Text(AmountFormatter.money(vm.state.totalGiven))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Color.moneyIn)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("You took").font(.caption).foregroundStyle(.secondary)
                        Text(AmountFormatter.money(vm.state.totalTaken))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Color.moneyOut)
                    }
                }
                .accessibilityElement(children: .combine)

                HStack {
                    Button("I gave") {
                        addDebtDirection = .iGave
                        showAddDebtSheet = true
                    }
                    .buttonStyle(.bordered)

                    Button("I took") {
                        addDebtDirection = .iTook
                        showAddDebtSheet = true
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                if vm.state.net != 0 {
                    HStack {
                        Button("Settle up") { showSettleAlert = true }
                            .buttonStyle(.bordered)
                        Button("Clear All", role: .destructive) { showClearConfirm = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("History") {
                if vm.state.debts.isEmpty {
                    Text("No debts yet").foregroundStyle(.secondary)
                }
                ForEach(vm.state.debts, id: \.id) { debt in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(debt.direction == .iGave ? "I gave" : "I took").font(.callout)
                            if let note = debt.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                            if let due = debt.dueDate {
                                Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            if debt.settled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Settled")
                            }
                            Text(AmountFormatter.money(debt.remaining))
                                .font(.callout.monospacedDigit())
                                .strikethrough(debt.settled)
                        }
                    }
                    .opacity(debt.settled ? 0.4 : 1.0)
                    .swipeActions {
                        if !debt.settled && debt.direction == .iGave {
                            Button("Write off", role: .destructive) {
                                Task { await vm.writeOff(debt.id) }
                            }
                        }
                    }
                }
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle(vm.state.friendName)
        .sheet(isPresented: $showAddDebtSheet) {
            NavigationStack {
                AddDebtSheet(vm: vm, direction: addDebtDirection, store: store)
            }
        }
        .textFieldAlert(
            isPresented: $showSettleAlert,
            title: "Settle Up",
            placeholder: "Amount (blank = full)",
            keyboardType: .decimalPad
        ) { text in
            Task { await vm.settle(amountText: text.isEmpty ? nil : text) }
        }
        .confirmationDialog("Clear balance with \(vm.state.friendName)?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) { Task { await vm.clearAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marks every open amount as settled and resets the balance to zero.")
        }
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
    }
}

private struct AddDebtSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: FriendDetailViewModel
    let direction: DebtDirection
    let store: ExpenseStore

    @State private var amountText = ""
    @State private var note = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        Form {
            TextField("Amount", text: $amountText)
                .keyboardType(.decimalPad)
            TextField("Note", text: $note)
            Toggle("Due date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Due", selection: $dueDate, displayedComponents: .date)
            }
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle(direction == .iGave ? "I Gave" : "I Took")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let dueDateToSave = hasDueDate ? dueDate : nil
                    Task {
                        await vm.addDebt(
                            direction: direction, amountText: amountText, note: note,
                            dueDate: dueDateToSave
                        )
                        if vm.state.errorMessage == nil {
                            if dueDateToSave != nil {
                                Task { await NotificationScheduler.shared.resync(store: store) }
                            }
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
