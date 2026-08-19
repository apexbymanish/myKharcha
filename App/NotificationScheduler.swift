import Foundation
import UserNotifications
import KharchaKit

/// Applies ReminderPlanner output to UNUserNotificationCenter. App-side only — the math is in KharchaKit.
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let prefix = "kharcha."

    /// True when the user has explicitly denied notification permission — used to
    /// surface a "reminders won't fire" notice in the UI instead of failing silently.
    static func authorizationDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    func resync(store: ExpenseStore, now: Date = Date(), calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let rules = (try? await store.recurringRules()) ?? []
        let debts = (try? await store.openDebts()) ?? []
        let specs = ReminderPlanner.plan(rules: rules, debts: debts, now: now, calendar: calendar)

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        for spec in specs {
            let content = UNMutableNotificationContent()
            content.title = spec.title
            content.body = spec.body
            content.sound = .default
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: spec.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + spec.id, content: content, trigger: trigger))
        }
    }
}
