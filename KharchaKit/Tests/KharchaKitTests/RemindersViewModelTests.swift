import Testing
import Foundation
@testable import KharchaKit

@Suite
struct RemindersViewModelTests {
    @Test
    @MainActor
    func loadPopulatesRules() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
        _ = try await store.addRecurringRule(
            name: "Groceries",
            amount: 50_000,
            categoryID: food.id,
            dayOfMonth: 15,
            remindDaysBefore: 2,
            autoLog: true
        )

        let vm = RemindersViewModel(store: store)
        await vm.load()

        #expect(vm.state.rules.count == 1)
        #expect(vm.state.rules[0].name == "Groceries")
        #expect(vm.state.rules[0].amount == 50_000)
    }

    @Test
    @MainActor
    func addWithValidAmount() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)

        let vm = RemindersViewModel(store: store)
        await vm.add(name: "Test", amountText: "100,000", dayOfMonth: 15, remindDaysBefore: 2, autoLog: false, categoryID: food.id)

        #expect(vm.state.errorMessage == nil)
        #expect(vm.state.rules.count == 1)
        #expect(vm.state.rules[0].amount == 100_000)
    }

    @Test
    @MainActor
    func addWithBadAmount() async throws {
        let store = try makeStore()
        let vm = RemindersViewModel(store: store)

        await vm.add(name: "Test", amountText: "junk", dayOfMonth: 15, remindDaysBefore: 2, autoLog: false, categoryID: nil)

        #expect(vm.state.errorMessage != nil)
    }

    @Test
    @MainActor
    func deleteRemovesRule() async throws {
        let store = try makeStore()
        let rule = try await store.addRecurringRule(
            name: "Test",
            amount: 50_000,
            categoryID: nil,
            dayOfMonth: 15,
            remindDaysBefore: 2,
            autoLog: false
        )

        let vm = RemindersViewModel(store: store)
        await vm.load()
        #expect(vm.state.rules.count == 1)

        await vm.delete(rule.id)

        #expect(vm.state.rules.count == 0)
    }

    @Test
    @MainActor
    func nextDueTextForCurrentMonth() async throws {
        let rule = RecurringRuleSnapshot(
            id: UUID(), name: "Test", amount: 1000, categoryName: "Food",
            dayOfMonth: 20, remindDaysBefore: 2, autoLog: false
        )

        let vm = RemindersViewModel(store: try makeStore())
        // Aug 19, 2026 at 12pm, dayOfMonth=20 → next due is Aug 20, 2026
        let text = vm.nextDueText(for: rule, now: d(2026, 8, 19), calendar: testCal)

        #expect(text == "Aug 20")
    }

    @Test
    @MainActor
    func nextDueTextRolloversToNextMonth() async throws {
        let rule = RecurringRuleSnapshot(
            id: UUID(), name: "Test", amount: 1000, categoryName: "Food",
            dayOfMonth: 15, remindDaysBefore: 2, autoLog: false
        )

        let vm = RemindersViewModel(store: try makeStore())
        // Aug 20, 2026 at 12pm, dayOfMonth=15 → next due is Sep 15, 2026
        let text = vm.nextDueText(for: rule, now: d(2026, 8, 20), calendar: testCal)

        #expect(text == "Sep 15")
    }
}
