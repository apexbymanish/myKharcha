import Foundation
import SwiftData

// MARK: - Sync export records (carry ids, relationships, and updatedAt)

public struct CategoryExport: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let symbol: String
    public let colorHex: String
    public let monthlyBudget: Decimal?
    public let isFallback: Bool
    public let kindRaw: String
    public let updatedAt: Date
    public init(id: UUID, name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?, isFallback: Bool, kindRaw: String, updatedAt: Date) {
        self.id = id; self.name = name; self.symbol = symbol; self.colorHex = colorHex
        self.monthlyBudget = monthlyBudget; self.isFallback = isFallback; self.kindRaw = kindRaw; self.updatedAt = updatedAt
    }
}

public struct FriendExport: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let phone: String?
    public let updatedAt: Date
    public init(id: UUID, name: String, phone: String?, updatedAt: Date) {
        self.id = id; self.name = name; self.phone = phone; self.updatedAt = updatedAt
    }
}

public struct TxnExport: Sendable, Equatable {
    public let id: UUID
    public let amount: Decimal
    public let kind: TxnKind
    public let categoryID: UUID?
    public let note: String?
    public let date: Date
    public let source: TxnSource
    public let updatedAt: Date
    public init(id: UUID, amount: Decimal, kind: TxnKind, categoryID: UUID?, note: String?, date: Date, source: TxnSource, updatedAt: Date) {
        self.id = id; self.amount = amount; self.kind = kind; self.categoryID = categoryID
        self.note = note; self.date = date; self.source = source; self.updatedAt = updatedAt
    }
}

public struct RuleExport: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let amount: Decimal
    public let categoryID: UUID?
    public let dayOfMonth: Int
    public let remindDaysBefore: Int
    public let autoLog: Bool
    public let updatedAt: Date
    public init(id: UUID, name: String, amount: Decimal, categoryID: UUID?, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool, updatedAt: Date) {
        self.id = id; self.name = name; self.amount = amount; self.categoryID = categoryID
        self.dayOfMonth = dayOfMonth; self.remindDaysBefore = remindDaysBefore; self.autoLog = autoLog; self.updatedAt = updatedAt
    }
}

public struct DebtExport: Sendable, Equatable {
    public let id: UUID
    public let friendID: UUID?
    public let amount: Decimal
    public let direction: DebtDirection
    public let date: Date
    public let note: String?
    public let dueDate: Date?
    public let settledAmount: Decimal
    public let settled: Bool
    public let updatedAt: Date
    public init(id: UUID, friendID: UUID?, amount: Decimal, direction: DebtDirection, date: Date, note: String?, dueDate: Date?, settledAmount: Decimal, settled: Bool, updatedAt: Date) {
        self.id = id; self.friendID = friendID; self.amount = amount; self.direction = direction
        self.date = date; self.note = note; self.dueDate = dueDate
        self.settledAmount = settledAmount; self.settled = settled; self.updatedAt = updatedAt
    }
}

public struct TombstoneExport: Sendable, Equatable {
    public let id: UUID
    public let collection: String
    public let deletedAt: Date
    public init(id: UUID, collection: String, deletedAt: Date) {
        self.id = id; self.collection = collection; self.deletedAt = deletedAt
    }
}

extension ExpenseStore {

    // MARK: Emptiness (restore-vs-backup on first sign-in)

    public func isEmptyForSync() throws -> Bool {
        try modelContext.fetch(FetchDescriptor<Txn>()).isEmpty
            && modelContext.fetch(FetchDescriptor<Friend>()).isEmpty
            && modelContext.fetch(FetchDescriptor<RecurringRule>()).isEmpty
            && modelContext.fetch(FetchDescriptor<Debt>()).isEmpty
    }

    // MARK: Exports (ids + updatedAt)

    public func exportCategories() throws -> [CategoryExport] {
        try modelContext.fetch(FetchDescriptor<Category>()).map {
            CategoryExport(id: $0.id, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex,
                           monthlyBudget: $0.monthlyBudget, isFallback: $0.isFallback, kindRaw: $0.kindRaw, updatedAt: $0.updatedAt)
        }
    }

    public func exportFriends() throws -> [FriendExport] {
        try modelContext.fetch(FetchDescriptor<Friend>()).map {
            FriendExport(id: $0.id, name: $0.name, phone: $0.phone, updatedAt: $0.updatedAt)
        }
    }

    public func exportTxns() throws -> [TxnExport] {
        try modelContext.fetch(FetchDescriptor<Txn>()).map {
            TxnExport(id: $0.id, amount: $0.amount, kind: $0.kind, categoryID: $0.category?.id,
                      note: $0.note, date: $0.date, source: $0.source, updatedAt: $0.updatedAt)
        }
    }

