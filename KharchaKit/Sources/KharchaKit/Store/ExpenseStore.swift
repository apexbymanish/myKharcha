import Foundation
import SwiftData

public struct CategorySnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let symbol: String
    public let colorHex: String
    public let monthlyBudget: Decimal?
    public let isFallback: Bool

    public init(id: UUID, name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?, isFallback: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.monthlyBudget = monthlyBudget
        self.isFallback = isFallback
    }
}

@ModelActor
public actor ExpenseStore {

    // MARK: Categories

    @discardableResult
    public func addCategory(name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?) throws -> CategorySnapshot {
        let category = Category(name: name, symbol: symbol, colorHex: colorHex, monthlyBudget: monthlyBudget)
        modelContext.insert(category)
        try modelContext.save()
        return snapshot(category)
    }

    public static let defaultCategories: [(name: String, symbol: String, colorHex: String)] = [
        ("Food", "fork.knife", "#E07A5F"),
        ("Transport", "bus", "#3D405B"),
        ("Rent", "house", "#8E7DBE"),
        ("Subscriptions", "arrow.triangle.2.circlepath", "#5F797B"),
        ("Shopping", "bag", "#F2CC8F"),
        ("Health", "cross.case", "#81B29A"),
        ("Entertainment", "gamecontroller", "#E5989B"),
        ("Other", "tag", "#9A9A9A")
    ]

    public func seedDefaultCategoriesIfNeeded() throws {
        guard try modelContext.fetch(FetchDescriptor<Category>()).isEmpty else { return }
        for c in Self.defaultCategories {
            modelContext.insert(Category(name: c.name, symbol: c.symbol, colorHex: c.colorHex, monthlyBudget: nil, isFallback: c.name == "Other"))
        }
        try modelContext.save()
    }

    public func categories() throws -> [CategorySnapshot] {
        try modelContext.fetch(FetchDescriptor<Category>())
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(snapshot)
    }

    public func setBudget(categoryID: UUID, amount: Decimal?) throws {
        if let amount, amount <= 0 { throw StoreError.invalidAmount }
        guard let category = try fetchCategory(id: categoryID) else { throw StoreError.notFound }
        category.monthlyBudget = amount
        category.updatedAt = .now
        try modelContext.save()
    }

    public func budgetStatuses(now: Date, calendar: Calendar) throws -> [BudgetStatus] {
        let range = Period.month.dateRange(now: now, calendar: calendar)
        // Single pass: fetch Txn once and bucket sums by category, instead of
        // re-fetching the whole table per category via spent(). Do not
        // reintroduce the N+1 fetch pattern here.
        let txns = try modelContext.fetch(FetchDescriptor<Txn>())
        var spentByCategory: [UUID: Decimal] = [:]
        for txn in txns where txn.kind == .expense && range.contains(txn.date) {
            guard let categoryID = txn.category?.id else { continue }
            spentByCategory[categoryID, default: 0] += txn.amount
        }

        return try modelContext.fetch(FetchDescriptor<Category>())
            .compactMap { category in
                guard let budget = category.monthlyBudget else { return nil }
                let spent = spentByCategory[category.id] ?? 0
                return BudgetStatus(categoryID: category.id, categoryName: category.name, spent: spent, budget: budget)
            }
            .sorted { $0.categoryName.localizedStandardCompare($1.categoryName) == .orderedAscending }
    }

    // MARK: Transactions

    @discardableResult
    public func addTxn(amount: Decimal, kind: TxnKind, categoryID: UUID?, note: String?, date: Date, source: TxnSource) throws -> UUID {
        guard amount > 0 else { throw StoreError.invalidAmount }
        var category: Category?
        if let categoryID {
            guard let found = try fetchCategory(id: categoryID) else { throw StoreError.notFound }
            category = found
        }
        let txn = Txn(amount: amount, kind: kind, category: category, note: note, date: date, source: source)
        modelContext.insert(txn)
        try modelContext.save()
        return txn.id
    }

    public func spent(in period: Period, categoryID: UUID?, now: Date, calendar: Calendar) throws -> Decimal {
        try total(kind: .expense, period: period, categoryID: categoryID, now: now, calendar: calendar)
    }

    public func income(in period: Period, now: Date, calendar: Calendar) throws -> Decimal {
        try total(kind: .income, period: period, categoryID: nil, now: now, calendar: calendar)
    }

    /// True when an identical Siri-logged expense (same amount + category)
    /// exists within the last 120 seconds — used by LogExpenseIntent to
    /// re-prompt instead of double-logging.
    public func isDuplicate(amount: Decimal, categoryID: UUID?, now: Date) throws -> Bool {
        let cutoff = now.addingTimeInterval(-120)
        return try modelContext.fetch(FetchDescriptor<Txn>()).contains {
            $0.source == .siri
                && $0.kind == .expense
                && $0.amount == amount
                && $0.category?.id == categoryID
                && $0.date > cutoff && $0.date <= now
        }
    }

    public func txnRows() throws -> [TxnRow] {
        try modelContext.fetch(FetchDescriptor<Txn>())
            .sorted { $0.date < $1.date }
            .map {
                TxnRow(
                    id: $0.id,
                    date: $0.date,
                    kind: $0.kind,
                    amount: $0.amount,
                    categoryName: $0.category?.name ?? "",
                    note: $0.note,
                    source: $0.source
                )
            }
    }

    // MARK: Internals

    private func total(kind: TxnKind, period: Period, categoryID: UUID?, now: Date, calendar: Calendar) throws -> Decimal {
        let range = period.dateRange(now: now, calendar: calendar)
        // Deliberate: fetch all, filter in memory. #Predicate + enum/Decimal is unreliable,
        // and this is personal-scale data. Do not "optimize" into a predicate.
        let txns = try modelContext.fetch(FetchDescriptor<Txn>())
        return txns
            .filter { $0.kind == kind && range.contains($0.date) }
            .filter { categoryID == nil || $0.category?.id == categoryID }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func fetchCategory(id: UUID) throws -> Category? {
        try modelContext.fetch(FetchDescriptor<Category>()).first { $0.id == id }
    }

    private func snapshot(_ c: Category) -> CategorySnapshot {
        CategorySnapshot(id: c.id, name: c.name, symbol: c.symbol, colorHex: c.colorHex, monthlyBudget: c.monthlyBudget, isFallback: c.isFallback)
    }

    /// Single-pass per-category expense breakdown for a period (Siri "how much did I spend").
    public func spendingBreakdown(in period: Period, now: Date, calendar: Calendar) throws -> SpendingBreakdown {
        let range = period.dateRange(now: now, calendar: calendar)
        let expenses = try modelContext.fetch(FetchDescriptor<Txn>())
            .filter { $0.kind == .expense && range.contains($0.date) }
        var buckets: [String: (id: UUID?, amount: Decimal)] = [:]
        var total = Decimal(0)
        for txn in expenses {
            let name = txn.category?.name ?? "Uncategorized"
            var bucket = buckets[name] ?? (txn.category?.id, 0)
            bucket.amount += txn.amount
            buckets[name] = bucket
            total += txn.amount
        }
        let categories = buckets
            .map { CategorySpend(categoryID: $0.value.id, categoryName: $0.key, amount: $0.value.amount) }
            .sorted { ($1.amount, $0.categoryName) < ($0.amount, $1.categoryName) }
        return SpendingBreakdown(total: total, categories: categories)
    }

    // MARK: Friends & Debts

    @discardableResult
    public func addFriend(name: String, phone: String?) throws -> FriendSnapshot {
        let friend = Friend(name: name, phone: phone, photoData: nil)
        modelContext.insert(friend)
        try modelContext.save()
        return FriendSnapshot(id: friend.id, name: friend.name)
    }

    public func friends() throws -> [FriendSnapshot] {
        try modelContext.fetch(FetchDescriptor<Friend>())
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { FriendSnapshot(id: $0.id, name: $0.name) }
    }

    @discardableResult
    public func addDebt(friendID: UUID, amount: Decimal, direction: DebtDirection, date: Date, note: String?, dueDate: Date?) throws -> DebtSnapshot {
        guard amount > 0 else { throw StoreError.invalidAmount }
        guard let friend = try fetchFriend(id: friendID) else { throw StoreError.notFound }
        let debt = Debt(friend: friend, amount: amount, direction: direction, date: date, note: note, dueDate: dueDate)
        modelContext.insert(debt)
        try modelContext.save()
        return snapshot(debt)
    }

    @discardableResult
    public func settleDebt(debtID: UUID, amount: Decimal) throws -> DebtSnapshot {
        guard let debt = try fetchDebt(id: debtID) else { throw StoreError.notFound }
        guard amount > 0, amount <= debt.remaining else { throw StoreError.invalidAmount }
        debt.settledAmount += amount
        debt.settled = debt.remaining == 0
        debt.updatedAt = .now
        try modelContext.save()
        return snapshot(debt)
    }

    public func openDebts() throws -> [DebtSnapshot] {
        try modelContext.fetch(FetchDescriptor<Debt>())
            .filter { !$0.settled }
            .sorted { $0.date < $1.date }
            .map(snapshot)
    }

    /// Positive = the friend owes me; negative = I owe the friend.
    public func netBalance(friendID: UUID) throws -> Decimal {
        try modelContext.fetch(FetchDescriptor<Debt>())
            .filter { $0.friend?.id == friendID && !$0.settled }
            .reduce(Decimal(0)) { sum, debt in
                switch debt.direction {
                case .iGave: sum + debt.remaining
                case .iTook: sum - debt.remaining
                }
            }
    }

    /// Single actor entry for SettleDebtHandler: fetch this friend's open iGave debts
    /// oldest-first, allocate the settle amount across them in one save, and report
    /// what got settled vs. what's left. Do not reintroduce the read-then-loop
    /// pattern (one `settleDebt` call per debt) that used to live in the handler —
    /// that split the write across multiple saves.
    @discardableResult
    public func settleFriendDebts(friendID: UUID, amount: Decimal?) throws -> (settled: Decimal, remaining: Decimal) {
        let open = try modelContext.fetch(FetchDescriptor<Debt>())
            .filter { $0.friend?.id == friendID && $0.direction == .iGave && !$0.settled }
            .sorted { $0.date < $1.date }
        guard !open.isEmpty else { throw StoreError.notFound }
        let total = open.reduce(Decimal(0)) { $0 + $1.remaining }
        let toSettle = amount ?? total
        guard toSettle > 0, toSettle <= total else { throw StoreError.invalidAmount }

        var left = toSettle
        for debt in open where left > 0 {
            let chunk = min(debt.remaining, left)
            debt.settledAmount += chunk
            debt.settled = debt.remaining == 0
            debt.updatedAt = .now
            left -= chunk
        }
        try modelContext.save()
        return (toSettle, total - toSettle)
    }

    /// Single Debt fetch: net balance per friend (positive = they owe me, negative = I owe them).
    /// Use this instead of calling `netBalance(friendID:)` once per friend.
    public func netBalances() throws -> [UUID: Decimal] {
        var balances: [UUID: Decimal] = [:]
        for debt in try modelContext.fetch(FetchDescriptor<Debt>()) where !debt.settled {
            guard let friendID = debt.friend?.id else { continue }
            switch debt.direction {
            case .iGave: balances[friendID, default: 0] += debt.remaining
            case .iTook: balances[friendID, default: 0] -= debt.remaining
            }
        }
        return balances
    }

    /// Give up on an unpaid debt: the remaining amount becomes a real expense
    /// (category "Other") and the debt is closed.
    @discardableResult
    public func convertDebtToExpense(debtID: UUID, date: Date) throws -> UUID {
        guard let debt = try fetchDebt(id: debtID) else { throw StoreError.notFound }
        guard !debt.settled else { throw StoreError.debtAlreadySettled }
        guard debt.direction == .iGave else { throw StoreError.wrongDebtDirection }

        let other = try ensureOtherCategory()
        let txn = Txn(
            amount: debt.remaining,
            kind: .expense,
            category: other,
            note: "Unpaid: \(debt.friend?.name ?? "?")",
            date: date,
            source: .manual
        )
        modelContext.insert(txn)
        debt.settledAmount = debt.amount
        debt.settled = true
        debt.updatedAt = .now
        try modelContext.save()
        return txn.id
    }

    private func fetchFriend(id: UUID) throws -> Friend? {
        try modelContext.fetch(FetchDescriptor<Friend>()).first { $0.id == id }
    }

    private func fetchDebt(id: UUID) throws -> Debt? {
        try modelContext.fetch(FetchDescriptor<Debt>()).first { $0.id == id }
    }

    private func snapshot(_ debt: Debt) -> DebtSnapshot {
        DebtSnapshot(
            id: debt.id,
            friendID: debt.friend?.id,
            friendName: debt.friend?.name ?? "?",
            amount: debt.amount,
            direction: debt.direction,
            remaining: debt.remaining,
            settled: debt.settled,
            dueDate: debt.dueDate,
            date: debt.date,
            note: debt.note
        )
    }

    // MARK: Deletion rules

    public func deleteCategory(categoryID: UUID) throws {
        guard let category = try fetchCategory(id: categoryID) else { throw StoreError.notFound }
        guard !category.isFallback else { throw StoreError.cannotDeleteFallbackCategory }

        let other = try ensureOtherCategory()
        for txn in try modelContext.fetch(FetchDescriptor<Txn>()) where txn.category?.id == categoryID {
            txn.category = other
            txn.updatedAt = .now
        }
        for rule in try modelContext.fetch(FetchDescriptor<RecurringRule>()) where rule.category?.id == categoryID {
            rule.category = other
            rule.updatedAt = .now
        }
        modelContext.delete(category)
        try modelContext.save()
    }

    public func deleteFriend(friendID: UUID) throws {
        guard let friend = try fetchFriend(id: friendID) else { throw StoreError.notFound }
        let debts = try modelContext.fetch(FetchDescriptor<Debt>()).filter { $0.friend?.id == friendID }
        guard debts.allSatisfy(\.settled) else { throw StoreError.friendHasOpenDebts }
        for debt in debts { modelContext.delete(debt) }
        modelContext.delete(friend)
        try modelContext.save()
    }

    public func deleteTxn(txnID: UUID) throws {
        guard let txn = try modelContext.fetch(FetchDescriptor<Txn>()).first(where: { $0.id == txnID }) else {
            throw StoreError.notFound
        }
        modelContext.delete(txn)
        try modelContext.save()
    }

    private func ensureOtherCategory() throws -> Category {
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        if let other = categories.first(where: { $0.isFallback }) {
            return other
        }
        // Safety net: an older store might have an "Other" category that predates
        // the isFallback flag. Adopt it by name before creating a duplicate.
        if let other = categories.first(where: { $0.name == "Other" }) {
            other.isFallback = true
            other.updatedAt = .now
            return other
        }
        let other = Category(name: "Other", symbol: "tag", colorHex: "#9A9A9A", monthlyBudget: nil, isFallback: true)
        modelContext.insert(other)
        return other
    }

    // MARK: Recurring rules

    @discardableResult
    public func addRecurringRule(name: String, amount: Decimal, categoryID: UUID?, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool) throws -> RecurringRuleSnapshot {
        guard amount > 0 else { throw StoreError.invalidAmount }
        guard (1...31).contains(dayOfMonth) else { throw StoreError.invalidDayOfMonth }
        var category: Category?
        if let categoryID {
            guard let found = try fetchCategory(id: categoryID) else { throw StoreError.notFound }
            category = found
        }
        let rule = RecurringRule(name: name, amount: amount, category: category, dayOfMonth: dayOfMonth, remindDaysBefore: remindDaysBefore, autoLog: autoLog)
        modelContext.insert(rule)
        try modelContext.save()
        return snapshot(rule)
    }

    public func recurringRules() throws -> [RecurringRuleSnapshot] {
        try modelContext.fetch(FetchDescriptor<RecurringRule>())
            .sorted { ($0.dayOfMonth, $0.name) < ($1.dayOfMonth, $1.name) }
            .map(snapshot)
    }

    public func deleteRecurringRule(ruleID: UUID) throws {
        guard let rule = try modelContext.fetch(FetchDescriptor<RecurringRule>()).first(where: { $0.id == ruleID }) else {
            throw StoreError.notFound
        }
        modelContext.delete(rule)
        try modelContext.save()
    }

    private func snapshot(_ rule: RecurringRule) -> RecurringRuleSnapshot {
        RecurringRuleSnapshot(
            id: rule.id, name: rule.name, amount: rule.amount,
            categoryName: rule.category?.name ?? "",
            dayOfMonth: rule.dayOfMonth, remindDaysBefore: rule.remindDaysBefore, autoLog: rule.autoLog
        )
    }
}
