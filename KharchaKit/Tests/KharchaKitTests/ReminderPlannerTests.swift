import Testing
import Foundation
@testable import KharchaKit

private func rule(_ name: String, amount: Decimal, day: Int, remind: Int) -> RecurringRuleSnapshot {
    RecurringRuleSnapshot(id: UUID(), name: name, amount: amount, categoryName: "", dayOfMonth: day, remindDaysBefore: remind, autoLog: false)
}

@Test func rulePlansReminderBeforeDueDate() {
    let specs = ReminderPlanner.plan(rules: [rule("Rent", amount: 500_000, day: 25, remind: 3)], debts: [], now: d(2026, 8, 19), calendar: testCal)
    #expect(specs.count == 1)
    #expect(specs[0].id.hasPrefix("rule-"))
    #expect(specs[0].title == "Rent")
    #expect(specs[0].body == "Rent (₩500,000) is due on Aug 25.")
    // remind = Aug 22 at 09:00 KST
    #expect(specs[0].fireDate == testCal.date(bySettingHour: 9, minute: 0, second: 0, of: d(2026, 8, 22, 0))!)
}

@Test func rulePastRemindWindowRollsToNextMonth() {
    // now = Aug 24: due Aug 25 but remind day (Aug 22, 09:00) already passed → roll to Sep 25 due, Sep 22 fire
    let specs = ReminderPlanner.plan(rules: [rule("Rent", amount: 500_000, day: 25, remind: 3)], debts: [], now: d(2026, 8, 24), calendar: testCal)
    #expect(specs[0].body == "Rent (₩500,000) is due on Sep 25.")
    #expect(specs[0].fireDate == testCal.date(bySettingHour: 9, minute: 0, second: 0, of: d(2026, 9, 22, 0))!)
}

@Test func debtReminderOneDayBeforeDueSkippingPast() {
    let ram = UUID()
    let due = DebtSnapshot(id: UUID(), friendID: ram, friendName: "Ram", amount: 50_000, direction: .iGave, remaining: 50_000, settled: false, dueDate: d(2026, 8, 30, 0), date: d(2026, 8, 1), note: nil)
    let past = DebtSnapshot(id: UUID(), friendID: ram, friendName: "Ram", amount: 10_000, direction: .iGave, remaining: 10_000, settled: false, dueDate: d(2026, 8, 10, 0), date: d(2026, 8, 1), note: nil)
    let settled = DebtSnapshot(id: UUID(), friendID: ram, friendName: "Ram", amount: 5_000, direction: .iGave, remaining: 0, settled: true, dueDate: d(2026, 8, 30, 0), date: d(2026, 8, 1), note: nil)
    let specs = ReminderPlanner.plan(rules: [], debts: [due, past, settled], now: d(2026, 8, 19), calendar: testCal)
    #expect(specs.count == 1)
    #expect(specs[0].body == "Ram's ₩50,000 is due on Aug 30.")
    #expect(specs[0].fireDate == testCal.date(bySettingHour: 9, minute: 0, second: 0, of: d(2026, 8, 29, 0))!)
}

@Test func autoLogCatchUpFindsMissedOccurrences() {
    // since = Jun 20, now = Aug 19, day 25 → Jun 25, Jul 25 (Aug 25 not yet)
    let dates = AutoLogCatchUp.dueOccurrences(dayOfMonth: 25, since: d(2026, 6, 20), now: d(2026, 8, 19), calendar: testCal)
    #expect(dates == [d(2026, 6, 25, 0), d(2026, 7, 25, 0)])
    #expect(AutoLogCatchUp.dueOccurrences(dayOfMonth: 25, since: d(2026, 8, 18), now: d(2026, 8, 19), calendar: testCal).isEmpty)
}
