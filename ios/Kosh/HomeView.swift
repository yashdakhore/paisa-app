import SwiftUI

struct HomeView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let ms = d.monthSummary(router.month)
        let cats = d.liveCategories
        let totalBudget = cats.filter { $0.id != "debt" }.reduce(0) { $0 + ($1.budget ?? 0) }
        let plan = d.buildPlan()
        let next = plan.goals.filter { !$0.st.done && $0.want > 0 }.prefix(3)
        let recent = ms.entries.sorted { ($0.date + ($0.createdAt ?? "")) > ($1.date + ($1.createdAt ?? "")) }.prefix(6)
        let isNew = d.liveGoals.isEmpty && d.liveDebts.isEmpty && d.liveEntries.isEmpty
        let spentAny = ms.spent > 0

        VStack(spacing: 12) {
            if let rule = d.settings.rule, !rule.isEmpty { Banner(symbol: "shield", text: rule) }

            if isNew {
                Card {
                    Eyebrow(text: "Welcome to Kosh").padding(.bottom, 8)
                    Text("Load your budget, goals and debts from a backup or the starting plan.").foregroundStyle(K.muted).padding(.bottom, 14)
                    Button("Set up from backup") { router.tab = .more }.buttonStyle(PrimaryButton())
                }
            }

            HeroCard {
                Eyebrow(text: "Left this month", color: .white.opacity(0.85)).padding(.bottom, 8)
                if ms.incomeKnown {
                    HeroAmount(value: ms.left)
                    Label("Spent \(inr(ms.spent)) of \(inr(totalBudget)) budget", systemImage: ms.left < 0 ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.black.opacity(0.22), in: Capsule())
                        .padding(.top, 12)
                } else {
                    HeroAmount(value: nil)
                    Button { router.sheet = .income } label: {
                        Text("Add your take-home salary").underline().font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.black.opacity(0.22), in: Capsule())
                    }
                    .foregroundStyle(.white).padding(.top, 12)
                }
                if ms.extraIncome >= 1, ms.salaryIncome > 0 {
                    Text("\(inr(ms.salaryIncome)) salary + \(inr(ms.extraIncome)) extra")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 14).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Button { router.tab = .budget; router.budgetSeg = .income } label: { HeroStat(label: "Income ›", value: inr(ms.income)) }
                        .buttonStyle(.plain).accessibilityHint("Opens Income")
                    HeroStat(label: "Spent", value: inr(ms.spent))
                    HeroStat(label: "Saved", value: inr(ms.saved + ms.invested))
                }
                .padding(.top, 20)
            }

            HStack(spacing: 8) {
                quick("mic", "Speak") { router.newEntry(listen: true) }
                quick("keyboard", "Type") { router.newEntry(listen: false) }
                quick("target", "Plan") { router.tab = .plan; router.planSeg = .month }
            }

            InboxCard()
            GuessesCard()
            HeldMoneyCard()

            SummaryCard()

            DueRecurringCard()

            CardUsageCard(showLink: true)

            let due = d.liveDebts.filter { ($0.dueDay ?? 0) > 0 && ($0.balance ?? 0) > 0 }
            if !due.isEmpty {
                Card {
                    CardHeader(title: "Pay on time")
                    ForEach(Array(due.enumerated()), id: \.element.id) { i, debt in
                        if i > 0 { RowDivider() }
                        ListRow(symbol: "calendar", title: debt.name, subtitle: "Due on the \(ordinal(Int(debt.dueDay ?? 1)))", amount: inr(debt.balance))
                    }
                }
            }

            Card {
                CardHeader(title: spentAny ? "Where the money went" : "Your budget plan", action: "Budget") { router.tab = .budget }
                let items = cats.map { c -> BubbleItem in
                    let s = ms.byCat[c.id] ?? 0
                    return BubbleItem(id: c.id, label: c.name, value: spentAny ? s : (c.budget ?? 0), over: (c.budget ?? 0) > 0 && s > (c.budget ?? 0), symbol: categorySymbol(c.id))
                }
                BubbleChart(items: items) { id in
                    if let c = d.category(id) { router.sheet = .category(c) }
                }
                Text(spentAny ? "Bubble size shows each category’s share of spending. A red ring means over budget." : "Nothing spent yet this month. Bubbles show how your budget is split.")
                    .font(.system(size: 13)).foregroundStyle(K.faint).padding(.top, 8)
            }

            if !next.isEmpty {
                Card {
                    CardHeader(title: "Save next", action: "Plan") { router.tab = .plan; router.planSeg = .month }
                    ForEach(Array(next.enumerated()), id: \.element.goal.id) { i, row in
                        if i > 0 { RowDivider() }
                        ListRow(symbol: row.goal.kind == "save" ? "wallet.pass" : "creditcard", title: row.goal.name,
                                subtitle: "\(Int(row.st.progress * 100))% done", amount: inr(row.want), amountSub: "this month")
                    }
                }
            }

            Card {
                CardHeader(title: "Recent", action: "All") { router.tab = .budget }
                if recent.isEmpty {
                    Text("No entries yet. Tap the mic and say “spent 250 on groceries”.").foregroundStyle(K.muted)
                } else {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { RowDivider() }
                        EntryRow(entry: e)
                    }
                }
            }
        }
    }

    func quick(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(K.brand)
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(K.text)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(K.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(K.line))
        }
    }
}

