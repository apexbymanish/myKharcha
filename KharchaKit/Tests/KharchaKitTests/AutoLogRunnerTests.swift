import Testing
import Foundation
@testable import KharchaKit

/// Simple in-memory stub — mirrors what the app target's UserDefaults-backed
/// AutoLogWatermark does, without touching UserDefaults from KharchaKit tests.
final class TestAutoLogWatermark: AutoLogWatermark {
    private var stored: Date?
    init(_ date: Date? = nil) { stored = date }
    func lastRun() -> Date? { stored }
    func setLastRun(_ date: Date) { stored = date }
}

@Test func autoLogRunnerNoRulesInsertsNothing() async throws {
    let store = try makeStore()
    let watermark = TestAutoLogWatermark(d(2026, 5, 1))
    let now = d(2026, 8, 1)

    let count = try await AutoLogRunner.run(store: store, watermark: watermark, now: now, calendar: testCal)

    #expect(count == 0)
    let txns = try await store.txnRows()
    #expect(txns.isEmpty)
}

@Test func autoLogRunnerCatchesUpMissedOccurrencesAndAdvancesWatermark() async throws {
    let store = try makeStore()
    _ = try await store.addRecurringRule(name: "Rent", amount: 500_000, categoryID: nil, dayOfMonth: 1, remindDaysBefore: 3, autoLog: true)
    let watermark = TestAutoLogWatermark(d(2026, 5, 15))
    let now = d(2026, 7, 20)

    let count = try await AutoLogRunner.run(store: store, watermark: watermark, now: now, calendar: testCal)

    #expect(count == 2) // Jun 1 + Jul 1 occurrences were missed
    let rentTxns = try await store.txnRows().filter { $0.note == "Rent" }
    #expect(rentTxns.count == 2)
    #expect(rentTxns.allSatisfy { $0.amount == 500_000 && $0.kind == .expense })
    #expect(watermark.lastRun() == now)
}

@Test func autoLogRunnerIgnoresRulesWithAutoLogDisabled() async throws {
    let store = try makeStore()
    _ = try await store.addRecurringRule(name: "Netflix", amount: 15_000, categoryID: nil, dayOfMonth: 1, remindDaysBefore: 3, autoLog: false)
    let watermark = TestAutoLogWatermark(d(2026, 5, 15))
    let now = d(2026, 7, 20)

    let count = try await AutoLogRunner.run(store: store, watermark: watermark, now: now, calendar: testCal)

    #expect(count == 0)
    let txns = try await store.txnRows()
    #expect(txns.isEmpty)
}

@Test func autoLogRunnerTwiceWithFreshNilWatermarkInsertsNothingBothTimes() async throws {
    let store = try makeStore()
    _ = try await store.addRecurringRule(name: "Rent", amount: 500_000, categoryID: nil, dayOfMonth: 1, remindDaysBefore: 3, autoLog: true)
    let now = d(2026, 8, 1)

    // Two independent runs, each handed a brand-new watermark whose lastRun() is
    // nil — i.e. "since" falls back to `now` both times, so there's no backfill
    // window to scan. Confirms repeated fresh-install runs are harmless (0, 0),
    // never explode into a giant backfill just because the watermark never persisted.
    let first = try await AutoLogRunner.run(store: store, watermark: TestAutoLogWatermark(nil), now: now, calendar: testCal)
    let second = try await AutoLogRunner.run(store: store, watermark: TestAutoLogWatermark(nil), now: now, calendar: testCal)

    #expect(first == 0)
    #expect(second == 0)
}

@Test func autoLogRunnerIdempotencyNotWatermarkPreventsDuplicateInserts() async throws {
    let store = try makeStore()
    _ = try await store.addRecurringRule(name: "Rent", amount: 500_000, categoryID: nil, dayOfMonth: 1, remindDaysBefore: 3, autoLog: true)
    let now = d(2026, 7, 20)
    let staleSince = d(2026, 5, 15)

    let first = try await AutoLogRunner.run(store: store, watermark: TestAutoLogWatermark(staleSince), now: now, calendar: testCal)
    #expect(first == 2)

    // Second run gets a brand-new watermark instance still reporting the SAME
    // stale lastRun (as if the watermark write never persisted) — so the runner
    // recomputes the identical Jun+Jul occurrence window. It must be the txnRows
    // idempotency check, not the watermark, that prevents re-inserting them.
    let second = try await AutoLogRunner.run(store: store, watermark: TestAutoLogWatermark(staleSince), now: now, calendar: testCal)
    #expect(second == 0)

    let rentTxns = try await store.txnRows().filter { $0.note == "Rent" }
    #expect(rentTxns.count == 2)
}
