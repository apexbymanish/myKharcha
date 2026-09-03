import Foundation
import SwiftData

// MARK: - Snapshots (read models for the UI)

public struct InstallmentSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let kind: InstallmentKind
    public let monthlyAmount: Decimal
    public let termCount: Int
    public let dayOfMonth: Int
    public let startDate: Date
    public let categoryID: UUID?
    public let categoryName: String
    public let remindDaysBefore: Int
    public let autoLog: Bool
    public let recordPrincipalAsIncome: Bool
    public let note: String?
    public let isClosed: Bool
    // Derived (from InstallmentMath):
    public let paidAmount: Decimal
    public let remainingAmount: Decimal
    public let paidCount: Int
    public let remainingCount: Int
    public let progress: Double
    public let nextDueDate: Date
    public let isComplete: Bool

    /// Still owed and not closed — the set that feeds the plan and reminders.
    public var isActive: Bool { !isClosed && !isComplete }

    public init(id: UUID, name: String, kind: InstallmentKind, monthlyAmount: Decimal, termCount: Int, dayOfMonth: Int, startDate: Date, categoryID: UUID?, categoryName: String, remindDaysBefore: Int, autoLog: Bool, recordPrincipalAsIncome: Bool, note: String?, isClosed: Bool, paidAmount: Decimal, remainingAmount: Decimal, paidCount: Int, remainingCount: Int, progress: Double, nextDueDate: Date, isComplete: Bool) {
        self.id = id; self.name = name; self.kind = kind; self.monthlyAmount = monthlyAmount
        self.termCount = termCount; self.dayOfMonth = dayOfMonth; self.startDate = startDate
        self.categoryID = categoryID; self.categoryName = categoryName; self.remindDaysBefore = remindDaysBefore
        self.autoLog = autoLog; self.recordPrincipalAsIncome = recordPrincipalAsIncome; self.note = note
        self.isClosed = isClosed; self.paidAmount = paidAmount; self.remainingAmount = remainingAmount
        self.paidCount = paidCount; self.remainingCount = remainingCount; self.progress = progress
        self.nextDueDate = nextDueDate; self.isComplete = isComplete
    }
}

public struct InstallmentPaymentSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let installmentID: UUID
    public let amount: Decimal
    public let date: Date
    public let note: String?
    public let txnID: UUID?
    public init(id: UUID, installmentID: UUID, amount: Decimal, date: Date, note: String?, txnID: UUID?) {
        self.id = id; self.installmentID = installmentID; self.amount = amount
        self.date = date; self.note = note; self.txnID = txnID
    }
}

// MARK: - Sync export records (ids + updatedAt)

public struct InstallmentExport: Sendable, Equatable {
    public let id: UUID; public let name: String; public let kindRaw: String
    public let monthlyAmount: Decimal; public let termCount: Int; public let dayOfMonth: Int
    public let startDate: Date; public let categoryID: UUID?; public let remindDaysBefore: Int
    public let autoLog: Bool; public let recordPrincipalAsIncome: Bool; public let note: String?
    public let isClosed: Bool; public let closedDate: Date?; public let updatedAt: Date
    public init(id: UUID, name: String, kindRaw: String, monthlyAmount: Decimal, termCount: Int, dayOfMonth: Int, startDate: Date, categoryID: UUID?, remindDaysBefore: Int, autoLog: Bool, recordPrincipalAsIncome: Bool, note: String?, isClosed: Bool, closedDate: Date?, updatedAt: Date) {
        self.id = id; self.name = name; self.kindRaw = kindRaw; self.monthlyAmount = monthlyAmount
        self.termCount = termCount; self.dayOfMonth = dayOfMonth; self.startDate = startDate
        self.categoryID = categoryID; self.remindDaysBefore = remindDaysBefore; self.autoLog = autoLog
        self.recordPrincipalAsIncome = recordPrincipalAsIncome; self.note = note; self.isClosed = isClosed
        self.closedDate = closedDate; self.updatedAt = updatedAt
    }
}

public struct InstallmentPaymentExport: Sendable, Equatable {
    public let id: UUID; public let installmentID: UUID; public let amount: Decimal
    public let date: Date; public let note: String?; public let txnID: UUID?; public let updatedAt: Date
    public init(id: UUID, installmentID: UUID, amount: Decimal, date: Date, note: String?, txnID: UUID?, updatedAt: Date) {
        self.id = id; self.installmentID = installmentID; self.amount = amount
        self.date = date; self.note = note; self.txnID = txnID; self.updatedAt = updatedAt
    }
}

extension ExpenseStore {

    // MARK: Create

