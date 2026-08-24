import Testing
import Foundation
@testable import KharchaKit

@Test func monthlyPlanSplitsIncomeCommitmentsAndSavings() {
    let plan = MonthlyPlanner.plan(
        income: 3_000_000,
        commitments: [
            PlanCommitment(name: "Rent", amount: 800_000, dayOfMonth: 1, isSubscription: false),
            PlanCommitment(name: "Netflix", amount: 15_000, dayOfMonth: 5, isSubscription: true),
            PlanCommitment(name: "Spotify", amount: 10_000, dayOfMonth: 5, isSubscription: true)
        ],
        savingsRatePercent: 20,
        now: d(2026, 8, 1),
        calendar: testCal
    )
    #expect(plan.commitmentsTotal == 825_000)
    #expect(plan.subscriptionsTotal == 25_000)
    // disposable = 2,175,000 → 20% = 435,000
    #expect(plan.recommendedSavings == 435_000)
    #expect(plan.safeToSpend == 1_740_000)      // 2,175,000 − 435,000
    #expect(plan.shortfall == 0)
    #expect(!plan.isOverCommitted)
}

@Test func monthlyPlanFlagsOverCommitment() {
    let plan = MonthlyPlanner.plan(
        income: 500_000,
        commitments: [PlanCommitment(name: "Rent", amount: 800_000, dayOfMonth: 1, isSubscription: false)],
        savingsRatePercent: 20,
        now: d(2026, 8, 1),
        calendar: testCal
    )
    #expect(plan.shortfall == 300_000)
    #expect(plan.recommendedSavings == 0)       // nothing disposable
    #expect(plan.safeToSpend == -300_000)
    #expect(plan.isOverCommitted)
}

@Test func monthlyPlanListsOnlySoonDueUpcoming() {
    let now = d(2026, 8, 1)
    let plan = MonthlyPlanner.plan(
        income: 1_000_000,
        commitments: [
            PlanCommitment(name: "Rent", amount: 800_000, dayOfMonth: 3, isSubscription: false),   // due Aug 3 → 2 days
            PlanCommitment(name: "Gym", amount: 50_000, dayOfMonth: 20, isSubscription: true)       // due Aug 20 → 19 days
        ],
        savingsRatePercent: 10,
        now: now,
        calendar: testCal,
        upcomingWithinDays: 7
    )
    #expect(plan.upcoming.map(\.name) == ["Rent"])  // only the soon-due one
}

@Test func monthlyPlanWithNoCommitmentsSavesFromFullIncome() {
    let plan = MonthlyPlanner.plan(
        income: 1_000_000,
        commitments: [],
        savingsRatePercent: 25,
        now: d(2026, 8, 1),
        calendar: testCal
    )
    #expect(plan.commitmentsTotal == 0)
    #expect(plan.recommendedSavings == 250_000)
    #expect(plan.safeToSpend == 750_000)
}

@Test func suggestedTargetIncomeCoversCommitmentsSpendAndSavingsRate() {
    // Commitments 825k + typical spend 600k, saving 20% of income.
    // T = (825,000 + 600,000) / (1 − 0.20) = 1,425,000 / 0.8 = 1,781,250.
    let plan = MonthlyPlanner.plan(
        income: 1_500_000,
        commitments: [
            PlanCommitment(name: "Rent", amount: 800_000, dayOfMonth: 1, isSubscription: false),
            PlanCommitment(name: "Netflix", amount: 15_000, dayOfMonth: 5, isSubscription: true),
            PlanCommitment(name: "Spotify", amount: 10_000, dayOfMonth: 5, isSubscription: true)
        ],
        savingsRatePercent: 20,
        typicalMonthlySpend: 600_000,
        now: d(2026, 8, 1),
        calendar: testCal
    )
    #expect(plan.suggestedTargetIncome == 1_781_250)
    #expect(plan.targetIncomeExceedsIncome)  // 1,781,250 > 1,500,000
}

@Test func suggestedTargetIncomeNeverBelowCurrentIncome() {
    // Already earning well above what commitments+spend require → no upsell.
    let plan = MonthlyPlanner.plan(
        income: 5_000_000,
        commitments: [PlanCommitment(name: "Rent", amount: 800_000, dayOfMonth: 1, isSubscription: false)],
        savingsRatePercent: 20,
        typicalMonthlySpend: 500_000,
        now: d(2026, 8, 1),
        calendar: testCal
    )
    #expect(plan.suggestedTargetIncome == 5_000_000)
    #expect(!plan.targetIncomeExceedsIncome)
}

@Test func summaryTextIsDeterministicAndMentionsKeyFigures() {
    pinTestCurrency()  // ₩, so assertions are region-independent
    let plan = MonthlyPlanner.plan(
        income: 3_000_000,
        commitments: [
            PlanCommitment(name: "Rent", amount: 800_000, dayOfMonth: 3, isSubscription: false),
            PlanCommitment(name: "Netflix", amount: 25_000, dayOfMonth: 5, isSubscription: true)
        ],
        savingsRatePercent: 20,
        now: d(2026, 8, 1),
        calendar: testCal
    )
    let text = plan.summaryText(currencyCode: "KRW")
    #expect(text.contains("can save"))
    #expect(text.contains("Subscriptions account for"))
    #expect(text.contains("Rent"))
    #expect(!plan.isOverCommitted)
}

@Test func summaryTextWarnsWhenOverCommitted() {
    let plan = MonthlyPlanner.plan(
        income: 500_000,
        commitments: [PlanCommitment(name: "Rent", amount: 800_000, dayOfMonth: 1, isSubscription: false)],
        savingsRatePercent: 20,
        now: d(2026, 8, 1),
        calendar: testCal
    )
    let text = plan.summaryText(currencyCode: "KRW")
    #expect(text.contains("more than your income"))
}
