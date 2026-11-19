import Foundation

/// Reads Indian bank / card transaction alerts from SMS **and email**, e.g.
///   "Rs.250.00 spent on your SBI Credit Card ending 1234 at SWIGGY on 18/11/26."
///   "Rs 120 debited from A/c XX1234 on 18-11-26 to VPA rapido@ybl (UPI Ref 6123…)"
///   table emails: "| Terminal Owner Name | PTM*ZOMATO LIMITED | … | Amount (INR) | 845.50 |"
///   card bill payments: "Payment of Rs. 1500.00 was received on your … Credit Card"
/// Card and account numbers are never kept — only amount, merchant, date, and a hint like "sbi".
enum BankSMS {
    struct Txn: Equatable {
        var type: String        // expense | income | payment (a credit card bill payment)
        var amount: Double
        var merchant: String
        var date: String        // YYYY-MM-DD
        var cardHint: String?   // bank name word for credit card purchases/payments, e.g. "sbi"
        var ref: String? = nil  // bank's unique reference (UPI Ref / RRN / Txn ID); the SMS and the email share it
        var time: String? = nil // "HH:mm" if the alert gives one
        var isCash = false      // cash deposit / ATM withdrawal: your money changing form
    }

    static let banks = ["sbi", "hdfc", "icici", "axis", "kotak", "idfc", "yes", "au", "rbl", "indusind", "amex", "bob", "pnb", "canara", "onecard", "one card", "supermoney", "super money", "federal", "citi", "standard chartered"]

    /// Flatten email bodies: links, HTML, table pipes and line breaks become plain spaced text.
    static func normalize(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "https?://\\S+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;|&amp;|&#39;", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "-{3,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[|\\n\\r\\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ raw: String, now: Date = Date()) -> Txn? {
        let text = normalize(raw)
        let t = text.lowercased()

        // Amount: the first Rs/INR/₹ figure (later ones are usually the balance/limit), or an "Amount (INR)" table row.
        guard let (amount, amountRange) = findAmount(text) else { return nil }

        // Only the part around the amount decides what this is — email footers ("never share your OTP",
        // "view statement", offers) must not hide a real alert.
        let endIdx = text.index(amountRange.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        let core = String(text[text.startIndex..<endIdx]).lowercased()

        let ignore = ["otp", "one time password", "one-time password", "declined", "failed", "unsuccessful", "reversed", "is due", "due date",
                      "total amount due", "minimum amount due", "min amt due", "will be debited", "request", "offer", "cashback of", "emi conversion",
                      "up to rs", "upto rs", "save rs", "get rs", "win rs"]
        if ignore.contains(where: { core.contains($0) }) { return nil }
        // Cash in or out of your own account (deposit machine, ATM): your money changing form. Kosh files it as Moved.
        let isCash = core.range(of: "deposit of cash|cash deposit|cash dep\\b|\\bcdm\\b|\\bby cash\\b|\\batm\\b|cash withdrawal|atm wdl|\\bwdl\\b", options: .regularExpression) != nil

        // Credit card bill payment (lowers the card's balance).
        let isCardPayment = core.range(of: "(payment|amount paid).{0,140}credit card|credit card.{0,80}payment", options: .regularExpression) != nil
            && core.range(of: "received|thank you for making payment|payment success|successful|amount paid", options: .regularExpression) != nil

        let creditAt = core.range(of: "\\b(credited|received|deposited|refunded|refund|has credit|credit for)\\b", options: .regularExpression)?.lowerBound
        let debitAt = core.range(of: "\\b(debited|spent|paid|purchase|withdrawn|sent|used|done using)\\b", options: .regularExpression)?.lowerBound
        let type: String
        if isCardPayment { type = "payment" }
        else if let d = debitAt, let c = creditAt { type = d < c ? "expense" : "income" }
        else if debitAt != nil { type = "expense" }
        else if creditAt != nil { type = "income" }
        else { return nil }

        // Which bank's credit card (whole text — the bank name is often only in the signature).
        var cardHint: String? = nil
        if type != "income", t.contains("credit card") || t.contains("onecard") || t.contains("one card") || t.contains("super.money")
            || t.contains("supermoney") || t.range(of: "\\bcc\\b", options: .regularExpression) != nil {
            let tt = t.replacingOccurrences(of: "super.money", with: "supermoney")
            cardHint = banks.first { tt.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }?.replacingOccurrences(of: " ", with: "")
        }

        let merchant: String
        if isCash {
            merchant = type == "income" ? "Cash deposit" : "ATM withdrawal"
        } else if type == "payment" {
            merchant = (cardHint.map { $0.uppercased() + " " } ?? "") + "card bill payment"
        } else {
            merchant = merchantName(text, credit: type == "income") ?? (type == "income" ? "Money received" : "Card/UPI payment")
        }
        return Txn(type: type, amount: amount, merchant: merchant, date: smsDate(t, now: now), cardHint: cardHint,
                   ref: reference(text), time: time(text), isCash: isCash)
    }

    /// "UPI Ref No 612345678901", "RRN: 600012345678", "Txn ID AXI123456789", "Transaction Ref: ABC123456"
    /// Only codes with at least 6 digits count, so words and masked card numbers ("XX1234") are never taken.
    static func reference(_ raw: String) -> String? {
        let text = normalize(raw)
        let p = "(?i)\\b(?:upi\\s*ref(?:erence)?|rrn|utr|imps\\s*ref|neft\\s*ref|txn\\s*(?:id|ref|no)|transaction\\s*(?:id|ref(?:erence)?|no)|ref(?:erence)?|mref|approval\\s*code)"
            + "(?:\\s*(?:no|number|id|#))?\\.?\\s*[:#-]?\\s*([A-Za-z0-9]{6,24})\\b"
        guard let re = try? NSRegularExpression(pattern: p) else { return nil }
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let code = String(text[r])
            if code.filter(\.isNumber).count >= 6, !code.lowercased().hasPrefix("xx") { return code.uppercased() }
        }
        return nil
    }

