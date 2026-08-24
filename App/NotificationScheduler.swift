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
        let installments = (try? await store.activeInstallments(now: now, calendar: calendar)) ?? []
        let specs = ReminderPlanner.plan(rules: rules, debts: debts, installments: installments, now: now, calendar: calendar)

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

    /// The Monthly Plan pre-alert: one notification at 9am on the next payday
    /// carrying the plan summary (`body`). The body is composed by the caller —
    /// engine numbers, optionally rephrased by Apple Intelligence. A fixed id so
    /// re-planning replaces the previous alert instead of stacking.
    func schedulePlanSummary(body: String, paydayDay: Int, now: Date = Date(), calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let id = prefix + "plan.summary"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let nextPayday = PayCyclePlanner.cycle(now: now, dayOfMonth: paydayDay, calendar: calendar).next
        let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextPayday) ?? nextPayday

        let content = UNMutableNotificationContent()
        content.title = "Your monthly plan"
        content.body = body
        content.sound = .default
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
