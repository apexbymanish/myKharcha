import Foundation

/// Where AutoLogRunner reads/writes the "last time we caught up" timestamp.
/// Kept as a protocol so KharchaKit stays free of UserDefaults/App Group concerns —
/// the app target supplies a concrete `UserDefaults`-backed implementation.
public protocol AutoLogWatermark {
    func lastRun() -> Date?
    func setLastRun(_ date: Date)
}

/// Inserts one expense per missed `autoLog` recurring-rule occurrence since the
/// watermark was last advanced. Idempotent by construction: before inserting for a
/// given occurrence, it checks whether a txn with the same note and the same
/// start-of-day date already exists, and skips it if so. This means the watermark
/// is an optimization (avoids rescanning all history every launch) — correctness
/// (no duplicate auto-logged expenses) is guaranteed by the idempotency check, not
/// by the watermark. Do not remove the txnRows() dedup check even though the
/// watermark also narrows the search window.
public enum AutoLogRunner {
    @discardableResult
    public static func run(store: ExpenseStore, watermark: AutoLogWatermark, now: Date, calendar: Calendar) async throws -> Int {
        let rules = try await store.recurringRules().filter(\.autoLog)
        let autoInstallments = try await store.activeInstallments(now: now, calendar: calendar).filter(\.autoLog)
        guard !rules.isEmpty || !autoInstallments.isEmpty else {
            watermark.setLastRun(now)
            return 0
        }

        let since = watermark.lastRun() ?? now
        let existing = try await store.txnRows()
        var insertedCount = 0

        for rule in rules {
            let occurrences = AutoLogCatchUp.dueOccurrences(dayOfMonth: rule.dayOfMonth, since: since, now: now, calendar: calendar)
            for occurrence in occurrences {
                let alreadyLogged = existing.contains {
                    $0.note == rule.name && calendar.isDate($0.date, inSameDayAs: occurrence)
                }
                guard !alreadyLogged else { continue }

                _ = try await store.addTxn(
                    amount: rule.amount, kind: .expense, categoryID: nil,
                    note: rule.name, date: occurrence, source: .manual
                )
                insertedCount += 1
            }
        }

        // Auto-log installments the same way: one recorded payment per missed due
        // date, bounded by the remaining term. Idempotent via the per-installment
        // ledger (a due date already in the ledger is skipped), independent of the
        // watermark — mirroring the rule dedup above.
        for inst in autoInstallments {
            let ledger = try await store.installmentPayments(installmentID: inst.id)
            var remainingToRecord = inst.remainingCount
            let occurrences = AutoLogCatchUp.dueOccurrences(dayOfMonth: inst.dayOfMonth, since: since, now: now, calendar: calendar)
            for occurrence in occurrences {
                guard remainingToRecord > 0 else { break }
                let alreadyPaid = ledger.contains { calendar.isDate($0.date, inSameDayAs: occurrence) }
                guard !alreadyPaid else { continue }

                _ = try await store.recordInstallmentPayment(
                    installmentID: inst.id, amount: inst.monthlyAmount, date: occurrence, now: now, calendar: calendar
                )
                insertedCount += 1
                remainingToRecord -= 1
            }
        }

        // Only advance the watermark once every insert above succeeded (no thrown
        // error escaped this function before reaching here) — errors propagate to
        // the caller and the watermark is left where it was, so the next run
        // re-scans the same window instead of silently skipping missed occurrences.
        watermark.setLastRun(now)
        return insertedCount
    }
}
