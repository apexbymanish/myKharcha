import Testing
import Foundation
@testable import KharchaKit

@MainActor
struct MonthlyPlanViewModelTests {

    private func seedCategory(_ store: ExpenseStore, _ name: String) async throws -> UUID {
        try await store.addCategory(name: name, symbol: "tag", colorHex: "#999999", monthlyBudget: nil).id
    }

    @Test func loadComposesCommitmentsAndDetectsSubscriptions() async throws {
        let store = try makeStore()
        let rent = try await seedCategory(store, "Rent")
        let subs = try await seedCategory(store, "Subscriptions")
        _ = try await store.addRecurringRule(name: "Rent", amount: 800_000, categoryID: rent, dayOfMonth: 1, remindDaysBefore: 3, autoLog: false)
        _ = try await store.addRecurringRule(name: "Netflix", amount: 15_000, categoryID: subs, dayOfMonth: 5, remindDaysBefore: 2, autoLog: false)

        let vm = MonthlyPlanViewModel(store: store)
        await vm.load(income: 3_000_000, savingsRatePercent: 20, now: d(2026, 8, 1), calendar: testCal)

        #expect(vm.state.commitments.count == 2)
        #expect(vm.state.commitments.contains { $0.name == "Netflix" && $0.isSubscription })
        #expect(vm.state.commitments.contains { $0.name == "Rent" && !$0.isSubscription })
        #expect(vm.state.plan?.subscriptionsTotal == 15_000)
        #expect(vm.state.plan?.commitmentsTotal == 815_000)
    }

    @Test func typicalSpendExcludesCommitmentsAndDrivesTargetIncome() async throws {
        let store = try makeStore()
        let rent = try await seedCategory(store, "Rent")
        _ = try await store.addRecurringRule(name: "Rent", amount: 800_000, categoryID: rent, dayOfMonth: 1, remindDaysBefore: 3, autoLog: false)
        // 900k of expenses in each of the previous three months → avg 900k.
        for m in [5, 6, 7] {
            _ = try await store.addTxn(amount: 900_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, m, 15), source: .manual)
        }

        let vm = MonthlyPlanViewModel(store: store)
        await vm.load(income: 1_000_000, savingsRatePercent: 20, now: d(2026, 8, 15), calendar: testCal)

        // discretionary = max(0, 900k − 800k) = 100k
        #expect(vm.state.typicalMonthlySpend == 100_000)
        // T = (800k + 100k) / 0.8 = 1,125,000, above the 1,000,000 income.
        #expect(vm.state.plan?.suggestedTargetIncome == 1_125_000)
    }

    @Test func allocationSplitsRecommendedSavingsAcrossGoals() async throws {
        let store = try makeStore()
        _ = try await store.addSavingsGoal(name: "Emergency", targetAmount: 1_000_000, priority: 0)
        _ = try await store.addSavingsGoal(name: "Vacation", targetAmount: 500_000, priority: 1)

        let vm = MonthlyPlanViewModel(store: store)
        // No commitments → 20% of 1,000,000 income = 200,000 to save.
        await vm.load(income: 1_000_000, savingsRatePercent: 20, now: d(2026, 8, 1), calendar: testCal)

        let alloc = try #require(vm.state.allocation)
        // Priority 0 (Emergency) reserves first: all 200k goes there, none to Vacation.
        #expect(alloc.lines.first?.name == "Emergency")
        #expect(alloc.lines.first?.reserved == 200_000)
        #expect(alloc.free == 0)
    }

    @Test func setIncomeReevaluatesPlan() async throws {
        let store = try makeStore()
        let vm = MonthlyPlanViewModel(store: store)
        await vm.load(income: 1_000_000, savingsRatePercent: 10, now: d(2026, 8, 1), calendar: testCal)
        #expect(vm.state.plan?.recommendedSavings == 100_000)

        vm.setIncome(2_000_000, now: d(2026, 8, 1), calendar: testCal)
        #expect(vm.state.plan?.recommendedSavings == 200_000)
        #expect(vm.state.income == 2_000_000)
    }

    private struct StubRates: RateProviding {
        let value: Decimal
        func rate(from: String, to: String, on date: Date?) async -> Decimal? { value }
    }

    @Test func parseIncomeExtractsAndConvertsForeignAmount() async throws {
        let store = try makeStore()
        let vm = MonthlyPlanViewModel(store: store, rates: StubRates(value: 1300))
        await vm.load(income: 0, savingsRatePercent: 20, now: d(2026, 8, 1), calendar: testCal)

        await vm.parseIncome("Salary $2000 received", now: d(2026, 8, 1), allowModel: false, baseCurrency: "KRW")
        #expect(vm.state.income == 2_600_000)  // 2000 × 1300, KRW whole units
    }
}
