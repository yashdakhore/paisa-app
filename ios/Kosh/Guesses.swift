import SwiftUI

// MARK: - Home: what Kosh sorted by itself (checking is optional)

struct GuessesCard: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let g = store.guesses
        let weekAgo = Parser.iso(Parser.addDays(Date(), -7))
        let auto = store.data.liveEntries.filter { $0.source == "bank sms" && $0.date >= weekAgo }.count
        if !g.isEmpty {
            Card {
                HStack(spacing: 12) {
                    Tile(symbol: "sparkles", tint: K.brand2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(g.count) guess\(g.count == 1 ? "" : "es") you might want to check").font(.system(size: 15, weight: .semibold))
                        Text("Kosh sorted \(auto) bank transaction\(auto == 1 ? "" : "s") this week by itself. Totals are already counted.")
                            .font(.system(size: 12)).foregroundStyle(K.muted)
                    }
                }
                HStack(spacing: 10) {
                    Button("All look right") { for e in g { store.acceptGuess(e) } }.buttonStyle(SecondaryButton())
                    Button("Check") { router.sheet = .guesses }.buttonStyle(PrimaryButton())
                }
                .padding(.top, 10)
            }
        }
    }
}

// MARK: - Check guesses

struct GuessCheck: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var potFor: Entry?
    @State private var potName = ""

    var body: some View {
        let d = store.data
        let g = store.guesses
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if g.isEmpty {
                        Card { Text("All checked. Kosh will remember your answers.").foregroundStyle(K.muted) }
                    }
                    ForEach(g) { e in
                        Card {
                            row(e, d)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(hex: 0x121215))
            .navigationTitle("Kosh's guesses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .alert("New held-money pot", isPresented: Binding(get: { potFor != nil }, set: { if !$0 { potFor = nil } })) {
                TextField("e.g. Dad's money", text: $potName)
                Button("Create") {
                    if let e = potFor { let p = store.createPot(potName.isEmpty ? "Held money" : potName); store.correct(e, kind: "held", potId: p.id, learn: false) }
                    potFor = nil; potName = ""
                }
                Button("Cancel", role: .cancel) { potFor = nil }
            } message: { Text("Money you're keeping for someone. It won't count as your income or spending.") }
        }
        .tint(K.brand)
    }

    private func chip(_ text: String) -> some View {
        Label(text, systemImage: "chevron.up.chevron.down")
            .font(.system(size: 13, weight: .medium)).lineLimit(1).padding(.horizontal, 12).frame(minHeight: 36)
            .background(K.surface2, in: Capsule())
    }

    @ViewBuilder
    private func row(_ e: Entry, _ d: AppData) -> some View {
        let flowIn = e.type == "income" || e.flow == "in"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.note ?? "").font(.system(size: 16, weight: .medium)).lineLimit(1)
                    Text(shortDate(e.date)).font(.system(size: 13)).foregroundStyle(K.muted)
                }
                Spacer()
                Text((flowIn ? "+" : "−") + inr(e.amount)).font(.num(16, .semibold)).foregroundStyle(flowIn ? K.good : K.text)
            }
            if let r = e.reason { Label(r, systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(K.muted) }
            if e.askWho == true {
                Text("Who is \(e.note ?? "this")?").font(.system(size: 14, weight: .semibold))
                FlowLayout(spacing: 8) {
                    ForEach(Person.roles, id: \.id) { r in
                        Button { store.setRole(e.note ?? "", role: r.id) } label: {
                            Text(r.name).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(minHeight: 34)
                                .background(K.surface2, in: Capsule()).overlay(Capsule().strokeBorder(K.lineStrong))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text("Counted as:").font(.system(size: 12)).foregroundStyle(K.faint)
            FlowLayout(spacing: 8) {
                Menu {
                    ForEach(KoshStore.kinds, id: \.id) { k in
                        Button(k.name) {
                            if k.id == "held" { store.openPots.count == 1 ? store.correct(e, kind: "held", potId: store.openPots[0].id) : (potFor = e) }
                            else { store.correct(e, kind: k.id) }
                        }
                    }
                } label: { chip(KoshStore.kindName(e.type)) }
                switch e.type {
                case "expense":
                    Menu { ForEach(d.liveCategories) { c in Button(c.name) { store.correct(e, kind: "expense", categoryId: c.id) } } } label: {
                        chip(d.category(e.categoryId)?.name ?? "Other")
                    }
                case "income":
                    Menu { ForEach(AppData.incomeSources, id: \.id) { s in Button(s.name) { store.correct(e, kind: "income", incomeSource: s.id) } } } label: {
                        chip(AppData.incomeSourceName(d.incomeSource(e)))
                    }
                case "held":
                    Menu {
                        ForEach(store.openPots) { p in Button(p.name) { store.correct(e, kind: "held", potId: p.id, learn: false) } }
                        Button("New pot…") { potFor = e }
                    } label: { chip(e.potId.flatMap { id in d.pots.first { $0.id == id }?.name } ?? "Choose pot") }
                default: EmptyView()
                }
            }
            Button { store.acceptGuess(e) } label: { Label("Looks right", systemImage: "checkmark") }
                .font(.system(size: 14, weight: .semibold)).padding(.top, 4)
        }
    }
}
