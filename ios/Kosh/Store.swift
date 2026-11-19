import Foundation
import Observation
import WidgetKit

/// Holds all data, saves it to the phone, and applies the side effects of entries
/// (a card payment lowers that card's balance, savings raise a goal, and so on).
@Observable
final class KoshStore {
    /// One shared store, so Siri and Shortcut actions see the same data as the app.
    static let shared = KoshStore()

    var data: AppData
    var lastError: String?
    /// Called after each local save (used to sync shortly after a change).
    var onSaved: (() -> Void)?
    private var fromSync = false

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("kosh.json")
    }

    init() {
        if let raw = try? Data(contentsOf: KoshStore.fileURL), let d = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = AppData.merge(AppData.empty(), d)
        } else {
            data = AppData.empty()
            if let plan = KoshStore.bundledStartingPlan() { data = AppData.merge(data, plan) }
            save()
        }
    }

    static func bundledStartingPlan() -> AppData? {
        guard let url = Bundle.main.url(forResource: "starting-plan", withExtension: "json"),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: raw)
    }

    var hasBundledPlan: Bool { KoshStore.bundledStartingPlan() != nil }

    func save() {
        do {
            let raw = try JSONEncoder().encode(data)
            try raw.write(to: KoshStore.fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
        writeWidgetSnapshot()
        if !fromSync { onSaved?() }
    }

    /// Take the merged copy from a sync without triggering another sync.
    func replaceFromSync(_ merged: AppData) {
        fromSync = true
        data = merged
        save()
        fromSync = false
    }

    /// Small summary for the Home Screen widget (only works when the App Group is available).
    private func writeWidgetSnapshot() {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yashdakhore.kosh") else { return }
        let mk = monthKey(Date())
        let ms = data.monthSummary(mk)
        let cu = data.cardUsage()
        struct Snap: Codable { var month: String; var left: Double?; var income: Double; var spent: Double; var budget: Double; var cardPct: Double?; var updated: Date }
        let s = Snap(month: mk, left: ms.incomeKnown ? ms.left : nil, income: ms.income, spent: ms.spent,
                     budget: data.liveCategories.filter { $0.id != "debt" }.reduce(0) { $0 + ($1.budget ?? 0) },
                     cardPct: cu.cards.isEmpty ? nil : cu.pct, updated: Date())
        if let raw = try? JSONEncoder().encode(s) {
            try? raw.write(to: dir.appendingPathComponent("widget.json"), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - generic edits

    private func upsert<T: Syncable>(_ kp: WritableKeyPath<AppData, [T]>, _ item: T) {
        var it = item
        it.updatedAt = nowMillis()
        if let i = data[keyPath: kp].firstIndex(where: { $0.id == it.id }) { data[keyPath: kp][i] = it } else { data[keyPath: kp].append(it) }
    }

    private func tombstone<T: Syncable>(_ kp: WritableKeyPath<AppData, [T]>, _ id: String) {
        if let i = data[keyPath: kp].firstIndex(where: { $0.id == id }) {
            data[keyPath: kp][i].deleted = true
            data[keyPath: kp][i].updatedAt = nowMillis()
        }
    }

    func saveCategory(_ c: Category) { upsert(\.categories, c); save() }
    func deleteCategory(_ id: String) { tombstone(\.categories, id); save() }
    func saveGoal(_ g: Goal) { upsert(\.goals, g); save() }
    func deleteGoal(_ id: String) { tombstone(\.goals, id); save() }
    func saveDebt(_ d: Debt) { upsert(\.debts, d); save() }
    func deleteDebt(_ id: String) { tombstone(\.debts, id); save() }
    func saveInvestment(_ i: Investment) { upsert(\.investments, i); save() }
    func deleteInvestment(_ id: String) { tombstone(\.investments, id); save() }

    func saveSettings(salary: Double?, rule: String) {
        data.settings.salary = salary
        data.settings.rule = rule
        data.settings.updatedAt = nowMillis()
        save()
    }

    // MARK: - entries

    func saveEntry(_ entry: Entry, previous: Entry?) {
        if previous == nil { BudgetAlerts.check(entry, in: data) }
        if let previous { applyEffects(previous, sign: -1) }
        applyEffects(entry, sign: 1)
        upsert(\.entries, entry)
        save()
    }

    func deleteEntry(_ entry: Entry) {
        applyEffects(entry, sign: -1)
        tombstone(\.entries, entry.id)
        save()
    }

    private func applyEffects(_ e: Entry, sign: Double) {
        guard e.applied == true else { return }
        func bump(_ v: Double?, _ mult: Double) -> Double { max(0, (((v ?? 0) + sign * mult * e.amount) * 100).rounded() / 100) }
        if e.type == "expense", let id = e.debtId, let i = data.debts.firstIndex(where: { $0.id == id && $0.isLive }) {
            data.debts[i].balance = bump(data.debts[i].balance, -1); data.debts[i].updatedAt = nowMillis()
        }
        if e.type == "expense", e.debtId == nil, let id = e.cardId, let i = data.debts.firstIndex(where: { $0.id == id && $0.isLive }) {
            data.debts[i].balance = bump(data.debts[i].balance, 1); data.debts[i].updatedAt = nowMillis()
        }
        if e.type == "save", let id = e.goalId, let i = data.goals.firstIndex(where: { $0.id == id && $0.isLive }) {
            data.goals[i].saved = bump(data.goals[i].saved, 1); data.goals[i].updatedAt = nowMillis()
        }
        if e.type == "invest", let id = e.investmentId, let i = data.investments.firstIndex(where: { $0.id == id && $0.isLive }) {
            data.investments[i].invested = bump(data.investments[i].invested, 1)
            data.investments[i].value = bump(data.investments[i].value, 1)
            data.investments[i].updatedAt = nowMillis()
        }
    }

    // MARK: - repeating entries

    var liveRecurring: [Recurring] { data.recurring.filter(\.isLive).sorted { $0.day < $1.day } }

    /// Repeating entries whose day has come this month and that haven't been added or skipped yet.
    func dueRecurring(today: Date = Date()) -> [Recurring] {
        let mk = monthKey(today)
        let day = Parser.cal.component(.day, from: today)
        let monthDays = Parser.cal.range(of: .day, in: .month, for: today)?.count ?? 28
        return liveRecurring.filter { r in
            r.active != false && r.lastAdded != mk && day >= min(Int(r.day), monthDays)
        }
    }

    func saveRecurring(_ r: Recurring) { upsert(\.recurring, r); save() }
    func deleteRecurring(_ id: String) { tombstone(\.recurring, id); save() }

    @discardableResult
    func addRecurring(_ r: Recurring, today: Date = Date()) -> Entry {
        let mk = monthKey(today)
        let monthDays = Parser.cal.range(of: .day, in: .month, for: today)?.count ?? 28
        let d = min(Int(r.day), monthDays)
        var e = Entry(id: newId(), type: r.type, amount: r.amount, date: mk + String(format: "-%02d", d),
                      note: r.note, categoryId: r.categoryId, debtId: r.debtId, goalId: r.goalId, investmentId: r.investmentId,
                      createdAt: ISO8601DateFormatter().string(from: Date()), source: "repeat")
        e.applied = r.debtId != nil || r.goalId != nil || r.investmentId != nil
        var rr = r
        rr.lastAdded = mk
        upsert(\.recurring, rr)
        saveEntry(e, previous: nil)
        return e
    }

    func skipRecurring(_ r: Recurring, today: Date = Date()) {
        var rr = r
        rr.lastAdded = monthKey(today)
        upsert(\.recurring, rr)
        save()
    }

    /// Make an entry repeat every month (on the same day of the month).
    func makeRecurring(from e: Entry) {
        let day = Double(Int(e.date.suffix(2)) ?? 1)
        let r = Recurring(id: newId(), note: (e.note?.isEmpty == false ? e.note! : (data.category(e.categoryId)?.name ?? "Repeat")),
                          type: e.type, amount: e.amount, categoryId: e.categoryId, debtId: e.debtId, goalId: e.goalId,
                          investmentId: e.investmentId, day: day, active: true, lastAdded: monthKey(e.date))
        saveRecurring(r)
    }

    // MARK: - learning

    /// Remember that these words mean this category (from a correction you made).
    @discardableResult
    func learn(from text: String, categoryId: String) -> [String] {
        let words = Parser.learnableWords(text)
        guard !words.isEmpty, data.categories.contains(where: { $0.id == categoryId && $0.isLive }) else { return [] }
        for i in data.categories.indices {
            var c = data.categories[i]
            let before = c.learned ?? []
            if c.id == categoryId {
                c.learned = Array(Set(before + words)).sorted()
            } else {
                c.learned = before.filter { !words.contains($0) }
            }
            if (c.learned ?? []) != before { c.updatedAt = nowMillis(); data.categories[i] = c }
        }
        save()
        return words
    }

    // MARK: - bank SMS inbox

    var liveInbox: [InboxItem] { data.inbox.filter(\.isLive).sorted { ($0.received ?? "") > ($1.received ?? "") } }

    /// Read a bank/card message and queue it for review. Returns nil if it isn't a transaction or is a duplicate.
    @discardableResult
    func addBankMessage(_ text: String, now: Date = Date()) -> InboxItem? {
        guard let t = BankSMS.parse(text, now: now) else { return nil }
        // Banks sometimes send the same alert twice.
        if data.inbox.contains(where: { $0.amount == t.amount && $0.date == t.date && $0.merchant == t.merchant && !($0.received ?? "").isEmpty
            && abs((ISO8601DateFormatter().date(from: $0.received!) ?? .distantPast).timeIntervalSince(now)) < 600 }) { return nil }
        let cat = t.type == "expense" ? (parse(t.merchant).sureCategory ? parse(t.merchant).categoryId : "other") : nil
        var cardId: String? = nil
        if let hint = t.cardHint {
            cardId = data.liveDebts.first { d in d.kind == "card" && (Parser.nameWords(d.name) + (d.keywords ?? [])).contains { $0.lowercased() == hint } }?.id
        }
        let item = InboxItem(id: newId(), type: t.type, amount: t.amount, merchant: t.merchant, date: t.date, categoryId: cat, cardId: cardId,
                             received: ISO8601DateFormatter().string(from: now))
        upsert(\.inbox, item)
        save()
        return item
    }

    @discardableResult
    func confirmInbox(_ item: InboxItem, categoryId: String?) -> Entry {
        var e = Entry(id: newId(), type: item.type, amount: item.amount, date: item.date, note: item.merchant,
                      categoryId: item.type == "expense" ? (categoryId ?? item.categoryId ?? "other") : nil,
                      createdAt: ISO8601DateFormatter().string(from: Date()), source: "bank sms")
        e.cardId = item.type == "expense" ? item.cardId : nil
        e.applied = e.cardId != nil
        if let c = categoryId, c != item.categoryId { learn(from: item.merchant, categoryId: c) }
        tombstone(\.inbox, item.id)
        saveEntry(e, previous: nil)
        return e
    }

    func discardInbox(_ item: InboxItem) { tombstone(\.inbox, item.id); save() }

    // MARK: - credit scores

    static let bureaus = ["CIBIL", "Experian", "Equifax", "CRIF"]
    var liveScores: [CreditScore] { data.scores.filter(\.isLive).sorted { $0.date < $1.date } }
    func saveScore(_ s: CreditScore) { upsert(\.scores, s); save() }
    func deleteScore(_ id: String) { tombstone(\.scores, id); save() }

    func deleteEntries(_ ids: [String]) {
        for id in ids { if let e = data.entries.first(where: { $0.id == id && $0.isLive }) { applyEffects(e, sign: -1); tombstone(\.entries, id) } }
        save()
    }

    // MARK: - parsing context

    private func parseItems() -> (cats: [Parser.Item], debts: [Parser.Item], goals: [Parser.Item], invs: [Parser.Item]) {
        // Saved keywords plus the built-in ones, so new words (like Hinglish) work with existing categories too.
        // A learned word belongs only to the category you taught it, even if another category has it built in.
        var owner: [String: String] = [:]
        for c in data.liveCategories { for w in c.learned ?? [] { owner[w.lowercased()] = c.id } }
        let cats = data.liveCategories.map { c in
            Parser.Item(id: c.id, words: ((c.learned ?? []) + (c.keywords ?? []) + (Parser.defaultKeywords[c.id] ?? []) + Parser.nameWords(c.name))
                .filter { owner[$0.lowercased()] == nil || owner[$0.lowercased()] == c.id })
        }
        let debts = data.liveDebts.map { d in Parser.Item(id: d.id, words: Parser.nameWords(d.name) + (d.keywords ?? [])) }
        let goals = data.liveGoals.map { g in Parser.Item(id: g.id, words: Parser.nameWords(g.name)) }
        let invs = data.liveInvestments.map { i in Parser.Item(id: i.id, words: Parser.nameWords(i.name) + [i.type]) }
        return (cats, debts, goals, invs)
    }

    func parse(_ text: String) -> Parser.Result {
        let i = parseItems()
        return Parser.parse(text, categories: i.cats, debts: i.debts, goals: i.goals, investments: i.invs)
    }

    func parseMany(_ text: String) -> [Parser.Result] {
        let i = parseItems()
        return Parser.parseMany(text, categories: i.cats, debts: i.debts, goals: i.goals, investments: i.invs)
    }

    // MARK: - backup

    func exportFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kosh-backup-\(Parser.iso(Date())).json")
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(data).write(to: url, options: .atomic)
            return url
        } catch {
            lastError = "Couldn't create the backup: \(error.localizedDescription)"
            return nil
        }
    }

    func importBackup(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let raw = try Data(contentsOf: url)
        let incoming = try JSONDecoder().decode(AppData.self, from: raw)
        guard !incoming.categories.isEmpty || !incoming.entries.isEmpty || !incoming.goals.isEmpty else {
            throw NSError(domain: "Kosh", code: 1, userInfo: [NSLocalizedDescriptionKey: "That file isn't a Kosh backup."])
        }
        data = AppData.merge(data, incoming)
        save()
    }

    func loadStartingPlan() {
        if let plan = KoshStore.bundledStartingPlan() { data = AppData.merge(data, plan); save() }
    }

    func eraseAll() {
        data = AppData.empty()
        save()
    }
}