struct EntryRow: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    let entry: Entry
    var body: some View {
        let d = store.data
        let (symbol, tint, label): (String, Color, String) = {
            switch entry.type {
            case "income": return ("arrow.down.left", K.good, "Income")
            case "save": return ("wallet.pass", Color(hex: 0xC4B5FD), "Saving · " + (d.goals.first { $0.id == entry.goalId }?.name ?? "goal"))
            case "invest": return ("chart.line.uptrend.xyaxis", Color(hex: 0x67E8F9), "Investment · " + (d.investments.first { $0.id == entry.investmentId }?.name ?? ""))
            case "move": return ("arrow.left.arrow.right", K.muted, "Moved · not counted")
            case "held": return ("person.2", Color(hex: 0xFCD34D), "Held · " + (d.pots.first { $0.id == entry.potId }?.name ?? "someone's money"))
            case "owed": return ("arrow.uturn.left", Color(hex: 0x93C5FD), entry.flow == "in" ? "Paid back" : "Lent")
            default: return (categorySymbol(entry.categoryId), K.brand2, d.category(entry.categoryId)?.name ?? "Other")
            }
        }()
        let sign = entry.type == "income" ? "+" : (entry.type == "expense" ? "−" : "")
        Button { router.sheet = .entry(entry, listen: false, text: "") } label: {
            ListRow(symbol: symbol, tint: tint, title: (entry.note?.isEmpty == false ? entry.note! : label),
                    subtitle: "\(shortDate(entry.date)) · \(label)", amount: sign + inr(entry.amount).replacingOccurrences(of: "−", with: ""),
                    amountColor: entry.type == "income" ? K.good : K.text)
        }
        .buttonStyle(.plain)
    }
}

struct CardUsageCard: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    var showLink: Bool
    var body: some View {
        let cu = store.data.cardUsage()
        if !cu.cards.isEmpty {
            Card {
                CardHeader(title: "Credit card usage", action: showLink ? "Debts" : nil) { router.tab = .plan; router.planSeg = .debts }
                HStack(spacing: 20) {
                    Ring(fraction: cu.pct / 100,
                         color: cu.pct > 30 ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFB37A), K.brand, K.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(cu.pct > 10 ? K.warn : K.good),
                         marks: [0.1, 0.3], label: "\(Int(cu.pct.rounded()))%", sub: "used")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inr(cu.balance)).font(.num(22, .semibold))
                        Text("of \(inr(cu.limit)) limit").font(.system(size: 14)).foregroundStyle(K.muted)
                        VStack(alignment: .leading, spacing: 6) {
                            chip("Under 30%", inr(cu.limit * 0.3))
                            chip("Under 10%", inr(cu.limit * 0.1))
                        }
                        .padding(.top, 6)
                    }
                }
                if cu.pct > 30 {
                    (Text("Ticks on the ring mark 10% and 30%. Pay down ") + Text(inr(cu.balance - cu.limit * 0.3)).foregroundColor(K.bad).bold() + Text(" to get under 30%."))
                        .font(.system(size: 13)).foregroundStyle(K.faint).padding(.top, 12)
                }
            }
        }
    }
    func chip(_ a: String, _ b: String) -> some View {
        HStack(spacing: 6) { Text(a).foregroundStyle(K.muted); Text(b).bold().foregroundStyle(K.text) }
            .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 5)
            .background(K.surface2, in: Capsule())
    }
}

