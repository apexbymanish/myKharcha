import UIKit
import SwiftData
import KharchaKit

/// App delegate that wires up the shared SwiftData container, runs auto-log
/// catch-up for recurring rules, and (re)syncs local notifications on launch.
final class AppBootstrap: NSObject, UIApplicationDelegate {
    private static let lastAutoLogDateKey = "kharcha.lastAutoLogDate"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let container: ModelContainer
        do {
            container = try KharchaContainerFactory.appGroup()
        } catch {
            // Dev fallback — e.g. running without the App Group entitlement provisioned.
            print("Kharcha: App Group container unavailable (\(error)); falling back to local on-disk store.")
            do {
                container = try KharchaContainerFactory.localOnDisk()
            } catch {
                fatalError("Kharcha: unable to create any ModelContainer: \(error)")
            }
        }
        IntentStoreProvider.override(container: container)

        Task {
            guard let store = try? IntentStoreProvider.store() else { return }
            try? await store.seedDefaultCategoriesIfNeeded()
            await Self.runAutoLogCatchUp(store: store)
            await NotificationScheduler.shared.resync(store: store)
        }

        return true
    }

    /// Logs the transactions for any recurring-rule occurrences that fell due
    /// while the app wasn't running (only for rules with `autoLog` enabled).
    private static func runAutoLogCatchUp(store: ExpenseStore, now: Date = Date(), calendar: Calendar = .current) async {
        let defaults = UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard
        let lastDate = defaults.object(forKey: lastAutoLogDateKey) as? Date
        let since = lastDate ?? now

        guard let rules = try? await store.recurringRules() else { return }
        for rule in rules where rule.autoLog {
            let occurrences = AutoLogCatchUp.dueOccurrences(dayOfMonth: rule.dayOfMonth, since: since, now: now, calendar: calendar)
            for occurrence in occurrences {
                _ = try? await store.addTxn(
                    amount: rule.amount, kind: .expense, categoryID: nil,
                    note: rule.name, date: occurrence, source: .manual
                )
            }
        }

        defaults.set(now, forKey: lastAutoLogDateKey)
    }
}
