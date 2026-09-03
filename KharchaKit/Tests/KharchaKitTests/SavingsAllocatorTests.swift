import Testing
import Foundation
@testable import KharchaKit

private func line(_ result: SavingsAllocation, _ name: String) -> SavingsAllocationLine? {
    result.lines.first { $0.name == name }
}

@Test func savingsFullyCoversLeavesRemainderFree() {
    let r = SavingsAllocator.plan(balance: 1_000_000, obligations: [
        SavingsObligation(name: "Rent", amount: 500_000, priority: 0),
        SavingsObligation(name: "Subs", amount: 50_000, priority: 1)
    ])
    #expect(line(r, "Rent")?.reserved == 500_000)
    #expect(line(r, "Subs")?.reserved == 50_000)
    #expect(r.free == 450_000)
    #expect(r.totalShortfall == 0)
    #expect(r.isFullyFunded)
}

@Test func savingsExactlyCoversLeavesZeroFree() {
    let r = SavingsAllocator.plan(balance: 550_000, obligations: [
        SavingsObligation(name: "Rent", amount: 500_000, priority: 0),
        SavingsObligation(name: "Subs", amount: 50_000, priority: 1)
    ])
    #expect(r.free == 0)
    #expect(r.totalShortfall == 0)
}

@Test func savingsUnderfundedReservesByPriority() {
    let r = SavingsAllocator.plan(balance: 520_000, obligations: [
        SavingsObligation(name: "Rent", amount: 500_000, priority: 0),
        SavingsObligation(name: "Subs", amount: 50_000, priority: 1)
    ])
    #expect(line(r, "Rent")?.reserved == 500_000)
    #expect(line(r, "Subs")?.reserved == 20_000)
    #expect(line(r, "Subs")?.shortfall == 30_000)
    #expect(r.free == 0)
    #expect(r.totalShortfall == 30_000)
    #expect(!r.isFullyFunded)
}

@Test func savingsNoObligationsIsAllFree() {
    let r = SavingsAllocator.plan(balance: 1_000_000, obligations: [])
    #expect(r.lines.isEmpty)
    #expect(r.free == 1_000_000)
    #expect(r.totalShortfall == 0)
}

@Test func savingsEmptyPotIsAllShortfall() {
    let r = SavingsAllocator.plan(balance: 0, obligations: [
        SavingsObligation(name: "Rent", amount: 500_000, priority: 0)
    ])
    #expect(line(r, "Rent")?.reserved == 0)
    #expect(line(r, "Rent")?.shortfall == 500_000)
    #expect(r.free == 0)
    #expect(r.totalShortfall == 500_000)
}

@Test func savingsReservesSoonestDueFirst() {
    // Priority encodes due date: A (due sooner) = 0, B (later) = 1.
    let r = SavingsAllocator.plan(balance: 100_000, obligations: [
        SavingsObligation(name: "B", amount: 80_000, priority: 1),
        SavingsObligation(name: "A", amount: 80_000, priority: 0)
    ])
    #expect(line(r, "A")?.reserved == 80_000)
    #expect(line(r, "B")?.reserved == 20_000)
}

@Test func savingsAggregatedPotsCoverThenFree() {
    // Aggregation of two pots (300k + 400k) happens before planning.
    let r = SavingsAllocator.plan(balance: 700_000, obligations: [
        SavingsObligation(name: "Rent", amount: 500_000, priority: 0)
    ])
    #expect(line(r, "Rent")?.reserved == 500_000)
    #expect(r.free == 200_000)
}

@Test func savingsDecimalExactNoFloatDrift() {
    let r = SavingsAllocator.plan(balance: Decimal(string: "100000.50")!, obligations: [
        SavingsObligation(name: "a", amount: Decimal(string: "0.25")!, priority: 0),
        SavingsObligation(name: "b", amount: Decimal(string: "0.25")!, priority: 0),
        SavingsObligation(name: "c", amount: Decimal(string: "0.25")!, priority: 0)
    ])
    #expect(r.free == Decimal(string: "99999.75")!)
    #expect(r.totalShortfall == 0)
}

@Test func savingsMixesBillsAndGoals() {
    let r = SavingsAllocator.plan(balance: 1_000_000, obligations: [
        SavingsObligation(name: "Rent", amount: 500_000, priority: 0),        // bill
        SavingsObligation(name: "Emergency", amount: 400_000, priority: 3)    // goal
    ])
    #expect(line(r, "Rent")?.reserved == 500_000)
    #expect(line(r, "Emergency")?.reserved == 400_000)
    #expect(r.free == 100_000)
}
