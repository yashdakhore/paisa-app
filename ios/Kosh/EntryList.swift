import SwiftUI

/// One list for every screen: filter chips by kind, grouped by day with day totals, 20 at a time.
struct EntryList: View {
    let entries: [Entry]
    var showFilters = true
    var pageSize = 20
    var emptyText = "No entries."
    @State private var filter = "all"
    @State private var shown = 20

    static let filters: [(id: String, name: String)] = [("all", "All"), ("expense", "Spent"), ("income", "Earned"), ("move", "Moved"),
                                                        ("held", "Held"), ("owed", "Lent"), ("save", "Saved")]

    var body: some View {
        let sorted = entries.sorted { $0.date == $1.date ? ($0.createdAt ?? "") > ($1.createdAt ?? "") : $0.date > $1.date }
        let counts = Dictionary(grouping: sorted, by: { $0.type == "invest" ? "save" : $0.type }).mapValues(\.count)
        let list = filter == "all" ? sorted : sorted.filter { ($0.type == "invest" ? "save" : $0.type) == filter }
        let page = Array(list.prefix(shown))
        let days = Dictionary(grouping: page, by: \.date)
        let order = page.map(\.date).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }

        VStack(alignment: .leading, spacing: 0) {
            if showFilters, counts.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.filters.filter { $0.id == "all" || counts[$0.id] != nil }, id: \.id) { f in
                            let n = f.id == "all" ? sorted.count : (counts[f.id] ?? 0)
                            Button { filter = f.id; shown = pageSize } label: {
                                Text("\(f.name) \(n)").font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(filter == f.id ? .white : K.text)
                                    .padding(.horizontal, 12).frame(minHeight: 34)
                                    .background(filter == f.id ? AnyShapeStyle(K.brandGradient) : AnyShapeStyle(K.surface2), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            if list.isEmpty { Text(emptyText).foregroundStyle(K.muted).padding(.vertical, 6) }
            ForEach(order, id: \.self) { day in
                let es = days[day] ?? []
                let out = es.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
                let inn = es.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
                HStack {
                    Text(dayTitle(day)).font(.system(size: 12, weight: .semibold)).foregroundStyle(K.muted).textCase(.uppercase)
                    Spacer()
                    Text([out > 0 ? "−" + inr(out) : nil, inn > 0 ? "+" + inr(inn) : nil].compactMap { $0 }.joined(separator: "  "))
                        .font(.num(12, .medium)).foregroundStyle(K.faint)
                }
                .padding(.top, day == order.first ? 0 : 14).padding(.bottom, 2)
                ForEach(Array(es.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { RowDivider() }
                    EntryRow(entry: e, showDate: false)
                }
            }
            if list.count > shown {
                Button { withAnimation { shown += pageSize } } label: {
                    Label("Show \(min(pageSize, list.count - shown)) more · \(list.count - shown) left", systemImage: "chevron.down")
                }
                .buttonStyle(SecondaryButton()).padding(.top, 12)
            }
        }
        .onChange(of: entries.count) { _, _ in if shown < pageSize { shown = pageSize } }
        .onAppear { shown = pageSize }
    }

    func dayTitle(_ iso: String) -> String {
        let today = Parser.iso(Date())
        if iso == today { return "Today" }
        if iso == Parser.iso(Parser.addDays(Date(), -1)) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }
}
