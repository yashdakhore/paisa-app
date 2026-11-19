import Foundation

/// Every bank transaction gets one of six kinds before anything else:
///   expense  Spent   — counts against your budget
///   income   Earned  — your income
///   move     Moved   — your money changing place (cash, own accounts, card bills): not counted
///   held     Held    — someone else's money passing through you, tracked in a pot
///   owed     Owed    — lent to / paid back by a friend
///   save     Saved
/// Kosh suggests a kind with a reason. When it's sure (a rule you taught it, a person you labelled, a known shop,
/// salary, cash), it adds the transaction by itself; otherwise it waits on Home for you.
extension KoshStore {
    static let kinds: [(id: String, name: String)] = [("expense", "Spent"), ("income", "Earned"), ("move", "Moved"),
                                                      ("held", "Held"), ("owed", "Lent / repaid")]
    static func kindName(_ id: String) -> String { kinds.first { $0.id == id }?.name ?? "Spent" }

    static func payeeKey(_ name: String) -> String {
        name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static let companyWords: Set<String> = ["pvt", "private", "ltd", "limited", "llp", "inc", "enterprises", "enterprise", "store", "stores",
        "mart", "shop", "traders", "trading", "services", "service", "bank", "communications", "technologies", "tech", "pay", "payments", "foods",
        "food", "restaurant", "cafe", "medical", "medicals", "petroleum", "fuel", "agency", "agencies", "industries", "solutions", "retail",
        "money", "received", "card", "upi", "payment", "bill", "kirana", "general", "hotel", "dhaba", "center", "centre", "and", "co"]

    /// "Rohit Vijay Varma" yes; "Mdk Enterprises", "Iocl", "Money received" no.
    func looksLikePerson(_ name: String) -> Bool {
        let words = Self.payeeKey(name).split(separator: " ").map(String.init)
        guard (2...4).contains(words.count), words.allSatisfy({ $0.allSatisfy(\.isLetter) }) else { return false }
        if words.contains(where: { Self.companyWords.contains($0) }) { return false }
        return !parse(name).sureCategory
    }

    // MARK: people

    var livePeople: [Person] { data.people.filter(\.isLive).sorted { $0.name < $1.name } }

    /// The person behind a payee name: same name, a saved spelling, or every word of their name in it
    /// ("Sanskar Dakhore" matches "SANSKAR PARAGRAO DAKHORE").
    func person(for payee: String) -> Person? {
        let key = Self.payeeKey(payee)
        let words = Set(key.split(separator: " ").map(String.init))
        return livePeople.first { p in
            ([p.name] + (p.aliases ?? [])).contains { n in
                let k = Self.payeeKey(n)
                let w = k.split(separator: " ").map(String.init).filter { $0.count >= 3 }
                return k == key || (w.count >= 2 && w.allSatisfy { words.contains($0) })
            }
        }
    }

    /// Answer to "Who is …?". Re-sorts anything waiting from the same person.
    @discardableResult
    func setRole(_ payee: String, role: String) -> Person {
        var p = person(for: payee) ?? Person(id: newId(), name: payee.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " "), role: role)
        p.role = role
        if Self.payeeKey(p.name) != Self.payeeKey(payee), !(p.aliases ?? []).contains(payee) { p.aliases = (p.aliases ?? []) + [payee] }
        upsert(\.people, p)
        // Everything waiting from this person is re-sorted, and added straight away where Kosh is now sure.
        for var item in data.inbox where item.isLive && person(for: item.merchant)?.id == p.id {
            let sure = classify(&item, text: item.merchant)
            upsert(\.inbox, item)
            if sure, item.maybeDuplicate != true, data.settings.autoAdd != false { confirmInbox(item) }
        }
        resortGuesses(for: p)
        save()
        return p
    }

    /// Lent minus paid back: positive = they owe you.
    func owedBalance(_ personId: String) -> Double {
        data.liveEntries.filter { $0.type == "owed" && $0.personId == personId }.reduce(0) { $0 + ($1.flow == "in" ? -$1.amount : $1.amount) }
    }

