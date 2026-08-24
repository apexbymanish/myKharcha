import SwiftUI
import UIKit
import KharchaKit

/// Installments & Loans: multi-month obligations with a running balance. Active
/// ones show progress and next due; tap to record payments or close.
struct InstallmentsView: View {
    let store: ExpenseStore
    @StateObject private var vm: InstallmentsViewModel

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
                        NavigationLink {
                            InstallmentDetailView(store: store, installmentID: item.id)
                        } label: {
                            InstallmentRow(item: item)
                        }
                        .swipeActions {
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
    }
}

/// One row: name + kind, a progress bar, paid-count/next-due, and remaining.
private struct InstallmentRow: View {
    let item: InstallmentSnapshot

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
                    Text("Next: \(InstallmentDateText.short(item.nextDueDate))")
                }
                .font(.caption).foregroundStyle(.secondary)
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
