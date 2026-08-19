import UIKit
import SwiftData
import UserNotifications
import KharchaKit

/// App delegate that wires up the shared SwiftData container, runs auto-log
/// catch-up for recurring rules, and (re)syncs local notifications on launch.
final class AppBootstrap: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        IntentStoreProvider.override(container: AppContainer.shared)
        UNUserNotificationCenter.current().delegate = self

        Task {
            guard let store = try? IntentStoreProvider.store() else { return }
            try? await store.seedDefaultCategoriesIfNeeded()
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
