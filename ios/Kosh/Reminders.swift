import Foundation
import UserNotifications

/// Local notifications (no server): 3 days before, 1 day before and on each card/loan due day,
/// plus a nudge on the day a repeating entry is due.
enum Reminders {
    private static let key = "kosh.reminders"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Asks iPhone for permission. Returns true if reminders are on.
    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        enabled = granted
        return granted
    }

    static func disable() {
        enabled = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func reschedule(_ data: AppData) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        for d in data.liveDebts {
            guard let dueD = d.dueDay, dueD >= 1, (d.balance ?? 0) > 0 else { continue }
            let due = Int(dueD)
            for before in [3, 1, 0] where due - before >= 1 {
                let c = UNMutableNotificationContent()
                c.title = before == 0 ? "\(d.name) is due today" : "\(d.name) is due in \(before) day\(before == 1 ? "" : "s")"
                c.body = "Pay it by the \(ordinal(due)) to keep your record clean. Balance in Kosh: \(inr(d.balance))."
                c.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(day: due - before, hour: 10), repeats: true)
                center.add(UNNotificationRequest(identifier: "due-\(d.id)-\(before)", content: c, trigger: trigger))
            }
        }

        for r in data.recurring where r.isLive && r.active != false {
            let c = UNMutableNotificationContent()
            c.title = "\(r.note) · \(inr(r.amount))"
            c.body = "It's due today. Open Kosh to add it with one tap."
            c.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(day: min(28, max(1, Int(r.day))), hour: 9), repeats: true)
            center.add(UNNotificationRequest(identifier: "rec-\(r.id)", content: c, trigger: trigger))
        }
    }
}
