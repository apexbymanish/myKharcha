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
    let updateChecker = AppUpdateChecker()

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
                .environmentObject(services.updateChecker)
                .onOpenURL { _ in
                    // Universal Link from jebkharcha-7e514.web.app/kharcha —
                    // app is already open or launching. No extra navigation
                    // needed for the basic share flow.
                }
        }
    }
}
