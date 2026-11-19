import Observation
import SwiftUI
import UserNotifications

@main
struct KoshApp: App {
    @State private var store = KoshStore.shared
    @State private var router = Router()
    @State private var lock = AppLock()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        GmailService.registerBackground()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(lock)
                .preferredColorScheme(.dark)
                .tint(K.brand)
        }
    }
}

enum Tab: String { case home, budget, plan, more }
enum PlanSeg: String, CaseIterable { case month = "Month", goals = "Goals", debts = "Debts", invest = "Invest", credit = "Credit" }

enum SheetRoute: Identifiable {
    case entry(Entry?, listen: Bool, text: String)
    case category(Category?)
    case goal(Goal?)
    case debt(Debt?)
    case investment(Investment?)
    case income
    case recurring(Recurring?)
    case recurringList
    case categoryDetail(Category)
    case scores(String?)
    case summary(String)
    case sync
    case payoff
    case smsSetup
    case gmail
    case budgetWizard
    case pot(String)
    case people
    case guesses

    var id: String {
        switch self {
        case .entry(let e, let l, let t): return "entry-\(e?.id ?? "new")-\(l)-\(t)"
        case .category(let c): return "cat-\(c?.id ?? "new")"
        case .goal(let g): return "goal-\(g?.id ?? "new")"
        case .debt(let d): return "debt-\(d?.id ?? "new")"
        case .investment(let i): return "inv-\(i?.id ?? "new")"
        case .income: return "income"
        case .recurring(let r): return "rec-\(r?.id ?? "new")"
        case .recurringList: return "recurring-list"
        case .categoryDetail(let c): return "catdetail-\(c.id)"
        case .scores(let b): return "scores-\(b ?? "all")"
        case .summary(let mk): return "summary-\(mk)"
        case .sync: return "sync"
        case .payoff: return "payoff"
        case .smsSetup: return "sms"
        case .gmail: return "gmail"
        case .budgetWizard: return "budget-wizard"
        case .pot(let id): return "pot-\(id)"
        case .people: return "people"
        case .guesses: return "guesses"
        }
    }
}

@Observable
final class Router {
    var tab: Tab = .home
    var planSeg: PlanSeg = .month
    var budgetSeg: BudgetSeg = .budget
    var month: String = monthKey(Date())
    var sheet: SheetRoute?
    var toast: String?
    var toastUndo: (() -> Void)?
    private var toastSerial = 0

    func newEntry(listen: Bool = true, text: String = "") { sheet = .entry(nil, listen: listen, text: text) }
    func show(_ message: String, undo: (() -> Void)? = nil) {
        toast = message
        toastUndo = undo
        toastSerial += 1
        let serial = toastSerial
        DispatchQueue.main.asyncAfter(deadline: .now() + (undo == nil ? 2.4 : 8)) {
            if self.toastSerial == serial { self.toast = nil; self.toastUndo = nil }
        }
    }
}

/// Text handed over from the Siri shortcut, picked up by the app when it opens.
@Observable
final class PendingEntry {
    static let shared = PendingEntry()
    var text: String?
}

