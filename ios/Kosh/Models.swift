import Foundation

// Same JSON shape as the Kosh web app, so backup files move freely between the two.

protocol Syncable: Codable, Identifiable {
    var id: String { get }
    var updatedAt: Double? { get set }
    var deleted: Bool? { get set }
}

extension Syncable {
    var isLive: Bool { deleted != true }
}

struct AppSettings: Codable, Equatable {
    var salary: Double?
    var rule: String?
    var updatedAt: Double?
    var myName: String?         // money you send to yourself (another of your accounts) isn't spending
    var fixedCosts: [FixedCost]? // what you pay every month no matter what (from Suggest my budget)
}

struct Category: Syncable, Hashable {
    var id: String
    var name: String
    var icon: String?
    var budget: Double?
    var keywords: [String]?
    var order: Double?
    var updatedAt: Double?
    var deleted: Bool?
    var learned: [String]?      // words Kosh learned from your corrections; they win over built-in words
}

enum EntryType: String, CaseIterable, Identifiable {
    case expense, income, save, invest
    var id: String { rawValue }
    var label: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .save: return "Saving to a goal"
        case .invest: return "Investment"
        }
    }
}

struct Entry: Syncable, Hashable {
    var id: String
    var type: String
    var amount: Double
    var date: String            // YYYY-MM-DD
    var note: String?
    var categoryId: String?
    var debtId: String?
    var goalId: String?
    var investmentId: String?
    var createdAt: String?
    var source: String?
    var applied: Bool?
    var updatedAt: Double?
    var deleted: Bool?
    var cardId: String?         // paid with this credit card: the purchase adds to the card's balance
    var txnKey: String?         // scrambled bank reference / fingerprint, so one transaction is never added twice
    var gmailId: String?        // the alert email it came from
}

/// A transaction read from a bank/card SMS, waiting for you to confirm.
struct InboxItem: Syncable, Hashable {
    var id: String
    var type: String            // expense | income | payment (credit card bill paid)
    var amount: Double
    var merchant: String
    var date: String
    var categoryId: String?
    var cardId: String?
    var received: String?
    var maybeDuplicate: Bool?   // same amount and day as one already seen (e.g. both the SMS and the email arrived)
    var txnKey: String?
    var gmailId: String?
    var backfill: Bool?         // from a month fetch: already part of the card balances you entered
    var updatedAt: Double?
    var deleted: Bool?
}

struct Goal: Syncable, Hashable {
    var id: String
    var name: String
    var kind: String            // save | debt | cardUsage
    var target: Double?
    var saved: Double?
    var debtId: String?
    var targetPct: Double?
    var startBalance: Double?
    var deadline: String?       // YYYY-MM
    var priority: Double?
    var updatedAt: Double?
    var deleted: Bool?
}

struct Debt: Syncable, Hashable {
    var id: String
    var name: String
    var kind: String            // card | loan | emi
    var balance: Double?
    var limit: Double?
    var emi: Double?
    var rate: Double?
    var dueDay: Double?
    var keywords: [String]?
    var note: String?
    var updatedAt: Double?
    var deleted: Bool?
}

struct Investment: Syncable, Hashable {
    var id: String
    var name: String
    var type: String
    var monthly: Double?
    var invested: Double?
    var value: Double?
    var maturity: String?
    var note: String?
    var updatedAt: Double?
    var deleted: Bool?
}

/// A monthly repeating entry (rent, recharge, SIP...). Kosh offers to add it each month on `day`.
struct Recurring: Syncable, Hashable {
    var id: String
    var note: String
    var type: String
    var amount: Double
    var categoryId: String?
    var debtId: String?
    var goalId: String?
    var investmentId: String?
    var day: Double
    var active: Bool?
    var lastAdded: String?      // YYYY-MM it was last added or skipped
    var updatedAt: Double?
    var deleted: Bool?
}

/// A credit score from one bureau on one date (CIBIL, Experian, Equifax or CRIF; 300–900).
struct CreditScore: Syncable, Hashable {
    var id: String
    var bureau: String
    var score: Double
    var date: String            // YYYY-MM-DD
    var note: String?
    var updatedAt: Double?
    var deleted: Bool?
}

struct AppData: Codable {
    var settings = AppSettings(salary: nil, rule: nil, updatedAt: 0)
    var categories: [Category] = []
    var entries: [Entry] = []
    var investments: [Investment] = []
    var goals: [Goal] = []
    var debts: [Debt] = []
    var recurring: [Recurring] = []
    var scores: [CreditScore] = []
    var inbox: [InboxItem] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings(salary: nil, rule: nil, updatedAt: 0)
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        investments = try c.decodeIfPresent([Investment].self, forKey: .investments) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        debts = try c.decodeIfPresent([Debt].self, forKey: .debts) ?? []
        recurring = try c.decodeIfPresent([Recurring].self, forKey: .recurring) ?? []
        scores = try c.decodeIfPresent([CreditScore].self, forKey: .scores) ?? []
        inbox = try c.decodeIfPresent([InboxItem].self, forKey: .inbox) ?? []
    }

    static let defaultCategories: [(String, String)] = [
        ("rent", "Rent"), ("bills", "Electricity & Bills"), ("groceries", "Groceries"), ("food", "Food & Dining"),
        ("transport", "Transport"), ("phone", "Phone & Internet"), ("shopping", "Shopping"), ("health", "Health"),
        ("entertainment", "Entertainment"), ("debt", "Card/Loan Payments"), ("other", "Other"),
    ]

    static func empty() -> AppData {
        var d = AppData()
        d.categories = defaultCategories.enumerated().map { i, c in
            Category(id: c.0, name: c.1, icon: nil, budget: 0, keywords: Parser.defaultKeywords[c.0] ?? [], order: Double(i), updatedAt: 0, deleted: nil)
        }
        return d
    }

    /// Item-by-item merge: the newest edit of each item wins; deletions are kept as tombstones.
    static func merge(_ a: AppData, _ b: AppData) -> AppData {
        func m<T: Syncable>(_ x: [T], _ y: [T]) -> [T] {
            var order: [String] = []
            var map: [String: T] = [:]
            for it in x + y {
                if let cur = map[it.id] {
                    if (it.updatedAt ?? 0) > (cur.updatedAt ?? 0) { map[it.id] = it }
                } else {
                    map[it.id] = it
                    order.append(it.id)
                }
            }
            return order.compactMap { map[$0] }
        }
        var out = AppData()
        out.settings = (b.settings.updatedAt ?? 0) > (a.settings.updatedAt ?? 0) ? b.settings : a.settings
        out.categories = m(a.categories, b.categories)
        out.entries = m(a.entries, b.entries)
        out.investments = m(a.investments, b.investments)
        out.goals = m(a.goals, b.goals)
        out.debts = m(a.debts, b.debts)
        out.recurring = m(a.recurring, b.recurring)
        out.scores = m(a.scores, b.scores)
        out.inbox = m(a.inbox, b.inbox)
        return out
    }
}

func nowMillis() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

func newId() -> String {
    String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(UUID().uuidString.prefix(6)).lowercased()
}
