import SwiftUI

/// Budget → Suggest my budget: income → fixed costs → suggested budget you can edit, then save.
struct BudgetWizard: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var income = ""
    @State private var fixed: [FixedCost] = []
    @State private var amounts: [String: String] = [:]      // category id → edited amount
    @State private var suggestion: BudgetSuggest.Result?
    @FocusState private var focus: Bool

    static let quickAdds: [(String, String)] = [("Rent", "rent"), ("WiFi", "phone"), ("Mobile recharge", "phone"), ("Electricity", "bills"),
                                                ("Gas cylinder", "bills"), ("Money to home", "other"), ("Travel to work", "transport"),
                                                ("Subscriptions", "entertainment"), ("Gym", "health"), ("Maid / help", "other")]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        ForEach(1...3, id: \.self) { i in
                            Capsule().fill(i <= step ? K.brand : K.surface2).frame(height: 4)
                        }
                    }
                    .padding(.top, 4)
                    switch step {
                    case 1: incomeStep
                    case 2: fixedStep
                    default: suggestionStep
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(hex: 0x121215))
            .navigationTitle("Suggest my budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step > 1 { Button("Back") { step -= 1 } } else { Button("Close") { dismiss() } }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() }.bold() }
            }
        }
        .tint(K.brand)
        .onAppear {
            if let s = store.data.settings.salary { income = fmtAmount(s) }
            fixed = store.data.settings.fixedCosts ?? []
        }
    }

    // MARK: step 1

    private var incomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you get each month?").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Your take-home salary: what actually reaches your bank account.").foregroundStyle(K.muted)
            HStack {
                Text("₹").font(.num(28, .bold)).foregroundStyle(K.muted)
                TextField("30000", text: $income).keyboardType(.numberPad).font(.num(32, .bold)).focused($focus)
            }
            .padding(16)
            .background(K.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button("Next") { step = 2 }.buttonStyle(PrimaryButton()).disabled(value(income) <= 0).opacity(value(income) > 0 ? 1 : 0.5)
        }
        .onAppear { if income.isEmpty { focus = true } }
    }

    // MARK: step 2

    private var fixedStep: some View {
        let loans = store.data.liveDebts.filter { $0.kind != "card" && ($0.emi ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 14) {
            Text("What must you pay every month?").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Rent, WiFi, recharge, money to home… Tap to add, then type the amount. A guess is fine.").foregroundStyle(K.muted)

            FlowChips(items: Self.quickAdds.map(\.0).filter { n in !fixed.contains { $0.name == n } }) { name in
                let cat = Self.quickAdds.first { $0.0 == name }?.1 ?? "other"
                fixed.append(FixedCost(id: newId(), name: name, amount: 0, categoryId: cat))
            }

            if !fixed.isEmpty || !loans.isEmpty {
                Card {
                    ForEach($fixed) { $f in
                        HStack(spacing: 10) {
                            TextField("Name", text: $f.name).font(.system(size: 16))
                                .onChange(of: f.name) { _, n in f.categoryId = guessCategory(n, current: f.categoryId) }
                            HStack(spacing: 2) {
                                Text("₹").foregroundStyle(K.muted)
                                TextField("0", text: Binding(get: { f.amount > 0 ? fmtAmount(f.amount) : "" }, set: { f.amount = value($0) }))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                            }
                            .font(.num(16, .semibold))
                            Button { fixed.removeAll { $0.id == f.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(K.faint) }
                                .accessibilityLabel("Remove \(f.name)")
                        }
                        .frame(minHeight: 44)
                        RowDivider()
                    }
                    ForEach(loans) { l in
                        HStack {
                            Text("\(l.name) EMI").foregroundStyle(K.muted)
                            Spacer()
                            Text(inr(l.emi)).font(.num(16, .semibold)).foregroundStyle(K.muted)
                        }
                        .frame(minHeight: 40)
                    }
                    if !loans.isEmpty { Text("EMIs come from your loans in Plan → Debts.").font(.system(size: 12)).foregroundStyle(K.faint) }
                }
                Button { fixed.append(FixedCost(id: newId(), name: "", amount: 0, categoryId: "other")) } label: {
                    Label("Add another", systemImage: "plus")
                }.font(.system(size: 15, weight: .medium))
            }
            let total = fixed.reduce(0) { $0 + $1.amount } + loans.reduce(0) { $0 + ($1.emi ?? 0) }
            Text("Fixed each month: \(inr(total)) of \(inr(value(income)))").font(.system(size: 14)).foregroundStyle(total > value(income) ? K.warn : K.muted)
            Button("Suggest my budget") { makeSuggestion(); step = 3 }.buttonStyle(PrimaryButton())
        }
    }

    // MARK: step 3

    private var suggestionStep: some View {
        let d = store.data
        let edited = amounts.reduce(0) { $0 + value($1.value) }
        let emis = suggestion?.emis ?? 0
        let left = value(income) - edited - emis
        let cardDebt = d.cardUsage().balance
        return VStack(alignment: .leading, spacing: 14) {
            Text("Here's a plan for \(inr(value(income)))").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Change any amount you like, then tap Use this budget.").foregroundStyle(K.muted)
            Card {
                ForEach(Array((suggestion?.lines ?? []).enumerated()), id: \.element.categoryId) { i, line in
                    if i > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        Tile(symbol: categorySymbol(line.categoryId))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.category(line.categoryId)?.name ?? line.categoryId.capitalized).font(.system(size: 15, weight: .medium))
                            Text(line.reason).font(.system(size: 12)).foregroundStyle(K.faint).lineLimit(2)
                        }
                        Spacer()
                        HStack(spacing: 2) {
                            Text("₹").foregroundStyle(K.muted)
                            TextField("0", text: Binding(get: { amounts[line.categoryId] ?? "" }, set: { amounts[line.categoryId] = $0 }))
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 72)
                        }
                        .font(.num(16, .semibold))
                        .padding(.horizontal, 10).frame(minHeight: 40)
                        .background(K.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.vertical, 4)
                }
            }
            HeroCard {
                Eyebrow(text: cardDebt > 0 ? "Left for card payoff & savings" : "Left to save & invest", color: .white.opacity(0.85))
                Text(inr(left)).font(.num(32, .bold)).padding(.top, 4)
                if emis > 0 { Text("after \(inr(emis)) of EMIs").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)) }
                Text(BudgetSuggest.note(leftover: left, flexible: suggestion?.flexible ?? 0, cardDebt: cardDebt,
                                        apr: d.cardUsage().cards.compactMap(\.rate).max() ?? 42))
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.92)).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Start over") { makeSuggestion() }.buttonStyle(SecondaryButton())
                Button("Use this budget") { save() }.buttonStyle(PrimaryButton()).disabled(left < 0).opacity(left < 0 ? 0.5 : 1)
            }
            if left < 0 { Text("Budgets are \(inr(-left)) more than your income. Lower one.").font(.system(size: 13)).foregroundStyle(K.warn) }
        }
    }

    // MARK: logic

    private func value(_ s: String) -> Double { Double(s.filter { $0.isNumber || $0 == "." }) ?? 0 }

    private func guessCategory(_ name: String, current: String) -> String {
        let p = store.parse(name)
        return p.sureCategory ? (p.categoryId == "debt" ? "other" : (p.categoryId ?? current)) : current
    }

    private func makeSuggestion() {
        let d = store.data
        let emis = d.liveDebts.filter { $0.kind != "card" }.reduce(0) { $0 + ($1.emi ?? 0) }
        let cu = d.cardUsage()
        let r = BudgetSuggest.suggest(income: value(income), fixed: fixed.filter { $0.amount > 0 }, emis: emis, cardDebt: cu.balance,
                                      cardAPR: cu.cards.compactMap(\.rate).max() ?? 42)
        suggestion = r
        amounts = Dictionary(uniqueKeysWithValues: r.lines.map { ($0.categoryId, fmtAmount($0.amount)) })
    }

    private func save() {
        let budgets = amounts.mapValues { value($0) }
        store.applyBudgetPlan(income: value(income), fixed: fixed.filter { $0.amount > 0 && !$0.name.isEmpty }, budgets: budgets)
        router.show("Budget set · \(inr(budgets.values.reduce(0, +))) a month")
        dismiss()
    }
}

/// Wrapping row of tappable "+ Rent" chips.
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { name in
                Button { onTap(name) } label: {
                    Label(name, systemImage: "plus").font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(K.surface, in: Capsule()).overlay(Capsule().strokeBorder(K.lineStrong))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing; row = max(row, sz.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; row = max(row, sz.height)
        }
    }
}
