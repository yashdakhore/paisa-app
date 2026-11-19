import Foundation

/// Reads Indian bank / card transaction alerts, e.g.
///   "Rs.250.00 spent on your SBI Credit Card ending 1234 at SWIGGY on 18/11/26."
///   "Rs 120 debited from A/c XX1234 on 18-11-26 to VPA rapido@ybl (UPI Ref 6123…)"
/// Card and account numbers are never kept — only amount, merchant, date, and a hint like "sbi".
enum BankSMS {
    struct Txn: Equatable {
        var type: String        // expense | income
        var amount: Double
        var merchant: String
        var date: String        // YYYY-MM-DD
        var cardHint: String?   // bank name word when it was a credit card purchase, e.g. "sbi"
    }

    static let banks = ["sbi", "hdfc", "icici", "axis", "kotak", "idfc", "yes", "au", "rbl", "indusind", "amex", "bob", "pnb", "canara", "onecard", "federal", "citi", "standard chartered"]

    static func parse(_ raw: String, now: Date = Date()) -> Txn? {
        let text = raw.replacingOccurrences(of: "\n", with: " ")
        let t = text.lowercased()

        // Not a completed transaction.
        let ignore = ["otp", "one time password", "one-time password", "declined", "failed", "unsuccessful", "reversed", "is due", "due date",
                      "total amount due", "minimum amount due", "min amt due", "statement", "will be debited", "request", "offer", "cashback of", "emi conversion"]
        if ignore.contains(where: { t.contains($0) }) { return nil }

        let creditAt = t.range(of: "\\b(credited|received|deposited|refunded|refund)\\b", options: .regularExpression)?.lowerBound
        let debitAt = t.range(of: "\\b(debited|spent|paid|purchase|withdrawn|sent|used)\\b", options: .regularExpression)?.lowerBound
        guard creditAt != nil || debitAt != nil else { return nil }
        // Whichever comes first decides: "debited from your a/c … credited to rapido" is money out.
        let type: String
        if let d = debitAt, let c = creditAt { type = d < c ? "expense" : "income" } else { type = debitAt != nil ? "expense" : "income" }

        // Amount: the first Rs/INR/₹ figure (later ones are usually the balance).
        guard let amount = firstAmount(text) else { return nil }

        let merchant = merchantName(text, credit: type == "income") ?? (type == "income" ? "Money received" : "Card/UPI payment")

        // Credit card purchase → which bank's card.
        var cardHint: String? = nil
        if type == "expense", t.contains("credit card") || t.range(of: "\\bcc\\b", options: .regularExpression) != nil {
            cardHint = banks.first { t.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
        }

        return Txn(type: type, amount: amount, merchant: merchant, date: smsDate(t, now: now), cardHint: cardHint)
    }

    static func firstAmount(_ text: String) -> Double? {
        let p = "(?i)(?:rs\\.?|inr|₹)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"
        guard let re = try? NSRegularExpression(pattern: p), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        let v = Double(text[r].replacingOccurrences(of: ",", with: ""))
        return (v ?? 0) > 0 ? v : nil
    }

    static func merchantName(_ text: String, credit: Bool) -> String? {
        let stops = "(?:\\s+on\\s|\\s+ref|\\s+upi|\\s+avl|\\s+avail|\\s+bal|\\s+not\\s|\\s+if\\s|\\s+txn|\\s+via\\s|\\.\\s|\\(|\\s*$)"
        let patterns: [String] = credit
            ? ["(?i)\\bfrom\\s+(?:vpa\\s+)?([A-Za-z0-9@._&' -]{2,40}?)" + stops, "(?i)\\bby\\s+(?:neft|imps|upi|rtgs)?[- ]*(?:from\\s+)?([A-Za-z0-9._&' -]{2,40}?)" + stops]
            : ["(?i)\\bat\\s+([A-Za-z0-9@._&'*/ -]{2,40}?)" + stops,
               "(?i)\\bto\\s+vpa\\s+([A-Za-z0-9._-]+)@", "(?i)\\bto\\s+([A-Za-z0-9@._&' -]{2,40}?)" + stops,
               "(?i)\\binfo:?\\s*(?:upi/)?([A-Za-z0-9._&' -]{2,30})"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: 1), in: text) else { continue }
            var name = String(text[r]).trimmingCharacters(in: .whitespaces)
            if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }   // rapido@ybl -> rapido
            name = name.replacingOccurrences(of: "[*/._-]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            // Never keep account/card numbers.
            if name.range(of: "\\d{4,}", options: .regularExpression) != nil || name.lowercased().hasPrefix("a/c") || name.lowercased().hasPrefix("xx") { continue }
            if name.count < 2 { continue }
            return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
        }
        return nil
    }

    static func smsDate(_ t: String, now: Date) -> String {
        let cal = Parser.cal
        let today = cal.startOfDay(for: now)
        func ok(_ y: Int, _ m: Int, _ d: Int) -> String? {
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            let date = Parser.day(y, m, d)
            return date <= today.addingTimeInterval(86_400) ? Parser.iso(date) : nil
        }
        // 2026-11-18
        if let m = Parser.match("\\b(20\\d\\d)-(\\d{1,2})-(\\d{1,2})", t), let s = ok(Int(m.groups[1])!, Int(m.groups[2])!, Int(m.groups[3])!) { return s }
        // 18-11-26, 18/11/2026
        if let m = Parser.match("\\b(\\d{1,2})[-/](\\d{1,2})[-/](\\d{2,4})\\b", t) {
            var y = Int(m.groups[3])!; if y < 100 { y += 2000 }
            if let s = ok(y, Int(m.groups[2])!, Int(m.groups[1])!) { return s }
        }
        // 18Nov26, 18-Nov-2026, 18 nov
        if let m = Parser.match("\\b(\\d{1,2})[- ]?\(Parser.monthRE)[a-z]*[- ]?(\\d{2,4})?\\b", t), let mi = Parser.monthIndex(m.groups[2]) {
            var y = Int(m.groups[3]) ?? cal.component(.year, from: today); if y < 100 { y += 2000 }
            if let s = ok(y, mi + 1, Int(m.groups[1])!) { return s }
        }
        return Parser.iso(today)
    }
}
