import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    public struct State: Sendable {
        /// An active installment whose next due date falls within 7 days.
        public struct DueSoonItem: Sendable, Equatable, Identifiable {
            public let id: UUID
            public let name: String
            public let amount: Decimal
            /// Days until due from today's start-of-day (0 = today, 1 = tomorrow, 2–7 = this week).
            public let daysUntil: Int
            /// True when the installment is set to auto-log — no user action needed.
            public let autoLog: Bool
        }

        public var monthSpent: Decimal = 0
        public var monthIncome: Decimal = 0
        /// True when `monthIncome` is the salary fallback (no logged income this month).
        public var monthIncomeIsFromSalary: Bool = false
        public var budgets: [BudgetStatus] = []
        public var friendRows: [DebtRow] = []
        public var recent: [TxnRow] = []
        /// This week's daily spend/income, for the compact Home trend chart.
        public var weekBars: [ActivityBar] = []
        public var breakdown: SpendingBreakdown = SpendingBreakdown(total: 0, categories: [])
        /// Category id → stored colorHex, so the spending chart can color slices to
        /// match each category's chip elsewhere in the app.
        public var categoryColors: [UUID: String] = [:]
        /// Current categories, so recent-transaction rows can show the same
        /// icon/color swatch used on History rows.
        public var categories: [CategorySnapshot] = []
        /// Present only when the user has set a payday + salary in Settings.
        public var payPlan: PayCyclePlan?
        /// Active installments whose next due date is within the next 7 days.
        public var dueSoonItems: [DueSoonItem] = []

        /// The single nearest upcoming bill (recurring rule or installment) when
        /// nothing is due within 7 days. Nil when dueSoonItems is non-empty or
        /// when no reminders/installments are configured at all.
        public struct NextUpcomingItem: Sendable, Equatable {
            public let name: String
            public let amount: Decimal   // 0 if unset / no amount to show
            public let daysUntil: Int    // days from today's start-of-day
            /// True when this item is set to auto-log — no user action needed.
            public let autoLog: Bool
        }
        public var nextUpcomingItem: NextUpcomingItem?

        public var isLoading = false
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) {
        self.store = store
    }

    /// `payday`/`monthlySalary`/`savingsRatePercent` come from the app's shared
    /// preferences (set in Settings). When both payday and salary > 0, a
    /// `PayCyclePlan` is built; otherwise the plan section stays hidden.
    /// `monthlySalary` is also used as a fallback for "Income this month" when
    /// no income transactions have been logged yet this month.
    public func load(
        now: Date = Date(),
        calendar: Calendar = .current,
        payday: Int? = nil,
        monthlySalary: Decimal? = nil,
        savingsRatePercent: Int = 0
    ) async {
        state.errorMessage = nil
        state.isLoading = true
        defer { state.isLoading = false }

        do {
            let spent = try await store.spent(in: .month, categoryID: nil, now: now, calendar: calendar)
            state.monthSpent = spent

            let income = try await store.income(in: .month, now: now, calendar: calendar)
            if income > 0 {
                state.monthIncome = income
                state.monthIncomeIsFromSalary = false
            } else if let salary = monthlySalary, salary > 0 {
                // No income logged yet — show salary so the hero card isn't empty.
                state.monthIncome = salary
                state.monthIncomeIsFromSalary = true
            } else {
                state.monthIncome = 0
                state.monthIncomeIsFromSalary = false
            }

            let budgets = try await store.budgetStatuses(now: now, calendar: calendar)
            state.budgets = budgets

            state.breakdown = try await store.spendingBreakdown(in: .month, now: now, calendar: calendar)
            let categories = try await store.categories()
            state.categories = categories
            state.categoryColors = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.colorHex) })

            if let payday, let salary = monthlySalary, salary > 0 {
                let cycle = PayCyclePlanner.cycle(now: now, dayOfMonth: payday, calendar: calendar)
                let spentThisCycle = try await store.spent(from: cycle.start, to: cycle.next)
                state.payPlan = PayCyclePlan(
                    salary: salary,
                    spentThisCycle: spentThisCycle,
                    cycleStart: cycle.start,
                    nextPayday: cycle.next,
                    daysUntilPayday: cycle.daysUntilNext,
                    savingsRatePercent: savingsRatePercent
                )
            } else {
                state.payPlan = nil
            }

            let friends = try await store.friends()
            let balances = try await store.netBalances()
            var friendRows: [DebtRow] = []
            for friend in friends {
                let balance = balances[friend.id] ?? 0
                if balance != 0 {
                    friendRows.append(DebtRow(friendID: friend.id, name: friend.name, amount: balance))
                }
            }
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
            // Progressive disclosure: home shows the 5 most recent; History has the full ledger.
            state.recent = Array(sorted.prefix(5))
            state.weekBars = ActivitySeries.bars(rows, period: .week, now: now, calendar: calendar)

            let installs = try await store.activeInstallments(now: now, calendar: calendar)
            state.dueSoonItems = installs.compactMap { snap in
                let next = HomeViewModel.nextDue(dayOfMonth: snap.dayOfMonth, from: now, calendar: calendar)
                guard next.timeIntervalSince(now) <= 7 * 24 * 3600 else { return nil }
                let days = max(0, calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: now),
                    to: calendar.startOfDay(for: next)
                ).day ?? 0)
                return State.DueSoonItem(id: snap.id, name: snap.name, amount: snap.monthlyAmount, daysUntil: days, autoLog: snap.autoLog)
            }

            // "Next upcoming" hint — surface the nearest future bill when nothing
            // is urgently due, so the Home screen always has forward context.
            if state.dueSoonItems.isEmpty {
                let rules = try await store.recurringRules()
                var candidates: [(name: String, amount: Decimal, dueDate: Date, autoLog: Bool)] = []
                for rule in rules {
                    let due = HomeViewModel.nextDue(dayOfMonth: rule.dayOfMonth, from: now, calendar: calendar)
                    candidates.append((rule.name, rule.amount, due, rule.autoLog))
                }
                // Include installments that are beyond the 7-day window.
                for snap in installs {
                    let due = HomeViewModel.nextDue(dayOfMonth: snap.dayOfMonth, from: now, calendar: calendar)
                    candidates.append((snap.name, snap.monthlyAmount, due, snap.autoLog))
                }
                if let nearest = candidates.min(by: { $0.dueDate < $1.dueDate }) {
                    let days = max(0, calendar.dateComponents(
                        [.day],
                        from: calendar.startOfDay(for: now),
                        to: calendar.startOfDay(for: nearest.dueDate)
                    ).day ?? 0)
                    state.nextUpcomingItem = State.NextUpcomingItem(
                        name: nearest.name, amount: nearest.amount, daysUntil: days, autoLog: nearest.autoLog)
                } else {
                    state.nextUpcomingItem = nil
                }
            } else {
                state.nextUpcomingItem = nil
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
        monthlySalary: Decimal? = nil,
        savingsRatePercent: Int = 0
    ) async {
        do {
            try await store.deleteTxn(txnID: id)
            await load(now: now, calendar: calendar, payday: payday, monthlySalary: monthlySalary, savingsRatePercent: savingsRatePercent)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}