    /// Create an installment. For a loan with `recordPrincipalAsIncome`, also logs
    /// the borrowed cash (monthly × term) as income on the start date.
    @discardableResult
    public func addInstallment(
        name: String, kind: InstallmentKind, monthlyAmount: Decimal, termCount: Int,
        dayOfMonth: Int, startDate: Date, categoryID: UUID?, remindDaysBefore: Int,
        autoLog: Bool, recordPrincipalAsIncome: Bool, note: String?,
        now: Date = .now, calendar: Calendar = .current
    ) throws -> InstallmentSnapshot {
        guard monthlyAmount > 0 else { throw StoreError.invalidAmount }
        guard termCount > 0 else { throw StoreError.invalidAmount }
        guard (1...31).contains(dayOfMonth) else { throw StoreError.invalidDayOfMonth }

        let inst = Installment(
            name: name, kind: kind, monthlyAmount: monthlyAmount, termCount: termCount,
            dayOfMonth: dayOfMonth, startDate: startDate, categoryID: resolvedCategoryID(categoryID),
            remindDaysBefore: remindDaysBefore, autoLog: autoLog,
            recordPrincipalAsIncome: recordPrincipalAsIncome, note: note
        )
        modelContext.insert(inst)
        try modelContext.save()

        if kind == .loan && recordPrincipalAsIncome {
            _ = try addTxn(amount: monthlyAmount * Decimal(termCount), kind: .income,
                           categoryID: nil, note: name, date: startDate, source: .manual)
        }
        return try snapshot(of: inst, now: now, calendar: calendar)
    }

    // MARK: Read

    public func installments(now: Date = .now, calendar: Calendar = .current) throws -> [InstallmentSnapshot] {
        let payments = try modelContext.fetch(FetchDescriptor<InstallmentPayment>())
        var amountsByID: [UUID: [Decimal]] = [:]
        for p in payments { amountsByID[p.installmentID, default: []].append(p.amount) }
        var catName: [UUID: String] = [:]
        for c in try modelContext.fetch(FetchDescriptor<Category>()) { catName[c.id] = c.name }

        return try modelContext.fetch(FetchDescriptor<Installment>())
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { inst in
                makeSnapshot(inst,
                             status: InstallmentMath.evaluate(
                                monthlyAmount: inst.monthlyAmount, termCount: inst.termCount,
                                dayOfMonth: inst.dayOfMonth, payments: amountsByID[inst.id] ?? [],
                                now: now, calendar: calendar),
                             categoryName: inst.categoryID.flatMap { catName[$0] } ?? "")
            }
    }

    /// Installments that still have a balance and aren't closed — the ones the
    /// Monthly Plan treats as commitments and that generate reminders.
    public func activeInstallments(now: Date = .now, calendar: Calendar = .current) throws -> [InstallmentSnapshot] {
        try installments(now: now, calendar: calendar).filter(\.isActive)
    }

    public func installmentPayments(installmentID: UUID) throws -> [InstallmentPaymentSnapshot] {
        try modelContext.fetch(FetchDescriptor<InstallmentPayment>())
            .filter { $0.installmentID == installmentID }
            .sorted { $0.date > $1.date }
            .map { InstallmentPaymentSnapshot(id: $0.id, installmentID: $0.installmentID, amount: $0.amount, date: $0.date, note: $0.note, txnID: $0.txnID) }
    }

    // MARK: Payments

    /// Record a payment: creates an expense `Txn` (filed under the installment's
    /// category) and appends a linked ledger entry. Auto-completes once paid off.
    @discardableResult
    public func recordInstallmentPayment(installmentID: UUID, amount: Decimal, date: Date, now: Date = .now, calendar: Calendar = .current) throws -> InstallmentSnapshot {
        guard amount > 0 else { throw StoreError.invalidAmount }
        guard let inst = try firstInstallment(id: installmentID) else { throw StoreError.notFound }
        let txnID = try addTxn(amount: amount, kind: .expense, categoryID: resolvedCategoryID(inst.categoryID), note: inst.name, date: date, source: .manual)
        let payment = InstallmentPayment(installmentID: installmentID, amount: amount, date: date, note: nil, txnID: txnID)
        modelContext.insert(payment)
        inst.updatedAt = .now
        try modelContext.save()
        return try snapshot(of: inst, now: now, calendar: calendar)
    }

    /// Pay off the remaining balance in one payment and complete the plan.
    @discardableResult
    public func payoffInstallment(installmentID: UUID, date: Date, now: Date = .now, calendar: Calendar = .current) throws -> InstallmentSnapshot {
        guard let inst = try firstInstallment(id: installmentID) else { throw StoreError.notFound }
        let status = try status(of: inst, now: now, calendar: calendar)
        guard status.remainingAmount > 0 else { return try snapshot(of: inst, now: now, calendar: calendar) }
        return try recordInstallmentPayment(installmentID: installmentID, amount: status.remainingAmount, date: date, now: now, calendar: calendar)
    }

