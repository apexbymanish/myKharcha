import SwiftUI
import SwiftData
import KharchaKit

/// Single shared environment object exposing the `ExpenseStore` that wraps
/// `AppContainer.shared` — the same container `AppBootstrap` installs into
/// `IntentStoreProvider` for the Siri intents, so every screen and every intent
/// read/write through the exact same underlying store. No fallback branch here:
/// `AppContainer.shared` already resolves appGroup → localOnDisk → inMemory
/// (and `fatalError`s only if none of those work), so there's nothing left for
/// this initializer to catch.
@MainActor
final class AppServices: ObservableObject {
    let store: ExpenseStore

    init() {
        store = ExpenseStore(modelContainer: AppContainer.shared)
    }
}

@main
struct KharchaApp: App {
    @UIApplicationDelegateAdaptor(AppBootstrap.self) private var bootstrap
    @StateObject private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services)
        }
    }
}
