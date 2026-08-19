import SwiftUI
import UIKit
import KharchaKit

struct BudgetsView: View {
    @StateObject private var vm: BudgetsViewModel
    @State private var budgetAlertCategory: CategorySnapshot?
    @State private var showBudgetAlert = false

    init(store: ExpenseStore) {
        _vm = StateObject(wrappedValue: BudgetsViewModel(store: store))
    }

    private func status(for category: CategorySnapshot) -> BudgetStatus? {
        vm.state.statuses.first { $0.categoryID == category.id }
    }

    var body: some View {
        List {
            ForEach(vm.state.categories, id: \.id) { category in
                Button {
                    budgetAlertCategory = category
                    showBudgetAlert = true
                } label: {
                    HStack {
                        Label(category.name, systemImage: category.symbol)
                            .foregroundStyle(.primary)
                        Spacer()
                        if let s = status(for: category) {
                            Text("\(AmountFormatter.krw(s.spent)) / \(AmountFormatter.krw(s.budget))")
                                .font(.caption)
                                .foregroundStyle(s.isOver ? .red : .secondary)
                        } else if let budget = category.monthlyBudget {
                            Text(AmountFormatter.krw(budget)).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("No budget").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error = vm.state.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("Budgets")
        .textFieldAlert(
            isPresented: $showBudgetAlert,
            title: "Set Budget",
            placeholder: "Amount (blank clears)",
            keyboardType: .decimalPad,
            initialText: budgetAlertCategory?.monthlyBudget.map { "\($0)" } ?? ""
        ) { text in
            if let category = budgetAlertCategory {
                Task { await vm.setBudget(categoryID: category.id, amountText: text) }
            }
        }
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
    }
}
