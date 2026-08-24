import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    public struct State: Sendable {
        /// An active installment whose next due date falls within 7 days.
        public struct DueSoonItem: Sendable, Equatable {
            public let name: String
            public let amount: Decimal
        }

        public var monthSpent: Decimal = 0
        public var monthIncome: Decimal = 0
        public var budgets: [BudgetStatus] = []
        public var friendRows: [DebtRow] = []
        public var recent: [TxnRow] = []
        /// This week's daily spend/income, for the compact Home trend chart.
        public var weekBars: [ActivityBar] = []
        public var breakdown: SpendingBreakdown = SpendingBreakdown(total: 0, categories: [])
        /// Category id → stored colorHex, so the spending chart can color slices to
        /// match each category's chip elsewhere in the app.
        public var categoryColors: [UUID: String] = [:]
        /// Present only when the user has set a payday + salary in Settings.
        public var payPlan: PayCyclePlan?
        /// Active installments whose next due date is within the next 7 days.
        public var dueSoonItems: [DueSoonItem] = []
        public var isLoading = false
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    /// `payday`/`monthlySalary` come from the app's shared preferences (set in
    /// Settings). When both are present and salary > 0, a `PayCyclePlan` is built;
    /// otherwise the plan section stays hidden.
    public func load(
        now: Date = Date(),
        calendar: Calendar = .current,
        payday: Int? = nil,
        monthlySalary: Decimal? = nil
    ) async {
        state.errorMessage = nil
        state.isLoading = true
        defer { state.isLoading = false }

        do {
            let spent = try await store.spent(in: .month, categoryID: nil, now: now, calendar: calendar)
            state.monthSpent = spent

            let income = try await store.income(in: .month, now: now, calendar: calendar)
            state.monthIncome = income

            let budgets = try await store.budgetStatuses(now: now, calendar: calendar)
            state.budgets = budgets

            state.breakdown = try await store.spendingBreakdown(in: .month, now: now, calendar: calendar)
            state.categoryColors = Dictionary(
                uniqueKeysWithValues: try await store.categories().map { ($0.id, $0.colorHex) }
            )

            if let payday, let salary = monthlySalary, salary > 0 {
                let cycle = PayCyclePlanner.cycle(now: now, dayOfMonth: payday, calendar: calendar)
                let spentThisCycle = try await store.spent(from: cycle.start, to: cycle.next)
                state.payPlan = PayCyclePlan(
                    salary: salary,
                    spentThisCycle: spentThisCycle,
                    cycleStart: cycle.start,
                    nextPayday: cycle.next,
                    daysUntilPayday: cycle.daysUntilNext
                )
            } else {
                state.payPlan = nil
            }

            let friends = try await store.friends()
            let balances = try await store.netBalances()
            var friendRows: [DebtRow] = []
            for friend in friends {
                let balance = balances[friend.id] ?? 0
                // Skip zero-net friends; store signed net
                if balance != 0 {
                    friendRows.append(DebtRow(friendID: friend.id, name: friend.name, amount: balance))
                }
            }
            // Sort: positive (they owe me) descending, then negative (I owe) by abs descending
            friendRows.sort { a, b in
                let aNet = a.amount
                let bNet = b.amount
                if (aNet > 0) && (bNet <= 0) { return true }
                if (aNet <= 0) && (bNet > 0) { return false }
                return abs(aNet) > abs(bNet)
            }
            state.friendRows = friendRows

            let rows = try await store.txnRows()
            let sorted = rows.sorted { $0.date > $1.date }
            state.recent = Array(sorted.prefix(10))
            state.weekBars = ActivitySeries.bars(rows, period: .week, now: now, calendar: calendar)

            let installs = try await store.activeInstallments(now: now, calendar: calendar)
            state.dueSoonItems = installs.compactMap { snap in
                let next = HomeViewModel.nextDue(dayOfMonth: snap.dayOfMonth, from: now, calendar: calendar)
                guard next.timeIntervalSince(now) <= 7 * 24 * 3600 else { return nil }
                return State.DueSoonItem(name: snap.name, amount: snap.monthlyAmount)
            }
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Returns the next calendar date on which `dayOfMonth` falls, on or after `now`.
    private static func nextDue(dayOfMonth: Int, from now: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: now)
        comps.day = dayOfMonth
        if let d = calendar.date(from: comps), d >= calendar.startOfDay(for: now) { return d }
        comps.month! += 1
        return calendar.date(from: comps) ?? calendar.startOfDay(for: now)
    }

    public func deleteTxn(
        _ id: UUID,
        now: Date = Date(),
        calendar: Calendar = .current,
        payday: Int? = nil,
        monthlySalary: Decimal? = nil
    ) async {
        do {
            try await store.deleteTxn(txnID: id)
            await load(now: now, calendar: calendar, payday: payday, monthlySalary: monthlySalary)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
