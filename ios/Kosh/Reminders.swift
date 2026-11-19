import Foundation
import UserNotifications

/// Shows Kosh's notifications even while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

/// "Food & Dining: ₹2,000 of ₹2,500 used" when a category passes 80% or 100% of its budget.
enum BudgetAlerts {
    private static let key = "kosh.budgetAlerts"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func check(_ e: Entry, in d: AppData) {
        guard enabled, e.type == "expense", let cid = e.categoryId, cid != "debt",
              let c = d.categories.first(where: { $0.id == cid }), let budget = c.budget, budget > 0,
              monthKey(e.date) == monthKey(Date()) else { return }
        let before = d.spent(in: monthKey(e.date), category: cid)
        let after = before + e.amount
        for t in [1.0, 0.8] where before < budget * t && after >= budget * t {
            let title = t >= 1 ? "\(c.name) is over budget" : "\(c.name) is at \(Int(after / budget * 100))% of budget"
            send(id: "budget-\(cid)-\(Int(t * 100))", title: title,
                 body: "\(inr(after)) of \(inr(budget)) used this month" + (t >= 1 ? "." : ", \(inr(budget - after)) left."))
            break
        }
    }

    static func notifyInbox(_ item: InboxItem) {
        send(id: "inbox-\(item.id)", title: "\(inr(item.amount)) \(item.type == "income" ? "received" : "· " + item.merchant)",
             body: "Open Kosh to confirm or change the category.")
    }

    private static func send(id: String, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}

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

        // Monthly summary on the 1st.
        let sc = UNMutableNotificationContent()
        sc.title = "Your monthly summary is ready"
        sc.body = "See where last month's money went, debt paid, goals and credit scores."
        sc.sound = .default
        center.add(UNNotificationRequest(identifier: "summary", content: sc,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(day: 1, hour: 9), repeats: true)))

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
