import SwiftUI
import UIKit
import KharchaKit

struct RemindersView: View {
    let store: ExpenseStore
    @StateObject private var vm: RemindersViewModel
    @State private var showAddSheet = false
    @State private var notificationsDenied = false

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: RemindersViewModel(store: store))
    }

    var body: some View {
        List {
            ForEach(vm.state.rules, id: \.id) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(rule.name).font(.headline)
                        Spacer()
                        Text(AmountFormatter.krw(rule.amount)).font(.callout.monospacedDigit())
                    }
                    HStack {
                        Text("Day \(rule.dayOfMonth) (next: \(vm.nextDueText(for: rule)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if rule.autoLog {
                            Spacer()
                            Text("Auto-log")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task {
                            await vm.delete(rule.id)
                            if vm.state.errorMessage == nil {
                                Task { await NotificationScheduler.shared.resync(store: store) }
                            }
                        }
                    }
                }
            }
            if let error = vm.state.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if notificationsDenied {
                Text("Notifications are off — reminders won't fire. Enable them in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Reminders")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                AddReminderSheet(vm: vm, store: store)
            }
        }
        .task {
            await vm.load()
            notificationsDenied = await NotificationScheduler.authorizationDenied()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
    }
}

/// Multi-field add form (name, amount, day, remind-days, auto-log). Category
/// selection is intentionally omitted: `RemindersViewModel.State` doesn't
/// expose a categories list (unlike TxnFormViewModel/BudgetsViewModel), so new
/// rules are added uncategorized (`categoryID: nil`) rather than reaching past
/// the ViewModel into the store — recorded as an adaptation in the task report.
private struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemindersViewModel
    let store: ExpenseStore

    @State private var name = ""
    @State private var amountText = ""
    @State private var dayOfMonth = 1
    @State private var remindDaysBefore = 3
    @State private var autoLog = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
            }
            Section {
                Stepper("Day of month: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                Stepper("Remind days before: \(remindDaysBefore)", value: $remindDaysBefore, in: 0...14)
                Toggle("Auto-log", isOn: $autoLog)
            }
            if let error = vm.state.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("Add Reminder")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await vm.add(
                            name: name, amountText: amountText, dayOfMonth: dayOfMonth,
                            remindDaysBefore: remindDaysBefore, autoLog: autoLog, categoryID: nil
                        )
                        if vm.state.errorMessage == nil {
                            Task { await NotificationScheduler.shared.resync(store: store) }
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
