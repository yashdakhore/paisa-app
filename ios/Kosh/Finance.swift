import Foundation

// Money calculations — same rules as the web app's store.js.

let CARDS = "__cards"

func monthKey(_ date: String) -> String { String(date.prefix(7)) }
func monthKey(_ d: Date) -> String { String(Parser.iso(d).prefix(7)) }

struct MonthSummary {
    var entries: [Entry]
    var income: Double
    var incomeKnown: Bool
    var incomeFromEntries: Bool
    var spent: Double
    var saved: Double
    var invested: Double
    var left: Double
    var byCat: [String: Double]
}

struct CardUsage {
    var cards: [Debt]
    var balance: Double
    var limit: Double
    var pct: Double
}

struct GoalStatus {
    var target: Double
    var current: Double
    var remaining: Double
    var progress: Double
    var months: Int
    var perMonth: Double
    var thisMonth: Double
    var done: Bool
}

struct PlanRow {
    var goal: Goal
    var st: GoalStatus
    var want: Double
    var give: Double
}

struct Plan {
    var income: Double
    var incomeKnown: Bool
    var budgeted: Double
    var sips: Double
    var emis: Double
    var free: Double
    var goals: [PlanRow]
    var leftover: Double
}

extension AppData {
    var liveCategories: [Category] { categories.filter(\.isLive).sorted { ($0.order ?? 99) < ($1.order ?? 99) } }
    var liveEntries: [Entry] { entries.filter(\.isLive) }
    var liveGoals: [Goal] { goals.filter(\.isLive).sorted { ($0.priority ?? 99) < ($1.priority ?? 99) } }
    var liveDebts: [Debt] { debts.filter(\.isLive) }
    var liveInvestments: [Investment] { investments.filter(\.isLive) }

    func category(_ id: String?) -> Category? { categories.first { $0.id == id } }

    func monthSummary(_ mk: String) -> MonthSummary {
        let es = liveEntries.filter { monthKey($0.date) == mk }
        let incomeEntries = es.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
        let salary = settings.salary ?? 0
        let income = incomeEntries > 0 ? incomeEntries : salary
        let spent = es.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
        let saved = es.filter { $0.type == "save" }.reduce(0) { $0 + $1.amount }
        let invested = es.filter { $0.type == "invest" }.reduce(0) { $0 + $1.amount }
        var byCat: [String: Double] = [:]
        for e in es where e.type == "expense" { byCat[e.categoryId ?? "other", default: 0] += e.amount }
        return MonthSummary(entries: es, income: income, incomeKnown: income > 0, incomeFromEntries: incomeEntries > 0,
                            spent: spent, saved: saved, invested: invested, left: income - spent - saved - invested, byCat: byCat)
    }

    func cardUsage() -> CardUsage {
        let cards = liveDebts.filter { $0.kind == "card" }
        let balance = cards.reduce(0) { $0 + ($1.balance ?? 0) }
        let limit = cards.reduce(0) { $0 + ($1.limit ?? 0) }
        return CardUsage(cards: cards, balance: balance, limit: limit, pct: limit > 0 ? balance / limit * 100 : 0)
    }

    static func monthsUntil(_ deadline: String?, today: Date = Date()) -> Int {
        guard let deadline, deadline.count >= 7 else { return 12 }
        let parts = deadline.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return 12 }
        let c = Parser.cal.dateComponents([.year, .month], from: today)
        return max(1, (parts[0] - c.year!) * 12 + (parts[1] - c.month!) + 1)
    }

    func goalStatus(_ g: Goal, today: Date = Date()) -> GoalStatus {
        let mk = monthKey(today)
        let monthEntries = liveEntries.filter { monthKey($0.date) == mk }
        var target = 0.0, current = 0.0, remaining = 0.0, progress = 0.0, thisMonth = 0.0
        if g.kind == "save" {
            target = g.target ?? 0
            current = g.saved ?? 0
            remaining = max(0, target - current)
            progress = target > 0 ? current / target : 0
            thisMonth = monthEntries.filter { $0.type == "save" && $0.goalId == g.id }.reduce(0) { $0 + $1.amount }
        } else {
            var debtIds: [String] = []
            if g.debtId == CARDS || g.kind == "cardUsage" {
                let cu = cardUsage()
                current = cu.balance
                debtIds = cu.cards.map(\.id)
                target = g.kind == "cardUsage" ? (cu.limit * (g.targetPct ?? 0) / 100).rounded() : 0
            } else if let d = liveDebts.first(where: { $0.id == g.debtId }) {
                current = d.balance ?? 0
                debtIds = [d.id]
            }
            let start = max(g.startBalance ?? current, current)
            remaining = max(0, current - target)
            progress = start > target ? min(1, max(0, (start - current) / (start - target))) : (remaining == 0 ? 1 : 0)
            thisMonth = monthEntries.filter { $0.type == "expense" && debtIds.contains($0.debtId ?? "") }.reduce(0) { $0 + $1.amount }
        }
        let months = AppData.monthsUntil(g.deadline, today: today)
        let perMonth = remaining == 0 ? 0 : ((remaining + thisMonth) / Double(months)).rounded(.up)
        return GoalStatus(target: target, current: current, remaining: remaining, progress: progress,
                          months: months, perMonth: perMonth, thisMonth: thisMonth, done: remaining == 0)
    }

    func buildPlan(today: Date = Date()) -> Plan {
        let ms = monthSummary(monthKey(today))
        let budgeted = liveCategories.filter { $0.id != "debt" }.reduce(0) { $0 + ($1.budget ?? 0) }
        let sips = liveInvestments.reduce(0) { $0 + ($1.monthly ?? 0) }
        let emis = liveDebts.filter { $0.kind != "card" }.reduce(0) { $0 + ($1.emi ?? 0) }
        let free = ms.income - budgeted - sips - emis
        var pool = free
        var givenTo: [String: Double] = [:]   // goals on the same debt share money
        let rows = liveGoals.map { g -> PlanRow in
            let st = goalStatus(g, today: today)
            let key = g.kind == "save" ? "goal:" + g.id : ((g.kind == "cardUsage" || g.debtId == CARDS) ? CARDS : (g.debtId ?? ""))
            let want = st.done ? 0 : max(0, st.perMonth - st.thisMonth - (givenTo[key] ?? 0))
            let give = max(0, min(want, pool))
            pool -= give
            givenTo[key, default: 0] += want
            return PlanRow(goal: g, st: st, want: want, give: give)
        }
        return Plan(income: ms.income, incomeKnown: ms.incomeKnown, budgeted: budgeted, sips: sips, emis: emis, free: free, goals: rows, leftover: pool)
    }
}

// ₹ with Indian digit grouping: ₹1,23,456
func inr(_ v: Double?) -> String {
    guard let v, v.isFinite else { return "—" }
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_IN")
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    let s = f.string(from: NSNumber(value: abs(v.rounded()))) ?? "\(Int(abs(v)))"
    return (v.rounded() < 0 ? "−" : "") + "₹" + s
}
