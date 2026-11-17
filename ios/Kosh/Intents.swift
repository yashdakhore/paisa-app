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
