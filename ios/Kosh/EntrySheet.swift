import SwiftUI

/// One item heard in a sentence like "250 groceries and 120 auto".
struct Draft: Identifiable, Equatable {
    let id = UUID()
    var amount: String
    var type: String
    var categoryId: String
    var debtId: String?
    var goalId: String?
    var investmentId: String?
    var date: String
    var note: String
    var guessed: String = ""     // category Kosh guessed, to learn from corrections
}

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
    @State private var paidWith = ""            // credit card id, "" = cash/UPI/debit
    @State private var incomeSource = ""        // "" = let Kosh guess from the note
    @State private var note = ""
    @State private var reduceDebt = true
    @State private var repeatMonthly = false
    @State private var unsureAmount = false
    @State private var unsureCategory = false
    @State private var drafts: [Draft] = []
    @State private var command: VoiceCommand?
    @State private var hint = "Speak or type an expense (“250 groceries and 120 auto”), a set-up (“add SBI card limit 50000”), or a question (“how much can I spend today?”)."
    @State private var confirmDelete = false
    @State private var pulse = false
    @FocusState private var focused: Bool

    var body: some View {
        let d = store.data
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(existing != nil ? "Edit entry" : command.map { c -> String in if case .question = c { return "Ask Kosh" } else { return "Set up" } } ?? "New entry").font(.system(size: 22, weight: .semibold, design: .rounded)).padding(.top, 8)

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
                        Text(speech.errorMessage ?? (speech.isListening ? "Listening… pause when you're done." : hint))
                            .font(.system(size: 13)).foregroundStyle(speech.errorMessage == nil ? K.muted : K.warn)
                    }

                    if let c = command {
                        commandCard(c)
                    } else if drafts.count > 1 {
                        multiItems(d)
                    } else {
                        singleItem(d)
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
        .onDisappear { speech.cancel(); Speaker.shared.stop() }
        .onChange(of: speech.transcript) { _, t in
            guard speech.isListening, !t.isEmpty else { return }
            text = t
        }
        .onChange(of: text) { _, t in applyParse(t) }
    }

    // MARK: - single item

    @ViewBuilder
    private func singleItem(_ d: AppData) -> some View {
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
        if type == .income {
            field("From") {
                Picker("From", selection: $incomeSource) {
                    Text("Kosh decides (\(AppData.incomeSourceName(AppData.guessIncomeSource(note + " " + text, myName: d.settings.myName, familyNames: d.settings.familyNames ?? []))))").tag("")
                    ForEach(AppData.incomeSources, id: \.id) { Text($0.name).tag($0.id) }
                }
            }
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
            } else if !d.liveDebts.filter({ $0.kind == "card" }).isEmpty {
                field("Paid with") {
                    Picker("Paid with", selection: $paidWith) {
                        Text("Cash / UPI / debit card").tag("")
                        ForEach(d.liveDebts.filter { $0.kind == "card" }) { Text($0.name).tag($0.id) }
                    }
                }
                if !paidWith.isEmpty {
                    Text("This adds \(amount.isEmpty ? "the amount" : inr(Double(amount) ?? 0)) to \(d.debts.first { $0.id == paidWith }?.name ?? "the card")'s balance.")
                        .font(.system(size: 12)).foregroundStyle(K.muted).padding(.horizontal, 4)
                }
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
        if existing == nil {
            Toggle(isOn: $repeatMonthly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat every month")
                    Text("Kosh will offer to add it on day \(Parser.cal.component(.day, from: date)) each month.").font(.system(size: 12)).foregroundStyle(K.muted)
                }
            }
            .tint(K.brand).padding(.horizontal, 4)
        }

        HStack(spacing: 10) {
            Button("Cancel") { speech.cancel(); dismiss() }.buttonStyle(SecondaryButton())
            Button("Save", action: saveSingle).buttonStyle(PrimaryButton())
        }
        .padding(.top, 6)
        if existing != nil {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                .buttonStyle(SecondaryButton(destructive: true))
        }
    }

    // MARK: - set-up commands and questions

    @ViewBuilder
    private func commandCard(_ c: VoiceCommand) -> some View {
        let p = store.preview(c)
        let isQuestion: Bool = { if case .question = c { return true } else { return false } }()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isQuestion ? "bubble.left.and.text.bubble.right" : "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(K.brand)
                Text(p.title).font(.system(size: 18, weight: .semibold))
            }
            ForEach(p.lines, id: \.self) { line in
                Text(line).font(.system(size: isQuestion ? 17 : 16)).foregroundStyle(isQuestion ? K.text : K.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = p.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.system(size: 14)).foregroundStyle(K.warn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(K.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

        HStack(spacing: 10) {
            if isQuestion {
                Button {
                    if case .question(let q) = c { Speaker.shared.say(store.answer(q)) }
                } label: { Label("Read aloud", systemImage: "speaker.wave.2") }.buttonStyle(SecondaryButton())
                Button("Done") { Speaker.shared.stop(); dismiss() }.buttonStyle(PrimaryButton())
            } else {
                Button("Cancel") { speech.cancel(); dismiss() }.buttonStyle(SecondaryButton())
                Button("Save") {
                    let msg = store.perform(c)
                    router.show(msg)
                    dismiss()
                }
                .buttonStyle(PrimaryButton()).disabled(!p.canSave).opacity(p.canSave ? 1 : 0.5)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - several items

    @ViewBuilder
    private func multiItems(_ d: AppData) -> some View {
        Eyebrow(text: "\(drafts.count) items heard").padding(.top, 4)
        ForEach($drafts) { $draft in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: draft.type == "income" ? "arrow.down.left" : categorySymbol(draft.categoryId))
                        .foregroundStyle(K.brand2).frame(width: 36, height: 36)
                        .background(K.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    TextField("0", text: $draft.amount).keyboardType(.decimalPad).font(.num(18, .semibold)).frame(maxWidth: 110)
                    Spacer()
                    Text(shortDate(draft.date)).font(.system(size: 13)).foregroundStyle(K.muted)
                    Button { drafts.removeAll { $0.id == draft.id } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(K.faint)
                    }
                    .accessibilityLabel("Remove this item")
                }
                if draft.type == "expense" {
                    Picker("Category", selection: $draft.categoryId) { ForEach(d.liveCategories) { Text($0.name).tag($0.id) } }
                        .pickerStyle(.menu)
                }
                TextField("Note", text: $draft.note).font(.system(size: 14)).foregroundStyle(K.muted)
            }
            .padding(14)
            .background(K.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(K.lineStrong))
        }
        let total = drafts.compactMap { Double($0.amount) }.reduce(0, +)
        HStack(spacing: 10) {
            Button("Cancel") { speech.cancel(); dismiss() }.buttonStyle(SecondaryButton())
            Button("Save all · \(inr(total))", action: saveAll).buttonStyle(PrimaryButton())
        }
        .padding(.top, 6)
    }

    // MARK: - pieces

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

    // MARK: - logic

    private func setup() {
        speech.onFinish = { t in
            text = t
            applyParse(t)
            if let c = command {
                if case .question(let q) = c { Speaker.shared.say(store.answer(q)); hint = "Ask another question with the mic, or tap Done." }
                else { hint = "Check what Kosh understood, then tap Save." }
                return
            }
            if drafts.count > 1 { hint = "Check each item, then tap Save all." }
            else { hint = unsureAmount ? "Couldn't hear an amount. Type it in below." : "Check the details, then tap Save. Orange boxes are guesses." }
        }
        if let e = existing {
            amount = fmtAmount(e.amount)
            date = isoDate(e.date) ?? Date()
            type = EntryType(rawValue: e.type) ?? .expense
            categoryId = e.categoryId ?? "other"
            debtId = e.debtId ?? ""
            goalId = e.goalId ?? ""
            investmentId = e.investmentId ?? ""
            paidWith = e.cardId ?? ""
            incomeSource = e.incomeSource ?? ""
            note = e.note ?? ""
            return
        }
        if !prefill.isEmpty { text = prefill; applyParse(prefill) }
        if autoListen { speech.toggle() } else if prefill.isEmpty { focused = true }
    }

    private func applyParse(_ t: String) {
        guard existing == nil, !t.trimmingCharacters(in: .whitespaces).isEmpty else { command = nil; return }
        command = Commands.parse(t)
        if command != nil { drafts = []; return }
        let results = store.parseMany(t)
        if results.count > 1 {
            drafts = results.map { p in
                Draft(amount: p.amount.map(fmtAmount) ?? "", type: p.type, categoryId: p.categoryId ?? "other", debtId: p.debtId,
                      goalId: p.goalId, investmentId: p.investmentId, date: p.date, note: p.note, guessed: p.categoryId ?? "other")
            }
            return
        }
        drafts = []
        let p = results[0]
        if let a = p.amount { amount = fmtAmount(a) }
        date = isoDate(p.date) ?? date
        type = EntryType(rawValue: p.type) ?? .expense
        if let c = p.categoryId { categoryId = c }
        debtId = p.debtId ?? ""
        // "spent 500 on swiggy with sbi card": a purchase on the card, not a card payment.
        if p.categoryId != "debt", let dId = p.debtId, store.data.debts.first(where: { $0.id == dId })?.kind == "card" { paidWith = dId } else { paidWith = "" }
        if let g = p.goalId { goalId = g }
        if let i = p.investmentId { investmentId = i }
        note = p.note
        unsureAmount = !p.sureAmount
        unsureCategory = p.type == "expense" && !p.sureCategory
    }

    private func saveSingle() {
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
        e.cardId = (type == .expense && categoryId != "debt" && !paidWith.isEmpty) ? paidWith : nil
        e.incomeSource = type == .income ? (incomeSource.isEmpty ? AppData.guessIncomeSource(note + " " + text, myName: store.data.settings.myName, familyNames: store.data.settings.familyNames ?? []) : incomeSource) : nil
        if existing == nil {
            e.applied = type == .expense ? ((e.debtId != nil && reduceDebt) || e.cardId != nil) : (e.goalId != nil || e.investmentId != nil)
        } else if e.cardId != nil {
            e.applied = true
        }
        // Learn from corrections: if Kosh guessed a different category, remember these words.
        var learned: [String] = []
        if type == .expense, categoryId != "debt", categoryId != "other" {
            if let old = existing, old.categoryId != categoryId {
                learned = store.learn(from: note.isEmpty ? (old.note ?? "") : note, categoryId: categoryId)
            } else if existing == nil, !text.isEmpty, store.parse(text).categoryId != categoryId {
                learned = store.learn(from: note.isEmpty ? text : note, categoryId: categoryId)
            }
        }
        store.saveEntry(e, previous: existing)
        if existing == nil, repeatMonthly { store.makeRecurring(from: e) }
        let catName = type == .expense ? (store.data.category(categoryId)?.name ?? "") : type.label
        if existing == nil {
            let id = e.id
            let s = store
            router.show("Saved \(inr(amt)) · \(catName)" + (repeatMonthly ? " · repeats monthly" : "") + (learned.isEmpty ? "" : " · learned “\(learned.joined(separator: " "))”")) { s.deleteEntries([id]) }
        } else {
            router.show("Updated \(inr(amt))")
        }
        dismiss()
    }

    private func saveAll() {
        speech.cancel()
        var ids: [String] = []
        var total = 0.0
        for dr in drafts {
            guard let amt = Double(dr.amount.replacingOccurrences(of: ",", with: "")), amt > 0 else { continue }
            var e = Entry(id: newId(), type: dr.type, amount: amt, date: dr.date, note: dr.note,
                          categoryId: dr.type == "expense" ? dr.categoryId : nil,
                          debtId: dr.type == "expense" && dr.categoryId == "debt" ? dr.debtId : nil,
                          goalId: dr.type == "save" ? dr.goalId : nil,
                          investmentId: dr.type == "invest" ? dr.investmentId : nil,
                          createdAt: ISO8601DateFormatter().string(from: Date()), source: text)
            e.applied = e.debtId != nil || e.goalId != nil || e.investmentId != nil
            if dr.type == "expense", dr.categoryId != dr.guessed, dr.categoryId != "other", dr.categoryId != "debt" {
                store.learn(from: dr.note, categoryId: dr.categoryId)
            }
            store.saveEntry(e, previous: nil)
            ids.append(e.id)
            total += amt
        }
        guard !ids.isEmpty else { hint = "Add an amount to at least one item."; return }
        let s = store
        router.show("Saved \(ids.count) items · \(inr(total))") { s.deleteEntries(ids) }
        dismiss()
    }
}

func fmtAmount(_ a: Double) -> String { a == a.rounded() ? String(Int(a)) : String(a) }

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

func isoDate(_ s: String) -> Date? {
    let f = DateFormatter()
    f.calendar = Parser.cal
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: s)
}