    /// Close without paying (cancelled / forgiven / entered by mistake). No Txn.
    @discardableResult
    public func closeInstallment(installmentID: UUID, now: Date = .now, calendar: Calendar = .current) throws -> InstallmentSnapshot {
        guard let inst = try firstInstallment(id: installmentID) else { throw StoreError.notFound }
        inst.isClosed = true
        inst.closedDate = .now
        inst.updatedAt = .now
        try modelContext.save()
        return try snapshot(of: inst, now: now, calendar: calendar)
    }

    // MARK: Update

    @discardableResult
    public func updateInstallment(
        id: UUID, name: String, monthlyAmount: Decimal, termCount: Int, dayOfMonth: Int,
        categoryID: UUID?, remindDaysBefore: Int, autoLog: Bool, note: String?,
        now: Date = .now, calendar: Calendar = .current
    ) throws -> InstallmentSnapshot {
        guard monthlyAmount > 0, termCount > 0 else { throw StoreError.invalidAmount }
        guard (1...31).contains(dayOfMonth) else { throw StoreError.invalidDayOfMonth }
        guard let inst = try firstInstallment(id: id) else { throw StoreError.notFound }
        inst.name = name; inst.monthlyAmount = monthlyAmount; inst.termCount = termCount
        inst.dayOfMonth = dayOfMonth; inst.categoryID = resolvedCategoryID(categoryID)
        inst.remindDaysBefore = remindDaysBefore; inst.autoLog = autoLog; inst.note = note
        inst.updatedAt = .now
        try modelContext.save()
        return try snapshot(of: inst, now: now, calendar: calendar)
    }

    // MARK: Delete

    /// Delete the plan and its ledger (tombstoned for sync). The expense `Txn`s the
    /// payments created are left in history — the money was really spent.
    public func deleteInstallment(id: UUID) throws {
        guard let inst = try firstInstallment(id: id) else { throw StoreError.notFound }
        for p in try modelContext.fetch(FetchDescriptor<InstallmentPayment>()) where p.installmentID == id {
            recordTombstone(id: p.id, collection: "installmentPayments")
            modelContext.delete(p)
        }
        recordTombstone(id: id, collection: "installments")
        modelContext.delete(inst)
        try modelContext.save()
    }

    /// Delete one ledger entry and reverse the expense it created.
    public func deleteInstallmentPayment(id: UUID) throws {
        guard let p = try firstInstallmentPayment(id: id) else { throw StoreError.notFound }
        if let txnID = p.txnID { try? deleteTxn(txnID: txnID) }
        if let inst = try firstInstallment(id: p.installmentID) { inst.updatedAt = .now }
        recordTombstone(id: id, collection: "installmentPayments")
        modelContext.delete(p)
        try modelContext.save()
    }

    // MARK: Exports

    public func exportInstallments() throws -> [InstallmentExport] {
        try modelContext.fetch(FetchDescriptor<Installment>()).map {
            InstallmentExport(id: $0.id, name: $0.name, kindRaw: $0.kindRaw, monthlyAmount: $0.monthlyAmount,
                              termCount: $0.termCount, dayOfMonth: $0.dayOfMonth, startDate: $0.startDate,
                              categoryID: $0.categoryID, remindDaysBefore: $0.remindDaysBefore, autoLog: $0.autoLog,
                              recordPrincipalAsIncome: $0.recordPrincipalAsIncome, note: $0.note,
                              isClosed: $0.isClosed, closedDate: $0.closedDate, updatedAt: $0.updatedAt)
        }
    }

    public func exportInstallmentPayments() throws -> [InstallmentPaymentExport] {
        try modelContext.fetch(FetchDescriptor<InstallmentPayment>()).map {
            InstallmentPaymentExport(id: $0.id, installmentID: $0.installmentID, amount: $0.amount,
                                     date: $0.date, note: $0.note, txnID: $0.txnID, updatedAt: $0.updatedAt)
        }
    }

    // MARK: Upserts (newest-wins, tombstone-aware — mirrors ExpenseStoreSync)

