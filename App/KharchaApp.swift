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
    let sync: SyncEngine

    init() {
        let store = ExpenseStore(modelContainer: AppContainer.shared)
        self.store = store
        self.sync = SyncEngine(store: store)
    }
}

@main
struct KharchaApp: App {
    @UIApplicationDelegateAdaptor(AppBootstrap.self) private var bootstrap
    @StateObject private var services = AppServices()
    @StateObject private var signIn = SignInManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services)
                .environmentObject(signIn)
                .onOpenURL { url in
                    // Universal Link from doc.dynamc.link — the app is already
                    // open or has just been launched. No additional navigation
                    // needed for the basic share flow. Add routing here when
                    // deep-link paths (e.g. /invite/CODE) are introduced.
                    _ = url
                }
        }
    }
}
