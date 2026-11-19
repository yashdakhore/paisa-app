import SwiftUI

/// Home card: repeating entries due this month, added with one tap.
struct DueRecurringCard: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let due = store.dueRecurring()
        if !due.isEmpty {
            Card {
                CardHeader(title: "Due this month")
                ForEach(Array(due.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { RowDivider() }
                    HStack(spacing: 10) {
                        ListRow(symbol: symbol(r), title: r.note, subtitle: "Day \(Int(r.day)) · repeats monthly", amount: inr(r.amount))
                        Button {
                            let e = store.addRecurring(r)
                            let s = store
                            router.show("Added \(r.note)") { s.deleteEntries([e.id]) }
                        } label: {
                            Text("Add").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(minHeight: 36).background(K.brandGradient, in: Capsule())
                        }
                        .accessibilityLabel("Add \(r.note)")
                        Menu {
                            Button("Skip this month") { store.skipRecurring(r) }
                            Button("Edit…") { router.sheet = .recurring(r) }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 32, height: 36).foregroundStyle(K.muted)
                        }
                        .accessibilityLabel("More options for \(r.note)")
                    }
                }
                if due.count > 1 {
                    Button {
                        let ids = due.map { store.addRecurring($0).id }
                        let s = store
                        router.show("Added \(ids.count) entries") { s.deleteEntries(ids) }
                    } label: { Label("Add all \(due.count) · \(inr(due.reduce(0) { $0 + $1.amount }))", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButton()).padding(.top, 12)
                }
            }
        }
    }

    func symbol(_ r: Recurring) -> String {
        switch r.type {
        case "income": return "arrow.down.left"
        case "save": return "wallet.pass"
        case "invest": return "chart.line.uptrend.xyaxis"
        default: return categorySymbol(r.categoryId)
        }
    }
}

/// More → Repeating entries.
struct RecurringList: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Recurring?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.liveRecurring.isEmpty {
                        Text("Nothing repeats yet. When you save rent, a recharge or your SIP, switch on “Repeat every month”, or add one here.")
                            .foregroundStyle(K.muted)
                    }
                    ForEach(store.liveRecurring) { r in
                        Button { editing = r } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(r.note).foregroundStyle(K.text)
                                    Text("Day \(Int(r.day)) each month" + (r.active == false ? " · paused" : "")).font(.system(size: 13)).foregroundStyle(K.muted)
                                }
                                Spacer()
                                Text(inr(r.amount)).font(.num(16, .semibold)).foregroundStyle(K.text)
                            }
                        }
                    }
                } footer: { Text("Kosh shows these on Home when they're due, and can remind you on the day.") }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x121215))
            .navigationTitle("Repeating entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add repeating entry") }
            }
            .sheet(item: $editing) { r in RecurringForm(existing: r).environment(store) }
            .sheet(isPresented: $adding) { RecurringForm(existing: nil).environment(store) }
        }
        .tint(K.brand)
    }
}

struct RecurringForm: View {
    @Environment(KoshStore.self) private var store
    let existing: Recurring?
    @State private var note = ""
    @State private var type = "expense"
    @State private var amount = ""
    @State private var categoryId = "rent"
    @State private var debtId = ""
    @State private var investmentId = ""
    @State private var day = 1
    @State private var active = true

    var body: some View {
        let d = store.data
        FormShell(title: existing == nil ? "New repeating entry" : "Repeating entry", canDelete: existing != nil,
                  onSave: save, onDelete: { if let r = existing { store.deleteRecurring(r.id) } }) {
            Section {
                TextField("Name (e.g. Rent, Jio recharge)", text: $note)
                Picker("Type", selection: $type) { ForEach(EntryType.allCases.prefix(4)) { Text($0.label).tag($0.rawValue) } }
                LabeledContent("Amount (₹)") { TextField("0", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if type == "expense" {
                    Picker("Category", selection: $categoryId) { ForEach(d.liveCategories) { Text($0.name).tag($0.id) } }
                    if categoryId == "debt" {
                        Picker("Card/loan", selection: $debtId) {
                            Text("— not linked —").tag("")
                            ForEach(d.liveDebts) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                if type == "invest" {
                    Picker("Investment", selection: $investmentId) {
                        Text("— choose —").tag("")
                        ForEach(d.liveInvestments) { Text($0.name).tag($0.id) }
                    }
                }
                Stepper("Day \(day) of each month", value: $day, in: 1...31)
                Toggle("Active", isOn: $active)
            }
        }
        .onAppear {
            guard let r = existing else { return }
            note = r.note; type = r.type; amount = fmtAmount(r.amount); categoryId = r.categoryId ?? "other"
            debtId = r.debtId ?? ""; investmentId = r.investmentId ?? ""; day = Int(r.day); active = r.active != false
        }
    }

    func save() -> String? {
        let n = note.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "Enter a name." }
        guard let a = Double(amount.replacingOccurrences(of: ",", with: "")), a > 0 else { return "Enter an amount." }
        var r = existing ?? Recurring(id: newId(), note: n, type: type, amount: a, day: Double(day))
        r.note = n; r.type = type; r.amount = a; r.day = Double(day); r.active = active
        r.categoryId = type == "expense" ? categoryId : nil
        r.debtId = (type == "expense" && categoryId == "debt" && !debtId.isEmpty) ? debtId : nil
        r.investmentId = (type == "invest" && !investmentId.isEmpty) ? investmentId : nil
        store.saveRecurring(r)
        return nil
    }
}