// MARK: - Bubble chart

struct BubbleItem: Identifiable {
    let id: String
    let label: String
    let value: Double
    let over: Bool
    let symbol: String
}

struct BubbleChart: View {
    let items: [BubbleItem]
    var onTap: (String) -> Void

    struct Placed: Identifiable { let id: String; let cx: Double; let cy: Double; let r: Double; let item: BubbleItem; let rank: Int }
    static let W = 340.0, H = 260.0

    var body: some View {
        let placed = layout()
        let total = items.filter { $0.value > 0 }.reduce(0) { $0 + $1.value }
        if placed.isEmpty {
            Text("Set category budgets on the Budget tab.").foregroundStyle(K.muted)
        } else {
            GeometryReader { geo in
                let s = geo.size.width / Self.W
                ZStack(alignment: .topLeading) {
                    ForEach(placed) { p in
                        let pct = Int((p.item.value / total * 100).rounded())
                        Button { onTap(p.item.id) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: p.item.symbol).font(.system(size: 15))
                                if p.r >= 44 { Text(p.item.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.88)).multilineTextAlignment(.center).lineLimit(2) }
                                Text("\(pct)%").font(.num(14, .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(4)
                            .frame(width: p.r * 2 * s, height: p.r * 2 * s)
                            .background(fill(p.rank), in: Circle())
                            .overlay(Circle().strokeBorder(p.item.over ? K.bad : (p.rank == 0 ? Color.white.opacity(0.25) : K.lineStrong), lineWidth: p.item.over ? 2 : 1))
                            .shadow(color: p.rank == 0 ? K.heroA.opacity(0.6) : .clear, radius: 16, y: 10)
                        }
                        .buttonStyle(.plain)
                        .position(x: p.cx * s, y: p.cy * s)
                        .accessibilityLabel("\(p.item.label) \(pct) percent")
                    }
                }
            }
            .aspectRatio(Self.W / Self.H, contentMode: .fit)
        }
    }

    func fill(_ rank: Int) -> AnyShapeStyle {
        switch rank {
        case 0: return AnyShapeStyle(RadialGradient(colors: [Color(hex: 0xFFB37A), K.heroA, K.heroC], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 110))
        case 1: return AnyShapeStyle(RadialGradient(colors: [Color(hex: 0xFF8C46, alpha: 0.45), Color(hex: 0xC93A0E, alpha: 0.25)], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 80))
        default: return AnyShapeStyle(RadialGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 60))
        }
    }

    /// Largest first, spiralling out from the centre; if one doesn't fit, shrink everything and retry.
    func layout() -> [Placed] {
        let vals = items.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(7)
        guard let vmax = vals.first?.value else { return [] }
        var rs = vals.map { max(26, 88 * ($0.value / vmax).squareRoot()) }
        let area = rs.reduce(0) { $0 + .pi * $1 * $1 }
        let k = min(1, ((0.55 * Self.W * Self.H) / area).squareRoot())
        rs = rs.map { max(24, $0 * k) }
        for attempt in 0..<8 {
            let scale = pow(0.9, Double(attempt))
            var placed: [Placed] = []
            var ok = true
            for (i, item) in vals.enumerated() {
                let r = max(22, rs[i] * scale)
                var found = false
                var d = 0.0
                search: while d < 260 {
                    var a = 0.0
                    while a < 360 {
                        let t = (a + Double(i) * 47) * .pi / 180
                        let cx = Self.W / 2 + d * cos(t) * 1.3, cy = Self.H / 2 + d * sin(t)
                        if cx - r >= 0, cx + r <= Self.W, cy - r >= 0, cy + r <= Self.H,
                           placed.allSatisfy({ hypot($0.cx - cx, $0.cy - cy) >= $0.r + r + 4 }) {
                            placed.append(Placed(id: item.id, cx: cx, cy: cy, r: r, item: item, rank: i))
                            found = true
                            break search
                        }
                        a += 10
                    }
                    d += 2
                }
                if !found { ok = false; break }
            }
            if ok { return placed }
        }
        return []
    }
}
