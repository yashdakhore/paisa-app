import Foundation
import Observation
import Security

/// Syncs with your own Supabase project — the same database and format the Kosh web app uses,
/// so the iPhone app, the web app on your Mac and your PC all show the same data.
/// One JSON document per user, protected by row-level security. Talks to Supabase's REST API directly.
@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    private(set) var url = UserDefaults.standard.string(forKey: "kosh.sync.url") ?? ""
    private(set) var key = UserDefaults.standard.string(forKey: "kosh.sync.key") ?? ""
    private(set) var email = UserDefaults.standard.string(forKey: "kosh.sync.email") ?? ""
    private(set) var lastSynced: Date?
    var status = ""
    var busy = false

    private var userId = UserDefaults.standard.string(forKey: "kosh.sync.uid") ?? ""
    private var accessToken: String?
    private var tokenExpiry = Date.distantPast
    private var pending: Task<Void, Never>?

    var isConfigured: Bool { !url.isEmpty && !key.isEmpty }
    var isSignedIn: Bool { isConfigured && Keychain.get("kosh.sync.refresh") != nil && !userId.isEmpty }

    func configure(url: String, key: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        self.url = u
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.url, forKey: "kosh.sync.url")
        UserDefaults.standard.set(self.key, forKey: "kosh.sync.key")
    }

    // MARK: - auth

    struct Session: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let user: User?
        let id: String?   // signup without a session returns the user at the top level
        struct User: Decodable { let id: String }
    }

    /// Returns false when the account needs email confirmation first.
    func signIn(email: String, password: String, create: Bool) async throws -> Bool {
        let path = create ? "/auth/v1/signup" : "/auth/v1/token?grant_type=password"
        let s: Session = try await post(path, body: ["email": email, "password": password], auth: false)
        guard let at = s.access_token, let rt = s.refresh_token, let uid = s.user?.id else { return false }
        store(session: at, refresh: rt, expiresIn: s.expires_in ?? 3600, uid: uid)
        self.email = email
        UserDefaults.standard.set(email, forKey: "kosh.sync.email")
        return true
    }

    func signOut() {
        Keychain.delete("kosh.sync.refresh")
        accessToken = nil
        userId = ""
        UserDefaults.standard.removeObject(forKey: "kosh.sync.uid")
        status = "Signed out"
    }

    private func store(session at: String, refresh rt: String, expiresIn: Double, uid: String) {
        accessToken = at
        tokenExpiry = Date().addingTimeInterval(expiresIn - 60)
        userId = uid
        UserDefaults.standard.set(uid, forKey: "kosh.sync.uid")
        Keychain.set("kosh.sync.refresh", rt)
    }

    private func validToken() async throws -> String {
        if let t = accessToken, Date() < tokenExpiry { return t }
        guard let rt = Keychain.get("kosh.sync.refresh") else { throw SyncError.message("Sign in to sync.") }
        let s: Session = try await post("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": rt], auth: false)
        guard let at = s.access_token, let nrt = s.refresh_token, let uid = s.user?.id else { throw SyncError.message("Your login expired. Sign in again.") }
        store(session: at, refresh: nrt, expiresIn: s.expires_in ?? 3600, uid: uid)
        return at
    }

    // MARK: - sync

    /// Sync a moment after a change, so several quick edits go up together.
    func syncSoon(_ kosh: KoshStore) {
        guard isSignedIn else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            await self?.syncNow(kosh)
        }
    }

    /// Download, merge item-by-item (newest edit wins), upload the merged copy.
    func syncNow(_ kosh: KoshStore) async {
        guard isSignedIn, !busy else { return }
        busy = true
        status = "Syncing…"
        defer { busy = false }
        do {
            let token = try await validToken()
            var req = request("/rest/v1/finance_docs?select=data&user_id=eq.\(userId)", token: token)
            req.httpMethod = "GET"
            let (raw, resp) = try await URLSession.shared.data(for: req)
            try check(resp, raw)
            var merged = kosh.data
            if let rows = try JSONSerialization.jsonObject(with: raw) as? [[String: Any]], let doc = rows.first?["data"],
               JSONSerialization.isValidJSONObject(doc) {
                let docData = try JSONSerialization.data(withJSONObject: doc)
                let remote = try JSONDecoder().decode(AppData.self, from: docData)
                merged = AppData.merge(kosh.data, remote)
            }
            kosh.replaceFromSync(merged)

            let dataObj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(merged))
            let body: [[String: Any]] = [["user_id": userId, "data": dataObj, "updated_at": ISO8601DateFormatter().string(from: Date())]]
            var up = request("/rest/v1/finance_docs", token: token)
            up.httpMethod = "POST"
            up.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            up.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (r2, resp2) = try await URLSession.shared.data(for: up)
            try check(resp2, r2)
            lastSynced = Date()
            status = "Synced at " + lastSynced!.formatted(date: .omitted, time: .shortened)
        } catch {
            status = "Sync failed: " + ((error as? SyncError)?.text ?? error.localizedDescription)
        }
    }

    // MARK: - HTTP

    enum SyncError: Error {
        case message(String)
        var text: String { if case .message(let m) = self { return m }; return "" }
    }

    private func request(_ path: String, token: String?) -> URLRequest {
        var r = URLRequest(url: URL(string: url + path)!)
        r.setValue(key, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        r.timeoutInterval = 20
        return r
    }

    private func post<T: Decodable>(_ path: String, body: [String: String], auth: Bool) async throws -> T {
        guard isConfigured, URL(string: url + path) != nil else { throw SyncError.message("Add your Supabase project URL and key first.") }
        var r = request(path, token: nil)
        r.httpMethod = "POST"
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (raw, resp) = try await URLSession.shared.data(for: r)
        try check(resp, raw)
        return try JSONDecoder().decode(T.self, from: raw)
    }

    private func check(_ resp: URLResponse, _ raw: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
            let msg = (obj?["msg"] ?? obj?["message"] ?? obj?["error_description"] ?? obj?["error"]) as? String
            if http.statusCode == 404 { throw SyncError.message("Table not found. Run the setup code in Supabase's SQL Editor.") }
            throw SyncError.message(msg ?? "Server said \(http.statusCode).")
        }
    }
}

/// Tiny Keychain wrapper for the login's refresh token.
enum Keychain {
    static func set(_ account: String, _ value: String) {
        delete(account)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                kSecValueData as String: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account] as CFDictionary)
    }
}
