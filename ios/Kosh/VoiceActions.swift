import Foundation

/// What a spoken command will do (shown before saving), doing it, and answering questions from your own numbers.
struct CommandPreview {
    var title: String
    var lines: [String]
    var canSave: Bool
    var problem: String?
}

extension KoshStore {
    // MARK: finding things by name

    private static let generic: Set<String> = ["card", "credit", "bank", "loan", "emi", "the", "my", "first", "goal", "fund", "sip"]

    /// Best card/loan for "sbi", "home loan", "idfc first"…: most shared name words wins.
    func findDebt(_ query: String, kind: String? = nil) -> Debt? {
        let q = Set(query.lowercased().split(separator: " ").map(String.init))
        func words(_ d: Debt) -> Set<String> {
            Set((d.name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) + (d.keywords ?? []).map { $0.lowercased() }).filter { !$0.isEmpty })
        }
        let pool = data.liveDebts.filter { kind == nil || (kind == "card" ? $0.kind == "card" : $0.kind != "card") }
        let scored = pool.map { d -> (Debt, Int) in
            let w = words(d)
            let strong = q.subtracting(Self.generic).filter { qw in w.contains(qw) || w.contains { $0.hasPrefix(qw) && qw.count >= 3 } }.count
            return (d, strong * 10 + q.intersection(w).count)
        }.filter { $0.1 >= 10 }
        if let best = scored.max(by: { $0.1 < $1.1 }) { return best.0 }
        // "my card" with only one card.
        if q.subtracting(Self.generic).isEmpty, pool.count == 1 { return pool[0] }
        return nil
    }

    func findGoal(_ query: String) -> Goal? {
        let q = query.lowercased()
        return data.liveGoals.first { $0.name.lowercased() == q }
            ?? Parser.bestMatch(q, data.liveGoals.map { Parser.Item(id: $0.id, words: Parser.nameWords($0.name).map { $0.lowercased() }) })
                .flatMap { m in data.liveGoals.first { $0.id == m.id } }
    }

    func findCategory(_ query: String) -> Category? {
        guard let m = Parser.bestMatch(" " + query.lowercased() + " ", parseItems().cats) else { return nil }
        return data.liveCategories.first { $0.id == m.id }
    }

    // MARK: preview

    func preview(_ c: VoiceCommand) -> CommandPreview {
        func money(_ v: Double?) -> String { v.map(inr) ?? "—" }
        switch c {
        case let .card(name, limit, balance, due, rate):
            let existing = findDebt(name, kind: "card")
            var lines = ["Limit: \(money(limit ?? existing?.limit))", "Balance now: \(money(balance ?? existing?.balance ?? 0))"]
            if let d = due ?? existing?.dueDay.map(Int.init) { lines.append("Bill due: \(ordinal(d)) of each month") }
            if let r = rate ?? existing?.rate { lines.append("Interest: \(Parser.fmt(r))% a year") }
            return CommandPreview(title: existing == nil ? "Add card · \(name)" : "Update \(existing!.name)", lines: lines, canSave: true)
        case let .loan(name, kind, balance, emi, due, rate):
            let existing = findDebt(name, kind: "loan")
            var lines = ["Left to repay: \(money(balance ?? existing?.balance))"]
            if let e = emi ?? existing?.emi { lines.append("EMI: \(inr(e)) a month") }
            if let d = due ?? existing?.dueDay.map(Int.init) { lines.append("Due: \(ordinal(d)) of each month") }
            if let r = rate ?? existing?.rate { lines.append("Interest: \(Parser.fmt(r))% a year") }
            return CommandPreview(title: existing == nil ? "Add \(kind == "loan" ? "loan" : "EMI") · \(name)" : "Update \(existing!.name)", lines: lines,
                                  canSave: balance != nil || emi != nil || existing != nil,
                                  problem: balance == nil && emi == nil ? "Say how much is left or the EMI, e.g. “bike loan 80000 EMI 3500”." : nil)
        case let .debtUpdate(query, balance, limit, due):
            guard let d = findDebt(query) else {
                return CommandPreview(title: "Update a card or loan", lines: [], canSave: false,
                                      problem: "No card or loan called “\(query)”. Add it first, e.g. “add \(query) credit card limit 50000”.")
            }
            var lines: [String] = []
            if let b = balance { lines.append("Balance: \(money(d.balance)) → \(inr(b))") }
            if let l = limit { lines.append("Limit: \(money(d.limit)) → \(inr(l))") }
            if let due { lines.append("Due: \(ordinal(due)) of each month") }
            return CommandPreview(title: "Update \(d.name)", lines: lines, canSave: !lines.isEmpty, problem: lines.isEmpty ? "Say the new balance or limit." : nil)
        case let .goal(name, target, deadline):
            let existing = findGoal(name)
            var lines = ["Target: \(inr(target))"]
            if let dl = deadline ?? existing?.deadline {
                let months = AppData.monthsUntil(dl)
                lines.append("By \(monthTitle(dl)) · about \(inr((max(0, target - (existing?.saved ?? 0)) / Double(months)).rounded(.up))) a month")
            }
            return CommandPreview(title: existing == nil ? "New goal · \(name)" : "Update goal · \(existing!.name)", lines: lines, canSave: true)
        case let .investment(name, type, monthly, amount):
            var lines = ["Type: \(type)"]
            if let m = monthly { lines.append("\(inr(m)) every month") }
            if let a = amount { lines.append("Amount: \(inr(a))") }
            return CommandPreview(title: "Add investment · \(name)", lines: lines, canSave: monthly != nil || amount != nil,
                                  problem: monthly == nil && amount == nil ? "Say an amount, e.g. “start SIP 2000 in Nifty”." : nil)
        case let .budget(query, amount):
            guard let cat = findCategory(query) else {
                return CommandPreview(title: "Set a budget", lines: [], canSave: false, problem: "No category called “\(query)”. Try food, shopping, transport, bills…")
            }
            return CommandPreview(title: "\(cat.name) budget", lines: ["\(money(cat.budget)) → \(inr(amount)) a month"], canSave: true)
        case let .salary(v):
            return CommandPreview(title: "Monthly take-home salary", lines: ["\(money(data.settings.salary)) → \(inr(v))"], canSave: true)
        case let .score(bureau, score):
            return CommandPreview(title: "\(bureau) score", lines: ["\(score) on \(shortDate(Parser.iso(Date())))"], canSave: (300...900).contains(score))
        case let .question(q):
            return CommandPreview(title: "Answer", lines: [answer(q)], canSave: false)
        }
    }

    // MARK: do it

    /// Saves the command and returns a short confirmation.
    @discardableResult
    func perform(_ c: VoiceCommand) -> String {
        switch c {
        case let .card(name, limit, balance, due, rate):
            var d = findDebt(name, kind: "card") ?? Debt(id: newId(), name: name, kind: "card", balance: 0)
            if let limit { d.limit = limit }
            if let balance { d.balance = balance }
            if let due { d.dueDay = Double(due) }
            if let rate { d.rate = rate }
            saveDebt(d)
            return "Saved \(d.name)"
        case let .loan(name, kind, balance, emi, due, rate):
            var d = findDebt(name, kind: "loan") ?? Debt(id: newId(), name: name, kind: kind)
            if let balance { d.balance = balance }
            if let emi { d.emi = emi }
            if let due { d.dueDay = Double(due) }
            if let rate { d.rate = rate }
            saveDebt(d)
            return "Saved \(d.name)"
        case let .debtUpdate(query, balance, limit, due):
            guard var d = findDebt(query) else { return "Couldn't find that card or loan" }
            if let balance { d.balance = balance }
            if let limit { d.limit = limit }
            if let due { d.dueDay = Double(due) }
            saveDebt(d)
            return "Updated \(d.name)"
        case let .goal(name, target, deadline):
            var g = findGoal(name) ?? Goal(id: newId(), name: name, kind: "save", saved: 0, priority: Double(data.liveGoals.count + 1))
            g.target = target
            if let deadline { g.deadline = deadline }
            saveGoal(g)
            return "Saved goal \(g.name)"
        case let .investment(name, type, monthly, amount):
            var i = data.liveInvestments.first { $0.name.lowercased() == name.lowercased() } ?? Investment(id: newId(), name: name, type: type)
            if let monthly { i.monthly = monthly }
            if let amount { i.invested = amount; i.value = amount }
            saveInvestment(i)
            return "Saved \(i.name)"
        case let .budget(query, amount):
            guard var cat = findCategory(query) else { return "Couldn't find that category" }
            cat.budget = amount
            saveCategory(cat)
            return "\(cat.name) budget is now \(inr(amount))"
        case let .salary(v):
            saveSettings(salary: v, rule: data.settings.rule ?? "")
            return "Salary set to \(inr(v))"
        case let .score(bureau, score):
            saveScore(CreditScore(id: newId(), bureau: bureau, score: Double(score), date: Parser.iso(Date())))
            return "Logged \(bureau) \(score)"
        case let .question(q):
            return answer(q)
        }
    }

    // MARK: answers

    func answer(_ q: VoiceCommand.Question, today: Date = Date()) -> String {
        let d = data
        let mk = monthKey(today)
        let ms = d.monthSummary(mk)
        let cal = Parser.cal
        let daysLeft = (cal.range(of: .day, in: .month, for: today)?.count ?? 30) - cal.component(.day, from: today) + 1
        let noSalary = "Tell me your salary first. Say “my salary is 30000”."
        switch q {
        case .canSpend:
            guard ms.incomeKnown else { return noSalary }
            if ms.left <= 0 { return "You've used all of this month's money: \(inr(-ms.left)) over. Try to spend only on essentials until next month." }
            return "You have \(inr(ms.left)) left this month. That's about \(inr((ms.left / Double(daysLeft)).rounded(.down))) a day for the next \(daysLeft) day\(daysLeft == 1 ? "" : "s")."
        case let .spent(query, lastMonth):
            let month = lastMonth ? monthKey(cal.date(byAdding: .month, value: -1, to: today)!) : mk
            let when = lastMonth ? "in \(monthTitle(month))" : "this month"
            if let query, let cat = findCategory(query) {
                let s = d.spent(in: month, category: cat.id)
                let budget = cat.budget.map { b in b > 0 ? " of your \(inr(b)) budget" + (lastMonth ? "" : s > b ? ", \(inr(s - b)) over" : ", \(inr(b - s)) left") : "" } ?? ""
                return "You spent \(inr(s)) on \(cat.name) \(when)\(budget)."
            }
            let s = d.spent(in: month)
            let top = d.monthSummary(month).byCat.sorted { $0.value > $1.value }.prefix(2).compactMap { e in d.category(e.key).map { "\($0.name) \(inr(e.value))" } }
            return "You spent \(inr(s)) \(when)" + (top.isEmpty ? "." : ". Most went on " + top.joined(separator: " and ") + ".")
        case .owe:
            let debts = d.liveDebts.filter { ($0.balance ?? 0) > 0 }
            guard !debts.isEmpty else { return "You don't owe anything. Nice!" }
            let total = debts.reduce(0) { $0 + ($1.balance ?? 0) }
            let cu = d.cardUsage()
            let biggest = debts.sorted { ($0.balance ?? 0) > ($1.balance ?? 0) }.prefix(3).map { "\($0.name) \(inr($0.balance))" }.joined(separator: ", ")
            return "You owe \(inr(total)) in total: \(biggest)." + (cu.limit > 0 ? " Your cards are at \(Int(cu.pct.rounded()))% of their limits" + (cu.pct > 30 ? ". Under 30% helps your credit score." : ".") : "")
        case .debtFree:
            let debts = d.liveDebts.filter { ($0.balance ?? 0) > 0 }
            guard !debts.isEmpty else { return "You're already debt-free!" }
            let planned = d.buildPlan(today: today).goals.filter { $0.goal.kind != "save" }.reduce(0) { $0 + max($1.give, $1.want) }
            let emis = debts.reduce(0) { $0 + ($1.emi ?? 0) }
            let monthly = max(1000, ((max(planned, emis) > 0 ? max(planned, emis) : 5000) / 500).rounded() * 500)
            let r = simulatePayoff(debts.map { (balance: $0.balance ?? 0, apr: $0.rate ?? PayoffDefaults.apr[$0.kind] ?? 36) }, monthly: monthly, avalanche: true)
            guard let m = r.months else { return "At \(inr(monthly)) a month the interest grows faster than you pay. Open Plan → Debts → payoff planner to find an amount that works." }
            let date = cal.date(byAdding: .month, value: m, to: today)!
            return "Paying \(inr(monthly)) a month, highest interest first, you'll be debt-free by \(date.formatted(.dateTime.month(.wide).year())), in \(m) months, with about \(inr(r.interest)) of interest."
        case let .goal(query):
            let goals = query.flatMap { findGoal($0) }.map { [$0] } ?? Array(d.liveGoals.prefix(3))
            guard !goals.isEmpty else { return "You have no goals yet. Say “new goal emergency fund 50000 by December”." }
            return goals.map { g in
                let st = d.goalStatus(g, today: today)
                if st.done { return "\(g.name): done!" }
                return g.kind == "save"
                    ? "\(g.name): \(inr(st.current)) of \(inr(st.target)) saved, about \(inr(st.perMonth)) a month needed"
                    : "\(g.name): \(inr(st.remaining)) to go, about \(inr(st.perMonth)) a month"
            }.joined(separator: ". ") + "."
        case .score:
            let latest = Dictionary(grouping: d.scores.filter(\.isLive), by: \.bureau).compactMap { $0.value.max { $0.date < $1.date } }.sorted { $0.bureau < $1.bureau }
            guard !latest.isEmpty else { return "No credit score logged yet. Say “CIBIL score 750” after you check it in the OneCard or OneScore app." }
            return "Your latest scores: " + latest.map { "\($0.bureau) \(Int($0.score))" }.joined(separator: ", ") + "."
        case .plan:
            let p = d.buildPlan(today: today)
            guard p.incomeKnown else { return noSalary }
            var s = "From \(inr(p.income)): budgets take \(inr(p.budgeted)), SIPs \(inr(p.sips)), EMIs \(inr(p.emis)). That leaves \(inr(p.free))."
            let gives = p.goals.filter { $0.give > 0 }.prefix(3).map { "\(inr($0.give)) to \($0.goal.name)" }
            if !gives.isEmpty { s += " Put " + gives.joined(separator: ", ") + "." }
            if p.free < 0 { s += " Your budgets are more than your income. Lower one, like shopping or food." }
            else if p.leftover > 0 { s += " \(inr(p.leftover)) is still spare." }
            return s
        case .overview:
            var parts: [String] = []
            if ms.incomeKnown {
                parts.append("This month: income \(inr(ms.income)), spent \(inr(ms.spent)).")
                parts.append(ms.left > 0 ? "\(inr(ms.left)) left, about \(inr((ms.left / Double(daysLeft)).rounded(.down))) a day for \(daysLeft) days." : "You're \(inr(-ms.left)) over for the month.")
            } else {
                parts.append("This month you've spent \(inr(ms.spent)).")
            }
            if let top = ms.byCat.max(by: { $0.value < $1.value }), let c = d.category(top.key) { parts.append("Most went on \(c.name), \(inr(top.value)).") }
            let cu = d.cardUsage()
            if cu.limit > 0 { parts.append("Cards are at \(Int(cu.pct.rounded()))% of their limits.") }
            if !liveInbox.isEmpty { parts.append("\(liveInbox.count) bank transaction\(liveInbox.count == 1 ? "" : "s") waiting for you on Home.") }
            return parts.joined(separator: " ")
        case let .afford(v):
            guard ms.incomeKnown else { return noSalary }
            let left = ms.left
            if v <= left * 0.5 { return "Yes. You have \(inr(left)) left this month, and \(inr(left - v)) would still be left after it." }
            if v <= left { return "Just about. It leaves \(inr(left - v)) for the next \(daysLeft) days, about \(inr(((left - v) / Double(daysLeft)).rounded(.down))) a day." }
            let short = v - max(0, left)
            return "Not this month. You'd be \(inr(short)) short. Saving \(inr((v / 3).rounded(.up))) a month gets you there in 3 months. Say “new goal \(Int(v))” to track it."
        }
    }
}

enum PayoffDefaults {
    static let apr: [String: Double] = ["card": 42, "loan": 36, "emi": 16]
}
