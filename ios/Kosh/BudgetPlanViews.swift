import SwiftUI

struct BudgetView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let ms = d.monthSummary(router.month)
        let cats = d.liveCategories
        let total = cats.filter { $0.id != "debt" }.reduce(0) { $0 + ($1.budget ?? 0) }
        let f = total > 0 ? ms.spent / total : 0
        let all = ms.entries.sorted { $0.date > $1.date }

        VStack(spacing: 12) {
            Card {
                CardHeader(title: "Monthly budget")
                HStack(spacing: 20) {
                    Ring(fraction: f, size: 124, color: f > 1 ? AnyShapeStyle(K.bad) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFB37A), K.brand, K.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)),
                         label: "\(Int((f * 100).rounded()))%", sub: "spent")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inr(ms.spent)).font(.num(26, .bold))
                        Text("of \(inr(total))").foregroundStyle(K.muted)
                        Pill(text: (total - ms.spent >= 0 ? "Left " : "Over ") + inr(abs(total - ms.spent))).padding(.top, 6)
                    }
                }
            }
            Card {
                HStack {
                    Eyebrow(text: "Categories")
                    Spacer()
                    Button { router.sheet = .category(nil) } label: { Label("Add", systemImage: "plus").font(.system(size: 13, weight: .medium)).frame(minHeight: 44) }
                }
                ForEach(Array(cats.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { RowDivider() }
                    let s = ms.byCat[c.id] ?? 0
                    let b = c.budget ?? 0
                    Button { router.sheet = .category(c) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Tile(symbol: categorySymbol(c.id))
                            VStack(alignment: .leading, spacing: 0) {
                                HStack { Text(c.name).font(.system(size: 16, weight: .medium)); Spacer(); Text(inr(s)).font(.num(16, .semibold)) }
                                if b > 0 {
                                    Bar(fraction: s / b, tone: tone(spent: s, budget: b))
                                    HStack {
                                        Text(b - s >= 0 ? "\(inr(b - s)) left" : "\(inr(s - b)) over").foregroundStyle(b - s >= 0 ? K.muted : K.bad)
                                        Spacer()
                                        Text("of \(inr(b))").foregroundStyle(K.muted)
                                    }
                                    .font(.system(size: 13))
                                } else {
                                    Text("No budget set").font(.system(size: 13)).foregroundStyle(K.muted).padding(.top, 2)
                                }
                            }
                        }
                        .foregroundStyle(K.text)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Card {
                CardHeader(title: "All entries · \(monthTitle(router.month))")
                if all.isEmpty { Text("No entries.").foregroundStyle(K.muted) }
                ForEach(Array(all.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { RowDivider() }
                    EntryRow(entry: e)
                }
                Button { router.newEntry(listen: false) } label: { Label("Type an entry", systemImage: "keyboard") }
                    .buttonStyle(SecondaryButton()).padding(.top, 14)
            }
        }
    }
}

struct PlanView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 12) {
            Picker("Section", selection: $router.planSeg) {
                ForEach(PlanSeg.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)
            switch router.planSeg {
            case .month: MonthPlan()
            case .goals: GoalsList()
            case .debts: DebtsList()
            case .invest: InvestmentsList()
            }
        }
    }
}

