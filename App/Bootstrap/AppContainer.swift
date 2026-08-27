import SwiftData
import KharchaKit

/// Single source of truth for the app's shared `ModelContainer`. Computed once,
/// lazily, the first time anything touches `AppContainer.shared` — both
/// `AppBootstrap` (which installs it into `IntentStoreProvider` for the Siri
/// intents) and `AppServices` (which builds the `ExpenseStore` the SwiftUI
/// screens use) read from this single value, so there's exactly one container
/// for the whole process. Do not let `AppServices` construct its own fallback
/// container — that used to create a second, disconnected in-memory store if
/// `IntentStoreProvider` hadn't been populated yet.
enum AppContainer {
    static let shared: ModelContainer = {
        do {
            return try KharchaContainerFactory.appGroup()
        } catch {
            // Dev fallback — e.g. running without the App Group entitlement provisioned.
            print("Kharcha: App Group container unavailable (\(error)); falling back to local on-disk store.")
            do {
                return try KharchaContainerFactory.localOnDisk()
            } catch {
                // spec §8: the app must still function, not crash — last resort is an
                // in-memory container (data won't persist across launches, but the UI
                // and intents stay usable for this session).
                print("Kharcha: local on-disk store unavailable (\(error)); falling back to in-memory (non-persistent) store.")
                do {
                    return try KharchaContainerFactory.inMemory()
                } catch {
                    fatalError("Kharcha: unable to create any ModelContainer, including in-memory: \(error)")
                }
            }
        }
    }()
}
