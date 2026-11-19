import Charts
import SwiftUI

/// Rough, commonly used bands for Indian credit scores (300–900).
func scoreBand(_ s: Double) -> (label: String, color: Color) {
    switch s {
    case 750...: return ("Excellent", K.good)
    case 700..<750: return ("Good", Color(hex: 0xA3E635))
    case 650..<700: return ("Fair", K.warn)
    default: return ("Needs work", K.bad)
    }
}

private let bureauColors: [String: Color] = [
    "CIBIL": Color(hex: 0xFF7A2F), "Experian": Color(hex: 0x67E8F9), "Equifax": Color(hex: 0xC4B5FD), "CRIF": Color(hex: 0xFBBF24),
]

/// Plan → Credit: latest score per bureau, trend chart, history.
struct CreditView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let scores = store.liveScores
        VStack(spacing: 12) {
            Card {
                CardHeader(title: "Latest scores")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(KoshStore.bureaus, id: \.self) { b in bureauTile(b, scores.filter { $0.bureau == b }) }
                }
                Button { router.sheet = .scores(nil) } label: { Label("Log this month's scores", systemImage: "plus") }
                    .buttonStyle(PrimaryButton()).padding(.top, 14)
            }

            if scores.count >= 2 {
                Card {
                    CardHeader(title: "Trend")
                    let lo = max(300, (scores.map(\.score).min() ?? 600) - 30)
                    let hi = min(900, (scores.map(\.score).max() ?? 800) + 30)
                    Chart {
                        ForEach(scores) { s in
                            LineMark(x: .value("Date", isoDate(s.date) ?? Date()), y: .value("Score", s.score))
                                .foregroundStyle(by: .value("Bureau", s.bureau))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", isoDate(s.date) ?? Date()), y: .value("Score", s.score))
                                .foregroundStyle(by: .value("Bureau", s.bureau))
                                .symbolSize(30)
                        }
                        if lo < 750, hi > 750 {
                            RuleMark(y: .value("Excellent", 750)).foregroundStyle(K.good.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    .chartForegroundStyleScale(domain: KoshStore.bureaus, range: KoshStore.bureaus.map { bureauColors[$0] ?? K.brand })
                    .chartYScale(domain: lo...hi)
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(K.line); AxisValueLabel().foregroundStyle(K.faint) } }
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(K.muted) } }
                    .chartLegend(position: .bottom)
                    .frame(height: 200)
                    Text("The dashed line marks 750, the usual “excellent” mark.").font(.system(size: 12)).foregroundStyle(K.faint).padding(.top, 6)
                }
            }

            Card {
                CardHeader(title: "What moves your score")
                VStack(alignment: .leading, spacing: 8) {
                    tip("creditcard", "Card usage: yours is \(Int(store.data.cardUsage().pct.rounded()))% now. Under 30% helps; under 10% is best.")
                    tip("calendar.badge.checkmark", "Paying every bill on time. Bill reminders are in More.")
                    tip("hand.raised", "Fewer new loan or card applications." + ((store.data.settings.rule?.isEmpty == false) ? " Your reminder: \(store.data.settings.rule!)" : ""))
                    tip("clock.arrow.circlepath", "Bureaus update roughly monthly, so give changes 30–45 days to show.")
                }
            }

            if !scores.isEmpty {
                Card {
                    CardHeader(title: "History")
                    ForEach(Array(scores.reversed().enumerated()), id: \.element.id) { i, s in
                        if i > 0 { RowDivider() }
                        HStack {
                            Circle().fill(bureauColors[s.bureau] ?? K.brand).frame(width: 10, height: 10)
                            Text(s.bureau).font(.system(size: 15, weight: .medium))
                            Text(shortDate(s.date)).font(.system(size: 13)).foregroundStyle(K.muted)
                            Spacer()
                            Text("\(Int(s.score))").font(.num(17, .semibold))
                        }
                        .padding(.vertical, 10)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteScore(s.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    Text("Press and hold a row to delete it.").font(.system(size: 12)).foregroundStyle(K.faint).padding(.top, 6)
                }
            }
        }
    }

    @ViewBuilder
    func bureauTile(_ b: String, _ list: [CreditScore]) -> some View {
        let last = list.last
        let prev = list.dropLast().last
        Button { router.sheet = .scores(b) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(bureauColors[b] ?? K.brand).frame(width: 8, height: 8)
                    Text(b).font(.system(size: 13, weight: .medium)).foregroundStyle(K.muted)
                }
                if let last {
                    Text("\(Int(last.score))").font(.num(28, .bold)).foregroundStyle(K.text)
                    HStack(spacing: 6) {
                        Text(scoreBand(last.score).label).font(.system(size: 12, weight: .semibold)).foregroundStyle(scoreBand(last.score).color)
                        if let prev {
                            let d = Int(last.score - prev.score)
                            Text(d >= 0 ? "▲\(d)" : "▼\(-d)").font(.system(size: 12, weight: .semibold)).foregroundStyle(d >= 0 ? K.good : K.bad)
                        }
                    }
                    Text(shortDate(last.date)).font(.system(size: 11)).foregroundStyle(K.faint)
                } else {
                    Text("—").font(.num(28, .bold)).foregroundStyle(K.faint)
                    Text("Tap to add").font(.system(size: 12)).foregroundStyle(K.muted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(K.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(last.map { "\(b) \(Int($0.score))" } ?? "\(b), no score yet")
    }

    func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(K.brand).frame(width: 20)
            Text(text).font(.system(size: 14)).foregroundStyle(K.muted)
        }
    }
}

/// Log scores from any of the four bureaus for one date.
struct ScoreForm: View {
    @Environment(KoshStore.self) private var store
    let focusBureau: String?
    @State private var date = Date()
    @State private var values: [String: String] = [:]
    @State private var note = ""

    var body: some View {
        FormShell(title: "Log credit scores", onSave: save) {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            Section {
                ForEach(KoshStore.bureaus, id: \.self) { b in
                    LabeledContent(b) {
                        TextField("300–900", text: Binding(get: { values[b] ?? "" }, set: { values[b] = $0 }))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
            } header: { Text("Scores") } footer: {
                Text("Fill in the ones you checked. Free reports: CIBIL (cibil.com), Experian, Equifax and CRIF High Mark each give one free report a year, and many card apps show a score monthly.")
            }
            Section("Note") { TextField("optional", text: $note) }
        }
    }

    func save() -> String? {
        var saved = 0
        for b in KoshStore.bureaus {
            guard let raw = values[b]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { continue }
            guard let v = Double(raw), (300...900).contains(v) else { return "\(b) score must be between 300 and 900." }
            store.saveScore(CreditScore(id: newId(), bureau: b, score: v, date: Parser.iso(date), note: note.isEmpty ? nil : note))
            saved += 1
        }
        return saved == 0 ? "Enter at least one score." : nil
    }
}
