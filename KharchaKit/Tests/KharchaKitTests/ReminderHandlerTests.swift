import Testing
import Foundation
@testable import KharchaKit

@Test func addReminderSpeaksNextDueDate() async throws {
    let store = try makeStore()
    let result = try await AddReminderHandler.run(store: store, name: "Rent", amount: 500_000, dayOfMonth: 25, remindDaysBefore: 3, now: d(2026, 8, 19), calendar: testCal)
    #expect(result.message == "I'll remind you about Rent (₩500,000) on Aug 25.")
    let rules = try await store.recurringRules()
    #expect(rules.count == 1)
    #expect(rules[0].dayOfMonth == 25)
}

@Test func addReminderRollsToNextMonth() async throws {
    let store = try makeStore()
    let result = try await AddReminderHandler.run(store: store, name: "Gym", amount: 60_000, dayOfMonth: 10, remindDaysBefore: 1, now: d(2026, 8, 19), calendar: testCal)
    #expect(result.message == "I'll remind you about Gym (₩60,000) on Sep 10.")
}

@Test func addReminderRollsAcrossYearBoundary() async throws {
    let store = try makeStore()
    let result = try await AddReminderHandler.run(store: store, name: "Rent", amount: 500_000, dayOfMonth: 5, remindDaysBefore: 1, now: d(2026, 12, 19), calendar: testCal)
    #expect(result.message.hasSuffix("on Jan 5."))
}