struct MonthPlan: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let p = store.data.buildPlan()
        let open = p.goals.filter { !$0.st.done }
        VStack(spacing: 12) {
            if p.incomeKnown {
                HeroCard {
                    Eyebrow(text: "Free for goals this month", color: .white.opacity(0.85)).padding(.bottom, 8)
                    HeroAmount(value: p.free)
                    HStack(spacing: 8) {
                        HeroStat(label: "Income", value: inr(p.income))
                        HeroStat(label: "Budget", value: inr(p.budgeted))
                        HeroStat(label: p.emis > 0 ? "SIPs + EMIs" : "SIPs", value: inr(p.sips + p.emis))
                    }
                    .padding(.top, 20)
                }
            } else {
                Card {
                    Eyebrow(text: "Monthly plan").padding(.bottom, 8)
                    Text("Add your monthly take-home salary to see how much you can put toward each goal.").foregroundStyle(K.muted).padding(.bottom, 14)
                    Button { router.sheet = .income } label: { Label("Add salary", systemImage: "briefcase") }.buttonStyle(PrimaryButton())
                }
            }
            Card {
                CardHeader(title: p.incomeKnown ? "Put this toward your goals" : "Monthly need per goal")
                if open.isEmpty { Text("All goals done.").foregroundStyle(K.muted) }
                ForEach(Array(open.enumerated()), id: \.element.goal.id) { i, row in
                    if i > 0 { RowDivider() }
                    Button { router.sheet = .goal(row.goal) } label: {
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.num(16, .semibold)).foregroundStyle(K.brand2)
                                .frame(width: 44, height: 44).background(K.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.goal.name).font(.system(size: 16, weight: .medium)).lineLimit(1)
                                Group {
                                    Text("\(inr(row.st.perMonth))/mo for \(row.st.months) mo")
                                    + Text(row.st.thisMonth > 0 ? " · \(inr(row.st.thisMonth)) done" : "")
                                    + Text(p.incomeKnown && row.give < row.want ? " · short \(inr(row.want - row.give))" : "").foregroundColor(K.warn)
                                }
                                .font(.system(size: 13)).foregroundStyle(K.muted)
                            }
                            Spacer()
                            if row.want == 0 {
                                Text("covered by\nthe goal above").font(.system(size: 12)).foregroundStyle(K.muted).multilineTextAlignment(.trailing)
                            } else {
                                Text(inr(p.incomeKnown ? row.give : row.want)).font(.num(16, .semibold))
                            }
                        }
                        .foregroundStyle(K.text).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if p.incomeKnown, p.leftover > 0 {
                    Banner(symbol: "lightbulb", text: "After goals, \(inr(p.leftover)) is spare. Put it toward your first unfinished goal to finish sooner, or increase your SIP.").padding(.top, 14)
                }
                if p.incomeKnown, p.free < 0 {
                    Banner(symbol: "info.circle", text: "Your budgets are more than your income. Lower a category budget on the Budget tab.").padding(.top, 14)
                }
            }
        }
    }
}

struct GoalsList: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let d = store.data
        VStack(spacing: 12) {
            ForEach(d.liveGoals) { g in
                let st = d.goalStatus(g)
                Card {
                    HStack(spacing: 16) {
                        Ring(fraction: st.progress, size: 84, line: 9,
                             color: st.done ? AnyShapeStyle(K.good) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFB37A), K.brand, K.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)),
                             label: st.done ? "✓" : "\(Int((st.progress * 100).rounded()))%")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.name).font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text(g.kind == "save" ? "\(inr(st.current)) of \(inr(st.target)) saved" : "\(inr(st.current)) owed → \(inr(st.target))")
                                .font(.system(size: 14)).foregroundStyle(K.muted)
                            HStack(spacing: 6) {
                                if st.done { Pill(text: "Done", ok: true) } else { Pill(text: "\(inr(st.perMonth))/month", hot: true) }
                                if let dl = g.deadline { Pill(text: monthTitle(dl)) }
                            }
                            .padding(.top, 4)
                        }
                    }
                    HStack(spacing: 8) {
                        if g.kind == "save" {
                            Button { router.newEntry(listen: false, text: "saved  for \(g.name)") } label: { Label("Add money", systemImage: "plus") }.buttonStyle(PrimaryButton())
                        } else {
                            Button {
                                let target = (g.debtId == CARDS || g.kind == "cardUsage") ? d.cardUsage().cards.first : d.liveDebts.first { $0.id == g.debtId }
                                router.newEntry(listen: false, text: "paid  to \(target?.name ?? "")")
                            } label: { Text("Log payment") }.buttonStyle(PrimaryButton())
                        }
                        Button { router.sheet = .goal(g) } label: { Label("Edit", systemImage: "pencil") }.buttonStyle(SecondaryButton())
                    }
                    .padding(.top, 16)
                }
            }
            Button { router.sheet = .goal(nil) } label: { Label("New goal", systemImage: "plus") }.buttonStyle(SecondaryButton())
        }
    }
}

