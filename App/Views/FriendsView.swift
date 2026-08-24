import SwiftUI
import UIKit
import KharchaKit

struct FriendsView: View {
    let store: ExpenseStore
    @StateObject private var vm: FriendsViewModel
    @State private var showAddFriendAlert = false

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: FriendsViewModel(store: store))
    }

    private func phrase(_ row: FriendsViewModel.Row) -> String {
        if row.net > 0 { return "owes you \(AmountFormatter.money(row.net))" }
        if row.net < 0 { return "you owe \(AmountFormatter.money(abs(row.net)))" }
        return "settled"
    }

    var body: some View {
        List {
            if vm.state.rows.isEmpty && vm.state.errorMessage == nil {
                EmptyStateView(
                    icon: "person.2",
                    title: "No friends yet",
                    message: "Add a friend to track shared expenses and who owes whom."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(vm.state.rows, id: \.id) { row in
                NavigationLink {
                    FriendDetailView(store: store, friendID: row.id, friendName: row.name)
                } label: {
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(phrase(row))
                            .font(.caption)
                            .foregroundStyle(row.net > 0 ? Color.moneyIn : (row.net < 0 ? Color.moneyOut : .secondary))
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await vm.deleteFriend(row.id) }
                    }
                }
            }
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("Friends")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddFriendAlert = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add friend")
            }
        }
        .textFieldAlert(isPresented: $showAddFriendAlert, title: "Add Friend", placeholder: "Name") { text in
            Task { await vm.addFriend(name: text) }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kharchaRemoteDidChange)) { _ in
            Task { await vm.load() }
        }
    }
}