    // MARK: pots (held money)

    var openPots: [Pot] { data.pots.filter { $0.isLive && $0.closed != true } }

    func potIn(_ id: String) -> Double { data.liveEntries.filter { $0.type == "held" && $0.potId == id && $0.flow == "in" }.reduce(0) { $0 + $1.amount } }
    func potOut(_ id: String) -> Double { data.liveEntries.filter { $0.type == "held" && $0.potId == id && $0.flow != "in" }.reduce(0) { $0 + $1.amount } }
    func potLeft(_ id: String) -> Double { potIn(id) - potOut(id) }

    @discardableResult
    func createPot(_ name: String, personId: String? = nil) -> Pot {
        let p = Pot(id: newId(), name: name, personId: personId)
        upsert(\.pots, p); save()
        return p
    }

    /// "Dad said keep the rest": what's left becomes your income (Family) and the pot closes.
    func keepRest(_ potId: String) {
        let left = potLeft(potId)
        guard var pot = data.pots.first(where: { $0.id == potId }) else { return }
        if left > 0 {
            let today = Parser.iso(Date())
            var out = Entry(id: newId(), type: "held", amount: left, date: today, note: "Kept from \(pot.name)", createdAt: ISO8601DateFormatter().string(from: Date()))
            out.flow = "out"; out.potId = potId
            upsert(\.entries, out)
            var inc = Entry(id: newId(), type: "income", amount: left, date: today, note: "Kept from \(pot.name)", createdAt: ISO8601DateFormatter().string(from: Date()))
            inc.incomeSource = "family"
            upsert(\.entries, inc)
        }
        pot.closed = true
        upsert(\.pots, pot); save()
    }

    func closePot(_ potId: String) {
        guard var pot = data.pots.first(where: { $0.id == potId }) else { return }
        pot.closed = true; upsert(\.pots, pot); save()
    }

    // MARK: guesses (zero-review)

    var guesses: [Entry] { data.liveEntries.filter { $0.guess == true }.sorted { $0.date > $1.date } }

    /// The bank alert an entry came from, as an inbox item, so the classifier can look at it again.
    func item(from e: Entry) -> InboxItem {
        let flowIn = e.type == "income" || e.flow == "in"
        var it = InboxItem(id: "e-" + e.id, type: flowIn ? "income" : "expense", amount: e.amount, merchant: e.note ?? "", date: e.date,
                           categoryId: e.type == "expense" ? (e.categoryId ?? "other") : nil, cardId: e.cardId)
        it.incomeSource = flowIn ? AppData.guessIncomeSource(e.note ?? "", myName: data.settings.myName, familyNames: data.settings.familyNames ?? []) : nil
        return it
    }

    /// "That's not right": re-file an entry as another kind/category/source/pot. Kosh remembers it for that payee.
    func correct(_ e: Entry, kind: String, categoryId: String? = nil, incomeSource: String? = nil, potId: String? = nil, learn rememberIt: Bool = true) {
        let flowIn = e.type == "income" || e.flow == "in"
        var n = e
        n.type = kind
        n.categoryId = nil; n.incomeSource = nil; n.flow = nil; n.potId = nil
        n.cardId = kind == "expense" ? e.cardId : nil
        switch kind {
        case "expense": n.categoryId = categoryId ?? (e.type == "expense" ? e.categoryId : nil) ?? "other"
        case "income": n.incomeSource = incomeSource ?? AppData.guessIncomeSource(e.note ?? "", myName: data.settings.myName, familyNames: data.settings.familyNames ?? [])
        case "held": n.flow = flowIn ? "in" : "out"; n.potId = potId
        case "owed": n.flow = flowIn ? "in" : "out"; n.personId = e.personId ?? person(for: e.note ?? "")?.id ?? setRole(e.note ?? "Someone", role: "friend").id
        default: n.type = "move"; n.flow = flowIn ? "in" : "out"
        }
        n.applied = n.cardId != nil ? e.applied : false
        n.guess = nil; n.reason = nil; n.askWho = nil
        if rememberIt, let note = e.note, e.source == "bank sms" {
            if n.type == "expense", n.categoryId != e.categoryId { learn(from: note, categoryId: n.categoryId ?? "other") }
            saveRule(note, kind: n.type, categoryId: n.type == "expense" ? n.categoryId : nil, incomeSource: n.type == "income" ? n.incomeSource : nil)
        }
        saveEntry(n, previous: e)
    }

