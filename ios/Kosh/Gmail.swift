import AuthenticationServices
import BackgroundTasks
import CryptoKit
import Foundation
import Observation
import UIKit

/// Connect Gmail (read-only) and pull bank alert emails into "From your bank".
/// Runs on the iPhone only: Google → Kosh directly, no server in between.
@MainActor
@Observable
final class GmailService: NSObject {
    static let shared = GmailService()
    static let bgTask = "com.yashdakhore.kosh.gmail"

    private let d = UserDefaults.standard
    var clientId: String { d.string(forKey: "gmail.clientId") ?? "" }
    var email: String { d.string(forKey: "gmail.email") ?? "" }
    var extraSenders: String { d.string(forKey: "gmail.extraSenders") ?? "" }
    var isConnected: Bool { Keychain.get("kosh.gmail.refresh") != nil && !clientId.isEmpty }
    var lastCheck: Date? { d.double(forKey: "gmail.lastCheck") > 0 ? Date(timeIntervalSince1970: d.double(forKey: "gmail.lastCheck")) : nil }
    var status = ""
    var busy = false

    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var authSession: ASWebAuthenticationSession?

    static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    /// "1234-abc.apps.googleusercontent.com" (or a pasted block containing it).
    static func extractClientId(_ text: String) -> String? {
        guard let r = text.range(of: "[0-9]+-[a-z0-9]+\\.apps\\.googleusercontent\\.com", options: .regularExpression) else { return nil }
        return String(text[r])
    }
    /// Google's iOS redirect: the client ID reversed, e.g. com.googleusercontent.apps.1234-abc
    static func redirectScheme(_ clientId: String) -> String {
        "com.googleusercontent.apps." + clientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    func setClientId(_ id: String) {
        d.set(id, forKey: "gmail.clientId")
        status = ""
    }
    func setExtraSenders(_ s: String) { d.set(s, forKey: "gmail.extraSenders") }
    var startFrom: String {
        get { d.string(forKey: "gmail.startFrom") ?? "month" }
        set { d.set(newValue, forKey: "gmail.startFrom") }
    }

    var senders: [String] {
        GmailMessage.defaultSenders + extraSenders.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).map(String.init)
    }

    // MARK: sign in (OAuth with PKCE, no client secret)

