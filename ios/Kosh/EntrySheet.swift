import SwiftUI

/// Add or edit an entry. New entries start listening right away when opened from the mic.
struct EntrySheet: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    let existing: Entry?
    let autoListen: Bool
    let prefill: String

    @State private var speech = SpeechRecognizer()
    @State private var text = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var type: EntryType = .expense
    @State private var categoryId = "other"
    @State private var debtId = ""
    @State private var goalId = ""
    @State private var investmentId = ""
    @State private var note = ""
    @State private var reduceDebt = true
    @State private var unsureAmount = false
    @State private var unsureCategory = false
    @State private var hint = "Tap the mic and speak, or type. Check the details, then Save."
    @State private var confirmDelete = false
    @State private var pulse = false
    @FocusState private var focused: Bool

    var body: some View {
        let d = store.data
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(existing == nil ? "New entry" : "Edit entry").font(.system(size: 22, weight: .semibold, design: .rounded)).padding(.top, 8)

                if existing == nil {
                    HStack(alignment: .top, spacing: 12) {
                        TextField("Say or type: “spent 250 on groceries”", text: $text, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.system(size: 17))
                            .focused($focused)
                            .padding(14)
                            .frame(minHeight: 64, alignment: .topLeading)
                            .background(K.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(speech.isListening ? K.brand : K.lineStrong))
                        micButton
                    }
                    Text(speech.errorMessage ?? hint).font(.system(size: 13)).foregroundStyle(speech.errorMessage == nil ? K.muted : K.warn)
                }

                HStack(alignment: .top, spacing: 12) {
                    field("Amount (₹)", unsure: unsureAmount) {
                        TextField("0", text: $amount).keyboardType(.decimalPad).font(.num(18, .semibold))
                    }
                    field("Date") {
                        DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                    }
                }

                field("Type") {
                    Picker("Type", selection: $type) { ForEach(EntryType.allCases) { Text($0.label).tag($0) } }
                }

                if type == .expense {
                    field("Category", unsure: unsureCategory) {
                        Picker("Category", selection: $categoryId) { ForEach(d.liveCategories) { Text($0.name).tag($0.id) } }
                    }
                    if categoryId == "debt" {
                        field("Which card/loan?") {
                            Picker("Debt", selection: $debtId) {
                                Text("— not linked —").tag("")
                                ForEach(d.liveDebts) { Text($0.name).tag($0.id) }
                            }
                        }
                        if existing == nil { Toggle("Also lower that balance", isOn: $reduceDebt).tint(K.brand).padding(.horizontal, 4) }
                    }
                }
                if type == .save {
                    field("Goal") {
                        Picker("Goal", selection: $goalId) {
                            Text("— choose —").tag("")
                            ForEach(d.liveGoals.filter { $0.kind == "save" }) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                if type == .invest {
                    field("Investment") {
                        Picker("Investment", selection: $investmentId) {
                            Text("— choose —").tag("")
                            ForEach(d.liveInvestments) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                field("Note") { TextField("optional", text: $note) }

                HStack(spacing: 10) {
                    Button("Cancel") { speech.cancel(); dismiss() }.buttonStyle(SecondaryButton())
                    Button("Save", action: saveEntry).buttonStyle(PrimaryButton())
                }
                .padding(.top, 6)
                if existing != nil {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        .buttonStyle(SecondaryButton(destructive: true))
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }.bold()
            }
        }
        }
        .tint(K.brand)
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let e = existing { store.deleteEntry(e); router.show("Deleted") }
                dismiss()
            }
        }
        .onAppear(perform: setup)
        .onDisappear { speech.cancel() }
        .onChange(of: speech.transcript) { _, t in
            guard speech.isListening, !t.isEmpty else { return }
            text = t
        }
        .onChange(of: text) { _, t in applyParse(t) }
    }

    private var micButton: some View {
        Button { speech.toggle() } label: {
            ZStack {
                if speech.isListening {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(K.brand, lineWidth: 2)
                        .scaleEffect(pulse ? 1.18 : 0.96).opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
                        .onAppear { pulse = true }.onDisappear { pulse = false }
                }
                Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: speech.isListening)
            }
            .frame(width: 64, height: 64)
            .background(K.orbGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: K.brand.opacity(0.6), radius: 12, y: 6)
        }
        .accessibilityLabel(speech.isListening ? "Stop listening" : "Speak")
    }

    private func field<V: View>(_ label: String, unsure: Bool = false, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(K.muted)
            HStack { content(); Spacer(minLength: 0) }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(K.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(unsure ? K.warn : K.lineStrong))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setup() {
        speech.onFinish = { t in
            text = t
            applyParse(t)
            hint = unsureAmount ? "Couldn't hear an amount. Type it in below." : "Check the details, then tap Save. Orange boxes are guesses."
        }
        if let e = existing {
            amount = e.amount == e.amount.rounded() ? String(Int(e.amount)) : String(e.amount)
            date = isoDate(e.date) ?? Date()
            type = EntryType(rawValue: e.type) ?? .expense
            categoryId = e.categoryId ?? "other"
            debtId = e.debtId ?? ""
            goalId = e.goalId ?? ""
            investmentId = e.investmentId ?? ""
            note = e.note ?? ""
            return
        }
        if !prefill.isEmpty { text = prefill; applyParse(prefill) }
        if autoListen { speech.toggle() } else if prefill.isEmpty { focused = true }
    }

    private func applyParse(_ t: String) {
        guard existing == nil, !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let p = store.parse(t)
        if let a = p.amount { amount = a == a.rounded() ? String(Int(a)) : String(a) }
        date = isoDate(p.date) ?? date
        type = EntryType(rawValue: p.type) ?? .expense
        if let c = p.categoryId { categoryId = c }
        debtId = p.debtId ?? ""
        if let g = p.goalId { goalId = g }
        if let i = p.investmentId { investmentId = i }
        note = p.note
        unsureAmount = !p.sureAmount
        unsureCategory = p.type == "expense" && !p.sureCategory
    }

    private func saveEntry() {
        guard let amt = Double(amount.replacingOccurrences(of: ",", with: "")), amt > 0 else {
            hint = "Enter an amount."
            unsureAmount = true
            return
        }
        speech.cancel()
        var e = existing ?? Entry(id: newId(), type: "expense", amount: 0, date: "", createdAt: ISO8601DateFormatter().string(from: Date()), source: text)
        e.type = type.rawValue
        e.amount = amt
        e.date = Parser.iso(date)
        e.note = note.trimmingCharacters(in: .whitespaces)
        e.categoryId = type == .expense ? categoryId : nil
        e.debtId = (type == .expense && categoryId == "debt" && !debtId.isEmpty) ? debtId : nil
        e.goalId = (type == .save && !goalId.isEmpty) ? goalId : nil
        e.investmentId = (type == .invest && !investmentId.isEmpty) ? investmentId : nil
        if existing == nil {
            e.applied = type == .expense ? (e.debtId != nil && reduceDebt) : (e.goalId != nil || e.investmentId != nil)
        }
        store.saveEntry(e, previous: existing)
        let catName = type == .expense ? (store.data.category(categoryId)?.name ?? "") : type.label
        router.show("Saved \(inr(amt)) · \(catName)")
        dismiss()
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

func isoDate(_ s: String) -> Date? {
    let f = DateFormatter()
    f.calendar = Parser.cal
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: s)
}
