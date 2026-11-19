import SwiftUI

// Design tokens — the same dark glass + orange hero look as the Kosh web app.
enum K {
    static let bg = Color(hex: 0x09090B)
    static let surface = Color.white.opacity(0.045)
    static let surface2 = Color.white.opacity(0.08)
    static let line = Color.white.opacity(0.08)
    static let lineStrong = Color.white.opacity(0.16)
    static let text = Color(hex: 0xF5F5F4)
    static let muted = Color(hex: 0xA1A1AA)
    static let faint = Color(hex: 0x71717A)
    static let brand = Color(hex: 0xFF7A2F)
    static let brand2 = Color(hex: 0xFF9F5A)
    static let brandDeep = Color(hex: 0xC93A0E)
    static let heroA = Color(hex: 0xE2541A)
    static let heroB = Color(hex: 0xC13510)
    static let heroC = Color(hex: 0x8A1D07)
    static let good = Color(hex: 0x4ADE80)
    static let warn = Color(hex: 0xFBBF24)
    static let bad = Color(hex: 0xF87171)

    static let brandGradient = LinearGradient(colors: [brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let orbGradient = RadialGradient(colors: [Color(hex: 0xFFB37A), heroA, heroC], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 60)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension Font {
    static func num(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// SF Symbols for the default categories.
func categorySymbol(_ id: String?) -> String {
    switch id {
    case "rent": return "house"
    case "bills": return "bolt"
    case "groceries": return "cart"
    case "food": return "fork.knife"
    case "transport": return "car"
    case "phone": return "iphone"
    case "shopping": return "bag"
    case "health": return "heart"
    case "entertainment": return "film"
    case "debt": return "creditcard"
    case "other": return "shippingbox"
    default: return "tag"
    }
}

// MARK: - components

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(K.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(K.line))
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = K.muted
    var body: some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .medium)).tracking(1.1).foregroundStyle(color)
    }
}

struct CardHeader: View {
    let title: String
    var action: String? = nil
    var onTap: (() -> Void)? = nil
    var body: some View {
        HStack {
            Eyebrow(text: title)
            Spacer()
            if let action, let onTap {
                Button(action: onTap) {
                    HStack(spacing: 2) { Text(action); Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(K.brand)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.bottom, 8)
    }
}

struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background {
                ZStack {
                    LinearGradient(colors: [K.heroA, K.heroB, K.heroC], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))
                    RadialGradient(colors: [Color(hex: 0xFFBE78, alpha: 0.55), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                    Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 36).frame(width: 220, height: 220).offset(x: 140, y: 90)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: K.heroA.opacity(0.45), radius: 24, y: 14)
    }
}

struct HeroAmount: View {
    let value: Double?
    var body: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value < 0 ? "−₹" : "₹").font(.num(30, .bold)).opacity(0.8)
                Text(inr(abs(value)).replacingOccurrences(of: "₹", with: "")).font(.num(46, .bold))
            }
            .minimumScaleFactor(0.6).lineLimit(1)
        } else {
            Text("—").font(.num(46, .bold))
        }
    }
}

struct HeroStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            Text(value).font(.num(16, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }
}

struct Ring: View {
    let fraction: Double
    var size: CGFloat = 112
    var line: CGFloat = 12
    var color: AnyShapeStyle = AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFB37A), K.brand, K.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
    var marks: [Double] = []
    var label: String = ""
    var sub: String = ""
    var body: some View {
        ZStack {
            Circle().stroke(K.surface2, lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: fraction)
            ForEach(marks, id: \.self) { m in
                Capsule().fill(K.text.opacity(0.7)).frame(width: 2, height: line + 6)
                    .offset(y: -(size - line) / 2)
                    .rotationEffect(.degrees(m * 360))
            }
            VStack(spacing: 2) {
                Text(label).font(.num(22, .bold))
                if !sub.isEmpty { Text(sub).font(.system(size: 11, weight: .medium)).foregroundStyle(K.muted) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(sub)")
    }
}

enum Tone { case brand, good, warn, bad }

struct Bar: View {
    let fraction: Double
    var tone: Tone = .brand
    var marks: [Double] = []
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(K.surface2)
                Capsule().fill(fill).frame(width: max(0, min(1, fraction)) * geo.size.width)
                ForEach(marks, id: \.self) { m in
                    Capsule().fill(K.text.opacity(0.5)).frame(width: 2, height: 14).offset(x: m * geo.size.width - 1)
                }
            }
        }
        .frame(height: 6)
        .padding(.vertical, 4)
    }
    var fill: AnyShapeStyle {
        switch tone {
        case .brand: return AnyShapeStyle(LinearGradient(colors: [K.brandDeep, K.brand], startPoint: .leading, endPoint: .trailing))
        case .good: return AnyShapeStyle(K.good)
        case .warn: return AnyShapeStyle(K.warn)
        case .bad: return AnyShapeStyle(K.bad)
        }
    }
}

func tone(spent: Double, budget: Double) -> Tone {
    guard budget > 0 else { return .brand }
    let r = spent / budget
    return r > 1 ? .bad : (r > 0.85 ? .warn : .brand)
}

struct Tile: View {
    let symbol: String
    var tint: Color = K.brand2
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(K.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct Pill: View {
    let text: String
    var hot = false
    var ok = false
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(hot ? K.brand.opacity(0.16) : ok ? K.good.opacity(0.14) : K.surface2, in: Capsule())
            .foregroundStyle(hot ? K.brand2 : ok ? K.good : K.muted)
    }
}

struct Banner: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(K.brand)
            Text(text).font(.system(size: 14)).foregroundStyle(Color(hex: 0xFED7AA))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(K.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(K.brand.opacity(0.25)))
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(K.brandGradient, in: Capsule())
            .shadow(color: K.brand.opacity(0.5), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButton: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(destructive ? K.bad : K.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? K.surface2 : K.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(destructive ? K.bad.opacity(0.3) : K.lineStrong))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A row with an icon tile, title/subtitle and a trailing amount.
struct ListRow: View {
    let symbol: String
    var tint: Color = K.brand2
    let title: String
    var subtitle: String? = nil
    var amount: String? = nil
    var amountColor: Color = K.text
    var amountSub: String? = nil
    var chevron = false
    var body: some View {
        HStack(spacing: 12) {
            Tile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(K.text).lineLimit(1)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(K.muted).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if let amount {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(amount).font(.num(16, .semibold)).foregroundStyle(amountColor)
                    if let amountSub { Text(amountSub).font(.system(size: 12)).foregroundStyle(K.muted) }
                }
            }
            if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(K.faint) }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(K.line).frame(height: 1) }
}

func shortDate(_ iso: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: iso) else { return iso }
    f.dateFormat = "d MMM"
    return f.string(from: d)
}

func monthTitle(_ mk: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM"
    guard let d = f.date(from: mk) else { return mk }
    f.dateFormat = "MMM yyyy"
    return f.string(from: d)
}

func shiftMonth(_ mk: String, _ n: Int) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM"
    guard let d = f.date(from: mk), let s = Parser.cal.date(byAdding: .month, value: n, to: d) else { return mk }
    return f.string(from: s)
}

