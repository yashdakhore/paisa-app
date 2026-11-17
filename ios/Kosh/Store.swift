import Foundation
import Observation

/// Holds all data, saves it to the phone, and applies the side effects of entries
/// (a card payment lowers that card's balance, savings raise a goal, and so on).
@Observable
final class KoshStore {
    var data: AppData
    var lastError: String?

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
        if e.type == "save", let id = e.goalId, let i = data.goals.firstIndex(where: { $0.id == id && $0.isLive }) {
            data.goals[i].saved = bump(data.goals[i].saved, 1); data.goals[i].updatedAt = nowMillis()
        }
        if e.type == "invest", let id = e.investmentId, let i = data.investments.firstIndex(where: { $0.id == id && $0.isLive }) {
            data.investments[i].invested = bump(data.investments[i].invested, 1)
            data.investments[i].value = bump(data.investments[i].value, 1)
            data.investments[i].updatedAt = nowMillis()
        }
    }

    // MARK: - parsing context

    func parse(_ text: String) -> Parser.Result {
        let cats = data.liveCategories.map { c in Parser.Item(id: c.id, words: (c.keywords ?? Parser.defaultKeywords[c.id] ?? []) + Parser.nameWords(c.name)) }
        let debts = data.liveDebts.map { d in Parser.Item(id: d.id, words: Parser.nameWords(d.name) + (d.keywords ?? [])) }
        let goals = data.liveGoals.map { g in Parser.Item(id: g.id, words: Parser.nameWords(g.name)) }
        let invs = data.liveInvestments.map { i in Parser.Item(id: i.id, words: Parser.nameWords(i.name) + [i.type]) }
        return Parser.parse(text, categories: cats, debts: debts, goals: goals, investments: invs)
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
