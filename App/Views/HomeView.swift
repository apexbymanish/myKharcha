import SwiftUI
import UIKit
import KharchaKit

struct HomeView: View {
    let store: ExpenseStore
    @StateObject private var vm: HomeViewModel
    @State private var showAddSheet = false

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: HomeViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spent this month").font(.caption).foregroundStyle(.secondary)
                        Text(AmountFormatter.krw(vm.state.monthSpent)).font(.title2.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Income this month").font(.caption).foregroundStyle(.secondary)
                        Text(AmountFormatter.krw(vm.state.monthIncome))
                            .font(.title2.bold())
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            }

            if !vm.state.budgets.isEmpty {
                Section("Budgets") {
                    ForEach(vm.state.budgets, id: \.categoryID) { status in
                        BudgetBar(status: status)
                    }
                }
            }

            if !vm.state.friendRows.isEmpty {
                Section("Friends") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(vm.state.friendRows, id: \.friendID) { row in
                                FriendDebtChip(row: row)
                            }
                        }
                    }
                }
            }

            Section("Recent") {
                if vm.state.recent.isEmpty {
                    Text("No transactions yet").foregroundStyle(.secondary)
                }
                ForEach(vm.state.recent, id: \.id) { row in
                    TxnRowView(row: row)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task { await vm.deleteTxn(row.id) }
                            }
                        }
                }
            }

            if let error = vm.state.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("Kharcha")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { Task { await vm.load() } }) {
            NavigationStack {
                TxnFormView(store: store)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
    }
}
