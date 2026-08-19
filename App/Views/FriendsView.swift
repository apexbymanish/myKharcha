import SwiftUI
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
        if row.net > 0 { return "owes you \(AmountFormatter.krw(row.net))" }
        if row.net < 0 { return "you owe \(AmountFormatter.krw(abs(row.net)))" }
        return "settled"
    }

    var body: some View {
        List {
            ForEach(vm.state.rows, id: \.id) { row in
                NavigationLink {
                    FriendDetailView(store: store, friendID: row.id, friendName: row.name)
                } label: {
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(phrase(row))
                            .font(.caption)
                            .foregroundStyle(row.net > 0 ? .green : (row.net < 0 ? .red : .secondary))
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await vm.deleteFriend(row.id) }
                    }
                }
            }
            if let error = vm.state.errorMessage {
                Text(error).foregroundStyle(.red)
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
            }
        }
        .textFieldAlert(isPresented: $showAddFriendAlert, title: "Add Friend", placeholder: "Name") { text in
            Task { await vm.addFriend(name: text) }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}
