import Foundation
import SwiftData

extension ExpenseStore {

    // MARK: - Export

    public func exportBackup() throws -> KharchaBackup {
        let categories   = try modelContext.fetch(FetchDescriptor<Category>())
        let txns         = try modelContext.fetch(FetchDescriptor<Txn>())
        let friends      = try modelContext.fetch(FetchDescriptor<Friend>())
        let debts        = try modelContext.fetch(FetchDescriptor<Debt>())
        let pots         = try modelContext.fetch(FetchDescriptor<SavingsPot>())
        let entries      = try modelContext.fetch(FetchDescriptor<SavingsEntry>())
        let goals        = try modelContext.fetch(FetchDescriptor<SavingsGoal>())
        let installments = try modelContext.fetch(FetchDescriptor<Installment>())
        let payments     = try modelContext.fetch(FetchDescriptor<InstallmentPayment>())
        let rules        = try modelContext.fetch(FetchDescriptor<RecurringRule>())

        return KharchaBackup(
            version: 1,
            exportedAt: Date(),
            categories: categories.map {
                .init(id: $0.id, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex,
                      monthlyBudget: $0.monthlyBudget, isFallback: $0.isFallback,
                      kindRaw: $0.kindRaw, updatedAt: $0.updatedAt)
            },
            transactions: txns.map {
                .init(id: $0.id, amount: $0.amount, kindRaw: $0.kindRaw,
                      categoryID: $0.category?.id, note: $0.note, date: $0.date,
                      sourceRaw: $0.sourceRaw, updatedAt: $0.updatedAt)
            },
            friends: friends.map {
                .init(id: $0.id, name: $0.name, phone: $0.phone,
                      photoData: $0.photoData, updatedAt: $0.updatedAt)
            },
            debts: debts.map {
                .init(id: $0.id, friendID: $0.friend?.id, amount: $0.amount,
                      directionRaw: $0.directionRaw, date: $0.date, note: $0.note,
                      dueDate: $0.dueDate, settledAmount: $0.settledAmount,
                      settled: $0.settled, updatedAt: $0.updatedAt)
            },
            savingsPots: pots.map {
                .init(id: $0.id, name: $0.name, note: $0.note, updatedAt: $0.updatedAt)
            },
            savingsEntries: entries.map {
                .init(id: $0.id, potID: $0.potID, amount: $0.amount,
                      note: $0.note, date: $0.date, updatedAt: $0.updatedAt)
            },
            savingsGoals: goals.map {
                .init(id: $0.id, name: $0.name, targetAmount: $0.targetAmount,
                      priority: $0.priority, updatedAt: $0.updatedAt)
            },
            installments: installments.map {
                .init(id: $0.id, name: $0.name, kindRaw: $0.kindRaw,
                      monthlyAmount: $0.monthlyAmount, termCount: $0.termCount,
                      dayOfMonth: $0.dayOfMonth, startDate: $0.startDate,
                      categoryID: $0.categoryID, remindDaysBefore: $0.remindDaysBefore,
                      autoLog: $0.autoLog, recordPrincipalAsIncome: $0.recordPrincipalAsIncome,
                      note: $0.note, isClosed: $0.isClosed, closedDate: $0.closedDate,
                      createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            installmentPayments: payments.map {
                .init(id: $0.id, installmentID: $0.installmentID, amount: $0.amount,
                      date: $0.date, note: $0.note, txnID: $0.txnID, updatedAt: $0.updatedAt)
            },
            recurringRules: rules.map {
                .init(id: $0.id, name: $0.name, amount: $0.amount,
                      categoryID: $0.category?.id, dayOfMonth: $0.dayOfMonth,
                      remindDaysBefore: $0.remindDaysBefore, autoLog: $0.autoLog,
                      updatedAt: $0.updatedAt)
            }
        )
    }

    // MARK: - Import (additive — skips records whose UUID already exists)

    @discardableResult
    public func importBackup(_ backup: KharchaBackup) throws -> Int {
        var count = 0

        // Build lookup of existing categories (needed for Txn/Rule FK resolution)
        var catByID: [UUID: Category] = [:]
        for c in try modelContext.fetch(FetchDescriptor<Category>()) { catByID[c.id] = c }
        let existingCatIDs = Set(catByID.keys)

        // 1. Categories
        for rec in backup.categories where !existingCatIDs.contains(rec.id) {
            let c = Category(name: rec.name, symbol: rec.symbol, colorHex: rec.colorHex,
                             monthlyBudget: rec.monthlyBudget, isFallback: rec.isFallback,
                             kind: CategoryKind(rawValue: rec.kindRaw) ?? .expense)
            c.id = rec.id; c.updatedAt = rec.updatedAt
            modelContext.insert(c)
            catByID[rec.id] = c
            count += 1
        }

        // 2. Transactions
        let existingTxnIDs = Set(try modelContext.fetch(FetchDescriptor<Txn>()).map(\.id))
        for rec in backup.transactions where !existingTxnIDs.contains(rec.id) {
            let t = Txn(amount: rec.amount,
                        kind: TxnKind(rawValue: rec.kindRaw) ?? .expense,
                        category: rec.categoryID.flatMap { catByID[$0] },
                        note: rec.note, date: rec.date,
                        source: TxnSource(rawValue: rec.sourceRaw) ?? .manual)
            t.id = rec.id; t.updatedAt = rec.updatedAt
            modelContext.insert(t)
            count += 1
        }

        // 3. Friends
        var friendByID: [UUID: Friend] = [:]
        for f in try modelContext.fetch(FetchDescriptor<Friend>()) { friendByID[f.id] = f }
        for rec in backup.friends where !friendByID.keys.contains(rec.id) {
            let f = Friend(name: rec.name, phone: rec.phone, photoData: rec.photoData)
            f.id = rec.id; f.updatedAt = rec.updatedAt
            modelContext.insert(f)
            friendByID[rec.id] = f
            count += 1
        }

        // 4. Debts
        let existingDebtIDs = Set(try modelContext.fetch(FetchDescriptor<Debt>()).map(\.id))
        for rec in backup.debts where !existingDebtIDs.contains(rec.id) {
            let d = Debt(friend: rec.friendID.flatMap { friendByID[$0] },
                         amount: rec.amount,
                         direction: DebtDirection(rawValue: rec.directionRaw) ?? .iGave,
                         date: rec.date, note: rec.note, dueDate: rec.dueDate)
            d.id = rec.id; d.settledAmount = rec.settledAmount
            d.settled = rec.settled; d.updatedAt = rec.updatedAt
            modelContext.insert(d)
            count += 1
        }

        // 5. Savings Pots
        let existingPotIDs = Set(try modelContext.fetch(FetchDescriptor<SavingsPot>()).map(\.id))
        for rec in backup.savingsPots where !existingPotIDs.contains(rec.id) {
            let p = SavingsPot(name: rec.name, note: rec.note)
            p.id = rec.id; p.updatedAt = rec.updatedAt
            modelContext.insert(p)
            count += 1
        }

        // 6. Savings Entries
        let existingEntryIDs = Set(try modelContext.fetch(FetchDescriptor<SavingsEntry>()).map(\.id))
        for rec in backup.savingsEntries where !existingEntryIDs.contains(rec.id) {
            let e = SavingsEntry(potID: rec.potID, amount: rec.amount, note: rec.note, date: rec.date)
            e.id = rec.id; e.updatedAt = rec.updatedAt
            modelContext.insert(e)
            count += 1
        }

        // 7. Savings Goals
        let existingGoalIDs = Set(try modelContext.fetch(FetchDescriptor<SavingsGoal>()).map(\.id))
        for rec in backup.savingsGoals where !existingGoalIDs.contains(rec.id) {
            let g = SavingsGoal(name: rec.name, targetAmount: rec.targetAmount, priority: rec.priority)
            g.id = rec.id; g.updatedAt = rec.updatedAt
            modelContext.insert(g)
            count += 1
        }

        // 8. Installments
        let existingInstIDs = Set(try modelContext.fetch(FetchDescriptor<Installment>()).map(\.id))
        for rec in backup.installments where !existingInstIDs.contains(rec.id) {
            let i = Installment(name: rec.name,
                                kind: InstallmentKind(rawValue: rec.kindRaw) ?? .purchase,
                                monthlyAmount: rec.monthlyAmount, termCount: rec.termCount,
                                dayOfMonth: rec.dayOfMonth, startDate: rec.startDate,
                                categoryID: rec.categoryID, remindDaysBefore: rec.remindDaysBefore,
                                autoLog: rec.autoLog, recordPrincipalAsIncome: rec.recordPrincipalAsIncome,
                                note: rec.note)
            i.id = rec.id; i.isClosed = rec.isClosed; i.closedDate = rec.closedDate
            i.createdAt = rec.createdAt; i.updatedAt = rec.updatedAt
            modelContext.insert(i)
            count += 1
        }

        // 9. Installment Payments
        let existingPayIDs = Set(try modelContext.fetch(FetchDescriptor<InstallmentPayment>()).map(\.id))
        for rec in backup.installmentPayments where !existingPayIDs.contains(rec.id) {
            let p = InstallmentPayment(installmentID: rec.installmentID, amount: rec.amount,
                                       date: rec.date, note: rec.note, txnID: rec.txnID)
            p.id = rec.id; p.updatedAt = rec.updatedAt
            modelContext.insert(p)
            count += 1
        }

        // 10. Recurring Rules
        let existingRuleIDs = Set(try modelContext.fetch(FetchDescriptor<RecurringRule>()).map(\.id))
        for rec in backup.recurringRules where !existingRuleIDs.contains(rec.id) {
            let r = RecurringRule(name: rec.name, amount: rec.amount,
                                  category: rec.categoryID.flatMap { catByID[$0] },
                                  dayOfMonth: rec.dayOfMonth,
                                  remindDaysBefore: rec.remindDaysBefore,
                                  autoLog: rec.autoLog)
            r.id = rec.id; r.updatedAt = rec.updatedAt
            modelContext.insert(r)
            count += 1
        }

        try modelContext.save()
        return count
    }

    // MARK: - Delete All Data

    /// Wipes all user data locally and records tombstones for every deleted
    /// record so the next sync push removes them from Firestore too.
    /// Without tombstones a signed-in user would see their data resurrect
    /// from the server on the next foreground pull.
    public func deleteAllData() throws {
        // Collect IDs before deletion so we can tombstone them.
        let txnIDs        = try modelContext.fetch(FetchDescriptor<Txn>()).map(\.id)
        let debtIDs       = try modelContext.fetch(FetchDescriptor<Debt>()).map(\.id)
        let friendIDs     = try modelContext.fetch(FetchDescriptor<Friend>()).map(\.id)
        let potIDs        = try modelContext.fetch(FetchDescriptor<SavingsPot>()).map(\.id)
        let entryIDs      = try modelContext.fetch(FetchDescriptor<SavingsEntry>()).map(\.id)
        let goalIDs       = try modelContext.fetch(FetchDescriptor<SavingsGoal>()).map(\.id)
        let instIDs       = try modelContext.fetch(FetchDescriptor<Installment>()).map(\.id)
        let payIDs        = try modelContext.fetch(FetchDescriptor<InstallmentPayment>()).map(\.id)
        let ruleIDs       = try modelContext.fetch(FetchDescriptor<RecurringRule>()).map(\.id)
        let nonFallbackCatIDs = try modelContext.fetch(FetchDescriptor<Category>())
            .filter { !$0.isFallback }.map(\.id)

        // Batch delete all data.
        try modelContext.delete(model: InstallmentPayment.self)
        try modelContext.delete(model: Installment.self)
        try modelContext.delete(model: Txn.self)
        try modelContext.delete(model: Debt.self)
        try modelContext.delete(model: SavingsEntry.self)
        try modelContext.delete(model: SavingsPot.self)
        try modelContext.delete(model: SavingsGoal.self)
        try modelContext.delete(model: RecurringRule.self)
        try modelContext.delete(model: Friend.self)
        try modelContext.delete(model: Category.self)

        // Tombstone every deleted record so the sync engine can remove
        // them from Firestore on the next pushNow() call.
        for id in txnIDs            { recordTombstone(id: id, collection: "txns") }
        for id in debtIDs           { recordTombstone(id: id, collection: "debts") }
        for id in friendIDs         { recordTombstone(id: id, collection: "friends") }
        for id in potIDs            { recordTombstone(id: id, collection: "savingsPots") }
        for id in entryIDs          { recordTombstone(id: id, collection: "savingsEntries") }
        for id in goalIDs           { recordTombstone(id: id, collection: "savingsGoals") }
        for id in instIDs           { recordTombstone(id: id, collection: "installments") }
        for id in payIDs            { recordTombstone(id: id, collection: "installmentPayments") }
        for id in ruleIDs           { recordTombstone(id: id, collection: "rules") }
        for id in nonFallbackCatIDs { recordTombstone(id: id, collection: "categories") }

        try modelContext.save()
        try seedDefaultCategoriesIfNeeded()
    }
}