    func connect() async {
        guard !clientId.isEmpty else { status = "Paste your Google client ID first."; return }
        busy = true; defer { busy = false }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let scheme = Self.redirectScheme(clientId)
        let redirect = scheme + ":/oauth2redirect"
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [.init(name: "client_id", value: clientId), .init(name: "redirect_uri", value: redirect),
                        .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scope),
                        .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent")]
        do {
            let callback: URL = try await withCheckedThrowingContinuation { cont in
                let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: scheme) { url, error in
                    if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? URLError(.cancelled)) }
                }
                s.presentationContextProvider = self
                s.prefersEphemeralWebBrowserSession = false
                authSession = s
                s.start()
            }
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let err = items.first(where: { $0.name == "error" })?.value { status = "Google said: \(err)"; return }
            guard let code = items.first(where: { $0.name == "code" })?.value else { status = "Google didn't send a sign-in code."; return }
            let tok = try await token(["code": code, "client_id": clientId, "redirect_uri": redirect,
                                       "grant_type": "authorization_code", "code_verifier": verifier])
            guard let rt = tok.refresh_token else { status = "Google didn't allow offline access. Try again."; return }
            Keychain.delete("kosh.gmail.refresh")
            Keychain.set("kosh.gmail.refresh", rt)
            accessToken = tok.access_token
            accessExpiry = Date().addingTimeInterval(Double(tok.expires_in ?? 3000) - 60)
            if let p: Profile = try? await get("https://gmail.googleapis.com/gmail/v1/users/me/profile") { d.set(p.emailAddress, forKey: "gmail.email") }
            status = "Connected."
            busy = false
            let start = d.string(forKey: "gmail.startFrom") ?? "month"
            if start == "month" { _ = await check(since: GmailMessage.firstOfMonth()) }
            else if start == "week" { _ = await check(days: 7) }
            else { _ = await check(days: 1) }
            Self.scheduleBackground()
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            status = ""
        } catch {
            status = (error as? GmailError)?.message ?? error.localizedDescription
        }
    }

    func disconnect() {
        if let rt = Keychain.get("kosh.gmail.refresh") {
            var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = "token=\(rt)".data(using: .utf8)
            URLSession.shared.dataTask(with: r).resume()
        }
        Keychain.delete("kosh.gmail.refresh")
        accessToken = nil
        d.removeObject(forKey: "gmail.email")
        status = "Disconnected."
    }

    // MARK: fetch

    /// Look for alert emails. Automatic checks look back a few days and skip emails already read;
    /// a fetch you start (`since`, e.g. the 1st of the month) reads every email in the range again,
    /// and the duplicate check (bank reference / email ID) keeps anything from being added twice.
    @discardableResult
    func check(days: Int = 3, since: Date? = nil, notify: Bool = false) async -> [InboxItem] {
        guard isConnected, !busy else { return [] }
        busy = true; defer { busy = false }
        let manual = since != nil
        do {
            let q = since.map { GmailMessage.query(senders: senders, since: $0) } ?? GmailMessage.query(senders: senders, days: days)
            var refs: [MessageList.Ref] = []
            var page: String? = nil
            repeat {
                var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
                c.queryItems = [.init(name: "q", value: q), .init(name: "maxResults", value: "100")] + (page.map { [.init(name: "pageToken", value: $0)] } ?? [])
                let list: MessageList = try await get(c.url!.absoluteString)
                refs += list.messages ?? []
                page = list.nextPageToken
                if manual { status = "Finding emails… \(refs.count)" }
            } while page != nil && refs.count < 600
            var seen = Set(d.stringArray(forKey: "gmail.seen") ?? [])
            var added: [InboxItem] = []
            let todo = refs.reversed().filter { manual || !seen.contains($0.id) }
            for (i, ref) in todo.enumerated() {
                let m: GmailMessage.Message = try await get("https://gmail.googleapis.com/gmail/v1/users/me/messages/\(ref.id)?format=full")
                let when = GmailMessage.date(m) ?? Date()
                if let since, when < since { seen.insert(ref.id); continue }
                if let item = KoshStore.shared.addBankMessage(GmailMessage.text(m), now: when, gmailId: ref.id, manual: manual) {
                    added.append(item)
                    if notify { BudgetAlerts.notifyInbox(item) }
                }
                seen.insert(ref.id)
                if manual { status = "Reading \(i + 1) of \(todo.count) emails · \(added.count) found" }
            }
            d.set(Array(seen.suffix(1500)), forKey: "gmail.seen")
            d.set(Date().timeIntervalSince1970, forKey: "gmail.lastCheck")
            status = added.isEmpty ? (manual ? "No new transactions in \(todo.count) emails." : "Up to date.")
                                   : "Found \(added.count) new · review them on Home."
            return added
        } catch {
            status = (error as? GmailError)?.message ?? error.localizedDescription
            return []
        }
    }

    // MARK: background refresh (iOS decides when; usually a few times a day)

    nonisolated static func registerBackground() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTask, using: nil) { task in
            scheduleBackgroundNow()
            let work = Task { @MainActor in
                _ = await GmailService.shared.check(notify: true)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
    static func scheduleBackground() { Self.scheduleBackgroundNow() }
    nonisolated static func scheduleBackgroundNow() {
        let r = BGAppRefreshTaskRequest(identifier: bgTask)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    // MARK: HTTP

    struct Token: Decodable { var access_token: String; var expires_in: Double?; var refresh_token: String? }
    struct Profile: Decodable { var emailAddress: String }
    struct MessageList: Decodable { struct Ref: Decodable { var id: String }; var messages: [Ref]?; var nextPageToken: String? }
    struct GmailError: Error { var message: String }

    private func token(_ form: [String: String]) async throws -> Token {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents(); c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        r.httpBody = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("invalid_grant") {
                Keychain.delete("kosh.gmail.refresh")
                throw GmailError(message: "Google access expired. Tap Connect Gmail again.")
            }
            throw GmailError(message: "Google sign-in failed: " + body.prefix(160))
        }
        return try JSONDecoder().decode(Token.self, from: data)
    }

    private func validToken() async throws -> String {
        if let t = accessToken, Date() < accessExpiry { return t }
        guard let rt = Keychain.get("kosh.gmail.refresh") else { throw GmailError(message: "Connect Gmail first.") }
        let tok = try await token(["refresh_token": rt, "client_id": clientId, "grant_type": "refresh_token"])
        accessToken = tok.access_token
        accessExpiry = Date().addingTimeInterval(Double(tok.expires_in ?? 3000) - 60)
        return tok.access_token
    }

    private func get<T: Decodable>(_ url: String) async throws -> T {
        var r = URLRequest(url: URL(string: url)!)
        r.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if code == 403, body.contains("accessNotConfigured") || body.contains("has not been used") {
                throw GmailError(message: "Turn on the Gmail API in your Google Cloud project, wait a minute, then try again.")
            }
            throw GmailError(message: "Gmail error \(code).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

extension GmailService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
