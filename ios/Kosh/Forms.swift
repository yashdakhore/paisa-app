import SwiftUI

// Edit forms. Numbers are typed as text so an empty box means "not set".

private func num(_ s: String) -> Double? {
    let t = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    return t.isEmpty ? nil : Double(t)
}
private func str(_ v: Double?) -> String {
    guard let v else { return "" }
    return v == v.rounded() ? String(Int(v)) : String(v)
}

/// Shared shell: title, Cancel/Save, optional Delete, dark form styling.
struct FormShell<Content: View>: View {
    let title: String
    var canDelete = false
    var onSave: () -> String?   // returns an error message, or nil when saved
    var onDelete: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                content
                if let error { Section { Text(error).foregroundStyle(K.bad) } }
                if canDelete, onDelete != nil {
                    Section {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x121215))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let e = onSave() { error = e } else { dismiss() }
                    }.bold()
                }
            }
            .confirmationDialog("Delete this?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete?(); dismiss() }
            }
        }
        .tint(K.brand)
    }
}

struct CategoryForm: View {
    @Environment(KoshStore.self) private var store
    let existing: Category?
    @State private var name = ""
    @State private var budget = ""
    @State private var keywords = ""

    var body: some View {
        FormShell(title: existing == nil ? "New category" : "Edit category", canDelete: existing != nil && existing?.id != "other",
                  onSave: save, onDelete: { if let c = existing { store.deleteCategory(c.id) } }) {
            Section {
                TextField("Name", text: $name)
                LabeledContent("Monthly budget (₹)") { TextField("0", text: $budget).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section {
                TextField("e.g. swiggy, zomato, lunch", text: $keywords, axis: .vertical)
            } header: { Text("Voice keywords") } footer: { Text("Words that mean this category when you speak, separated by commas.") }
        }
        .onAppear {
            guard let c = existing else { return }
            name = c.name; budget = str(c.budget); keywords = (c.keywords ?? []).joined(separator: ", ")
        }
    }

    func save() -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "Enter a name." }
        var c = existing ?? Category(id: newId(), name: n, order: Double(store.data.categories.count))
        c.name = n
        c.budget = num(budget) ?? 0
        c.keywords = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        store.saveCategory(c)
        return nil
    }
}

