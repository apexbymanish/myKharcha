import Testing
import Foundation
@testable import KharchaKit

@Test func addAndListRecurringRules() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let rent = try await store.categories().first { $0.name == "Rent" }!
    let rule = try await store.addRecurringRule(name: "Rent", amount: 500_000, categoryID: rent.id, dayOfMonth: 25, remindDaysBefore: 3, autoLog: false)
    #expect(rule.categoryName == "Rent")
    _ = try await store.addRecurringRule(name: "Netflix", amount: 17_000, categoryID: nil, dayOfMonth: 3, remindDaysBefore: 1, autoLog: true)

    let rules = try await store.recurringRules()
    #expect(rules.map(\.name) == ["Netflix", "Rent"]) // sorted by dayOfMonth
    #expect(rules[0].categoryName == "")
}

@Test func addRecurringRuleValidation() async throws {
    let store = try makeStore()
    await #expect(throws: StoreError.invalidAmount) {
        _ = try await store.addRecurringRule(name: "X", amount: 0, categoryID: nil, dayOfMonth: 5, remindDaysBefore: 1, autoLog: false)
    }
    await #expect(throws: StoreError.invalidDayOfMonth) {
        _ = try await store.addRecurringRule(name: "X", amount: 1, categoryID: nil, dayOfMonth: 32, remindDaysBefore: 1, autoLog: false)
    }
    await #expect(throws: StoreError.notFound) {
        _ = try await store.addRecurringRule(name: "X", amount: 1, categoryID: UUID(), dayOfMonth: 5, remindDaysBefore: 1, autoLog: false)
    }
}

@Test func deleteRecurringRule() async throws {
    let store = try makeStore()
    let rule = try await store.addRecurringRule(name: "Gym", amount: 60_000, categoryID: nil, dayOfMonth: 1, remindDaysBefore: 0, autoLog: false)
    try await store.deleteRecurringRule(ruleID: rule.id)
    #expect(try await store.recurringRules().isEmpty)
    await #expect(throws: StoreError.notFound) {
        try await store.deleteRecurringRule(ruleID: rule.id)
    }
}
