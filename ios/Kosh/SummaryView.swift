import SwiftUI

/// A one-page report for a month: money in and out, budget, top spending, debt paid, goals, credit scores.
struct MonthlySummary: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let month: String

    struct Facts {
        var ms: MonthSummary
        var prevSpent: Double
        var budget: Double
        var spendOnly: Double
        var over: [(String, Double)]
        var top: [(Category, Double)]
        var biggest: Entry?
        var debtPaid: Double
        var goalLines: [(String, Double, Double)]   // name, put in this month, progress now
        var scoreLines: [(String, Int, Int?)]       // bureau, score, change
    }

    func facts(_ d: AppData) -> Facts {
        let ms = d.monthSummary(month)
        let cats = d.liveCategories
        let budget = cats.filter { $0.id != "debt" }.reduce(0) { $0 + ($1.budget ?? 0) }
        let debtPaid = ms.byCat["debt"] ?? 0
        let over = cats.compactMap { c -> (String, Double)? in
            let s = ms.byCat[c.id] ?? 0
            guard let b = c.budget, b > 0, s > b, c.id != "debt" else { return nil }
            return (c.name, s - b)
        }
        let top = cats.filter { $0.id != "debt" }.map { ($0, ms.byCat[$0.id] ?? 0) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3)
        let biggest = ms.entries.filter { $0.type == "expense" && $0.categoryId != "debt" }.max { $0.amount < $1.amount }
        let goalLines = d.liveGoals.map { g -> (String, Double, Double) in
            let st = d.goalStatus(g)
            let put: Double
            if g.kind == "save" {
                put = ms.entries.filter { $0.type == "save" && $0.goalId == g.id }.reduce(0) { $0 + $1.amount }
            } else {
                let ids: [String] = (g.kind == "cardUsage" || g.debtId == CARDS) ? d.cardUsage().cards.map(\.id) : [g.debtId ?? ""]
                put = ms.entries.filter { $0.type == "expense" && ids.contains($0.debtId ?? "") }.reduce(0) { $0 + $1.amount }
            }
            return (g.name, put, st.progress)
        }
        let scores = d.scores.filter(\.isLive)
        let scoreLines = KoshStore.bureaus.compactMap { b -> (String, Int, Int?)? in
            let list = scores.filter { $0.bureau == b }.sorted { $0.date < $1.date }
            guard let last = list.last(where: { monthKey($0.date) <= month }) else { return nil }
            let before = list.last(where: { $0.date < last.date && monthKey($0.date) < monthKey(last.date) })
            return (b, Int(last.score), before.map { Int(last.score - $0.score) })
        }
        return Facts(ms: ms, prevSpent: d.monthSummary(shiftMonth(month, -1)).spent, budget: budget, spendOnly: ms.spent - debtPaid,
                     over: over, top: Array(top), biggest: biggest, debtPaid: debtPaid, goalLines: goalLines, scoreLines: scoreLines)
    }

    var body: some View {
        let d = store.data
        let f = facts(d)
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HeroCard {
                        Eyebrow(text: "\(monthTitle(month)) summary", color: .white.opacity(0.85)).padding(.bottom, 8)
                        if f.ms.incomeKnown {
                            HeroAmount(value: f.ms.left)
                            Text(f.ms.left >= 0 ? "left over" : "more than you earned").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                        } else {
                            HeroAmount(value: f.ms.spent)
                            Text("spent in total").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                        }
                        HStack(spacing: 8) {
                            HeroStat(label: "Income", value: inr(f.ms.income))
                            HeroStat(label: "Spent", value: inr(f.ms.spent))
                            HeroStat(label: "Saved", value: inr(f.ms.saved + f.ms.invested))
                        }
                        .padding(.top, 18)
                    }

                    Card {
                        CardHeader(title: "Budget")
                        line("Everyday spending", "\(inr(f.spendOnly)) of \(inr(f.budget))", f.spendOnly > f.budget ? K.bad : K.good)
                        line("Compared with \(shortMonthName(shiftMonth(month, -1)))", f.prevSpent > 0 ? change(f.ms.spent, f.prevSpent) : "no data", K.text)
                        if !f.over.isEmpty {
                            Text("Over budget: " + f.over.map { "\($0.0) (+\(inr($0.1)))" }.joined(separator: ", "))
                                .font(.system(size: 13)).foregroundStyle(K.bad).padding(.top, 8)
                        } else if f.budget > 0, f.spendOnly > 0 {
                            Text("Every category stayed within budget.").font(.system(size: 13)).foregroundStyle(K.good).padding(.top, 8)
                        }
                    }

                    if !f.top.isEmpty {
                        Card {
                            CardHeader(title: "Where it went")
                            ForEach(Array(f.top.enumerated()), id: \.element.0.id) { i, row in
                                if i > 0 { RowDivider() }
                                ListRow(symbol: categorySymbol(row.0.id), title: row.0.name, amount: inr(row.1))
                            }
                            if let b = f.biggest {
                                Text("Biggest single expense: \(inr(b.amount)) · \(b.note?.isEmpty == false ? b.note! : (d.category(b.categoryId)?.name ?? "")) on \(shortDate(b.date))")
                                    .font(.system(size: 13)).foregroundStyle(K.muted).padding(.top, 8)
                            }
                        }
                    }

                    Card {
                        CardHeader(title: "Debts & goals")
                        line("Paid toward cards & loans", inr(f.debtPaid), f.debtPaid > 0 ? K.good : K.muted)
                        line("Card usage now", "\(Int(d.cardUsage().pct.rounded()))%", d.cardUsage().pct > 30 ? K.warn : K.good)
                        ForEach(f.goalLines, id: \.0) { g in
                            line(g.0, "+\(inr(g.1)) · \(Int((g.2 * 100).rounded()))% done", g.1 > 0 ? K.text : K.muted)
                        }
                    }

                    if !f.scoreLines.isEmpty {
                        Card {
                            CardHeader(title: "Credit scores")
                            ForEach(f.scoreLines, id: \.0) { s in
                                line(s.0, "\(s.1)" + (s.2.map { $0 >= 0 ? "  ▲\($0)" : "  ▼\(-$0)" } ?? ""), scoreBand(Double(s.1)).color)
                            }
                        }
                    }

                    ShareLink(item: shareText(f)) { Label("Share summary", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButton())
                }
                .padding(16)
            }
            .background(Color(hex: 0x121215))
            .navigationTitle("Monthly summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .tint(K.brand)
    }

    func line(_ k: String, _ v: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(K.muted)
            Spacer(minLength: 12)
            Text(v).font(.num(15, .semibold)).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 15))
        .padding(.vertical, 6)
    }

    func change(_ now: Double, _ before: Double) -> String {
        let p = (now - before) / before * 100
        return (p >= 0 ? "▲ " : "▼ ") + "\(Int(abs(p).rounded()))% (\(inr(before)) before)"
    }

    func shortMonthName(_ mk: String) -> String { monthTitle(mk) }

    func shareText(_ f: Facts) -> String {
        var t = "Kosh · \(monthTitle(month))\n"
        t += "Income \(inr(f.ms.income)) · Spent \(inr(f.ms.spent)) · Saved \(inr(f.ms.saved + f.ms.invested))\n"
        if f.ms.incomeKnown { t += "Left over: \(inr(f.ms.left))\n" }
        t += "Everyday spending \(inr(f.spendOnly)) of \(inr(f.budget)) budget\n"
        if !f.top.isEmpty { t += "Top: " + f.top.map { "\($0.0.name) \(inr($0.1))" }.joined(separator: ", ") + "\n" }
        t += "Paid toward debts: \(inr(f.debtPaid))\n"
        return t
    }
}

/// Home card during the first week of a month: last month's summary.
struct SummaryCard: View {
    @Environment(Router.self) private var router
    var body: some View {
        let day = Parser.cal.component(.day, from: Date())
        if day <= 7 {
            let last = shiftMonth(monthKey(Date()), -1)
            Button { router.sheet = .summary(last) } label: {
                Card {
                    ListRow(symbol: "doc.text.magnifyingglass", title: "\(monthTitle(last)) summary is ready", subtitle: "Spending, budget, debts, goals and credit scores", chevron: true)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
