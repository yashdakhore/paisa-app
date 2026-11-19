import Foundation

/// Turns a Gmail API message (format=full) into plain text Kosh can read. No network, so it is tested on the Mac.
enum GmailMessage {
    struct Payload: Decodable {
        var mimeType: String?
        var headers: [Header]?
        var body: Body?
        var parts: [Payload]?
    }
    struct Header: Decodable { var name: String; var value: String }
    struct Body: Decodable { var data: String? }
    struct Message: Decodable {
        var id: String
        var internalDate: String?
        var payload: Payload?
    }

    /// Bank alert senders searched in Gmail. Only these are ever read.
    static let defaultSenders = ["idfcfirstbank.com", "slice.bank.in", "alerts.sbi.co.in", "alerts.sbi.bank.in", "sbi.co.in", "billdesk.in",
                                 "sbicard.com", "getonecard.app", "onecard", "super.money", "supermoney", "hdfcbank.net", "hdfcbank.bank.in",
                                 "icicibank.com", "axisbank.com", "kotak.com", "kotak.bank.in", "yesbank.in", "aubank.in", "rblbank.com", "federalbank.co.in"]

    /// Gmail search: only alert senders, only recent mail.
    static func query(senders: [String], days: Int) -> String {
        from(senders) + " newer_than:\(days)d"
    }
    /// Everything since a day, e.g. the 1st of the month: "after:2026/11/01" (Gmail reads it as midnight, Pacific time,
    /// so one day earlier is asked for and anything before `since` is dropped by date later).
    static func query(senders: [String], since: Date) -> String {
        let d = Parser.cal.date(byAdding: .day, value: -1, to: since)!
        let c = Parser.cal.dateComponents([.year, .month, .day], from: d)
        return from(senders) + String(format: " after:%04d/%02d/%02d", c.year!, c.month!, c.day!)
    }
    static func from(_ senders: [String]) -> String {
        "from:(" + senders.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " OR ") + ")"
    }
    static func firstOfMonth(_ now: Date = Date()) -> Date {
        Parser.cal.date(from: Parser.cal.dateComponents([.year, .month], from: now))!
    }

    static func base64url(_ s: String) -> String? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b) else { return nil }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1)
    }

    /// Subject + body (plain text if there is one, otherwise the HTML, which BankSMS.normalize flattens).
    static func text(_ m: Message) -> String {
        guard let p = m.payload else { return "" }
        let subject = p.headers?.first { $0.name.lowercased() == "subject" }?.value ?? ""
        var plain: [String] = [], html: [String] = []
        func walk(_ part: Payload) {
            let type = (part.mimeType ?? "").lowercased()
            if let d = part.body?.data, let s = base64url(d) {
                if type == "text/plain" { plain.append(s) } else if type == "text/html" { html.append(s) }
            }
            part.parts?.forEach(walk)
        }
        walk(p)
        let body = !plain.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? plain.joined(separator: "\n") : html.joined(separator: "\n")
        return subject + "\n" + body
    }

    static func date(_ m: Message) -> Date? {
        guard let ms = m.internalDate.flatMap(Double.init) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
