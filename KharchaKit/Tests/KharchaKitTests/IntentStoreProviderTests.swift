import Testing
import Foundation
import SwiftData
@testable import KharchaKit

/// `IntentStoreProvider` caches a single process-wide `ModelContainer`. Every
/// test in this file (and `IntentPerformTests.swift`, see its extension of
/// this suite) calls `.override(container:)`/`.reset()` on that same global,
/// so they must never run concurrently with each other — hence `.serialized`.
@Suite(.serialized)
struct IntentGlobalStateTests {
    @Test func overriddenProviderSharesOneContainer() async throws {
        let container = try KharchaContainerFactory.inMemory()
        IntentStoreProvider.override(container: container)
        defer { IntentStoreProvider.reset() }

        let storeA = try IntentStoreProvider.store()
        let id = try await storeA.addTxn(amount: 500, kind: .expense, categoryID: nil, note: nil, date: .now, source: .siri)

        let storeB = try IntentStoreProvider.store()
        let rows = try await storeB.txnRows()
        #expect(rows.contains { $0.id == id })
    }
}
