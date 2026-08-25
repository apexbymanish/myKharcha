import SwiftUI
import UIKit
import KharchaKit

/// Installments & Loans: multi-month obligations with a running balance. Active
/// ones show progress and next due; tap to record payments or close.
struct InstallmentsView: View {
    let store: ExpenseStore
    @StateObject private var vm: InstallmentsViewModel

    @State private var undoPaymentID: UUID?
    @State private var undoTask: Task<Void, Never>?

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: InstallmentsViewModel(store: store))
    }

    var body: some View {
        List {
            if vm.state.active.isEmpty && vm.state.finished.isEmpty {
                EmptyStateView(
                    icon: "creditcard",
                    title: "No installments yet",
                    message: "Add one from ➕ (choose Installment) to pay a purchase over months or track a loan."
                )
                .listRowSeparator(.hidden)
            }

            if !vm.state.active.isEmpty {
                Section("Active") {
                    ForEach(vm.state.active) { item in
                        let isPaid = vm.state.paidThisMonthIDs.contains(item.id)
                        NavigationLink {
                            InstallmentDetailView(store: store, installmentID: item.id)
                        } label: {
                            InstallmentRow(item: item, isPaidThisMonth: isPaid)
                        }
                        .swipeActions(edge: .leading) {
                            if !isPaid {
                                Button {
                                    Task {
                                        if let id = await vm.recordPayment(installmentID: item.id) {
                                            await NotificationScheduler.shared.resync(store: store)
                                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                                            showUndo(paymentID: id)
                                        }
                                    }
                                } label: {
                                    Label("Pay", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                Task {
                                    await vm.delete(item.id)
                                    await NotificationScheduler.shared.resync(store: store)
                                }
                            }
                        }
                    }
                }
            }

            if !vm.state.finished.isEmpty {
                Section("Finished") {
                    ForEach(vm.state.finished) { item in
                        NavigationLink {
                            InstallmentDetailView(store: store, installmentID: item.id)
                        } label: {
                            InstallmentRow(item: item)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task { await vm.delete(item.id) }
                            }
                        }
                    }
                }
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("Installments & Loans")
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
        .safeAreaInset(edge: .bottom) {
            if undoPaymentID != nil {
                UndoToast(message: "Payment recorded") {
                    guard let id = undoPaymentID else { return }
                    undoTask?.cancel(); undoPaymentID = nil
                    Task { await vm.undoRecordPayment(paymentID: id) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: undoPaymentID)
            }
        }
    }

    private func showUndo(paymentID: UUID) {
        undoTask?.cancel()
        undoPaymentID = paymentID
        undoTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { undoPaymentID = nil }
        }
    }
}

/// One row: name + kind, a progress bar, paid-count/next-due, and remaining.
private struct InstallmentRow: View {
    let item: InstallmentSnapshot
    var isPaidThisMonth: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name).font(.headline)
                if item.kind == .loan {
                    Text("Loan")
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.brandPrimary.opacity(0.15)).clipShape(Capsule())
                }
                Spacer()
                Text(AmountFormatter.money(item.remainingAmount)).font(.callout.monospacedDigit().weight(.semibold))
            }
            if item.isActive {
                ProgressView(value: item.progress).tint(.brandPrimary)
                HStack {
                    Text("\(item.paidCount) of \(item.termCount) paid")
                    Spacer()
                    if isPaidThisMonth {
                        Text("✓ Paid this month")
                            .font(.caption2).bold()
                            .foregroundStyle(Color.moneyIn)
                    } else {
                        Text("Next: \(InstallmentDateText.short(item.nextDueDate))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            } else {
                Text(item.isComplete ? "Paid off" : "Closed")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Shared short date formatting for the installment screens.
enum InstallmentDateText {
    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
