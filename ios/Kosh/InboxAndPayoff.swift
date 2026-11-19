import Charts
import SwiftUI

// MARK: - Bank SMS review card (Home)

struct InboxCard: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @State private var chosen: [String: String] = [:]   // inbox id -> category

    var body: some View {
        let items = store.liveInbox
        if !items.isEmpty {
            Card {
                CardHeader(title: "From your bank · \(items.count) to review")
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { RowDivider() }
                    row(item)
                }
                if items.count > 1 {
                    Button {
                        let ids = items.map { store.confirmInbox($0, categoryId: chosen[$0.id]).id }
                        let s = store
                        router.show("Added \(ids.count) from your bank") { s.deleteEntries(ids) }
                    } label: { Label("Add all \(items.count)", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButton()).padding(.top, 12)
                }
            }
        }
    }

    func row(_ item: InboxItem) -> some View {
        let d = store.data
        let cat = chosen[item.id] ?? item.categoryId ?? "other"
        let card = item.cardId.flatMap { id in d.debts.first { $0.id == id }?.name }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Tile(symbol: item.type == "income" ? "arrow.down.left" : categorySymbol(cat), tint: item.type == "income" ? K.good : K.brand2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.merchant).font(.system(size: 16, weight: .medium)).lineLimit(1)
                    Text("\(shortDate(item.date))" + (card.map { " · \($0)" } ?? "")).font(.system(size: 13)).foregroundStyle(K.muted)
                }
                Spacer()
                Text((item.type == "income" ? "+" : "−") + inr(item.amount)).font(.num(16, .semibold)).foregroundStyle(item.type == "income" ? K.good : K.text)
            }
            HStack(spacing: 8) {
                if item.type == "expense" {
                    Menu {
                        ForEach(d.liveCategories) { c in Button(c.name) { chosen[item.id] = c.id } }
                    } label: {
                        Label(d.category(cat)?.name ?? "Other", systemImage: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(minHeight: 36)
                            .background(K.surface2, in: Capsule())
                    }
                }
                Spacer()
                Button { store.discardInbox(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(K.muted)
                        .frame(width: 44, height: 36).background(K.surface2, in: Capsule())
                }
                .accessibilityLabel("Discard \(item.merchant)")
                Button {
                    let e = store.confirmInbox(item, categoryId: item.type == "expense" ? cat : nil)
                    let s = store
                    router.show("Added \(inr(item.amount)) · \(item.merchant)") { s.deleteEntries([e.id]) }
                } label: {
                    Text("Add").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 36).background(K.brandGradient, in: Capsule())
                }
                .accessibilityLabel("Add \(item.merchant)")
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - SMS automation setup (More)

struct SMSSetup: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sample = ""
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    step(1, "Open the **Shortcuts** app → **Automation** tab → **+** (or **New Automation**).")
                    step(2, "Choose **Message**. Under **Message Contains**, type **debited**. Leave the sender empty.")
                    step(3, "Choose **Run Immediately** (and turn off **Notify When Run** if you like), then **Next**.")
                    step(4, "Tap **New Blank Automation** → **Add Action** → search **Kosh** → **Add bank message**.")
                    step(5, "Tap the blue **Message** field and pick **Shortcut Input** (the message's content). Tap **Done**.")
                    step(6, "Repeat steps 1–5 for the word **spent**, so card purchase alerts are caught too.")
                } header: { Text("Set up once in Shortcuts") } footer: {
                    Text("Each matching SMS lands in “From your bank” on Home. Nothing is added until you tap Add. Kosh never keeps card or account numbers, and OTPs, bill reminders and failed payments are ignored.")
                }
                Section {
                    TextField("Paste a bank SMS here to try", text: $sample, axis: .vertical).lineLimit(3...6)
                    Button("Try it") {
                        if let item = store.addBankMessage(sample) {
                            result = "✓ Read as \(item.type == "income" ? "money in" : "money out"): \(inr(item.amount)) · \(item.merchant) · \(shortDate(item.date)). It's now on Home under “From your bank”."
                            sample = ""
                        } else {
                            result = "That doesn't look like a completed transaction (or it's a duplicate)."
                        }
                    }
                    .disabled(sample.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let result { Text(result).font(.system(size: 14)).foregroundStyle(result.hasPrefix("✓") ? K.good : K.warn) }
                } header: { Text("Test with a real message") }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x121215))
            .navigationTitle("Auto-add from bank SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .tint(K.brand)
    }

    func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.num(14, .bold)).foregroundStyle(K.brand).frame(width: 22)
            Text(text).font(.system(size: 15))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Debt payoff planner


