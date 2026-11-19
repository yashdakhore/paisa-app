import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct MoreView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @State private var importing = false
    @State private var confirmErase = false
    @State private var backupURL: URL?
    @State private var speechOnDevice = SpeechRecognizer().onDevice
    @State private var remindersOn = Reminders.enabled
    @State private var budgetAlertsOn = BudgetAlerts.enabled
    @Environment(AppLock.self) private var lock

    var body: some View {
        let s = store.data.settings
        VStack(spacing: 12) {
            Card(padding: 12) {
                Button { router.sheet = .income } label: {
                    ListRow(symbol: "briefcase", title: "Monthly take-home salary", subtitle: s.salary.map { inr($0) } ?? "Not set", chevron: true)
                }.buttonStyle(.plain)
                RowDivider()
                Button { router.sheet = .income } label: {
                    ListRow(symbol: "shield", title: "Reminder on Home", subtitle: (s.rule?.isEmpty == false) ? s.rule! : "None", chevron: true)
                }.buttonStyle(.plain)
            }

            Card(padding: 12) {
                Toggle(isOn: Binding(get: { remindersOn }, set: { on in
                    if on {
                        Task {
                            let ok = await Reminders.enable()
                            remindersOn = ok
                            if ok { Reminders.reschedule(store.data); router.show("Reminders on") }
                            else { router.show("Allow notifications for Kosh in Settings") }
                        }
                    } else { Reminders.disable(); remindersOn = false }
                })) {
                    ListRow(symbol: "bell", title: "Bill reminders", subtitle: "3 days and 1 day before each card or loan due date, and on repeat days")
                }
                .tint(K.brand)
                RowDivider()
                Toggle(isOn: Binding(get: { lock.enabled }, set: { on in
                    lock.setEnabled(on) { ok in
                        if on { router.show(ok ? "\(lock.methodName) lock on" : "\(lock.methodName) isn't set up on this iPhone") }
                    }
                })) {
                    ListRow(symbol: "faceid", title: "Lock with \(lock.methodName)", subtitle: "Ask for \(lock.methodName) each time you open Kosh")
                }
                .tint(K.brand)
                RowDivider()
                Toggle(isOn: Binding(get: { BudgetAlerts.enabled }, set: { on in
                    BudgetAlerts.enabled = on
                    if on { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
                    budgetAlertsOn = on
                })) {
                    ListRow(symbol: "exclamationmark.triangle", title: "Budget alerts", subtitle: "When a category reaches 80% and 100% of its budget")
                }
                .tint(K.brand)
                .id(budgetAlertsOn)
                RowDivider()
                Button { router.sheet = .gmail } label: {
                    ListRow(symbol: "envelope.badge", title: "Connect Gmail",
                            subtitle: GmailService.shared.isConnected ? "On · \(GmailService.shared.email)" : "Bank alert emails land in Kosh automatically", chevron: true)
                }.buttonStyle(.plain)
                RowDivider()
                Button { router.sheet = .smsSetup } label: {
                    ListRow(symbol: "message.badge", title: "Auto-add with Shortcuts", subtitle: "Bank SMS (and email, if not using Connect Gmail)", chevron: true)
                }.buttonStyle(.plain)
                RowDivider()
                Button { router.sheet = .sync } label: {
                    ListRow(symbol: "arrow.triangle.2.circlepath.icloud", title: "Sync between devices",
                            subtitle: SyncService.shared.isSignedIn ? (SyncService.shared.status.isEmpty ? "On · \(SyncService.shared.email)" : SyncService.shared.status) : "Off · keep iPhone, Mac and PC the same",
                            chevron: true)
                }.buttonStyle(.plain)
                RowDivider()
                Button { router.sheet = .recurringList } label: {
                    ListRow(symbol: "arrow.triangle.2.circlepath", title: "Repeating entries", subtitle: store.liveRecurring.isEmpty ? "Rent, recharge, SIP… added each month" : "\(store.liveRecurring.count) set up", chevron: true)
                }.buttonStyle(.plain)
            }

            Card(padding: 12) {
                if let url = backupURL {
                    ShareLink(item: url) {
                        ListRow(symbol: "square.and.arrow.up", title: "Share backup file", subtitle: "Save to Files, AirDrop to your Mac, or send to yourself", chevron: true)
                    }.buttonStyle(.plain)
                } else {
                    Button { backupURL = store.exportFile() } label: {
                        ListRow(symbol: "square.and.arrow.down", title: "Make a backup file", subtitle: "Everything in one file (works with the web app too)", chevron: true)
                    }.buttonStyle(.plain)
                }
                RowDivider()
                Button { importing = true } label: {
                    ListRow(symbol: "square.and.arrow.down.on.square", title: "Restore from backup", subtitle: "Merges with what's on this phone", chevron: true)
                }.buttonStyle(.plain)
                if store.hasBundledPlan {
                    RowDivider()
                    Button { store.loadStartingPlan(); router.show("Starting plan loaded") } label: {
                        ListRow(symbol: "flag", title: "Load starting plan", subtitle: "Budgets, debts and goals set up on your Mac", chevron: true)
                    }.buttonStyle(.plain)
                }
            }

            Card {
                CardHeader(title: "Voice")
                Text("**Spending:** “spent 250 on groceries”, “120 auto yesterday”, “paid 5000 to SBI card”, “saved 2000 for emergency fund”, “got salary 30000”.\n\n**Set up:** “add SBI credit card limit 50000 due on 5th”, “SBI card balance is 8000”, “add bike loan 80000 EMI 3500”, “new goal bike 80000 by June”, “start SIP 2000 in Nifty”, “set food budget 6000”, “my salary is 30000”, “CIBIL score 760”.\n\n**Ask:** “how much can I spend today?”, “how much did I spend on food?”, “can I afford a 15000 phone?”, “how much do I owe?”, “when will I be debt-free?”, “how are my goals?”, “how should I plan my money?”\n\nWith Siri: “Hey Siri, add an expense in Kosh”.")
                    .font(.system(size: 14)).foregroundStyle(K.muted)
                Text(speechOnDevice ? "Speech is recognised on this iPhone." : "This iPhone uses Apple’s speech service for Indian English.")
                    .font(.system(size: 13)).foregroundStyle(K.faint).padding(.top, 10)
            }

            Card {
                CardHeader(title: "About")
                Text("Kosh keeps your data on this iPhone. It never asks for card numbers, account numbers or PAN.").font(.system(size: 14)).foregroundStyle(K.muted)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · native iPhone app").font(.system(size: 13)).foregroundStyle(K.faint).padding(.top, 10)
                Button(role: .destructive) { confirmErase = true } label: { Label("Erase data on this iPhone", systemImage: "trash") }
                    .buttonStyle(SecondaryButton(destructive: true)).padding(.top, 14)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do { try store.importBackup(from: url); router.show("Backup restored") } catch { router.show("Restore failed: \(error.localizedDescription)") }
            case .failure(let e): router.show("Restore failed: \(e.localizedDescription)")
            }
        }
        .confirmationDialog("Erase all Kosh data on this iPhone? Backup files aren't affected.", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { store.eraseAll(); router.show("Data erased") }
        }
        .onChange(of: store.data.entries.count) { _, _ in backupURL = nil }
    }
}
