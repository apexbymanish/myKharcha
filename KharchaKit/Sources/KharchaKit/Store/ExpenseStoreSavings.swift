import Foundation
import SwiftData

// MARK: - Snapshots (read models for the UI)

public struct SavingsPotSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let note: String?
    public let balance: Decimal
    public init(id: UUID, name: String, note: String?, balance: Decimal) {
        self.id = id; self.name = name; self.note = note; self.balance = balance
    }
}

public struct SavingsEntrySnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let potID: UUID
    public let amount: Decimal
    public let note: String?
    public let date: Date
    public init(id: UUID, potID: UUID, amount: Decimal, note: String?, date: Date) {
        self.id = id; self.potID = potID; self.amount = amount; self.note = note; self.date = date
    }
}

public struct SavingsGoalSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let targetAmount: Decimal
    public let priority: Int
    public init(id: UUID, name: String, targetAmount: Decimal, priority: Int) {
        self.id = id; self.name = name; self.targetAmount = targetAmount; self.priority = priority
    }
}

// MARK: - Sync export records (ids + updatedAt)

public struct SavingsPotExport: Sendable, Equatable {
    public let id: UUID; public let name: String; public let note: String?; public let updatedAt: Date
    public init(id: UUID, name: String, note: String?, updatedAt: Date) {
        self.id = id; self.name = name; self.note = note; self.updatedAt = updatedAt
    }
}
public struct SavingsEntryExport: Sendable, Equatable {
    public let id: UUID; public let potID: UUID; public let amount: Decimal; public let note: String?; public let date: Date; public let updatedAt: Date
    public init(id: UUID, potID: UUID, amount: Decimal, note: String?, date: Date, updatedAt: Date) {
        self.id = id; self.potID = potID; self.amount = amount; self.note = note; self.date = date; self.updatedAt = updatedAt
    }
}
public struct SavingsGoalExport: Sendable, Equatable {
    public let id: UUID; public let name: String; public let targetAmount: Decimal; public let priority: Int; public let updatedAt: Date
    public init(id: UUID, name: String, targetAmount: Decimal, priority: Int, updatedAt: Date) {
        self.id = id; self.name = name; self.targetAmount = targetAmount; self.priority = priority; self.updatedAt = updatedAt
    }
}

extension ExpenseStore {

    // MARK: Pots + ledger

    @discardableResult
    public func addSavingsPot(name: String, note: String?) throws -> SavingsPotSnapshot {
        let pot = SavingsPot(name: name, note: note)
        modelContext.insert(pot)
        try modelContext.save()
        return SavingsPotSnapshot(id: pot.id, name: pot.name, note: pot.note, balance: 0)
    }

    /// All pots with balances derived from their ledgers, name-sorted.
    public func savingsPots() throws -> [SavingsPotSnapshot] {
        let entries = try modelContext.fetch(FetchDescriptor<SavingsEntry>())
        var balances: [UUID: Decimal] = [:]
        for e in entries { balances[e.potID, default: 0] += e.amount }
        return try modelContext.fetch(FetchDescriptor<SavingsPot>())
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { SavingsPotSnapshot(id: $0.id, name: $0.name, note: $0.note, balance: balances[$0.id] ?? 0) }
    }

    public func totalSavings() throws -> Decimal {
        try modelContext.fetch(FetchDescriptor<SavingsEntry>()).reduce(0) { $0 + $1.amount }
    }

    @discardableResult
    public func addSavingsEntry(potID: UUID, amount: Decimal, note: String?, date: Date) throws -> SavingsEntrySnapshot {
        guard amount != 0 else { throw StoreError.invalidAmount }
        let entry = SavingsEntry(potID: potID, amount: amount, note: note, date: date)
        modelContext.insert(entry)
        try modelContext.save()
        return SavingsEntrySnapshot(id: entry.id, potID: entry.potID, amount: entry.amount, note: entry.note, date: entry.date)
    }

    /// A pot's ledger, newest first.
    public func savingsEntries(potID: UUID) throws -> [SavingsEntrySnapshot] {
        try modelContext.fetch(FetchDescriptor<SavingsEntry>())
            .filter { $0.potID == potID }
            .sorted { $0.date > $1.date }
            .map { SavingsEntrySnapshot(id: $0.id, potID: $0.potID, amount: $0.amount, note: $0.note, date: $0.date) }
    }

    public func deleteSavingsEntry(id: UUID) throws {
        guard let e = try firstSavingsEntry(id: id) else { throw StoreError.notFound }
        recordTombstone(id: id, collection: "savingsEntries")
        modelContext.delete(e)
        try modelContext.save()
    }

    public func deleteSavingsPot(id: UUID) throws {
        guard let pot = try firstSavingsPot(id: id) else { throw StoreError.notFound }
        for e in try modelContext.fetch(FetchDescriptor<SavingsEntry>()) where e.potID == id {
            recordTombstone(id: e.id, collection: "savingsEntries")
            modelContext.delete(e)
        }
        recordTombstone(id: id, collection: "savingsPots")
        modelContext.delete(pot)
        try modelContext.save()
    }

