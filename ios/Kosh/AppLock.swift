import LocalAuthentication
import Observation
import SwiftUI

/// Optional Face ID / passcode lock. Kosh locks when it goes to the background,
/// and hides its contents in the app switcher.
@Observable
final class AppLock {
    private static let key = "kosh.faceid"
    private(set) var enabled = UserDefaults.standard.bool(forKey: AppLock.key)
    var locked = UserDefaults.standard.bool(forKey: AppLock.key)
    private var authenticating = false

    var methodName: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Turning the lock on asks for Face ID first, so you can't lock yourself out by mistake.
    func setEnabled(_ on: Bool, done: @escaping (Bool) -> Void) {
        guard on else {
            enabled = false; locked = false
            UserDefaults.standard.set(false, forKey: AppLock.key)
            done(true); return
        }
        authenticate(reason: "Turn on the lock for Kosh") { ok in
            if ok { self.enabled = true; UserDefaults.standard.set(true, forKey: AppLock.key) }
            done(ok)
        }
    }

    func unlock() {
        guard enabled, locked, !authenticating else { return }
        authenticate(reason: "Unlock Kosh to see your finances") { ok in if ok { self.locked = false } }
    }

    func lockNow() { if enabled { locked = true } }

    private func authenticate(reason: String, done: @escaping (Bool) -> Void) {
        let c = LAContext()
        var err: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { done(false); return }
        authenticating = true
        c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { self.authenticating = false; done(ok) }
        }
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock
    var body: some View {
        ZStack {
            K.bg.ignoresSafeArea()
            RadialGradient(colors: [K.brand.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 420).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("K").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(LinearGradient(colors: [K.heroA, K.heroC], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: K.heroA.opacity(0.5), radius: 20, y: 10)
                Text("Kosh is locked").font(.system(size: 22, weight: .semibold, design: .rounded))
                Button { lock.unlock() } label: {
                    Label("Unlock with \(lock.methodName)", systemImage: lock.methodName == "Face ID" ? "faceid" : "lock.open")
                }
                .buttonStyle(PrimaryButton())
                .frame(maxWidth: 280)
            }
        }
        .onAppear { lock.unlock() }
    }
}
