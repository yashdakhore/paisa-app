import Foundation

/// A cost you pay every month no matter what (rent, WiFi, money sent home…).
struct FixedCost: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var amount: Double
    var categoryId: String
}

/// Suggests a monthly budget: fixed costs first, then the rest of the salary split across everyday categories,
/// keeping a slice for card payoff and savings. Fixed rules, no AI.
enum BudgetSuggest {
    struct Line: Equatable {
        var categoryId: String
        var amount: Double
        var fixed: Double       // part that is a fixed cost
        var reason: String
    }
    struct Result: Equatable {
        var income: Double
        var fixed: Double
        var emis: Double
        var flexible: Double    // income − fixed − EMIs
        var lines: [Line]
        var leftover: Double    // for card payoff and savings
        var note: String
    }

    /// Share of the flexible money for each everyday category (before scaling).
    static let weights: [(String, Double, String)] = [
        ("groceries", 0.30, "home food basics"),
        ("food", 0.13, "eating out and orders"),
        ("transport", 0.13, "travel and fuel"),
        ("bills", 0.06, "electricity, gas, water"),
        ("phone", 0.04, "recharge and internet"),
        ("health", 0.07, "medicines and doctor"),
        ("shopping", 0.09, "clothes and things"),
        ("entertainment", 0.06, "movies, outings, OTT"),
        ("other", 0.12, "everything else"),
    ]

    static func round100(_ v: Double) -> Double { max(0, (v / 100).rounded(.down) * 100) }

    static func suggest(income: Double, fixed: [FixedCost], emis: Double, cardDebt: Double, cardAPR: Double = 42) -> Result {
        var fixedBy: [String: Double] = [:]
        for f in fixed where f.amount > 0 { fixedBy[f.categoryId, default: 0] += f.amount }
        let fixedTotal = fixedBy.values.reduce(0, +)
        let flexible = income - fixedTotal - emis

        // With card debt, keep more back for paying it off.
        let spendShare = cardDebt > 0 ? 0.55 : 0.65
        // Bills and phone get an everyday share only if they aren't already a fixed cost.
        let active = weights.filter { fixedBy[$0.0] == nil || !["bills", "phone"].contains($0.0) }
        let wsum = active.reduce(0) { $0 + $1.1 }
        var lines: [Line] = []
        var ids = Set<String>()
        for (id, w, why) in active {
            let flex = flexible > 0 ? round100(flexible * spendShare * w / wsum) : 0
            let fx = fixedBy[id] ?? 0
            lines.append(Line(categoryId: id, amount: fx + flex, fixed: fx,
                              reason: fx > 0 ? (flex > 0 ? "fixed \(inr(fx)) + \(inr(flex)) for \(why)" : "fixed") : why))
            ids.insert(id)
        }
        // Fixed costs in categories without an everyday share (rent, or one you made).
        for (id, fx) in fixedBy where !ids.contains(id) {
            lines.insert(Line(categoryId: id, amount: fx, fixed: fx, reason: "fixed"), at: 0)
        }
        let budgeted = lines.reduce(0) { $0 + $1.amount }
        let leftover = income - budgeted - emis
        return Result(income: income, fixed: fixedTotal, emis: emis, flexible: flexible, lines: lines, leftover: leftover,
                      note: note(leftover: leftover, flexible: flexible, cardDebt: cardDebt, apr: cardAPR))
    }

    static func note(leftover: Double, flexible: Double, cardDebt: Double, apr: Double) -> String {
        if flexible <= 0 { return "Your fixed costs and EMIs are more than your income. Look for one to cut or lower before anything else." }
        if leftover <= 0 { return "Nothing is left for savings or card payoff. Lower one of the budgets above." }
        if cardDebt > 0 {
            let toCards = round100(leftover * 0.8)
            let safety = leftover - toCards
            if let m = simulatePayoff([(balance: cardDebt, apr: apr)], monthly: toCards, avalanche: true).months {
                return "Put \(inr(toCards)) a month toward your cards: debt-free in about \(m) month\(m == 1 ? "" : "s"). Keep \(inr(safety)) as an emergency fund."
            }
            return "Put \(inr(toCards)) a month toward your cards. That's less than the interest, so try lowering a budget above."
        }
        let save = round100(leftover * 0.6)
        return "Save \(inr(save)) a month for emergencies and goals, and invest \(inr(leftover - save)) (for example a SIP)."
    }
}
