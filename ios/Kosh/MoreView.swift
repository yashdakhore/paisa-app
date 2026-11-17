import SwiftUI
import UniformTypeIdentifiers

struct MoreView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @State private var importing = false
    @State private var confirmErase = false
    @State private var backupURL: URL?
    @State private var speechOnDevice = SpeechRecognizer().onDevice

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
                Text("Tap the orange mic and say things like “spent 250 on groceries”, “paid 9000 rent”, “120 auto yesterday”, “paid 5000 to SBI card”, “saved 2000 for emergency fund” or “got salary 30000”.\n\nWith Siri: say “Hey Siri, add an expense in Kosh”, then what you spent.")
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
