import Testing
import SwiftData
@testable import KharchaKit

@MainActor
@Test func modelsInsertIntoInMemoryContainer() throws {
    let container = try ModelContainer(
        for: Schema(KharchaSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    let ctx = container.mainContext

    let food = Category(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: 300_000)
    ctx.insert(food)

    let txn = Txn(amount: 12_000, kind: .expense, category: food, note: "lunch", date: .now, source: .siri)
    ctx.insert(txn)

    let ram = Friend(name: "Ram", phone: nil, photoData: nil)
    ctx.insert(ram)

    let debt = Debt(friend: ram, amount: 50_000, direction: .iGave, date: .now, note: nil, dueDate: nil)
    ctx.insert(debt)

    let rent = RecurringRule(name: "Rent", amount: 500_000, category: food, dayOfMonth: 25, remindDaysBefore: 3, autoLog: true)
    ctx.insert(rent)

    try ctx.save()

    #expect(try ctx.fetch(FetchDescriptor<Txn>()).count == 1)
    #expect(try ctx.fetch(FetchDescriptor<Debt>()).first?.remaining == 50_000)
    #expect(try ctx.fetch(FetchDescriptor<Debt>()).first?.settled == false)
    #expect(txn.id != debt.id)
}
