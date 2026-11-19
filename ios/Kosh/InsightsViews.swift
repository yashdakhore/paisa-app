import Charts
import SwiftUI

enum BudgetSeg: String, CaseIterable { case budget = "Budget", income = "Income", trends = "Trends", search = "Search" }

/// Budget tab: the month's budget, spending trends, and search across all entries.
struct BudgetView: View {
    @Environment(Router.self) private var router
    var body: some View {
        @Bindable var router = router
        VStack(spacing: 12) {
            Picker("View", selection: $router.budgetSeg) { ForEach(BudgetSeg.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            switch router.budgetSeg {
            case .budget: BudgetMain()
            case .income: IncomeView()
            case .trends: TrendsView()
            case .search: SearchView()
            }
        }
    }
}


func lastMonths(_ count: Int, endingAt mk: String) -> [String] {
    (0..<count).reversed().map { shiftMonth(mk, -$0) }
}

func shortMonth(_ mk: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM"
    guard let d = f.date(from: mk) else { return mk }
    f.dateFormat = "MMM"
    return f.string(from: d)
}

struct MonthBar: Identifiable {
    let mk: String
    let value: Double
    var id: String { mk }
}

struct TrendsView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let mk = router.month
        let months = lastMonths(6, endingAt: mk)
        let bars = months.map { MonthBar(mk: $0, value: d.spent(in: $0)) }
        let earlier = bars.dropLast().filter { $0.value > 0 }
        let avg = earlier.isEmpty ? 0 : earlier.reduce(0) { $0 + $1.value } / Double(earlier.count)
        let thisMonth = bars.last?.value ?? 0
        let lastMonth = d.spent(in: shiftMonth(mk, -1))
        let isCurrent = mk == monthKey(Date())
        let dayNow = Parser.cal.component(.day, from: Date())
        let daysInMonth = Parser.cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        // Card/loan payments aren't part of the spending budget, so leave them out of the pace.
        let spendOnly = thisMonth - d.spent(in: mk, category: "debt")
        let projected = isCurrent && dayNow > 0 ? spendOnly / Double(dayNow) * Double(daysInMonth) : spendOnly
        let budget = d.liveCategories.filter { $0.id != "debt" }.reduce(0) { $0 + ($1.budget ?? 0) }

        VStack(spacing: 12) {
            Card {
                CardHeader(title: "Spending · last 6 months")
                Chart {
                    ForEach(bars) { b in
                        BarMark(x: .value("Month", shortMonth(b.mk)), y: .value("Spent", b.value))
                            .foregroundStyle(b.mk == mk
                                ? AnyShapeStyle(LinearGradient(colors: [K.brand2, K.brandDeep], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(K.surface2))
                            .cornerRadius(6)
                    }
                    if avg > 0 {
                        RuleMark(y: .value("Average", avg))
                            .foregroundStyle(K.muted)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("avg \(inr(avg))").font(.system(size: 11)).foregroundStyle(K.muted)
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(K.line)
                        AxisValueLabel { if let n = v.as(Double.self) { Text(n >= 1000 ? "\(Int(n / 1000))k" : "\(Int(n))").foregroundStyle(K.faint) } }
                    }
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(K.muted) } }
                .frame(height: 190)
                .accessibilityLabel("Spending for the last 6 months. This month \(inr(thisMonth)).")
            }

            Card {
                CardHeader(title: "This month")
                HStack(spacing: 8) {
                    stat("Spent", inr(thisMonth))
                    stat("Last month", inr(lastMonth))
                    stat(isCurrent ? "On pace for" : "Budget", inr(isCurrent ? projected : budget),
                         tint: isCurrent && budget > 0 && projected > budget ? K.bad : K.text)
                }
                if isCurrent, budget > 0 {
                    Text(projected > budget
                         ? "At this pace you'll go over your \(inr(budget)) budget by \(inr(projected - budget)). Your daily average is \(inr(spendOnly / Double(max(1, dayNow)))) (card and loan payments not counted)."
                         : "At this pace you'll stay \(inr(budget - projected)) under your \(inr(budget)) budget (card and loan payments not counted).")
                        .font(.system(size: 13)).foregroundStyle(K.muted).padding(.top, 10)
                }
            }

            Button { router.sheet = .summary(mk) } label: {
                Label("\(monthTitle(mk)) summary", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(SecondaryButton())

            Card {
                CardHeader(title: "By category vs last month")
                let rows = d.liveCategories.map { c -> (Category, Double, Double) in
                    (c, d.spent(in: mk, category: c.id), d.spent(in: shiftMonth(mk, -1), category: c.id))
                }.filter { $0.1 > 0 || $0.2 > 0 }.sorted { $0.1 > $1.1 }
                if rows.isEmpty { Text("No spending yet in these two months.").foregroundStyle(K.muted) }
                ForEach(Array(rows.enumerated()), id: \.element.0.id) { i, row in
                    if i > 0 { RowDivider() }
                    Button { router.sheet = .categoryDetail(row.0) } label: {
                        HStack(spacing: 12) {
                            Tile(symbol: categorySymbol(row.0.id))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.0.name).font(.system(size: 16, weight: .medium))
                                Text("Last month \(inr(row.2))").font(.system(size: 13)).foregroundStyle(K.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(inr(row.1)).font(.num(16, .semibold))
                                delta(row.1, row.2)
                            }
                        }
                        .foregroundStyle(K.text).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func stat(_ label: String, _ value: String, tint: Color = K.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(K.muted)
            Text(value).font(.num(16, .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(K.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    func delta(_ now: Double, _ before: Double) -> some View {
        if before > 0 {
            let p = (now - before) / before * 100
            Text((p >= 0 ? "▲ " : "▼ ") + "\(Int(abs(p).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p > 5 ? K.bad : (p < -5 ? K.good : K.muted))
        } else {
            Text("new").font(.system(size: 12)).foregroundStyle(K.muted)
        }
    }
}

struct SearchView: View {
    @Environment(KoshStore.self) private var store
    @State private var query = ""

    var body: some View {
        let d = store.data
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let results = q.isEmpty ? [] : d.liveEntries.filter { e in
            let cat = d.category(e.categoryId)?.name.lowercased() ?? ""
            return (e.note ?? "").lowercased().contains(q) || cat.contains(q) || fmtAmount(e.amount).contains(q) || e.type.contains(q) || shortDate(e.date).lowercased().contains(q)
        }.sorted { $0.date > $1.date }
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(K.muted)
                TextField("Search notes, categories or amounts", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(K.faint) }.accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(K.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(K.lineStrong))

            if !q.isEmpty {
                Card {
                    CardHeader(title: "\(results.count) result\(results.count == 1 ? "" : "s") · \(inr(results.reduce(0) { $0 + $1.amount }))")
                    EntryList(entries: results, emptyText: "Nothing matches “\(query)”.")
                }
            } else {
                Text("Try “swiggy”, “rent”, “250” or “Nov”.").font(.system(size: 14)).foregroundStyle(K.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Tap a category: this month's spending vs budget, its 6-month history, and its entries.
struct CategoryDetail: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    let category: Category
    @State private var editing = false

    var body: some View {
        let d = store.data
        let c = d.categories.first { $0.id == category.id } ?? category
        let mk = router.month
        let spent = d.spent(in: mk, category: c.id)
        let budget = c.budget ?? 0
        let bars = lastMonths(6, endingAt: mk).map { MonthBar(mk: $0, value: d.spent(in: $0, category: c.id)) }
        let entries = d.liveEntries.filter { $0.type == "expense" && ($0.categoryId ?? "other") == c.id && monthKey($0.date) == mk }.sorted { $0.date > $1.date }

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Card {
                        HStack(spacing: 18) {
                            Ring(fraction: budget > 0 ? spent / budget : 0, size: 104, line: 11,
                                 color: budget > 0 && spent > budget ? AnyShapeStyle(K.bad) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFB37A), K.brand, K.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)),
                                 label: budget > 0 ? "\(Int((spent / budget * 100).rounded()))%" : "—", sub: budget > 0 ? "of budget" : "no budget")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(inr(spent)).font(.num(24, .bold))
                                Text(budget > 0 ? (budget - spent >= 0 ? "\(inr(budget - spent)) left of \(inr(budget))" : "\(inr(spent - budget)) over \(inr(budget))") : "Set a budget to track it")
                                    .font(.system(size: 14)).foregroundStyle(budget > 0 && spent > budget ? K.bad : K.muted)
                                Button { editing = true } label: { Label("Edit budget", systemImage: "pencil").font(.system(size: 14, weight: .medium)) }
                                    .padding(.top, 6)
                            }
                        }
                    }
                    Card {
                        CardHeader(title: "Last 6 months")
                        Chart(bars) { b in
                            BarMark(x: .value("Month", shortMonth(b.mk)), y: .value("Spent", b.value))
                                .foregroundStyle(b.mk == mk ? AnyShapeStyle(K.brandGradient) : AnyShapeStyle(K.surface2))
                                .cornerRadius(5)
                            if budget > 0 {
                                RuleMark(y: .value("Budget", budget)).foregroundStyle(K.warn.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }
                        }
                        .chartYAxis(.hidden)
                        .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(K.muted) } }
                        .frame(height: 140)
                    }
                    let bySub = Dictionary(grouping: entries, by: { d.subcategory($0) ?? "" }).mapValues { $0.reduce(0) { $0 + $1.amount } }
                    if !Subcats.subs(c.id).isEmpty, bySub.keys.contains(where: { !$0.isEmpty }) {
                        Card {
                            CardHeader(title: "Breakdown")
                            let rows = bySub.sorted { $0.value > $1.value }
                            ForEach(Array(rows.enumerated()), id: \.element.key) { i, r in
                                if i > 0 { RowDivider() }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(Subcats.name(c.id, r.key) ?? "Other").font(.system(size: 15, weight: .medium))
                                        Spacer()
                                        Text(inr(r.value)).font(.num(15, .semibold))
                                    }
                                    GeometryReader { g in
                                        Capsule().fill(K.surface2).overlay(alignment: .leading) {
                                            Capsule().fill(K.brandGradient).frame(width: max(6, g.size.width * CGFloat(r.value / max(spent, 1))))
                                        }
                                    }
                                    .frame(height: 6)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    Card {
                        CardHeader(title: "Entries · \(monthTitle(mk))")
                        EntryList(entries: entries, showFilters: false, emptyText: "Nothing in \(c.name) this month.")
                    }
                }
                .padding(16)
            }
            .background(Color(hex: 0x121215))
            .navigationTitle(c.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $editing) { CategoryForm(existing: c).environment(store) }
        }
        .tint(K.brand)
    }
}
