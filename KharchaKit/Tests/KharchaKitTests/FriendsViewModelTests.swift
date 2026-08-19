import Testing
import Foundation
@testable import KharchaKit

@Suite
struct FriendsViewModelTests {
    @Test
    @MainActor
    func loadSortsNetBalances() async throws {
        let store = try makeStore()
        let ram = try await store.addFriend(name: "Ram", phone: nil)
        let sita = try await store.addFriend(name: "Sita", phone: nil)

        // Ram: I gave 50k → +50k
        _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

        // Sita: I took 20k → -20k
        _ = try await store.addDebt(friendID: sita.id, amount: 20_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)

        let vm = FriendsViewModel(store: store)
        await vm.load()

        #expect(vm.state.rows.count == 2)
        // Ram (positive 50k) should come before Sita (negative 20k)
        #expect(vm.state.rows[0].name == "Ram")
        #expect(vm.state.rows[0].net == 50_000)
        #expect(vm.state.rows[1].name == "Sita")
        #expect(vm.state.rows[1].net == -20_000)
    }

    @Test
    @MainActor
    func addFriendWithValidName() async throws {
        let store = try makeStore()
        let vm = FriendsViewModel(store: store)

        await vm.addFriend(name: "Test Friend")

        #expect(vm.state.errorMessage == nil)
        #expect(vm.state.rows.count == 1)
        #expect(vm.state.rows[0].name == "Test Friend")
    }

    @Test
    @MainActor
    func addFriendWithEmptyName() async throws {
        let store = try makeStore()
        let vm = FriendsViewModel(store: store)

        await vm.addFriend(name: "")

        #expect(vm.state.errorMessage != nil)
        #expect(vm.state.rows.isEmpty)
    }

    @Test
    @MainActor
    func addFriendWithWhitespaceOnlyName() async throws {
        let store = try makeStore()
        let vm = FriendsViewModel(store: store)

        await vm.addFriend(name: "   ")

        #expect(vm.state.errorMessage != nil)
        #expect(vm.state.rows.isEmpty)
    }

    @Test
    @MainActor
    func deleteFriendWithOpenDebtsShowsError() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Test", phone: nil)
        _ = try await store.addDebt(friendID: friend.id, amount: 10_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

        let vm = FriendsViewModel(store: store)
        await vm.load()

        await vm.deleteFriend(friend.id)

        #expect(vm.state.errorMessage == "That friend still has open debts.")
    }

    @Test
    @MainActor
    func deleteFriendWithoutDebts() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Test", phone: nil)

        let vm = FriendsViewModel(store: store)
        await vm.load()
        #expect(vm.state.rows.count == 1)

        await vm.deleteFriend(friend.id)

        #expect(vm.state.rows.isEmpty)
    }
}
