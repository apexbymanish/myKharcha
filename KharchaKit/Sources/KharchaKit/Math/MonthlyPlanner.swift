import Foundation

/// A recurring monthly commitment feeding the plan (rent, a subscription, etc.).
public struct PlanCommitment: Sendable, Equatable {
    public let name: String
    public let amount: Decimal
    public let dayOfMonth: Int
    public let isSubscription: Bool
    public init(name: String, amount: Decimal, dayOfMonth: Int, isSubscription: Bool) {
        self.name = name
        self.amount = amount
        self.dayOfMonth = dayOfMonth
        self.isSubscription = isSubscription
    }
}

/// The evaluated monthly plan: what's committed, what to save, what's safe to
/// spend, whether you're over-committed, and what's due soon (for pre-alerts).
public struct MonthlyPlan: Sendable, Equatable {
    public let income: Decimal
    public let commitmentsTotal: Decimal
    public let subscriptionsTotal: Decimal
    public let recommendedSavings: Decimal
    public let safeToSpend: Decimal
    /// Amount by which commitments exceed income (0 when income covers them).
    public let shortfall: Decimal
    /// Commitments due within the alert window, soonest first.
    public let upcoming: [PlanCommitment]
    /// The income you'd want to earn to cover commitments + your typical spending
    /// while still saving at your chosen rate. Exact, deterministic — never an AI
    /// estimate. Equals `income` when no typical-spend figure is supplied.
    public let suggestedTargetIncome: Decimal

    public var isOverCommitted: Bool { shortfall > 0 }
    /// True when the suggestion is meaningfully above current income (worth showing).
    public var targetIncomeExceedsIncome: Bool { suggestedTargetIncome > income }

    /// A deterministic, human-readable summary of the plan. Every number is exact
    /// (computed by the engine, never by a model). Used as the notification body
    /// and as the fallback text when Apple Intelligence isn't available to rephrase
    /// it. The AI layer, when present, only restyles the wording — the figures here
    /// stay authoritative.
    public func summaryLines(currencyCode: String = AmountFormatter.currencyCode) -> [String] {
        func money(_ v: Decimal) -> String { AmountFormatter.money(v, currencyCode: currencyCode) }
        var lines: [String] = []
        if isOverCommitted {
            lines.append(String(localized: "Your commitments (\(money(commitmentsTotal))) are \(money(shortfall)) more than your income of \(money(income)). Consider trimming subscriptions or adding income.", bundle: .module))
        } else {
            lines.append(String(localized: "After \(money(commitmentsTotal)) of commitments, you can save \(money(recommendedSavings)) and safely spend \(money(safeToSpend)) this month.", bundle: .module))
        }
        if subscriptionsTotal > 0 {
            lines.append(String(localized: "Subscriptions account for \(money(subscriptionsTotal)) of your commitments.", bundle: .module))
        }
        if let next = upcoming.first {
            lines.append(String(localized: "\(next.name) (\(money(next.amount))) is due soon.", bundle: .module))
        }
        if targetIncomeExceedsIncome {
            lines.append(String(localized: "To keep saving at this rate and cover your usual spending, aim to earn about \(money(suggestedTargetIncome)) per month.", bundle: .module))
        }
        return lines
    }

    /// The summary as a single paragraph — the notification body / AI fallback.
    public func summaryText(currencyCode: String = AmountFormatter.currencyCode) -> String {
        summaryLines(currencyCode: currencyCode).joined(separator: " ")
    }
}

/// Pure monthly-plan evaluator. Given income + commitments, it computes the
/// split, a recommended savings amount, safe-to-spend, and the soon-due items.
public enum MonthlyPlanner {
    public static func plan(
        income: Decimal,
        commitments: [PlanCommitment],
        savingsRatePercent: Int = 20,
        typicalMonthlySpend: Decimal = 0,
        now: Date,
        calendar: Calendar = .current,
        upcomingWithinDays: Int = 7
    ) -> MonthlyPlan {
        let rate = max(0, min(savingsRatePercent, 100))
        let commitmentsTotal = commitments.reduce(Decimal(0)) { $0 + $1.amount }
        let subscriptionsTotal = commitments.filter(\.isSubscription).reduce(Decimal(0)) { $0 + $1.amount }

        let afterCommitments = income - commitmentsTotal
        let shortfall = afterCommitments < 0 ? -afterCommitments : 0
        let disposable = max(afterCommitments, 0)

        let recommendedSavings = disposable * Decimal(rate) / 100
        let safeToSpend = afterCommitments - recommendedSavings

        let upcoming = commitments
            .compactMap { c -> (PlanCommitment, Date)? in
                let due = RecurringMath.nextDueDate(dayOfMonth: c.dayOfMonth, after: now, calendar: calendar)
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? .max
                return days <= upcomingWithinDays ? (c, due) : nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        // Target income solves: T − commitments − typicalSpend = rate% of T,
        // i.e. T = (commitments + typicalSpend) / (1 − rate/100). This is the
        // income at which you cover fixed costs, spend as you usually do, and
        // still hit your savings rate. Clamp the divisor so rate=100 can't blow up.
        let denom = max(Decimal(1) - Decimal(rate) / 100, Decimal(string: "0.01")!)
        let rawTarget = (commitmentsTotal + typicalMonthlySpend) / denom
        let suggestedTargetIncome = max(rounded(rawTarget), income)

        return MonthlyPlan(
            income: income,
            commitmentsTotal: commitmentsTotal,
            subscriptionsTotal: subscriptionsTotal,
            recommendedSavings: recommendedSavings,
            safeToSpend: safeToSpend,
            shortfall: shortfall,
            upcoming: upcoming,
            suggestedTargetIncome: suggestedTargetIncome
        )
    }

    /// Round a Decimal to a whole unit (banker's-free, half-up) — target income
    /// reads better as a round figure than a fractional one.
    private static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
