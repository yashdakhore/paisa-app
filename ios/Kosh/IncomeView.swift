import Charts
import SwiftUI

/// Budget → Income: where this month's money came from, salary status, and every money-in entry.
struct IncomeView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let mk = router.month
        let ms = d.monthSummary(mk)
        let incomes = ms.entries.filter { $0.type == "income" }.sorted { $0.date > $1.date }
        let salaryEntries = incomes.filter { d.incomeSource($0) == "salary" }
        let expected = d.settings.salary ?? 0

        VStack(spacing: 12) {
            HeroCard {
                Eyebrow(text: "Income · \(monthTitle(mk))", color: .white.opacity(0.85)).padding(.bottom, 8)
                HeroAmount(value: ms.income)
                Group {
                    if let s = salaryEntries.first {
                        Label("Salary \(inr(salaryEntries.reduce(0) { $0 + $1.amount })) received \(shortDate(s.date))", systemImage: "checkmark.circle")
                    } else if expected > 0 {
                        Label("Salary \(inr(expected)) not arrived yet · counted as expected", systemImage: "clock")
                    } else {
                        Label("Add your salary to plan around it", systemImage: "briefcase")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.black.opacity(0.22), in: Capsule())
                .padding(.top, 12)
                HStack(spacing: 8) {
                    HeroStat(label: "Salary", value: inr(ms.salaryIncome))
                    HeroStat(label: "Extra", value: inr(ms.extraIncome))
                    HeroStat(label: "Left", value: inr(ms.left))
                }
                .padding(.top, 20)
            }

            HStack(spacing: 8) {
                Button { router.newEntry(listen: false, text: "received ") } label: { Label("Add income", systemImage: "plus") }
                    .buttonStyle(PrimaryButton())
                Button { router.sheet = .income } label: { Label("Salary", systemImage: "briefcase") }
                    .buttonStyle(SecondaryButton())
            }

            Card {
                CardHeader(title: "Where it came from")
                let rows = AppData.incomeSources.compactMap { src -> (String, String, Double)? in
                    let v = src.id == "salary" ? ms.salaryIncome : (ms.bySource[src.id] ?? 0)
                    return v > 0 ? (src.id, src.name, v) : nil
                }
                if rows.isEmpty { Text("No money in yet this month.").foregroundStyle(K.muted) }
                ForEach(Array(rows.enumerated()), id: \.element.0) { i, r in
                    if i > 0 { RowDivider() }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.1).font(.system(size: 15, weight: .medium))
                            if r.0 == "salary", salaryEntries.isEmpty, expected > 0 { Text("expected").font(.system(size: 12)).foregroundStyle(K.faint) }
                            Spacer()
                            Text(inr(r.2)).font(.num(15, .semibold))
                        }
                        GeometryReader { g in
                            Capsule().fill(K.surface2).overlay(alignment: .leading) {
                                Capsule().fill(r.0 == "salary" ? AnyShapeStyle(K.brandGradient) : AnyShapeStyle(K.good.opacity(0.8)))
                                    .frame(width: max(6, g.size.width * CGFloat(r.2 / max(ms.income, 1))))
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 6)
                }
                Text("Family money and refunds add to this month. Your budget plan uses salary only.")
                    .font(.system(size: 12)).foregroundStyle(K.faint).padding(.top, 6)
            }

            let months = lastMonths(6, endingAt: mk)
            let bars = months.flatMap { m -> [(String, String, Double)] in
                let s = d.monthSummary(m)
                // Past months: only salary that actually arrived (the saved figure is just this month's expectation).
                let sal = m == monthKey(Date()) ? s.salaryIncome : (s.bySource["salary"] ?? 0)
                return [(m, "Salary", sal), (m, "Extra", s.extraIncome)]
            }
            if bars.contains(where: { $0.2 > 0 }) {
                Card {
                    CardHeader(title: "Last 6 months")
                    Chart {
                        ForEach(Array(bars.enumerated()), id: \.offset) { _, b in
                            BarMark(x: .value("Month", shortMonth(b.0)), y: .value("Amount", b.2))
                                .foregroundStyle(by: .value("Kind", b.1))
                                .cornerRadius(4)
                        }
                    }
                    .chartForegroundStyleScale(["Salary": K.brand, "Extra": K.good])
                    .chartYAxis {
                        AxisMarks(position: .leading) { v in
                            AxisGridLine().foregroundStyle(K.line)
                            AxisValueLabel { if let n = v.as(Double.self) { Text(n >= 1000 ? "\(Int(n / 1000))k" : "\(Int(n))").foregroundStyle(K.faint) } }
                        }
                    }
                    .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(K.muted) } }
                    .frame(height: 170)
                }
            }

            Card {
                CardHeader(title: "Money in · \(incomes.count)")
                EntryList(entries: incomes, showFilters: false, emptyText: "Nothing yet. Bank alerts land here automatically, or tap Add income.")
                if !incomes.isEmpty { Text("Tap one to change where it came from.").font(.system(size: 12)).foregroundStyle(K.faint).padding(.top, 4) }
            }

            HeldMoneyCard()
        }
    }
}