    public func exportRules() throws -> [RuleExport] {
        try modelContext.fetch(FetchDescriptor<RecurringRule>()).map {
            RuleExport(id: $0.id, name: $0.name, amount: $0.amount, categoryID: $0.category?.id,
                       dayOfMonth: $0.dayOfMonth, remindDaysBefore: $0.remindDaysBefore, autoLog: $0.autoLog, updatedAt: $0.updatedAt)
        }
    }

    public func exportDebts() throws -> [DebtExport] {
        try modelContext.fetch(FetchDescriptor<Debt>()).map {
            DebtExport(id: $0.id, friendID: $0.friend?.id, amount: $0.amount, direction: $0.direction,
                       date: $0.date, note: $0.note, dueDate: $0.dueDate,
                       settledAmount: $0.settledAmount, settled: $0.settled, updatedAt: $0.updatedAt)
        }
    }

    public func exportTombstones() throws -> [TombstoneExport] {
        try modelContext.fetch(FetchDescriptor<Tombstone>()).map {
            TombstoneExport(id: $0.id, collection: $0.collection, deletedAt: $0.deletedAt)
        }
    }

    // MARK: Upserts (id-preserving, newest-timestamp-wins, deletion-aware)

    public func upsertCategory(id: UUID, name: String, symbol: String, colorHex: String, monthlyBudget: Decimal?, isFallback: Bool, kindRaw: String = CategoryKind.expense.rawValue, updatedAt: Date) throws {
        if try tombstoneBlocks(id: id, incoming: updatedAt) { return }
        if let c = try firstCategory(id: id) {
            guard updatedAt > c.updatedAt else { return }
            c.name = name; c.symbol = symbol; c.colorHex = colorHex
            c.monthlyBudget = monthlyBudget; c.isFallback = isFallback; c.kindRaw = kindRaw; c.updatedAt = updatedAt
        } else {
            let c = Category(name: name, symbol: symbol, colorHex: colorHex, monthlyBudget: monthlyBudget, isFallback: isFallback, kind: CategoryKind(rawValue: kindRaw) ?? .expense)
            c.id = id; c.updatedAt = updatedAt
            modelContext.insert(c)
        }
        try modelContext.save()
    }

    public func upsertFriend(id: UUID, name: String, phone: String?, updatedAt: Date) throws {
        if try tombstoneBlocks(id: id, incoming: updatedAt) { return }
        if let f = try firstFriend(id: id) {
            guard updatedAt > f.updatedAt else { return }
            f.name = name; f.phone = phone; f.updatedAt = updatedAt
        } else {
            let f = Friend(name: name, phone: phone, photoData: nil)
            f.id = id; f.updatedAt = updatedAt
            modelContext.insert(f)
        }
        try modelContext.save()
    }

    public func upsertTxn(id: UUID, amount: Decimal, kind: TxnKind, categoryID: UUID?, note: String?, date: Date, source: TxnSource, updatedAt: Date) throws {
        if try tombstoneBlocks(id: id, incoming: updatedAt) { return }
        let category = try categoryID.flatMap { try firstCategory(id: $0) }
        if let t = try firstTxn(id: id) {
            guard updatedAt > t.updatedAt else { return }
            t.amount = amount; t.kind = kind; t.category = category; t.note = note; t.date = date; t.source = source; t.updatedAt = updatedAt
        } else {
            let t = Txn(amount: amount, kind: kind, category: category, note: note, date: date, source: source)
            t.id = id; t.updatedAt = updatedAt
            modelContext.insert(t)
        }
        try modelContext.save()
    }

    public func upsertDebt(_ debt: DebtExport) throws {
        if try tombstoneBlocks(id: debt.id, incoming: debt.updatedAt) { return }
        let friend = try debt.friendID.flatMap { try firstFriend(id: $0) }
        if let d = try firstDebt(id: debt.id) {
            guard debt.updatedAt > d.updatedAt else { return }
            d.friend = friend; d.amount = debt.amount; d.direction = debt.direction
            d.date = debt.date; d.note = debt.note; d.dueDate = debt.dueDate
            d.settledAmount = debt.settledAmount; d.settled = debt.settled; d.updatedAt = debt.updatedAt
        } else {
            let d = Debt(friend: friend, amount: debt.amount, direction: debt.direction, date: debt.date, note: debt.note, dueDate: debt.dueDate)
            d.id = debt.id; d.settledAmount = debt.settledAmount; d.settled = debt.settled; d.updatedAt = debt.updatedAt
            modelContext.insert(d)
        }
        try modelContext.save()
    }

