import UIKit
import SwiftData
import UserNotifications
import AppIntents
import FirebaseCore
import KharchaKit

/// App delegate that wires up the shared SwiftData container, runs auto-log
/// catch-up for recurring rules, and (re)syncs local notifications on launch.
final class AppBootstrap: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Configure Firebase if the config is bundled (guarded so unit/UI test
        // hosts without the plist don't crash).
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
        }

        IntentStoreProvider.override(container: AppContainer.shared)
        UNUserNotificationCenter.current().delegate = self

        // Nudge the system to (re)index this app's App Shortcuts + parameters on
        // every launch. Reduces the window after an install/rename/phrase change
        // where Siri hasn't yet picked up the intent metadata.
        KharchaShortcuts.updateAppShortcutParameters()

        // Apply the user's saved currency (falls back to the region default the
        // AmountFormatter already resolves). Shared App Group defaults so the
        // Siri extension can read the same preference.
        if let saved = UserDefaults(suiteName: KharchaContainerFactory.appGroupID)?
            .string(forKey: CurrencyPreference.defaultsKey) {
            AmountFormatter.currencyCode = saved
        }

        Task {
            guard let store = try? IntentStoreProvider.store() else { return }
            try? await store.seedDefaultCategoriesIfNeeded()
            // Merge duplicate categories every launch; run the income-name heuristic
            // only once (so a user's later manual kind change isn't overwritten).
            let defaults = UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard
            let alreadyTagged = defaults.bool(forKey: "kharcha.categoryKindsMigrated")
            try? await store.reconcileCategories(applyIncomeHeuristic: !alreadyTagged)
            defaults.set(true, forKey: "kharcha.categoryKindsMigrated")
            try? await AutoLogRunner.run(store: store, watermark: DefaultsWatermark(), now: Date(), calendar: .current)
            await NotificationScheduler.shared.resync(store: store)
        }

        return true
    }
}

extension AppBootstrap: UNUserNotificationCenterDelegate {
    /// Without this, local notifications scheduled by NotificationScheduler are
    /// silently swallowed while the app is in the foreground (the default
    /// UNUserNotificationCenter behavior). Show them as a banner + sound instead.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// UserDefaults-backed AutoLogWatermark — persists the "last auto-log catch-up"
/// timestamp in the same App Group defaults, under the same key the old inline
/// catch-up loop used. The actual dedup guarantee lives in AutoLogRunner's
/// txnRows() idempotency check; this watermark is only a scan-window optimization.
struct DefaultsWatermark: AutoLogWatermark {
    private static let key = "kharcha.lastAutoLogDate"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard) {
        self.defaults = defaults
    }

    func lastRun() -> Date? {
        defaults.object(forKey: Self.key) as? Date
    }

    func setLastRun(_ date: Date) {
        defaults.set(date, forKey: Self.key)
    }
}
