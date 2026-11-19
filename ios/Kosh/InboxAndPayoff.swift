import Charts
import SwiftUI

// MARK: - Bank SMS review card (Home)

struct InboxCard: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @State private var chosen: [String: String] = [:]   // inbox id -> category
    @State private var sources: [String: String] = [:]  // inbox id -> income source
    @State private var kinds: [String: String] = [:]    // inbox id -> kind
    @State private var pots: [String: String] = [:]     // inbox id -> pot
    @State private var newPotFor: InboxItem?
    @State private var newPotName = ""

    var body: some View {
        let items = store.liveInbox
        if !items.isEmpty {
            Card {
                CardHeader(title: "Needs a look · \(items.count)")
                Text("Kosh adds what it's sure about by itself. These need you once; your answer is remembered.")
                    .font(.system(size: 12)).foregroundStyle(K.faint).padding(.bottom, 6)
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { RowDivider() }
                    row(item)
                }
                let ready = items.filter { $0.askWho != true && !(kind($0) == "held" && pot($0) == nil) }
                if ready.count > 1 {
                    Button {
                        let ids = ready.compactMap { add($0)?.id }
                        let s = store
                        router.show("Added \(ids.count)") { s.deleteEntries(ids) }
                    } label: { Label("Add all \(ready.count) as shown", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButton()).padding(.top, 12)
                }
            }
            .alert("New held-money pot", isPresented: Binding(get: { newPotFor != nil }, set: { if !$0 { newPotFor = nil } })) {
                TextField("e.g. Dad's money", text: $newPotName)
                Button("Create") {
                    if let item = newPotFor {
                        let p = store.createPot(newPotName.isEmpty ? "Held money" : newPotName, personId: item.personId)
                        pots[item.id] = p.id; kinds[item.id] = "held"
                    }
                    newPotFor = nil; newPotName = ""
                }
                Button("Cancel", role: .cancel) { newPotFor = nil }
            } message: { Text("Money you're keeping for someone. It won't count as your income or spending.") }
        }
    }

    private func kind(_ item: InboxItem) -> String { kinds[item.id] ?? item.kind ?? (item.type == "income" ? "income" : "expense") }
    private func pot(_ item: InboxItem) -> String? { pots[item.id] ?? item.potId }

    private func add(_ item: InboxItem) -> Entry? {
        store.confirmInbox(item, categoryId: chosen[item.id], incomeSource: sources[item.id], kind: kinds[item.id], potId: pot(item))
    }

    private func chip(_ text: String) -> some View {
        Label(text, systemImage: "chevron.up.chevron.down")
            .font(.system(size: 13, weight: .medium)).lineLimit(1).padding(.horizontal, 12).frame(minHeight: 36)
            .background(K.surface2, in: Capsule())
    }

    func row(_ item: InboxItem) -> some View {
        let d = store.data
        let k = kind(item)
        let cat = chosen[item.id] ?? item.categoryId ?? "other"
        let src = sources[item.id] ?? item.incomeSource ?? "other"
        let card = item.cardId.flatMap { id in d.debts.first { $0.id == id }?.name }
        let flowIn = item.type == "income"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Tile(symbol: flowIn ? "arrow.down.left" : (k == "expense" ? categorySymbol(cat) : "arrow.up.right"), tint: flowIn ? K.good : K.brand2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.merchant).font(.system(size: 16, weight: .medium)).lineLimit(1)
                    Text("\(shortDate(item.date))" + (card.map { " · \($0)" } ?? "")).font(.system(size: 13)).foregroundStyle(K.muted)
                }
                Spacer()
                Text((flowIn ? "+" : "−") + inr(item.amount)).font(.num(16, .semibold)).foregroundStyle(flowIn ? K.good : K.text)
            }
            if let reason = item.reason {
                Label(reason, systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(K.muted).fixedSize(horizontal: false, vertical: true)
            }
            if item.maybeDuplicate == true {
                Label("Maybe already added (SMS and email both came)", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(K.warn)
            }
            if item.askWho == true {
                Text("Who is \(item.merchant)?").font(.system(size: 14, weight: .semibold))
                FlowLayout(spacing: 8) {
                    ForEach(Person.roles, id: \.id) { r in
                        Button { store.setRole(item.merchant, role: r.id) } label: {
                            Text(r.name).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(minHeight: 34)
                                .background(K.surface2, in: Capsule()).overlay(Capsule().strokeBorder(K.lineStrong))
                        }.buttonStyle(.plain)
                    }
                }
            } else if item.type != "payment" {
                FlowLayout(spacing: 8) {
                    Menu {
                        ForEach(KoshStore.kinds, id: \.id) { kk in Button(kk.name) { kinds[item.id] = kk.id } }
                    } label: { chip(KoshStore.kindName(k)) }
                    switch k {
                    case "expense":
                        Menu { ForEach(d.liveCategories) { c in Button(c.name) { chosen[item.id] = c.id } } } label: { chip(d.category(cat)?.name ?? "Other") }
                    case "income":
                        Menu { ForEach(AppData.incomeSources, id: \.id) { s in Button(s.name) { sources[item.id] = s.id } } } label: { chip(AppData.incomeSourceName(src)) }
                    case "held":
                        Menu {
                            ForEach(store.openPots) { p in Button("\(p.name) · \(inr(store.potLeft(p.id))) left") { pots[item.id] = p.id } }
                            Button("New pot…") { newPotName = item.personId.flatMap { id in d.people.first { $0.id == id }?.name.split(separator: " ").first.map { "\($0)'s money" } } ?? ""; newPotFor = item }
                        } label: { chip(pot(item).flatMap { id in d.pots.first { $0.id == id }?.name } ?? "Choose pot") }
                    default:
                        EmptyView()
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button { store.discardInbox(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(K.muted)
                        .frame(width: 44, height: 36).background(K.surface2, in: Capsule())
                }
                .accessibilityLabel("Discard \(item.merchant)")
                let blocked = item.askWho == true || (k == "held" && pot(item) == nil)
                Button {
                    guard let e = add(item) else { return }
                    let s = store
                    router.show("Added \(inr(item.amount)) · \(KoshStore.kindName(e.type == "move" ? "move" : e.type))") { s.deleteEntries([e.id]) }
                } label: {
                    Text("Add").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 36).background(K.brandGradient, in: Capsule())
                }
                .disabled(blocked).opacity(blocked ? 0.4 : 1)
                .accessibilityLabel("Add \(item.merchant)")
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Held money (Home) and pot details

struct HeldMoneyCard: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let pots = store.openPots
        if !pots.isEmpty {
            Card {
                CardHeader(title: "Held for others")
                ForEach(Array(pots.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { RowDivider() }
                    Button { router.sheet = .pot(p.id) } label: {
                        ListRow(symbol: "person.2", tint: Color(hex: 0xFCD34D), title: p.name,
                                subtitle: "\(inr(store.potIn(p.id))) in · \(inr(store.potOut(p.id))) out", amount: inr(store.potLeft(p.id)), chevron: true)
                    }.buttonStyle(.plain)
                }
                Text("Not counted as your income or spending.").font(.system(size: 12)).foregroundStyle(K.faint).padding(.top, 4)
            }
        }
    }
}

struct PotDetail: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let potId: String
    @State private var confirmKeep = false
    var body: some View {
        let d = store.data
        let pot = d.pots.first { $0.id == potId }
        let es = d.liveEntries.filter { $0.type == "held" && $0.potId == potId }.sorted { $0.date > $1.date }
        NavigationStack {
            List {
                Section {
                    LabeledContent("Received", value: inr(store.potIn(potId)))
                    LabeledContent("Sent on", value: inr(store.potOut(potId)))
                    LabeledContent("Still with you", value: inr(store.potLeft(potId))).bold()
                }
                Section("Money in and out") {
                    if es.isEmpty { Text("Nothing yet. Tag transfers to this pot from Home, or say “sent 5000 to Sanskar from \(pot?.name ?? "dad's money")”.").foregroundStyle(K.muted) }
                    ForEach(es) { e in
                        LabeledContent("\(shortDate(e.date)) · \(e.note ?? "")", value: (e.flow == "in" ? "+" : "−") + inr(e.amount))
                    }
                }
                if pot?.closed != true {
                    Section {
                        Button("Keep the rest (\(inr(max(0, store.potLeft(potId))))) as Family income") { confirmKeep = true }
                        Button("Close pot", role: .destructive) { store.closePot(potId); dismiss() }
                    } footer: { Text("Keep the rest when the money is yours to use now. Close it when it's all been given back or passed on.") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x121215))
            .navigationTitle(pot?.name ?? "Held money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Count \(inr(store.potLeft(potId))) as your Family income this month?", isPresented: $confirmKeep, titleVisibility: .visible) {
                Button("Keep the rest") { store.keepRest(potId); dismiss() }
            }
        }
        .tint(K.brand)
    }
}

// MARK: - People & rules (More)

struct PeopleRules: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let d = store.data
        NavigationStack {
            List {
                Section {
                    if store.livePeople.isEmpty { Text("Kosh asks “Who is …?” the first time someone new sends or receives money.").foregroundStyle(K.muted) }
                    ForEach(store.livePeople) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                let owed = store.owedBalance(p.id)
                                if abs(owed) >= 1 { Text(owed > 0 ? "Owes you \(inr(owed))" : "You owe \(inr(-owed))").font(.system(size: 12)).foregroundStyle(owed > 0 ? K.good : K.warn) }
                            }
                            Spacer()
                            Menu {
                                ForEach(Person.roles, id: \.id) { r in Button(r.name) { store.setRole(p.name, role: r.id) } }
                                Button("Forget", role: .destructive) { store.deletePerson(p.id) }
                            } label: { Text(Person.roles.first { $0.id == p.role }?.name ?? p.role).font(.system(size: 14)) }
                        }
                    }
                } header: { Text("People") }
                Section {
                    let rules = d.rules.filter(\.isLive).sorted { $0.id < $1.id }
                    if rules.isEmpty { Text("When you change what Kosh suggested, it remembers it here.").foregroundStyle(K.muted) }
                    ForEach(rules, id: \.id) { r in
                        LabeledContent(r.id.capitalized, value: KoshStore.kindName(r.kind) + (r.categoryId.flatMap { d.category($0)?.name }.map { " · \($0)" } ?? "")
                                       + (r.incomeSource.map { " · " + AppData.incomeSourceName($0) } ?? ""))
                    }
                    .onDelete { idx in for i in idx { store.deleteRule(rules[i].id) } }
                } header: { Text("Remembered") } footer: { Text("Swipe left to forget a rule.") }
                Section {
                    Toggle("Add sure ones automatically", isOn: Binding(get: { d.settings.autoAdd != false }, set: { store.setAutoAdd($0) })).tint(K.brand)
                } footer: { Text("Known shops, people you've labelled, salary, cash and anything you've taught Kosh are added without asking. Everything else waits on Home.") }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x121215))
            .navigationTitle("People & rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .tint(K.brand)
    }
}

// MARK: - SMS automation setup (More)

struct SMSSetup: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sample = ""
    @State private var result: String?
    @State private var myName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    step(1, "Open **Shortcuts** → **Automation** → **+** → choose **Email**.")
                    step(2, "Under **Subject Contains**, type **alert**. Leave **Sender** and **Account** empty.")
                    step(3, "Choose **Run Immediately**, then **Next** → **New Blank Automation**.")
                    step(4, "**Add Action** → search **Kosh** → **Add bank message**.")
                    step(5, "Tap the blue **Message** field and pick **Shortcut Input**. Tap **Done**.")
                    step(6, "Repeat for the subject words **debited**, **transaction** and **payment**.")
                } header: { Text("Bank emails with Shortcuts") } footer: {
                    Text("Not needed if you use More → Connect Gmail. The Mail app must have your Gmail added. Promotions and statements are ignored.")
                }
                Section {
                    step(1, "Shortcuts → **Automation** → **+** → **Message**.")
                    step(2, "Under **Message Contains**, type **debited**. Leave the sender empty.")
                    step(3, "**Run Immediately** → **Next** → **New Blank Automation** → **Add Action** → **Kosh** → **Add bank message**.")
                    step(4, "Set **Message** to **Shortcut Input** → **Done**. Repeat for the word **spent**.")
                } header: { Text("Bank SMS") } footer: {
                    Text("If both the SMS and the email arrive, the second one is marked “Maybe already added” so you can discard it.")
                }
                Section {
                    let d = UserDefaults.standard
                    let when = d.double(forKey: "lastBankRun")
                    if when > 0 {
                        LabeledContent("When", value: Date(timeIntervalSince1970: when).formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Text received", value: "\(d.integer(forKey: "lastBankChars")) characters")
                        LabeledContent("Result", value: d.string(forKey: "lastBankResult") ?? "—")
                    } else {
                        Text("No message from Shortcuts yet.").foregroundStyle(K.muted)
                    }
                } header: { Text("Last message from Shortcuts") } footer: {
                    Text("If nothing shows here after an alert, the automation didn't run. If it shows only a few characters, Shortcuts sent just the subject.")
                }
                Section {
                    TextField("e.g. Asha Kumar", text: $myName).textInputAutocapitalization(.words).autocorrectionDisabled()
                        .onSubmit { store.saveMyName(myName) }
                        .onChange(of: myName) { _, v in store.saveMyName(v) }
                } header: { Text("Your name") } footer: {
                    Text("Money you send to your own name (another of your accounts) is skipped, not counted as spending.")
                }
                Section {
                    TextField("Paste a bank SMS or email here to try", text: $sample, axis: .vertical).lineLimit(3...8)
                    Button("Try it") {
                        if let item = store.addBankMessage(sample) {
                            let kind = item.type == "income" ? "money in" : item.type == "payment" ? "card bill paid" : "money out"
                            result = "✓ Read as \(kind): \(inr(item.amount)) · \(item.merchant) · \(shortDate(item.date)). It's now on Home under “From your bank”."
                            sample = ""
                        } else {
                            result = "That doesn't look like a completed transaction (or it's a duplicate, or money to yourself)."
                        }
                    }
                    .disabled(sample.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let result { Text(result).font(.system(size: 14)).foregroundStyle(result.hasPrefix("✓") ? K.good : K.warn) }
                } header: { Text("Test with a real message") }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x121215))
            .navigationTitle("Auto-add from bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { myName = store.data.settings.myName ?? "" }
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
