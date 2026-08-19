import Testing
import Foundation
@testable import KharchaKit

@Suite
struct FriendDetailViewModelTests {
    @Test
    @MainActor
    func loadPopulatesDebtAndNet() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Alice", phone: nil)
        let debt = try await store.addDebt(friendID: friend.id, amount: 100_000, direction: .iGave, date: d(2026, 8, 1), note: "Lunch", dueDate: nil)

        let vm = FriendDetailViewModel(store: store, friendID: friend.id, friendName: friend.name)
        await vm.load()

        #expect(vm.state.debts.count == 1)
        #expect(vm.state.debts[0].id == debt.id)
        #expect(vm.state.net == 100_000)
    }

    @Test
    @MainActor
    func loadIncludesSettledDebts() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Bob", phone: nil)
        let debt = try await store.addDebt(friendID: friend.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)
        _ = try await store.settleDebt(debtID: debt.id, amount: 50_000)

        let vm = FriendDetailViewModel(store: store, friendID: friend.id, friendName: friend.name)
        await vm.load()

        #expect(vm.state.debts.count == 1)
        #expect(vm.state.debts[0].settled == true)
        #expect(vm.state.net == 0)
    }

    @Test
    @MainActor
    func addDebtWithValidAmount() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Charlie", phone: nil)

        let vm = FriendDetailViewModel(store: store, friendID: friend.id, friendName: friend.name)
        await vm.addDebt(direction: .iGave, amountText: "75,000", note: "Dinner", dueDate: nil)

        #expect(vm.state.errorMessage == nil)
        #expect(vm.state.debts.count == 1)
        #expect(vm.state.debts[0].amount == 75_000)
    }

    @Test
    @MainActor
    func addDebtWithBadAmount() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Dave", phone: nil)

        let vm = FriendDetailViewModel(store: store, friendID: friend.id, friendName: friend.name)
        await vm.addDebt(direction: .iGave, amountText: "bad", note: "", dueDate: nil)

        #expect(vm.state.errorMessage != nil)
    }

    @Test
    @MainActor
    func settleAllZeroesNet() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Eve", phone: nil)
        _ = try await store.addDebt(friendID: friend.id, amount: 100_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

        let vm = FriendDetailViewModel(store: store, friendID: friend.id, friendName: friend.name)
        await vm.load()
        #expect(vm.state.net == 100_000)

        await vm.settle(amountText: nil)

        #expect(vm.state.net == 0)
        #expect(vm.state.debts.allSatisfy { $0.settled })
    }

    @Test
    @MainActor
    func settlePartial() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Frank", phone: nil)
        _ = try await store.addDebt(friendID: friend.id, amount: 100_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

        let vm = FriendDetailViewModel(store: store, friendID: friend.id, friendName: friend.name)
        await vm.load()
        #expect(vm.state.net == 100_000)

        await vm.settle(amountText: "30,000")

        #expect(vm.state.net == 70_000)
    }

    @Test
    @MainActor
    func writeOffConvertsToExpense() async throws {
        let store = try makeStore()
        let friend = try await store.addFriend(name: "Grace", phone: nil)
        let debt = try await store.addDebt(friendID: friend.id, amount: 50_000, direction: .iGave, date: d(2026, 8, 1), note: nil, dueDate: nil)

        let vm = FriendDetailViewModel(store: store, friendID: friend.id, friendName: friend.name)
        await vm.load()
        #expect(vm.state.debts.count == 1)
        #expect(vm.state.net == 50_000)

        await vm.writeOff(debt.id)

        #expect(vm.state.debts.count == 1)
        #expect(vm.state.debts[0].settled == true)
        #expect(vm.state.net == 0)

        // Verify expense was created
        let txns = try await store.txnRows()
        #expect(txns.count == 1)
        #expect(txns[0].kind == .expense)
        #expect(txns[0].amount == 50_000)
    }
}
