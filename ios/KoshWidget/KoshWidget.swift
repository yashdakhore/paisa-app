import SwiftUI
import WidgetKit

// Home Screen + Lock Screen widget: what's left this month, and one tap to add an expense by voice.
// The app writes a small snapshot to the shared App Group; if it isn't available, the widget
// still works as a one-tap voice button.

struct WidgetSnapshot: Codable {
    var month: String
    var left: Double?
    var income: Double
    var spent: Double
    var budget: Double
    var cardPct: Double?
    var updated: Date
}

enum SharedStore {
    static let group = "group.com.yashdakhore.kosh"
    static func load() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget.json"),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: raw)
    }
}

struct KoshEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct KoshProvider: TimelineProvider {
    static let sample = WidgetSnapshot(month: "", left: 12_450, income: 30_000, spent: 13_050, budget: 16_900, cardPct: 88, updated: Date())
    func placeholder(in context: Context) -> KoshEntry { KoshEntry(date: Date(), snap: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (KoshEntry) -> Void) {
        completion(KoshEntry(date: Date(), snap: SharedStore.load() ?? (context.isPreview ? Self.sample : nil)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KoshEntry>) -> Void) {
        completion(Timeline(entries: [KoshEntry(date: Date(), snap: SharedStore.load())], policy: .after(Date().addingTimeInterval(3600))))
    }
}

private let addURL = URL(string: "kosh://add")!
private let heroA = Color(red: 0.886, green: 0.329, blue: 0.102)
private let heroC = Color(red: 0.541, green: 0.114, blue: 0.027)

private func money(_ v: Double) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_IN")
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return (v < 0 ? "−₹" : "₹") + (f.string(from: NSNumber(value: abs(v.rounded()))) ?? "\(Int(abs(v)))")
}

struct MicBadge: View {
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(heroA)
            .frame(width: size, height: size)
            .background(.white, in: Circle())
    }
}

struct KoshWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KoshEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.system(size: 22, weight: .semibold))
            }
            .widgetURL(addURL)
            .accessibilityLabel("Add an expense by voice in Kosh")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Kosh", systemImage: "mic.fill").font(.headline)
                if let left = entry.snap?.left { Text("\(money(left)) left").font(.system(.body, design: .rounded).monospacedDigit()) }
                else { Text("Tap to add by voice") }
            }
            .widgetURL(addURL)
        case .systemMedium:
            medium
        default:
            small
        }
    }

    var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LEFT THIS MONTH").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
            if let s = entry.snap, let left = s.left {
                Text(money(left)).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("Spent \(money(s.spent))").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            } else {
                Text("Kosh").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Tap to add by voice").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            HStack { Spacer(); MicBadge(size: 38) }
        }
        .foregroundStyle(.white)
        .widgetURL(addURL)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [heroA, heroC], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LEFT THIS MONTH").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                if let s = entry.snap, let left = s.left {
                    Text(money(left)).font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                    Text("Spent \(money(s.spent)) of \(money(s.budget))").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                    if let p = s.cardPct { Text("Cards \(Int(p.rounded()))% used").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9)) }
                } else {
                    Text("Kosh").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Open Kosh to see your month here").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
            Link(destination: addURL) {
                VStack(spacing: 6) {
                    MicBadge(size: 54)
                    Text("Add").font(.system(size: 12, weight: .semibold))
                }
            }
            .accessibilityLabel("Add an expense by voice")
        }
        .foregroundStyle(.white)
        .widgetURL(URL(string: "kosh://home")!)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [heroA, heroC], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct KoshWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KoshWidget", provider: KoshProvider()) { entry in
            KoshWidgetView(entry: entry)
        }
        .configurationDisplayName("Kosh")
        .description("See what's left this month and add an expense by voice.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct KoshWidgets: WidgetBundle {
    var body: some Widget { KoshWidget() }
}