struct DebtsList: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let d = store.data
        VStack(spacing: 12) {
            if let rule = d.settings.rule, !rule.isEmpty { Banner(symbol: "shield", text: rule) }
            CardUsageCard(showLink: false)
            ForEach(d.liveDebts) { debt in
                let usage: Double? = debt.kind == "card" && (debt.limit ?? 0) > 0 ? (debt.balance ?? 0) / (debt.limit ?? 1) : nil
                Card {
                    ListRow(symbol: debt.kind == "card" ? "creditcard" : "building.columns", title: debt.name,
                            subtitle: ["card": "Credit card", "loan": "Loan", "emi": "EMI"][debt.kind] ?? debt.kind,
                            amount: inr(debt.balance), amountSub: "owed")
                    if let usage {
                        Bar(fraction: usage, tone: usage > 0.3 ? .bad : (usage > 0.1 ? .warn : .good), marks: [0.1, 0.3])
                        detail("Limit", "\(inr(debt.limit)) · \(Int((usage * 100).rounded()))% used")
                    }
                    if let emi = debt.emi, emi > 0 { detail("EMI", "\(inr(emi))/month") }
                    if let rate = debt.rate, rate > 0 { detail("Interest", "\(rate.formatted())% a year") }
                    if let due = debt.dueDay, due > 0 { detail("Due", "\(ordinal(Int(due))) of each month") }
                    if let note = debt.note, !note.isEmpty { Text(note).font(.system(size: 13)).foregroundStyle(K.faint).padding(.top, 10) }
                    HStack(spacing: 8) {
                        Button { router.newEntry(listen: false, text: "paid  to \(debt.name)") } label: { Text("Log payment") }.buttonStyle(PrimaryButton())
                        Button { router.sheet = .debt(debt) } label: { Label("Edit", systemImage: "pencil") }.buttonStyle(SecondaryButton())
                    }
                    .padding(.top, 16)
                }
            }
            Button { router.sheet = .debt(nil) } label: { Label("Add debt, EMI or card", systemImage: "plus") }.buttonStyle(SecondaryButton())
        }
    }
    func detail(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(K.muted); Spacer(); Text(v) }.font(.system(size: 15)).padding(.top, 10)
    }
}

struct InvestmentsList: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let inv = store.data.liveInvestments
        let tv = inv.reduce(0) { $0 + ($1.value ?? 0) }
        let ti = inv.reduce(0) { $0 + ($1.invested ?? 0) }
        let tm = inv.reduce(0) { $0 + ($1.monthly ?? 0) }
        let gain = tv - ti
        VStack(spacing: 12) {
            HeroCard {
                Eyebrow(text: "Portfolio value", color: .white.opacity(0.85)).padding(.bottom, 8)
                HeroAmount(value: tv)
                Label((gain >= 0 ? "+" : "−") + inr(abs(gain)) + (ti > 0 ? String(format: " (%.1f%%)", gain / ti * 100) : ""), systemImage: gain >= 0 ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.black.opacity(0.22), in: Capsule()).padding(.top, 12)
                HStack(spacing: 8) {
                    HeroStat(label: "Invested", value: inr(ti))
                    HeroStat(label: "Monthly", value: inr(tm))
                    HeroStat(label: "Holdings", value: "\(inv.count)")
                }
                .padding(.top, 20)
            }
            ForEach(inv) { i in
                let g = (i.value ?? 0) - (i.invested ?? 0)
                Card {
                    ListRow(symbol: "chart.line.uptrend.xyaxis", tint: Color(hex: 0x67E8F9), title: i.name,
                            subtitle: i.type + ((i.monthly ?? 0) > 0 ? " · \(inr(i.monthly))/month" : ""),
                            amount: inr(i.value ?? 0),
                            amountColor: K.text,
                            amountSub: (i.invested ?? 0) > 0 ? (g >= 0 ? "+" : "−") + inr(abs(g)) : nil)
                    HStack { Text("Invested so far").foregroundStyle(K.muted); Spacer(); Text(inr(i.invested ?? 0)) }.font(.system(size: 15)).padding(.top, 6)
                    if let m = i.maturity, !m.isEmpty { HStack { Text("Matures").foregroundStyle(K.muted); Spacer(); Text(shortDate(m)) }.font(.system(size: 15)).padding(.top, 8) }
                    if let note = i.note, !note.isEmpty { Text(note).font(.system(size: 13)).foregroundStyle(K.faint).padding(.top, 10) }
                    HStack(spacing: 8) {
                        Button { router.newEntry(listen: false, text: "invested  in \(i.name)") } label: { Label("Add money", systemImage: "plus") }.buttonStyle(PrimaryButton())
                        Button { router.sheet = .investment(i) } label: { Label("Update", systemImage: "pencil") }.buttonStyle(SecondaryButton())
                    }
                    .padding(.top, 16)
                }
            }
            Button { router.sheet = .investment(nil) } label: { Label("Add investment", systemImage: "plus") }.buttonStyle(SecondaryButton())
        }
    }
}
