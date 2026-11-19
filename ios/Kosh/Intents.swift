import AppIntents

/// "Hey Siri, add an expense in Kosh" → Siri asks what you spent → Kosh opens with it filled in.
struct AddEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Add an expense"
    static var description = IntentDescription("Say what you spent, like “250 on groceries”, and Kosh fills in the entry for you to check.")
    static var openAppWhenRun = true

    @Parameter(title: "What did you spend?", requestValueDialog: "What did you spend?")
    var phrase: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingEntry.shared.text = phrase
        return .result()
    }
}

/// For a Shortcuts automation: "When I get a message containing 'debited' → Add bank message to Kosh".
/// Runs in the background and puts the transaction in Kosh's review list.
struct AddBankMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Add bank message"
    static var description = IntentDescription("Reads a bank or card SMS or email (amount, merchant, date) and adds it to Kosh for you to confirm. Card and account numbers are not stored.")
    static var openAppWhenRun = false

    @Parameter(title: "Message")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let item = KoshStore.shared.addBankMessage(message) {
            BudgetAlerts.notifyInbox(item)
            return .result(dialog: "Kosh: \(inr(item.amount)) \(item.type == "income" ? "from " : item.type == "payment" ? "· " : "at ")\(item.merchant) is ready to review.")
        }
        return .result(dialog: "Kosh: no transaction found in that message.")
    }
}

struct KoshShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddEntryIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Log spending in \(.applicationName)",
                "Add to \(.applicationName)",
            ],
            shortTitle: "Add expense",
            systemImageName: "mic.fill"
        )
    }
}
