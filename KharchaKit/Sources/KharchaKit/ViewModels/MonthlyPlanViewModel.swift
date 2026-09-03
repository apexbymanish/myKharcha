import Foundation

/// Drives the Monthly Plan screen: composes income + recurring commitments into a
/// `MonthlyPlan`, works out where to put the recommended savings, and prepares the
/// pre-alert list. All figures come from the pure `MonthlyPlanner`/`SavingsAllocator`
/// engines — nothing here (and no model) does arithmetic on money.
@MainActor
public final class MonthlyPlanViewModel: ObservableObject {

    public struct State: Sendable {
        /// Income used for the current evaluation (from Settings salary, or pasted).
        public var income: Decimal = 0
        public var savingsRatePercent: Int = 20
        public var commitments: [PlanCommitment] = []
        /// Average discretionary spend/month (past months' expenses minus commitments).
        public var typicalMonthlySpend: Decimal = 0
        public var plan: MonthlyPlan?
        /// How to split the recommended savings across the user's savings goals.
        public var allocation: SavingsAllocation?
        public var goals: [SavingsGoalSnapshot] = []
        /// A friendly summary. Deterministic (engine template) until `generateAIAdvice`
        /// replaces it with an Apple-Intelligence rephrasing.
        public var advice: String?
        /// True once Apple Intelligence has rephrased the advice.
        public var adviceFromModel = false
        public var isLoading = false
        public var isParsingIncome = false
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()

    private let store: ExpenseStore
    private let rates: RateProviding?
    /// Category name that marks a recurring rule as a subscription for the plan.
    private let subscriptionCategory = "Subscriptions"

    public init(store: ExpenseStore, rates: RateProviding? = nil) {
        self.store = store
        self.rates = rates
    }

    /// Load commitments + typical spend from the store and evaluate the plan.
    /// `income` and `savingsRatePercent` come from the caller (Settings).
    public func load(income: Decimal, savingsRatePercent: Int = 20, now: Date = Date(), calendar: Calendar = .current) async {
        state.isLoading = true
        state.errorMessage = nil
        defer { state.isLoading = false }
        do {
            let rules = try await store.recurringRules()
            let ruleCommitments = rules.map {
                PlanCommitment(
                    name: $0.name,
                    amount: $0.amount,
                    dayOfMonth: $0.dayOfMonth,
                    isSubscription: $0.categoryName.caseInsensitiveCompare(subscriptionCategory) == .orderedSame
                )
            }
            // Active installments/loans are monthly obligations too, so they count
            // as commitments in the forecast (their recorded payments already show
            // up in spending, so the discretionary calc below doesn't double-count).
            let installmentCommitments = try await store.activeInstallments(now: now, calendar: calendar).map {
                PlanCommitment(name: $0.name, amount: $0.monthlyAmount, dayOfMonth: $0.dayOfMonth, isSubscription: false)
            }
            let commitments = ruleCommitments + installmentCommitments
            let commitmentsTotal = commitments.reduce(Decimal(0)) { $0 + $1.amount }
            let avgSpend = try await averageMonthlyExpenses(now: now, calendar: calendar, months: 3)
            // Discretionary = what you spend beyond the fixed commitments, so the
            // target-income formula doesn't double-count rent/subscriptions.
            let discretionary = max(0, avgSpend - commitmentsTotal)

            state.income = income
            state.savingsRatePercent = savingsRatePercent
            state.commitments = commitments
            state.typicalMonthlySpend = discretionary
            state.goals = try await store.savingsGoals()
            evaluate(now: now, calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Set the income (e.g. after the user edits the field) and re-evaluate.
    public func setIncome(_ income: Decimal, now: Date = Date(), calendar: Calendar = .current) {
        state.income = income
        evaluate(now: now, calendar: calendar)
    }

    public func setSavingsRate(_ percent: Int, now: Date = Date(), calendar: Calendar = .current) {
        state.savingsRatePercent = percent
        evaluate(now: now, calendar: calendar)
    }

    /// Extract a monthly income figure from pasted text (payslip, bank message),
    /// converting a foreign amount to the base currency, then re-evaluate.
    public func parseIncome(_ text: String, now: Date = Date(), calendar: Calendar = .current, allowModel: Bool = true, baseCurrency: String = AmountFormatter.currencyCode) async {
        state.isParsingIncome = true
        state.errorMessage = nil
        defer { state.isParsingIncome = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var parsed: [ParsedExpense] = []
        if allowModel, ExpenseTextExtractor.isAvailable,
           let llm = await ExpenseTextExtractor.extract(text, now: now, calendar: calendar), !llm.isEmpty {
            parsed = llm
        } else {
            parsed = ExpenseTextParser.parse(text, now: now, calendar: calendar)
        }
        // Prefer an income-flagged amount; otherwise take the largest number found.
        let candidate = parsed.first(where: { $0.kind == .income }) ?? parsed.max(by: { $0.amount < $1.amount })
        guard let candidate else {
            state.errorMessage = "No amount found in that text."
            return
        }

        var amount = candidate.amount
        if let code = candidate.currencyCode, code != baseCurrency, let rates,
           let rate = await rates.rate(from: code, to: baseCurrency, on: candidate.date) {
            amount = CurrencyConverter.convert(amount, rate: rate, minorUnits: CurrencyConverter.minorUnits(for: baseCurrency))
        }
        setIncome(amount, now: now, calendar: calendar)
    }

    /// Replace the deterministic advice with an Apple-Intelligence rephrasing when
    /// available. The engine's numbers stay authoritative; the model only restyles.
    public func generateAIAdvice() async {
        guard let plan = state.plan else { return }
        let base = plan.summaryText()
        if let styled = await PlanAdvisor.rephrase(base) {
            state.advice = styled
            state.adviceFromModel = true
        }
    }

    /// Pre-alert specs for commitments due within the window — the app schedules these.
    public func upcomingCommitments() -> [PlanCommitment] {
        state.plan?.upcoming ?? []
    }

    // MARK: - Private

    private func evaluate(now: Date, calendar: Calendar) {
        let plan = MonthlyPlanner.plan(
            income: state.income,
            commitments: state.commitments,
            savingsRatePercent: state.savingsRatePercent,
            typicalMonthlySpend: state.typicalMonthlySpend,
            now: now,
            calendar: calendar
        )
        state.plan = plan
        state.advice = plan.summaryText()
        state.adviceFromModel = false

        let obligations = state.goals.map {
            SavingsObligation(name: $0.name, amount: $0.targetAmount, priority: $0.priority)
        }
        state.allocation = obligations.isEmpty
            ? nil
            : SavingsAllocator.plan(balance: plan.recommendedSavings, obligations: obligations)
    }

    /// Mean total expenses over the previous `months` complete calendar months.
    private func averageMonthlyExpenses(now: Date, calendar: Calendar, months: Int) async throws -> Decimal {
        guard months > 0 else { return 0 }
        var total = Decimal(0)
        for i in 1...months {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now),
                  let interval = calendar.dateInterval(of: .month, for: monthDate) else { continue }
            total += try await store.spent(from: interval.start, to: interval.end)
        }
        return total / Decimal(months)
    }
}