    /// "at 10:15 AM", "13:12", "2026-11-16:10:22:01" → "10:15", "13:12", "10:22"
    static func time(_ text: String) -> String? {
        guard let m = Parser.match("(?<![\\d-])(\\d{1,2}):(\\d{2})(?::\\d{2})?\\s*(am|pm|a\\.m\\.|p\\.m\\.)?", text.lowercased()),
              var h = Int(m.groups[1]), let mi = Int(m.groups[2]), h < 24, mi < 60 else { return nil }
        if m.groups[3].hasPrefix("p"), h < 12 { h += 12 }
        if m.groups[3].hasPrefix("a"), h == 12 { h = 0 }
        return String(format: "%02d:%02d", h, mi)
    }

    static func findAmount(_ text: String) -> (Double, Range<String.Index>)? {
        let patterns = ["(?i)(?:rs\\.?|inr|₹)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)",
                        "(?i)amount\\s*\\((?:inr|rs\\.?|₹)\\)\\s*:?\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)",
                        "(?i)amount(?: paid| debited| spent)?\\s*:\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: 1), in: text), let v = Double(text[r].replacingOccurrences(of: ",", with: "")), v > 0 else { continue }
            return (v, r)
        }
        return nil
    }

    static func firstAmount(_ text: String) -> Double? { findAmount(normalize(text))?.0 }

    /// Tidy a merchant: drop payment-gateway prefixes (PYU*, PTM*, RZP*…) and company suffixes, title-case it.
    static func cleanMerchant(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespaces)
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }   // rapido@ybl -> rapido
        name = name.replacingOccurrences(of: "^(?i)(pyu|ptm|rzp|payu|paytm|razorpay|bdk|ccavenue|cca|phonepe|gpay)\\s*\\*\\s*", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "[*/._-]+", with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: "(?i)\\b(private|pvt|limited|ltd|llp|india|inc)\\b\\.?", with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        // Never keep account/card numbers.
        if name.range(of: "\\d{4,}", options: .regularExpression) != nil || name.lowercased().hasPrefix("a/c") || name.lowercased().hasPrefix("xx") { return nil }
        guard name.count >= 2 else { return nil }
        return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    static func merchantName(_ text: String, credit: Bool) -> String? {
        let stops = "(?:\\s+on\\s|\\s+using\\s|\\s+with\\s|\\s+thru\\s|\\s+through\\s|\\s+by\\s|\\s+ref|\\s+rrn|\\s+best,|\\s+upi|\\s+avl|\\s+avail|\\s+bal|\\s+not\\s|\\s+if\\s|\\s+txn|\\s+via\\s|\\s+terminal\\s|\\.\\s|\\(|\\s*$)"
        let patterns: [String] = credit
            ? ["(?i)\\bfrom\\s+(?:vpa\\s+)?([A-Za-z0-9@._&' -]{2,40}?)" + stops, "(?i)\\bby\\s+(?:neft|imps|upi|rtgs)?[- ]*(?:from\\s+)?([A-Za-z0-9._&' -]{2,40}?)" + stops]
            : ["(?i)\\bterminal owner name\\s+([A-Za-z0-9@._&'*/ -]{2,50}?)\\s+terminal\\b",
               "(?i)\\bmerchant(?: name)?\\s*:?\\s+([A-Za-z0-9@._&'*/ -]{2,40}?)" + stops,
               "(?i)\\bat\\s+([A-Za-z0-9@._&'*/ -]{2,40}?)" + stops,
               "(?i)\\bto\\s+vpa\\s+([A-Za-z0-9._-]+)@", "(?i)\\bto\\s+([A-Za-z0-9@._&' -]{2,40}?)" + stops,
               "(?i)\\binfo:?\\s*(?:upi/)?([A-Za-z0-9._&' -]{2,30})"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: 1), in: text), let name = cleanMerchant(String(text[r])) else { continue }
            return name
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
        // Nov 19, 2026
        if let m = Parser.match("\\b\(Parser.monthRE)[a-z]*\\.?\\s+(\\d{1,2}),?\\s+(20\\d\\d)\\b", t), let mi = Parser.monthIndex(m.groups[1]),
           let s = ok(Int(m.groups[3])!, mi + 1, Int(m.groups[2])!) { return s }
        // 18Nov26, 18-Nov-2026, 18 nov
        if let m = Parser.match("\\b(\\d{1,2})[- ]?\(Parser.monthRE)[a-z]*[- ]?(\\d{2,4})?\\b", t), let mi = Parser.monthIndex(m.groups[2]) {
            var y = Int(m.groups[3]) ?? cal.component(.year, from: today); if y < 100 { y += 2000 }
            if let s = ok(y, mi + 1, Int(m.groups[1])!) { return s }
        }
        return Parser.iso(today)
    }
}