    public func upsertRule(id: UUID, name: String, amount: Decimal, categoryID: UUID?, dayOfMonth: Int, remindDaysBefore: Int, autoLog: Bool, updatedAt: Date) throws {
        if try tombstoneBlocks(id: id, incoming: updatedAt) { return }
        let category = try categoryID.flatMap { try firstCategory(id: $0) }
        if let r = try firstRule(id: id) {
            guard updatedAt > r.updatedAt else { return }
            r.name = name; r.amount = amount; r.category = category
            r.dayOfMonth = dayOfMonth; r.remindDaysBefore = remindDaysBefore; r.autoLog = autoLog; r.updatedAt = updatedAt
        } else {
            let r = RecurringRule(name: name, amount: amount, category: category, dayOfMonth: dayOfMonth, remindDaysBefore: remindDaysBefore, autoLog: autoLog)
            r.id = id; r.updatedAt = updatedAt
            modelContext.insert(r)
        }
        try modelContext.save()
    }

    /// Apply a remote deletion: remove the local record (unless it's newer than
    /// the deletion) and persist the tombstone locally so it keeps propagating.
    public func applyRemoteTombstone(id: UUID, collection: String, deletedAt: Date) throws {
        switch collection {
        case "txns": if let t = try firstTxn(id: id), t.updatedAt <= deletedAt { modelContext.delete(t) }
        case "friends": if let f = try firstFriend(id: id), f.updatedAt <= deletedAt { modelContext.delete(f) }
        case "categories": if let c = try firstCategory(id: id), c.updatedAt <= deletedAt { modelContext.delete(c) }
        case "debts": if let d = try firstDebt(id: id), d.updatedAt <= deletedAt { modelContext.delete(d) }
        case "rules": if let r = try firstRule(id: id), r.updatedAt <= deletedAt { modelContext.delete(r) }
        case "savingsPots": if let p = try modelContext.fetch(FetchDescriptor<SavingsPot>()).first(where: { $0.id == id }), p.updatedAt <= deletedAt { modelContext.delete(p) }
        case "savingsEntries": if let e = try modelContext.fetch(FetchDescriptor<SavingsEntry>()).first(where: { $0.id == id }), e.updatedAt <= deletedAt { modelContext.delete(e) }
        case "savingsGoals": if let g = try modelContext.fetch(FetchDescriptor<SavingsGoal>()).first(where: { $0.id == id }), g.updatedAt <= deletedAt { modelContext.delete(g) }
        case "installments": if let i = try modelContext.fetch(FetchDescriptor<Installment>()).first(where: { $0.id == id }), i.updatedAt <= deletedAt { modelContext.delete(i) }
        case "installmentPayments": if let p = try modelContext.fetch(FetchDescriptor<InstallmentPayment>()).first(where: { $0.id == id }), p.updatedAt <= deletedAt { modelContext.delete(p) }
        default: break
        }
        if let existing = try firstTombstone(id: id) {
            if deletedAt > existing.deletedAt { existing.deletedAt = deletedAt }
            existing.collection = collection
        } else {
            modelContext.insert(Tombstone(id: id, collection: collection, deletedAt: deletedAt))
        }
        try modelContext.save()
    }

    // MARK: Private helpers

    /// Returns true if a deletion should block this incoming write. If the write
    /// is newer than the tombstone (record was re-created/edited elsewhere after
    /// deletion), the tombstone is cleared and the write proceeds.
    private func tombstoneBlocks(id: UUID, incoming updatedAt: Date) throws -> Bool {
        guard let tomb = try firstTombstone(id: id) else { return false }
        if tomb.deletedAt >= updatedAt { return true }
        modelContext.delete(tomb)
        return false
    }

    private func firstCategory(id: UUID) throws -> Category? {
        try modelContext.fetch(FetchDescriptor<Category>()).first { $0.id == id }
    }
    private func firstFriend(id: UUID) throws -> Friend? {
        try modelContext.fetch(FetchDescriptor<Friend>()).first { $0.id == id }
    }
    private func firstTxn(id: UUID) throws -> Txn? {
        try modelContext.fetch(FetchDescriptor<Txn>()).first { $0.id == id }
    }
    private func firstDebt(id: UUID) throws -> Debt? {
        try modelContext.fetch(FetchDescriptor<Debt>()).first { $0.id == id }
    }
    private func firstRule(id: UUID) throws -> RecurringRule? {
        try modelContext.fetch(FetchDescriptor<RecurringRule>()).first { $0.id == id }
    }
    private func firstTombstone(id: UUID) throws -> Tombstone? {
        try modelContext.fetch(FetchDescriptor<Tombstone>()).first { $0.id == id }
    }
}
