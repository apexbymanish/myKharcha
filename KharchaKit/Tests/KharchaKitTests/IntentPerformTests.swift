import Testing
import Foundation
@testable import KharchaKit

// These share `IntentGlobalStateTests` (defined in IntentStoreProviderTests.swift)
// because they all mutate the `IntentStoreProvider` process-wide singleton via
// `.override(container:)`/`.reset()`. Without `.serialized` on that suite, Swift
// Testing's default concurrent scheduling interleaves these calls across threads
// and corrupts each other's in-memory container (observed: cross-test data
// bleed and an out-of-bounds crash) — see task-9-report.md.
extension IntentGlobalStateTests {
    @Test func logExpenseIntentPerformSaves() async throws {
        IntentStoreProvider.override(container: try KharchaContainerFactory.inMemory())
        defer { IntentStoreProvider.reset() }

        let intent = LogExpenseIntent()
        intent.amount = 12000
        intent.note = "lunch"
        _ = try await intent.perform()

        let store = try IntentStoreProvider.store()
        let rows = try await store.txnRows()
        #expect(rows.count == 1)
        #expect(rows[0].amount == 12_000)
        #expect(rows[0].source == .siri)
    }

    @Test func logIncomeIntentPerformSaves() async throws {
        IntentStoreProvider.override(container: try KharchaContainerFactory.inMemory())
        defer { IntentStoreProvider.reset() }

        let intent = LogIncomeIntent()
        intent.amount = 3_000_000
        _ = try await intent.perform()

        let store = try IntentStoreProvider.store()
        let rows = try await store.txnRows()
        #expect(rows.first?.kind == .income)
    }

    @Test func spendingQueryIntentPerformDoesNotThrowOnEmptyStore() async throws {
        IntentStoreProvider.override(container: try KharchaContainerFactory.inMemory())
        defer { IntentStoreProvider.reset() }
        let intent = SpendingQueryIntent()
        _ = try await intent.perform()  // default period .today, empty store → "haven't spent anything"
    }
}
