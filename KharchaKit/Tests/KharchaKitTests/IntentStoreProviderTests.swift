import Testing
import Foundation
import SwiftData
@testable import KharchaKit

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