struct GoalForm: View {
    @Environment(KoshStore.self) private var store
    let existing: Goal?
    @State private var name = ""
    @State private var kind = "save"
    @State private var target = ""
    @State private var saved = ""
    @State private var debtId = CARDS
    @State private var targetPct = "30"
    @State private var hasDeadline = true
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 12, to: Date())!
    @State private var priority = ""

    var body: some View {
        FormShell(title: existing == nil ? "New goal" : "Edit goal", canDelete: existing != nil,
                  onSave: save, onDelete: { if let g = existing { store.deleteGoal(g.id) } }) {
            Section {
                TextField("Goal name", text: $name)
                Picker("Kind", selection: $kind) {
                    Text("Save up an amount").tag("save")
                    Text("Pay off a debt").tag("debt")
                    Text("Card usage under a %").tag("cardUsage")
                }
            }
            Section {
                if kind == "save" {
                    LabeledContent("Target (₹)") { TextField("0", text: $target).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    LabeledContent("Saved so far (₹)") { TextField("0", text: $saved).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                } else if kind == "debt" {
                    Picker("Debt", selection: $debtId) {
                        Text("All credit cards").tag(CARDS)
                        ForEach(store.data.liveDebts) { Text($0.name).tag($0.id) }
                    }
                } else {
                    LabeledContent("Target usage (%)") { TextField("30", text: $targetPct).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
            }
            Section {
                Toggle("Finish by a date", isOn: $hasDeadline)
                if hasDeadline { DatePicker("Month", selection: $deadline, displayedComponents: .date) }
                LabeledContent("Priority (1 = first)") { TextField("1", text: $priority).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            }
        }
        .onAppear {
            guard let g = existing else { priority = String(store.data.liveGoals.count + 1); return }
            name = g.name; kind = g.kind; target = str(g.target); saved = str(g.saved)
            debtId = g.debtId ?? CARDS; targetPct = str(g.targetPct ?? 30); priority = str(g.priority)
            if let dl = g.deadline, let dd = isoDate(dl + "-01") { deadline = dd; hasDeadline = true } else { hasDeadline = false }
        }
    }

    func save() -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "Enter a name." }
        var g = existing ?? Goal(id: newId(), name: n, kind: kind)
        g.name = n
        g.kind = kind
        g.target = kind == "save" ? num(target) : nil
        g.saved = kind == "save" ? (num(saved) ?? 0) : nil
        g.debtId = kind == "save" ? nil : (kind == "cardUsage" ? CARDS : debtId)
        g.targetPct = kind == "cardUsage" ? (num(targetPct) ?? 30) : nil
        g.deadline = hasDeadline ? String(Parser.iso(deadline).prefix(7)) : nil
        g.priority = num(priority)
        if kind != "save", g.startBalance == nil {
            g.startBalance = (kind == "cardUsage" || g.debtId == CARDS) ? store.data.cardUsage().balance : (store.data.liveDebts.first { $0.id == g.debtId }?.balance ?? 0)
        }
        store.saveGoal(g)
        return nil
    }
}

struct DebtForm: View {
    @Environment(KoshStore.self) private var store
    let existing: Debt?
    @State private var name = ""
    @State private var kind = "card"
    @State private var balance = ""
    @State private var limit = ""
    @State private var emi = ""
    @State private var rate = ""
    @State private var dueDay = ""
    @State private var note = ""

    var body: some View {
        FormShell(title: existing == nil ? "New debt" : "Edit debt", canDelete: existing != nil,
                  onSave: save, onDelete: { if let d = existing { store.deleteDebt(d.id) } }) {
            Section {
                TextField("Name (e.g. SBI Card, mPokket)", text: $name)
                Picker("Kind", selection: $kind) { Text("Credit card").tag("card"); Text("Loan").tag("loan"); Text("EMI").tag("emi") }
                LabeledContent("Amount owed (₹)") { TextField("0", text: $balance).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if kind == "card" { LabeledContent("Credit limit (₹)") { TextField("0", text: $limit).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
                else { LabeledContent("EMI per month (₹)") { TextField("0", text: $emi).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
                LabeledContent("Interest % a year") { TextField("optional", text: $rate).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("Due day (1–31)") { TextField("optional", text: $dueDay).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            }
            Section("Note") { TextField("optional", text: $note, axis: .vertical) }
        }
        .onAppear {
            guard let d = existing else { return }
            name = d.name; kind = d.kind; balance = str(d.balance); limit = str(d.limit); emi = str(d.emi)
            rate = str(d.rate); dueDay = str(d.dueDay); note = d.note ?? ""
        }
    }

    func save() -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "Enter a name." }
        if let day = num(dueDay), !(1...31).contains(day) { return "Due day must be between 1 and 31." }
        var d = existing ?? Debt(id: newId(), name: n, kind: kind)
        d.name = n; d.kind = kind; d.balance = num(balance) ?? 0
        d.limit = kind == "card" ? num(limit) : nil
        d.emi = kind == "card" ? nil : num(emi)
        d.rate = num(rate); d.dueDay = num(dueDay); d.note = note
        d.keywords = n.lowercased().split(separator: " ").map(String.init).filter { $0.count > 2 && !["card", "loan", "other", "cards"].contains($0) }
        store.saveDebt(d)
        return nil
    }
}

struct InvestmentForm: View {
    @Environment(KoshStore.self) private var store
    let existing: Investment?
    @State private var name = ""
    @State private var type = "SIP"
    @State private var monthly = ""
    @State private var invested = ""
    @State private var value = ""
    @State private var hasMaturity = false
    @State private var maturity = Date()
    @State private var note = ""
    let types = Subcats.investmentTypes

    var body: some View {
        FormShell(title: existing == nil ? "New investment" : "Update investment", canDelete: existing != nil,
                  onSave: save, onDelete: { if let i = existing { store.deleteInvestment(i.id) } }) {
            Section {
                TextField("Name (e.g. Flexi Cap SIP)", text: $name)
                Picker("Type", selection: $type) { ForEach(types, id: \.self) { Text($0).tag($0) } }
                LabeledContent("Monthly (₹)") { TextField("0", text: $monthly).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("Invested so far (₹)") { TextField("0", text: $invested).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("Current value (₹)") { TextField("0", text: $value).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            } footer: { Text("Update the current value from your fund app once a month.") }
            Section {
                Toggle("Has a maturity date", isOn: $hasMaturity)
                if hasMaturity { DatePicker("Matures", selection: $maturity, displayedComponents: .date) }
            }
            Section("Note") { TextField("optional", text: $note, axis: .vertical) }
        }
        .onAppear {
            guard let i = existing else { return }
            name = i.name; type = types.contains(i.type) ? i.type : (i.type == "Gold" ? "Gold / SGB" : "Other")
            monthly = str(i.monthly); invested = str(i.invested); value = str(i.value); note = i.note ?? ""
            if let m = i.maturity, let d = isoDate(m) { hasMaturity = true; maturity = d }
        }
    }

    func save() -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "Enter a name." }
        var i = existing ?? Investment(id: newId(), name: n, type: type)
        i.name = n; i.type = type; i.monthly = num(monthly); i.invested = num(invested); i.value = num(value)
        i.maturity = hasMaturity ? Parser.iso(maturity) : nil
        i.note = note
        store.saveInvestment(i)
        return nil
    }
}

struct IncomeForm: View {
    @Environment(KoshStore.self) private var store
    @State private var salary = ""
    @State private var rule = ""
    var body: some View {
        FormShell(title: "Income & reminder", onSave: {
            if !salary.isEmpty, num(salary) == nil { return "Enter the salary as a number." }
            store.saveSettings(salary: num(salary), rule: rule.trimmingCharacters(in: .whitespaces))
            return nil
        }) {
            Section {
                LabeledContent("Take-home salary (₹)") { TextField("e.g. 30000", text: $salary).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            } footer: { Text("If you log income (say “got salary 30000”), that's used for the month instead.") }
            Section("Reminder shown on Home") { TextField("Reminder", text: $rule, axis: .vertical) }
        }
        .onAppear {
            salary = str(store.data.settings.salary)
            rule = store.data.settings.rule ?? ""
        }
    }
}