    /// Zero-review mode: anything still waiting (from before, or synced in) is added as a guess.
    func flushInbox() {
        guard data.settings.autoAdd != false, data.settings.zeroReview != false else { return }
        for item in data.inbox where item.isLive {
            if var e = confirmInbox(item) { e.guess = true; e.reason = item.reason; e.askWho = item.askWho; upsert(\.entries, e) }
        }
        save()
    }

    /// "Looks right": stop showing it as a guess.
    func acceptGuess(_ e: Entry) { var n = e; n.guess = nil; n.askWho = nil; upsert(\.entries, n); save() }

    /// After you say who someone is, their guessed entries are sorted again.
    func resortGuesses(for p: Person) {
        for e in guesses where person(for: e.note ?? "")?.id == p.id {
            var it = item(from: e)
            let sure = classify(&it, text: it.merchant)
            if sure {
                correct(e, kind: it.kind ?? e.type, categoryId: it.categoryId, incomeSource: it.incomeSource, potId: it.potId, learn: false)
            } else {
                var n = e; n.reason = it.reason; n.askWho = it.askWho; upsert(\.entries, n)
            }
        }
        save()
    }

    // MARK: rules

    func rule(for payee: String) -> PayeeRule? { data.rules.first { $0.isLive && $0.id == Self.payeeKey(payee) } }

    func saveRule(_ payee: String, kind: String, categoryId: String?, incomeSource: String?) {
        let key = Self.payeeKey(payee)
        guard !key.isEmpty, !["money received", "card upi payment", "cash deposit", "atm withdrawal"].contains(key) else { return }
        upsert(\.rules, PayeeRule(id: key, kind: kind, categoryId: categoryId, incomeSource: incomeSource))
    }

    func setAutoAdd(_ on: Bool) { data.settings.autoAdd = on; data.settings.updatedAt = nowMillis(); save() }
    func setReviewMode(_ mode: String) {
        data.settings.autoAdd = mode != "all"
        data.settings.zeroReview = mode == "none"
        data.settings.updatedAt = nowMillis(); save()
    }
    func deleteRule(_ id: String) { tombstone(\.rules, id); save() }
    func deletePerson(_ id: String) { tombstone(\.people, id); save() }

    func ensureFamilyCategory() {
        guard !data.categories.contains(where: { $0.id == "family" && $0.isLive }) else { return }
        upsert(\.categories, Category(id: "family", name: "Family & gifts", icon: nil, budget: 0,
                                       keywords: ["family", "gift", "gifts", "mom", "dad", "papa", "mummy", "ghar"], order: 10.5))
    }

    /// Payments below this to or from someone new are added without asking.
    var smallLimit: Double { data.settings.smallLimit ?? 200 }

    // MARK: the classifier

