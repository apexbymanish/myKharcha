import Foundation
import SwiftData

/// One shared container for every intent invocation (and injectable for tests/app).
public enum IntentStoreProvider {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: ModelContainer?

    public static func store() throws -> ExpenseStore {
        lock.lock(); defer { lock.unlock() }
        if cached == nil { cached = try KharchaContainerFactory.appGroup() }
        return ExpenseStore(modelContainer: cached!)
    }

    public static func override(container: ModelContainer) {
        lock.lock(); defer { lock.unlock() }
        cached = container
    }

    public static func reset() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
    }
}
