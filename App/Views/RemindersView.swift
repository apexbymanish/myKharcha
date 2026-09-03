import SwiftUI
import UIKit
import KharchaKit

struct RemindersView: View {
    let store: ExpenseStore
    @StateObject private var vm: RemindersViewModel
    @State private var showAddSheet = false
    @State private var editingRule: RecurringRuleSnapshot?
    @State private var notificationsDenied = false
    @State private var undoTxnID: UUID?
    @State private var undoTask: Task<Void, Never>?

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: RemindersViewModel(store: store))
    }

    var body: some View {
        List {
            ForEach(vm.state.rules) { rule in
                let isPaid = vm.state.paidRuleIDs.contains(rule.id)
                let days = vm.daysUntil(rule: rule)
                Button { editingRule = rule } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rule.name).font(.headline)
                            Spacer()
                            Text(AmountFormatter.money(rule.amount)).font(.callout.monospacedDigit())
                        }
                        HStack {
                            Text("Day \(rule.dayOfMonth) · next: \(vm.nextDueText(for: rule))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if isPaid {
                                Text("✓ Paid")
                                    .font(.caption2).bold()
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.moneyIn.opacity(0.15))
                                    .foregroundStyle(Color.moneyIn)
                                    .clipShape(Capsule())
                            } else if days == 0 {
                                Text("Due today")
                                    .font(.caption2).bold()
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.moneyOut.opacity(0.15))
                                    .foregroundStyle(Color.moneyOut)
                                    .clipShape(Capsule())
                            } else if days <= 3 {
                                Text("In \(days)d")
                                    .font(.caption2).bold()
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(Color.orange)
                                    .clipShape(Capsule())
                            } else if rule.autoLog {
                                Text("Auto-log")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    if !isPaid && !rule.autoLog {
                        Button {
                            Task {
                                if let id = await vm.markPaid(rule) {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    showUndo(txnID: id)
                                }
                            }
                        } label: {
                            Label("Mark Paid", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                    }
                }
                .swipeActions(edge: .trailing) {
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
                InlineError(message: error)
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
                .accessibilityLabel("Add reminder")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                ReminderFormSheet(vm: vm, store: store, editing: nil)
            }
        }
        .sheet(item: $editingRule) { rule in
            NavigationStack {
                ReminderFormSheet(vm: vm, store: store, editing: rule)
            }
        }
        .task {
            await vm.load()
            notificationsDenied = await NotificationScheduler.authorizationDenied()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
        .safeAreaInset(edge: .bottom) {
            if undoTxnID != nil {
                UndoToast(message: "Marked as paid") {
                    guard let id = undoTxnID else { return }
                    undoTask?.cancel(); undoTxnID = nil
                    Task { await vm.undoMarkPaid(txnID: id) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: undoTxnID)
            }
        }
    }

    private func showUndo(txnID: UUID) {
        undoTask?.cancel()
        undoTxnID = txnID
        undoTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { undoTxnID = nil }
        }
    }
}

/// Multi-field form for both adding and editing a reminder.
/// When `editing` is nil, creates a new rule; otherwise updates the existing one in-place.
private struct ReminderFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemindersViewModel
    let store: ExpenseStore
    let editing: RecurringRuleSnapshot?

    @State private var name = ""
    @State private var amountText = ""
    @State private var dayOfMonth = 1
    @State private var remindDaysBefore = 3
    @State private var autoLog = true

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
            } footer: {
                Text("Auto-log records this expense automatically each month on the due date — no manual entry needed.")
            }
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle(editing == nil ? "Add Reminder" : "Edit Reminder")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if let rule = editing {
                            await vm.update(
                                id: rule.id, name: name, amountText: amountText,
                                dayOfMonth: dayOfMonth, remindDaysBefore: remindDaysBefore, autoLog: autoLog
                            )
                        } else {
                            await vm.add(
                                name: name, amountText: amountText, dayOfMonth: dayOfMonth,
                                remindDaysBefore: remindDaysBefore, autoLog: autoLog, categoryID: nil
                            )
                        }
                        if vm.state.errorMessage == nil {
                            Task { await NotificationScheduler.shared.resync(store: store) }
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            if let rule = editing {
                name = rule.name
                amountText = "\(rule.amount)"
                dayOfMonth = rule.dayOfMonth
                remindDaysBefore = rule.remindDaysBefore
                autoLog = rule.autoLog
            }
        }
    }
}