struct RootView: View {
    @Environment(KoshStore.self) private var store
    @Environment(Router.self) private var router
    @State private var pending = PendingEntry.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppLock.self) private var lock

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            K.bg.ignoresSafeArea()
            RadialGradient(colors: [K.brand.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 380)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                Header()
                ScrollView {
                    Group {
                        switch router.tab {
                        case .home: HomeView()
                        case .budget: BudgetView()
                        case .plan: PlanView()
                        case .more: MoreView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 130)
                }
                .scrollIndicators(.hidden)
            }

            TabBar()

            if let t = router.toast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(K.good)
                    Text(t).font(.system(size: 14)).lineLimit(2)
                    if let undo = router.toastUndo {
                        Button {
                            undo()
                            router.show("Undone")
                        } label: {
                            Text("Undo").font(.system(size: 14, weight: .semibold)).foregroundStyle(K.brand)
                                .padding(.horizontal, 10).frame(minHeight: 36)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 110)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if lock.enabled && (lock.locked || scenePhase != .active) {
                LockScreen().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: router.toast)
        .sheet(item: $router.sheet) { route in
            Group {
                switch route {
                case .entry(let e, let listen, let text): EntrySheet(existing: e, autoListen: listen, prefill: text)
                case .category(let c): CategoryForm(existing: c)
                case .goal(let g): GoalForm(existing: g)
                case .debt(let d): DebtForm(existing: d)
                case .investment(let i): InvestmentForm(existing: i)
                case .income: IncomeForm()
                case .recurring(let r): RecurringForm(existing: r)
                case .recurringList: RecurringList()
                case .categoryDetail(let c): CategoryDetail(category: c)
                case .scores(let b): ScoreForm(focusBureau: b)
                case .summary(let mk): MonthlySummary(month: mk)
                case .sync: SyncSettings()
                case .payoff: PayoffPlanner()
                case .smsSetup: SMSSetup()
                case .gmail: GmailSetup()
                case .budgetWizard: BudgetWizard()
                case .pot(let id): PotDetail(potId: id)
                case .people: PeopleRules()
                case .guesses: GuessCheck()
                }
            }
            .environment(store)
            .environment(router)
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: 0x121215))
            .preferredColorScheme(.dark)
        }
        .onChange(of: pending.text) { _, new in
            if let t = new, !t.isEmpty { router.newEntry(listen: false, text: t); pending.text = nil }
        }
        .onOpenURL { url in
            guard url.scheme == "kosh" else { return }
            router.tab = .home
            if url.host == "add" { router.newEntry(listen: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Reminders.reschedule(store.data)
                if GmailService.shared.isConnected { GmailService.scheduleBackground() }
                if lock.enabled { router.sheet = nil; lock.lockNow() }
            }
            if phase == .active {
                lock.unlock()
                store.recategorizeBankEntries()
                store.flushInbox()
                store.repairIncomeSources()
                Task {
                    await GmailService.shared.check()
                    await SyncService.shared.syncNow(store)
                }
            }
        }
        .task {
            let s = store
            store.onSaved = { SyncService.shared.syncSoon(s) }
        }
        .onAppear {
            if let t = pending.text, !t.isEmpty { router.newEntry(listen: false, text: t); pending.text = nil }
        }
    }
}

struct Header: View {
    @Environment(Router.self) private var router
    var body: some View {
        HStack(spacing: 10) {
            Text("K").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(LinearGradient(colors: [K.heroA, K.heroC], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: K.heroA.opacity(0.35), radius: 9, y: 6)
            Text(title).font(.system(size: 20, weight: .semibold, design: .rounded))
            Spacer()
            if router.tab == .home || router.tab == .budget {
                HStack(spacing: 0) {
                    Button { router.month = shiftMonth(router.month, -1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                        .accessibilityLabel("Previous month")
                    Text(monthTitle(router.month)).font(.system(size: 14, weight: .medium)).monospacedDigit()
                    Button { router.month = shiftMonth(router.month, 1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                        .accessibilityLabel("Next month")
                }
                .foregroundStyle(K.muted)
                .background(K.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(K.line))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    var title: String {
        switch router.tab { case .home: return "Kosh"; case .budget: return "Budget"; case .plan: return "Plan"; case .more: return "Settings" }
    }
}

struct TabBar: View {
    @Environment(Router.self) private var router
    var body: some View {
        HStack(spacing: 0) {
            item(.home, "house", "Home")
            item(.budget, "chart.pie", "Budget")
            Button { router.newEntry(listen: true) } label: {
                Image(systemName: "mic.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(K.orbGradient, in: Circle())
                    .overlay(Circle().strokeBorder(K.bg, lineWidth: 4))
                    .shadow(color: K.brand.opacity(0.7), radius: 16, y: 8)
            }
            .offset(y: -22)
            .padding(.horizontal, 4)
            .accessibilityLabel("Add entry by voice")
            item(.plan, "target", "Plan")
            item(.more, "slider.horizontal.3", "More")
        }
        .padding(6)
        .frame(height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(K.lineStrong))
        .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    func item(_ t: Tab, _ symbol: String, _ label: String) -> some View {
        let on = router.tab == t
        return Button { router.tab = t } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(on ? K.brand : K.faint)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(on ? K.text : K.faint)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(on ? K.surface2 : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
