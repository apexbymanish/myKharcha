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

    @Test
    @MainActor
    func sortRanksZeroNetBeforeNegativeDebts() async throws {
        let store = try makeStore()
        let ram = try await store.addFriend(name: "Ram", phone: nil)
        let zoe = try await store.addFriend(name: "Zoe", phone: nil)
        let amy = try await store.addFriend(name: "Amy", phone: nil)
        let bob = try await store.addFriend(name: "Bob", phone: nil)

        // Ram: +50,000 (I gave)
        _ = try await store.addDebt(friendID: ram.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

        // Zoe: 0 (no debts)

        // Amy: -10,000 (I took)
        _ = try await store.addDebt(friendID: amy.id, amount: 10_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)

        // Bob: -30,000 (I took)
        _ = try await store.addDebt(friendID: bob.id, amount: 30_000, direction: .iTook, date: d(2026, 8, 1), note: nil, dueDate: nil)

        let vm = FriendsViewModel(store: store)
        await vm.load()

        let names = vm.state.rows.map(\.name)
        #expect(names == ["Ram", "Zoe", "Bob", "Amy"])
    }
}