struct PayoffPlanner: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var monthly: Double = 0
    @State private var avalanche = true

    static let defaultAPR: [String: Double] = ["card": 42, "loan": 36, "emi": 16]

    var body: some View {
        let debts = store.data.liveDebts.filter { ($0.balance ?? 0) > 0 }
        let inputs = debts.map { (balance: $0.balance ?? 0, apr: $0.rate ?? Self.defaultAPR[$0.kind] ?? 36) }
        let total = inputs.reduce(0) { $0 + $1.balance }
        let monthlyInterest = inputs.reduce(0) { $0 + $1.balance * $1.apr / 1200 }
        let r = simulatePayoff(inputs, monthly: monthly, avalanche: avalanche)
        let more = simulatePayoff(inputs, monthly: monthly + 1000, avalanche: avalanche)
        let assumed = debts.filter { $0.rate == nil }

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if debts.isEmpty {
                        Card { Text("No debts with a balance. Nothing to plan!").foregroundStyle(K.muted) }
                    } else {
                        HeroCard {
                            Eyebrow(text: "Debt-free by", color: .white.opacity(0.85)).padding(.bottom, 8)
                            if let m = r.months {
                                Text(freeDate(m)).font(.num(36, .bold))
                                Text("\(m) month\(m == 1 ? "" : "s") · interest \(inr(r.interest))").font(.system(size: 14)).foregroundStyle(.white.opacity(0.9)).padding(.top, 4)
                            } else {
                                Text("Never").font(.num(36, .bold))
                                Text("\(inr(monthly)) a month doesn't cover the \(inr(monthlyInterest)) of interest added each month.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.9)).padding(.top, 4)
                            }
                        }

                        Card {
                            CardHeader(title: "Paying each month")
                            Text(inr(monthly)).font(.num(28, .bold))
                            Slider(value: $monthly, in: 500...max(5000, (total / 3).rounded(.up)), step: 500).tint(K.brand)
                            HStack { Text("₹500"); Spacer(); Text(inr(max(5000, (total / 3).rounded(.up)))) }.font(.system(size: 12)).foregroundStyle(K.faint)
                            if let m = r.months, let m2 = more.months, m2 < m || more.interest < r.interest - 1 {
                                Banner(symbol: "lightbulb", text: "Paying \(inr(1000)) more a month gets you debt-free \(m - m2) month\(m - m2 == 1 ? "" : "s") sooner and saves \(inr(r.interest - more.interest)) in interest.")
                                    .padding(.top, 12)
                            }
                            Picker("Order", selection: $avalanche) {
                                Text("Highest interest first").tag(true)
                                Text("Smallest balance first").tag(false)
                            }
                            .pickerStyle(.segmented).padding(.top, 14)
                            Text(avalanche ? "Saves the most interest." : "Clears small debts (like mPokket) first for quick wins.")
                                .font(.system(size: 12)).foregroundStyle(K.faint).padding(.top, 6)
                        }

                        if r.points.count > 1 {
                            Card {
                                CardHeader(title: "Total owed over time")
                                Chart {
                                    ForEach(r.points, id: \.0) { p in
                                        AreaMark(x: .value("Month", p.0), y: .value("Owed", p.1))
                                            .foregroundStyle(LinearGradient(colors: [K.brand.opacity(0.6), K.brand.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                                        LineMark(x: .value("Month", p.0), y: .value("Owed", p.1)).foregroundStyle(K.brand)
                                    }
                                }
                                .chartXAxis { AxisMarks { v in AxisValueLabel { if let m = v.as(Int.self) { Text("\(m)m").foregroundStyle(K.faint) } } } }
                                .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine().foregroundStyle(K.line); AxisValueLabel { if let n = v.as(Double.self) { Text(n >= 1000 ? "\(Int(n / 1000))k" : "\(Int(n))").foregroundStyle(K.faint) } } } }
                                .frame(height: 180)
                            }
                        }

                        Card {
                            CardHeader(title: "Your debts")
                            ForEach(Array(debts.enumerated()), id: \.element.id) { i, d in
                                if i > 0 { RowDivider() }
                                Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.sheet = .debt(d) } } label: {
                                    ListRow(symbol: d.kind == "card" ? "creditcard" : "building.columns", title: d.name,
                                            subtitle: "\((d.rate ?? Self.defaultAPR[d.kind] ?? 36).formatted())% a year" + (d.rate == nil ? " (assumed)" : ""),
                                            amount: inr(d.balance), chevron: true)
                                }
                                .buttonStyle(.plain)
                            }
                            if !assumed.isEmpty {
                                Text("Interest rates marked “assumed” are typical figures (cards about 42% a year). Tap a debt and add its real rate for an exact plan.")
                                    .font(.system(size: 12)).foregroundStyle(K.faint).padding(.top, 8)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(hex: 0x121215))
            .navigationTitle("Payoff planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                if monthly == 0 {
                    // Start from what the monthly plan puts toward debt goals, or ₹5,000.
                    let planned = store.data.buildPlan().goals.filter { $0.goal.kind != "save" }.reduce(0) { $0 + max($1.give, $1.want) }
                    monthly = max(1000, ((planned > 0 ? planned : 5000) / 500).rounded() * 500)
                }
            }
        }
        .tint(K.brand)
    }

    func freeDate(_ months: Int) -> String {
        let d = Parser.cal.date(byAdding: .month, value: months, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }
}
