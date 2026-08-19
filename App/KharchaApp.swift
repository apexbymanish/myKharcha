import SwiftUI
import SwiftData
import KharchaKit

/// Single shared environment object exposing the `ExpenseStore` that
/// `AppBootstrap` already installed into `IntentStoreProvider` (synchronously,
/// in `application(_:didFinishLaunchingWithOptions:)`, before this object is
/// created) — every screen reads/writes through the same container the Siri
/// intents use.
@MainActor
final class AppServices: ObservableObject {
    let store: ExpenseStore

    init() {
        if let store = try? IntentStoreProvider.store() {
            self.store = store
        } else {
            // Should be unreachable — AppBootstrap installs a container
            // (falling back all the way to in-memory) before the first Scene
            // is built. Kept only so the UI never force-unwraps.
            print("Kharcha: IntentStoreProvider had no container at app launch; using a throwaway in-memory store.")
            do {
                let container = try KharchaContainerFactory.inMemory()
                self.store = ExpenseStore(modelContainer: container)
            } catch {
                fatalError("Kharcha: unable to create even an in-memory ModelContainer: \(error)")
            }
        }
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