    public func upsertInstallment(id: UUID, name: String, kindRaw: String, monthlyAmount: Decimal, termCount: Int, dayOfMonth: Int, startDate: Date, categoryID: UUID?, remindDaysBefore: Int, autoLog: Bool, recordPrincipalAsIncome: Bool, note: String?, isClosed: Bool, closedDate: Date?, updatedAt: Date) throws {
        if try installmentTombstoneBlocks(id: id, incoming: updatedAt) { return }
        if let inst = try firstInstallment(id: id) {
            guard updatedAt > inst.updatedAt else { return }
            inst.name = name; inst.kindRaw = kindRaw; inst.monthlyAmount = monthlyAmount
            inst.termCount = termCount; inst.dayOfMonth = dayOfMonth; inst.startDate = startDate
            inst.categoryID = categoryID; inst.remindDaysBefore = remindDaysBefore; inst.autoLog = autoLog
            inst.recordPrincipalAsIncome = recordPrincipalAsIncome; inst.note = note
            inst.isClosed = isClosed; inst.closedDate = closedDate; inst.updatedAt = updatedAt
        } else {
            let inst = Installment(name: name, kind: InstallmentKind(rawValue: kindRaw) ?? .purchase,
                                   monthlyAmount: monthlyAmount, termCount: termCount, dayOfMonth: dayOfMonth,
                                   startDate: startDate, categoryID: categoryID, remindDaysBefore: remindDaysBefore,
                                   autoLog: autoLog, recordPrincipalAsIncome: recordPrincipalAsIncome, note: note)
            inst.id = id; inst.isClosed = isClosed; inst.closedDate = closedDate; inst.updatedAt = updatedAt
            modelContext.insert(inst)
        }
        try modelContext.save()
    }

    public func upsertInstallmentPayment(id: UUID, installmentID: UUID, amount: Decimal, date: Date, note: String?, txnID: UUID?, updatedAt: Date) throws {
        if try installmentTombstoneBlocks(id: id, incoming: updatedAt) { return }
        if let p = try firstInstallmentPayment(id: id) {
            guard updatedAt > p.updatedAt else { return }
            p.installmentID = installmentID; p.amount = amount; p.date = date; p.note = note; p.txnID = txnID; p.updatedAt = updatedAt
        } else {
            let p = InstallmentPayment(installmentID: installmentID, amount: amount, date: date, note: note, txnID: txnID)
            p.id = id; p.updatedAt = updatedAt
            modelContext.insert(p)
        }
        try modelContext.save()
    }

    // MARK: Private helpers

    private func status(of inst: Installment, now: Date, calendar: Calendar) throws -> InstallmentStatus {
        let payments = try modelContext.fetch(FetchDescriptor<InstallmentPayment>())
            .filter { $0.installmentID == inst.id }.map(\.amount)
        return InstallmentMath.evaluate(monthlyAmount: inst.monthlyAmount, termCount: inst.termCount,
                                        dayOfMonth: inst.dayOfMonth, payments: payments, now: now, calendar: calendar)
    }

    private func snapshot(of inst: Installment, now: Date, calendar: Calendar) throws -> InstallmentSnapshot {
        var categoryName = ""
        if let cid = inst.categoryID, let cat = try? modelContext.fetch(FetchDescriptor<Category>()).first(where: { $0.id == cid }) {
            categoryName = cat.name
        }
        return makeSnapshot(inst, status: try status(of: inst, now: now, calendar: calendar), categoryName: categoryName)
    }

    private func makeSnapshot(_ inst: Installment, status s: InstallmentStatus, categoryName: String) -> InstallmentSnapshot {
        InstallmentSnapshot(
            id: inst.id, name: inst.name, kind: inst.kind, monthlyAmount: inst.monthlyAmount,
            termCount: inst.termCount, dayOfMonth: inst.dayOfMonth, startDate: inst.startDate,
            categoryID: inst.categoryID, categoryName: categoryName, remindDaysBefore: inst.remindDaysBefore,
            autoLog: inst.autoLog, recordPrincipalAsIncome: inst.recordPrincipalAsIncome, note: inst.note,
            isClosed: inst.isClosed, paidAmount: s.paidAmount, remainingAmount: s.remainingAmount,
            paidCount: s.paidCount, remainingCount: s.remainingCount, progress: s.progress,
            nextDueDate: s.nextDueDate, isComplete: s.isComplete
        )
    }

    /// Return `categoryID` only if that category still exists, else nil — so a
    /// stale id (deleted category) becomes "uncategorized" instead of throwing.
    private func resolvedCategoryID(_ categoryID: UUID?) -> UUID? {
        guard let categoryID else { return nil }
        let exists = (try? modelContext.fetch(FetchDescriptor<Category>()).contains { $0.id == categoryID }) ?? false
        return exists ? categoryID : nil
    }

    private func installmentTombstoneBlocks(id: UUID, incoming updatedAt: Date) throws -> Bool {
        guard let tomb = try modelContext.fetch(FetchDescriptor<Tombstone>()).first(where: { $0.id == id }) else { return false }
        if tomb.deletedAt >= updatedAt { return true }
        modelContext.delete(tomb)
        return false
    }
    private func firstInstallment(id: UUID) throws -> Installment? {
        try modelContext.fetch(FetchDescriptor<Installment>()).first { $0.id == id }
    }
    private func firstInstallmentPayment(id: UUID) throws -> InstallmentPayment? {
        try modelContext.fetch(FetchDescriptor<InstallmentPayment>()).first { $0.id == id }
    }
}