    // MARK: Goals

    @discardableResult
    public func addSavingsGoal(name: String, targetAmount: Decimal, priority: Int) throws -> SavingsGoalSnapshot {
        guard targetAmount > 0 else { throw StoreError.invalidAmount }
        let goal = SavingsGoal(name: name, targetAmount: targetAmount, priority: priority)
        modelContext.insert(goal)
        try modelContext.save()
        return SavingsGoalSnapshot(id: goal.id, name: goal.name, targetAmount: goal.targetAmount, priority: goal.priority)
    }

    public func savingsGoals() throws -> [SavingsGoalSnapshot] {
        try modelContext.fetch(FetchDescriptor<SavingsGoal>())
            .sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { SavingsGoalSnapshot(id: $0.id, name: $0.name, targetAmount: $0.targetAmount, priority: $0.priority) }
    }

    public func deleteSavingsGoal(id: UUID) throws {
        guard let g = try firstSavingsGoal(id: id) else { throw StoreError.notFound }
        recordTombstone(id: id, collection: "savingsGoals")
        modelContext.delete(g)
        try modelContext.save()
    }

    // MARK: Exports

    public func exportSavingsPots() throws -> [SavingsPotExport] {
        try modelContext.fetch(FetchDescriptor<SavingsPot>()).map {
            SavingsPotExport(id: $0.id, name: $0.name, note: $0.note, updatedAt: $0.updatedAt)
        }
    }
    public func exportSavingsEntries() throws -> [SavingsEntryExport] {
        try modelContext.fetch(FetchDescriptor<SavingsEntry>()).map {
            SavingsEntryExport(id: $0.id, potID: $0.potID, amount: $0.amount, note: $0.note, date: $0.date, updatedAt: $0.updatedAt)
        }
    }
    public func exportSavingsGoals() throws -> [SavingsGoalExport] {
        try modelContext.fetch(FetchDescriptor<SavingsGoal>()).map {
            SavingsGoalExport(id: $0.id, name: $0.name, targetAmount: $0.targetAmount, priority: $0.priority, updatedAt: $0.updatedAt)
        }
    }

    // MARK: Upserts (newest-wins, tombstone-aware — mirrors ExpenseStoreSync)

    public func upsertSavingsPot(id: UUID, name: String, note: String?, updatedAt: Date) throws {
        if try savingsTombstoneBlocks(id: id, incoming: updatedAt) { return }
        if let p = try firstSavingsPot(id: id) {
            guard updatedAt > p.updatedAt else { return }
            p.name = name; p.note = note; p.updatedAt = updatedAt
        } else {
            let p = SavingsPot(name: name, note: note); p.id = id; p.updatedAt = updatedAt
            modelContext.insert(p)
        }
        try modelContext.save()
    }

    public func upsertSavingsEntry(id: UUID, potID: UUID, amount: Decimal, note: String?, date: Date, updatedAt: Date) throws {
        if try savingsTombstoneBlocks(id: id, incoming: updatedAt) { return }
        if let e = try firstSavingsEntry(id: id) {
            guard updatedAt > e.updatedAt else { return }
            e.potID = potID; e.amount = amount; e.note = note; e.date = date; e.updatedAt = updatedAt
        } else {
            let e = SavingsEntry(potID: potID, amount: amount, note: note, date: date); e.id = id; e.updatedAt = updatedAt
            modelContext.insert(e)
        }
        try modelContext.save()
    }

    public func upsertSavingsGoal(id: UUID, name: String, targetAmount: Decimal, priority: Int, updatedAt: Date) throws {
        if try savingsTombstoneBlocks(id: id, incoming: updatedAt) { return }
        if let g = try firstSavingsGoal(id: id) {
            guard updatedAt > g.updatedAt else { return }
            g.name = name; g.targetAmount = targetAmount; g.priority = priority; g.updatedAt = updatedAt
        } else {
            let g = SavingsGoal(name: name, targetAmount: targetAmount, priority: priority); g.id = id; g.updatedAt = updatedAt
            modelContext.insert(g)
        }
        try modelContext.save()
    }

    // MARK: Private helpers

    private func savingsTombstoneBlocks(id: UUID, incoming updatedAt: Date) throws -> Bool {
        guard let tomb = try modelContext.fetch(FetchDescriptor<Tombstone>()).first(where: { $0.id == id }) else { return false }
        if tomb.deletedAt >= updatedAt { return true }
        modelContext.delete(tomb)
        return false
    }
    private func firstSavingsPot(id: UUID) throws -> SavingsPot? {
        try modelContext.fetch(FetchDescriptor<SavingsPot>()).first { $0.id == id }
    }
    private func firstSavingsEntry(id: UUID) throws -> SavingsEntry? {
        try modelContext.fetch(FetchDescriptor<SavingsEntry>()).first { $0.id == id }
    }
    private func firstSavingsGoal(id: UUID) throws -> SavingsGoal? {
        try modelContext.fetch(FetchDescriptor<SavingsGoal>()).first { $0.id == id }
    }
}
