import Foundation
import SwiftData

public struct CategorySnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let symbol: String
    public let colorHex: String
    public let monthlyBudget: Decimal?
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
            modelContext.insert(Category(name: c.name, symbol: c.symbol, colorHex: c.colorHex, monthlyBudget: nil))
        }
        try modelContext.save()
    }

    public func categories() throws -> [CategorySnapshot] {
        try modelContext.fetch(FetchDescriptor<Category>())
            .sorted { $0.name < $1.name }
            .map(snapshot)
    }

    public func setBudget(categoryID: UUID, amount: Decimal?) throws {
        guard let category = try fetchCategory(id: categoryID) else { throw StoreError.notFound }
        category.monthlyBudget = amount
        category.updatedAt = .now
        try modelContext.save()
    }

    public func budgetStatuses(now: Date, calendar: Calendar) throws -> [BudgetStatus] {
        try modelContext.fetch(FetchDescriptor<Category>())
            .compactMap { category in
                guard let budget = category.monthlyBudget else { return nil }
                let spent = try? self.spent(in: .month, categoryID: category.id, now: now, calendar: calendar)
                return BudgetStatus(categoryID: category.id, categoryName: category.name, spent: spent ?? 0, budget: budget)
            }
            .sorted { $0.categoryName < $1.categoryName }
    }

    // MARK: Transactions

    @discardableResult
    public func addTxn(amount: Decimal, kind: TxnKind, categoryID: UUID?, note: String?, date: Date, source: TxnSource) throws -> UUID {
        guard amount > 0 else { throw StoreError.invalidAmount }
        let category = try categoryID.flatMap { try fetchCategory(id: $0) }
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
        CategorySnapshot(id: c.id, name: c.name, symbol: c.symbol, colorHex: c.colorHex, monthlyBudget: c.monthlyBudget)
    }
}