    /// Sets item.kind (+ category/source/pot/person), a short reason, and whether Kosh is sure.
    /// Returns true when sure (then it can be added without asking).
    @discardableResult
    func classify(_ item: inout InboxItem, text: String) -> Bool {
        let flowIn = item.type == "income"
        item.askWho = nil
        item.potId = nil
        func set(_ kind: String, _ reason: String, sure: Bool) -> Bool { item.kind = kind; item.reason = reason; return sure }

        if item.type == "payment" { return set("expense", "Card bill payment: lowers what you owe on the card", sure: true) }

        if item.isCash == true {
            if flowIn, item.amount >= 10_000 {
                return set("move", "Cash deposit. Yours, or money you're holding for someone?", sure: false)
            }
            return set("move", flowIn ? "Cash deposited: your own money, not income" : "ATM cash: counted when you spend it", sure: true)
        }

        if let r = rule(for: item.merchant) {
            if r.kind == "expense", let c = r.categoryId { item.categoryId = c }
            if r.kind == "income" { item.incomeSource = r.incomeSource ?? item.incomeSource }
            if r.kind == "held" {
                // Held money goes to the open pot if there's exactly one; otherwise ask which.
                if openPots.count == 1 { item.potId = openPots[0].id } else { return set("held", "Held money: pick which pot", sure: false) }
            }
            if r.kind == "owed" { item.personId = person(for: item.merchant)?.id }
            return set(r.kind, "You told Kosh how to treat \(item.merchant)", sure: true)
        }

        if let p = person(for: item.merchant) {
            item.personId = p.id
            let name = p.name.split(separator: " ").first.map(String.init) ?? p.name
            switch p.role {
            case "me":
                return set("move", "Between your own accounts", sure: true)
            case "family":
                if flowIn {
                    item.incomeSource = "family"
                    if item.amount >= 10_000 { return set("income", "Big amount from \(name). Yours to keep, or holding it for someone?", sure: false) }
                    return set("income", "\(name) is family: counted as Family income", sure: true)
                }
                if let pot = openPots.first(where: { potLeft($0.id) > 0 }) {
                    item.potId = pot.id
                    return set("held", "To \(name): from \(pot.name)? (\(inr(potLeft(pot.id))) still held)", sure: false)
                }
                ensureFamilyCategory(); item.categoryId = "family"
                return set("expense", "Sent to \(name) (family)", sure: true)
            case "friend":
                if flowIn, owedBalance(p.id) > 0 { return set("owed", "\(name) paying you back (owes \(inr(owedBalance(p.id))))", sure: true) }
                return set(flowIn ? "income" : "owed", flowIn ? "From your friend \(name)" : "To your friend \(name): lent, or your share of something?", sure: false)
            case "landlord":
                if !flowIn { item.categoryId = "rent"; return set("expense", "Rent to \(name)", sure: true) }
                return set("income", "From your landlord \(name)", sure: false)
            case "shop":
                if !flowIn {
                    let c = parse(item.merchant)
                    if c.sureCategory, let id = c.categoryId { item.categoryId = id; return set("expense", "\(p.name) is a shop: \(data.category(id)?.name ?? "spent")", sure: true) }
                    return set("expense", "\(p.name) is a shop: pick a category", sure: false)
                }
                return set("income", "Refund from \(p.name)?", sure: false)
            default:
                break
            }
        }

        if flowIn {
            let src = item.incomeSource ?? "other"
            if src == "salary" { return set("income", "Your salary", sure: true) }
            if src == "refund" { return set("income", "Refund or cashback from a company", sure: true) }
            if src == "interest" { return set("income", "Bank interest", sure: true) }
            if looksLikePerson(item.merchant) {
                if item.amount < smallLimit { return set("income", "Small amount from \(item.merchant): counted as Other", sure: true) }
                item.askWho = true; return set("income", "Money from \(item.merchant). Who is this?", sure: false)
            }
            if src == "family" { return set("income", "Shares your surname: counted as Family", sure: item.amount < 10_000) }
            return set("income", "Money in from \(item.merchant)", sure: false)
        }

        // Money out
        if (item.categoryId ?? "other") != "other" {
            return set("expense", "\(item.merchant) is \(data.category(item.categoryId)?.name ?? "spending")", sure: true)
        }
        if looksLikePerson(item.merchant) {
            // Not worth a question: small payments to someone new are just spending (change it once if not, and Kosh remembers).
            if item.amount < smallLimit { return set("expense", "Small payment to \(item.merchant): counted as Other", sure: true) }
            item.askWho = true; return set("expense", "Sent to \(item.merchant). Who is this?", sure: false)
        }
        return set("expense", "New shop or service: pick a category", sure: false)
    }
}
