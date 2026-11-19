import Foundation

/// Spoken set-up commands and questions, read with fixed rules (no AI). Anything that isn't one of these
/// falls through to the normal expense parser.
///   "add SBI credit card limit 50000 due on 5th"      "new goal bike 80000 by June 2027"
///   "start SIP 2000 in Nifty index fund"              "set food budget 6000"
///   "my salary is 30000"                              "CIBIL score 760"
///   "SBI card balance is 12000"                       "how much can I spend today?"
enum VoiceCommand: Equatable {
    case card(name: String, limit: Double?, balance: Double?, dueDay: Int?, rate: Double?)
    case loan(name: String, kind: String, balance: Double?, emi: Double?, dueDay: Int?, rate: Double?)
    case debtUpdate(query: String, balance: Double?, limit: Double?, dueDay: Int?)
    case goal(name: String, target: Double, deadline: String?)
    case investment(name: String, type: String, monthly: Double?, amount: Double?)
    case budget(query: String, amount: Double)
    case salary(Double)
    case score(bureau: String, score: Int)
    case question(Question)

    enum Question: Equatable {
        case canSpend
        case spent(query: String?, lastMonth: Bool)
        case owe
        case debtFree
        case goal(query: String?)
        case score
        case plan
        case afford(Double)
        case overview
    }
}

enum Commands {
    static let setupVerb = "\\b(add|new|create|set ?up|setup|start|started|track|i have|i've got|i got|open(ed)?|took|taken|naya|nayi|banao|jodo)\\b"
    static let spendVerb = "\\b(spent|spend|paid|pay|bought|gave|kharch|diye|diya)\\b"
    static let numRE = "(\\d+(?:\\.\\d+)?)\\s*(k\\b|thousand\\b|lakhs?\\b|lacs?\\b|crores?\\b|cr\\b)?"

    static func value(_ n: String, _ mult: String) -> Double {
        var v = Double(n) ?? 0
        switch mult {
        case "k", "thousand": v *= 1000
        case let m where m.hasPrefix("lakh") || m.hasPrefix("lac"): v *= 100_000
        case let m where m.hasPrefix("crore") || m == "cr": v *= 10_000_000
        default: break
        }
        return v
    }

    /// Number right after one of the keywords: "limit 50k", "balance is ₹12,000", "emi of 3500".
    static func num(after keys: String, in t: String) -> (Double, NSRange)? {
        guard let m = Parser.match("\\b(?:\(keys))\\b\\s*(?:amount\\s*)?(?:of|is|=|:|at|to|was|hai|now|left)?\\s*(?:rs\\.?|₹|inr|rupees)?\\s*\(numRE)", t) else { return nil }
        return (value(m.groups[1], m.groups[2]), m.range)
    }

    /// Number right before a keyword: "50000 limit", "3500 emi".
    static func num(before keys: String, in t: String) -> (Double, NSRange)? {
        guard let m = Parser.match("(?:rs\\.?|₹|inr)?\\s*\(numRE)\\s*(?:rs|rupees)?\\s*(?:ka |ki |ke )?(?:\(keys))\\b", t) else { return nil }
        return (value(m.groups[1], m.groups[2]), m.range)
    }

    static func firstNumber(_ t: String) -> Double? {
        guard let m = Parser.match("(?:rs\\.?|₹|inr)?\\s*\(numRE)", t) else { return nil }
        return value(m.groups[1], m.groups[2])
    }

    static func remove(_ t: String, _ r: NSRange?) -> String {
        guard let r else { return t }
        return Parser.replacing(t, r, with: " ")
    }

    /// "due on 5th", "due date 15", "on the 5th of every month" → 5
    static func dueDay(_ t: String) -> (Int, NSRange)? {
        if let m = Parser.match("\\b(?:due|bill|payment)(?:\\s+date)?(?:\\s+(?:is|on|by))?(?:\\s+the)?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b", t),
           let d = Int(m.groups[1]), (1...31).contains(d) { return (d, m.range) }
        if let m = Parser.match("\\b(\\d{1,2})(?:st|nd|rd|th)\\s+(?:of\\s+)?(?:every|each)\\s+month\\b", t), let d = Int(m.groups[1]), (1...31).contains(d) { return (d, m.range) }
        return nil
    }

    /// "42%", "42 percent", "interest 12" → 42
    static func rate(_ t: String) -> (Double, NSRange)? {
        if let m = Parser.match("(\\d+(?:\\.\\d+)?)\\s*(?:%|percent|per cent|pc)", t), let v = Double(m.groups[1]), v < 100 { return (v, m.range) }
        if let m = Parser.match("\\b(?:interest|rate|apr|roi)(?:\\s+rate)?(?:\\s+(?:is|of))?\\s+(\\d+(?:\\.\\d+)?)\\b", t), let v = Double(m.groups[1]), v < 100 { return (v, m.range) }
        return nil
    }

    /// "by june 2027", "by dec", "in 8 months", "till march next year" → "2027-06"
    static func deadline(_ t: String, now: Date) -> (String, NSRange)? {
        let cal = Parser.cal
        let y0 = cal.component(.year, from: now), m0 = cal.component(.month, from: now)
        if let m = Parser.match("\\b(?:by|till|until|before|in)\\s+\(Parser.monthRE)[a-z]*\\s*(20\\d\\d|next year)?\\b", t), let mi = Parser.monthIndex(m.groups[1]) {
            var y = Int(m.groups.count > 2 ? m.groups[2] : "") ?? y0
            if m.groups.count > 2, m.groups[2] == "next year" { y = y0 + 1 }
            else if m.groups.count <= 2 || m.groups[2].isEmpty, mi + 1 <= m0 { y = y0 + 1 }
            return (String(format: "%04d-%02d", y, mi + 1), m.range)
        }
        if let m = Parser.match("\\b(?:in|within)\\s+(\\d{1,3})\\s+(months?|years?|mahine|saal)\\b", t), let n = Int(m.groups[1]) {
            let months = m.groups[2].hasPrefix("y") || m.groups[2] == "saal" ? n * 12 : n
            let d = cal.date(byAdding: .month, value: months, to: now)!
            return (String(Parser.iso(d).prefix(7)), m.range)
        }
        if let m = Parser.match("\\b(?:by|in|till)\\s+(20\\d\\d)\\b", t) { return (m.groups[1] + "-12", m.range) }
        return nil
    }

    /// Leftover words become a tidy name: "  my  sbi  " → "SBI"
    static func cleanName(_ s: String, drop: [String]) -> String {
        let stop: Set<String> = Set(["add", "new", "create", "set", "setup", "up", "start", "started", "track", "i", "have", "i've", "got", "open", "opened", "took", "taken",
                                     "a", "an", "the", "my", "for", "of", "with", "and", "in", "into", "on", "to", "is", "it", "which", "has", "having", "called", "named",
                                     "rs", "rupees", "₹", "inr", "limit", "balance", "outstanding", "due", "date", "interest", "rate", "percent", "emi", "monthly", "per", "month",
                                     "every", "each", "by", "till", "until", "before", "naya", "nayi", "banao", "jodo", "ka", "ki", "ke", "hai", "please", "kosh"] + drop)
        let words = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stop.contains($0) && Double($0) == nil }
        return words.map { w in
            let short: Set<String> = ["sbi", "hdfc", "icici", "idfc", "rbl", "au", "bob", "pnb", "sip", "fd", "rd", "ppf", "nps", "emi", "lic", "elss", "etf", "amex"]
            return short.contains(w) ? w.uppercased() : w.prefix(1).uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }

    static let bureaus = ["cibil": "CIBIL", "experian": "Experian", "equifax": "Equifax", "crif": "CRIF"]

    static func parse(_ input: String, now: Date = Date()) -> VoiceCommand? {
        var t = Parser.normalize(input).replacingOccurrences(of: "credit-card", with: "credit card")
        t = t.replacingOccurrences(of: "₹", with: " rs ")
        // Speech often starts with "ok", "hey Kosh", "so"…
        while let m = Parser.match("^\\s*(ok|okay|hey|hi|hello|so|and|um|uh|kosh|please|bro|yaar|acha|achha)\\b[ ,.]*", t), m.range.length > 0 {
            t = Parser.replacing(t, m.range, with: " ")
        }
        let isSetup = Parser.test(setupVerb, t)
        let isSpend = Parser.test(spendVerb, t)

        // Questions first: they never change anything.
        if let q = question(t) { return .question(q) }

        // Credit score: "cibil score 760", "my credit score is 742"
        if Parser.test("\\bscore\\b", t), let m = Parser.match("\\b([3-8]\\d\\d|900)\\b", t), let s = Int(m.groups[1]) {
            let b = bureaus.first { t.contains($0.key) }?.value ?? "CIBIL"
            return .score(bureau: b, score: s)
        }

        // Salary: "my salary is 30000", "set salary 28k" (not "got salary 30000", which is income received)
        if Parser.test("\\b(salary|take ?home|in ?hand)\\b", t), !Parser.test("\\b(got|received|credited|aayi|aaya|mili|mila)\\b", t),
           Parser.test("\\b(my|is|set|change|update|per month|monthly|hai)\\b", t), let v = firstNumber(t), v >= 1000 {
            return .salary(v)
        }

        // Budget: "set food budget 6000", "budget for shopping 3k"
        if Parser.test("\\bbudget\\b", t), !isSpend, let v = num(after: "budget(?:\\s+for\\s+[a-z ]+?)?|to", in: t)?.0 ?? num(before: "budget", in: t)?.0 ?? firstNumber(t) {
            var q = t.replacingOccurrences(of: "\\d+(\\.\\d+)?\\s*(k|lakhs?|thousand)?", with: " ", options: .regularExpression)
            q = cleanName(q, drop: ["budget", "set", "change", "make", "update", "should", "be", "monthly"])
            return .budget(query: q.lowercased(), amount: v)
        }

        // Credit card set-up: "add SBI credit card limit 50000 balance 12000 due on 5th 42%"
        if Parser.test("\\b(card|onecard)\\b", t), !isSpend || isSetup {
            let hasDetails = Parser.test("\\b(limit|outstanding|balance|due)\\b", t)
            if isSetup || hasDetails {
                var rest = t
                let due = dueDay(rest); rest = remove(rest, due?.1)
                let r = rate(rest); rest = remove(rest, r?.1)
                let limit = num(after: "limit|credit limit", in: rest) ?? num(before: "limit", in: rest); rest = remove(rest, limit?.1)
                let bal = num(after: "balance|outstanding|used|spent|owe|bill", in: rest) ?? num(before: "balance|outstanding|due", in: rest); rest = remove(rest, bal?.1)
                if isSetup {
                    let base = cleanName(rest.replacingOccurrences(of: "credit card", with: " ").replacingOccurrences(of: "card", with: " "), drop: ["credit"])
                    let name = base.isEmpty && !t.contains("onecard") ? "Credit card" : (t.contains("onecard") || t.contains("one card") ? "OneCard" : base + " Card")
                    return .card(name: name, limit: limit?.0, balance: bal?.0, dueDay: due?.0, rate: r?.0)
                }
                let q = cleanName(rest, drop: ["update", "change", "now", "current", "currently", "card", "credit"])
                return .debtUpdate(query: q.lowercased(), balance: bal?.0, limit: limit?.0, dueDay: due?.0)
            }
        }

        // Loan / EMI set-up: "add bike loan 80000 emi 3500 due 10th 12 percent"
        if Parser.test("\\b(loan|emi|borrowed|udhaar|udhar)\\b", t), isSetup || Parser.test("\\bborrowed\\b", t), !isSpend {
            var rest = t
            let due = dueDay(rest); rest = remove(rest, due?.1)
            let r = rate(rest); rest = remove(rest, r?.1)
            let emi = num(after: "emi|installment|instalment", in: rest) ?? num(before: "emi|a month|per month|monthly", in: rest); rest = remove(rest, emi?.1)
            let bal = num(after: "balance|outstanding|remaining|left|loan|of", in: rest)?.0 ?? firstNumber(rest)
            if let b = num(after: "balance|outstanding|remaining|left|loan|of", in: rest) { rest = remove(rest, b.1) } else if let m = Parser.match(numRE, rest) { rest = remove(rest, m.range) }
            let kind = Parser.test("\\bloan\\b", t) ? "loan" : "emi"
            var name = cleanName(rest, drop: ["loan", "borrowed", "from", "udhaar", "udhar", "remaining", "left", "installment", "instalment"])
            name = name.isEmpty ? (kind == "loan" ? "Loan" : "EMI") : name + (kind == "loan" ? " loan" : " EMI")
            return .loan(name: name, kind: kind, balance: bal, emi: emi?.0, dueDay: due?.0, rate: r?.0)
        }

        // Loan/card balance update without a set-up word: "home loan balance 4 lakh", "mpokket outstanding 3000"
        if Parser.test("\\b(balance|outstanding|remaining)\\b", t), !isSpend, !isSetup, let b = num(after: "balance|outstanding|remaining", in: t) {
            let q = cleanName(remove(t, b.1), drop: ["update", "change", "now", "current", "currently", "remaining"])
            if !q.isEmpty { return .debtUpdate(query: q.lowercased(), balance: b.0, limit: nil, dueDay: nil) }
        }

        // Goal: "new goal emergency fund 1 lakh by december 2027", "saving up for a bike 80000 in 10 months"
        if Parser.test("\\b(goal|save up for|saving up for|saving for a|want to buy|plan to buy|target)\\b", t), !isSpend,
           isSetup || Parser.test("\\b(goal|save up|saving up|want to buy|plan to buy)\\b", t) {
            var rest = t
            let dl = deadline(rest, now: now); rest = remove(rest, dl?.1)
            guard let v = firstNumber(rest) else { return nil }
            if let m = Parser.match(numRE, rest) { rest = remove(rest, m.range) }
            let name = cleanName(rest, drop: ["goal", "save", "saving", "up", "want", "buy", "plan", "target", "to", "need", "lakh"])
            return .goal(name: name.isEmpty ? "Goal" : name, target: v, deadline: dl?.0)
        }

        // Investment: "start SIP 2000 in Nifty index fund", "add PPF 50000", "new FD 1 lakh"
        let invTypes: [(String, String)] = [("\\bsip\\b", "SIP"), ("\\bmutual funds?\\b|\\bmf\\b|index fund|elss", "Mutual fund"), ("\\bfd\\b|fixed deposit", "FD"),
                                            ("\\brd\\b|recurring deposit", "RD"), ("\\bppf\\b", "PPF"), ("\\bnps\\b", "NPS"), ("\\bstocks?\\b|\\bshares?\\b", "Stocks"), ("\\bgold\\b|\\bsgb\\b", "Gold")]
        if isSetup, !isSpend, let type = invTypes.first(where: { Parser.test($0.0, t) })?.1 {
            var rest = t
            let monthly = num(after: "monthly|per month|every month|a month|sip(?: of)?", in: rest) ?? num(before: "a month|per month|monthly|every month", in: rest)
            if let m = monthly { rest = remove(rest, m.1) }
            let amount = monthly == nil ? firstNumber(rest) : nil
            if amount != nil, let m = Parser.match(numRE, rest) { rest = remove(rest, m.range) }
            let isMonthly = ["SIP", "RD"].contains(type) || monthly != nil
            var name = cleanName(rest, drop: ["sip", "invest", "investment", "investing", "fund", "funds", "in", "month", "every"])
            if name.isEmpty { name = type } else if !name.lowercased().contains(type.lowercased()) && type != "SIP" && type != "Mutual fund" { name = type + " " + name }
            return .investment(name: name, type: type, monthly: isMonthly ? (monthly?.0 ?? amount) : nil, amount: isMonthly ? nil : amount)
        }
        // A question we have no exact answer for gets a summary of the month, never the expense form.
        if looksLikeQuestion(t), firstNumber(t) == nil { return .question(.overview) }
        return nil
    }

    static func looksLikeQuestion(_ t: String) -> Bool {
        Parser.test("\\?|^\\s*(how|what|what's|whats|where|which|when|why|can|could|should|will|would|am|do|does|did|is|are|have|has|show|tell|give|list|kitna|kitne|kitni|kab|kya|kaise|kahan|kaha)\\b", t)
            || Parser.test("\\b(how much|how many|kitna|kitne|kitni|kya hai|batao|bata do|bataiye|summary|overview|report)\\b", t)
    }

    static func question(_ t: String) -> VoiceCommand.Question? {
        guard looksLikeQuestion(t) else { return nil }
        if Parser.test("\\b(afford|buy|le sakta|le sakti|kharid)\\b", t), let v = firstNumber(t) { return .afford(v) }
        if Parser.test("\\b(can|should|could) i (spend|pay|kharch)\\b|\\bkharch sakta\\b", t), let v = firstNumber(t) { return .afford(v) }
        if Parser.test("\\b(summary|overview|report|how am i doing|how('s| is) (my|this) month|how are things|status)\\b", t) { return .overview }
        if Parser.test("\\bdebt[- ]?free\\b|pay (it |everything |all )?off|clear (my )?(debts?|loans?|cards?)|karz", t) { return .debtFree }
        if Parser.test("\\b(owe|debt|debts|outstanding|loans?|card balance|cards? bill|udhaar|udhar)\\b", t) { return .owe }
        if Parser.test("\\b(credit )?score\\b|\\bcibil\\b", t) { return .score }
        if Parser.test("\\b(left|remaining|bacha|bache|bachi|can i spend|should i spend|spend today|daily|per day|balance|money do i have|paisa|paise)\\b", t) { return .canSpend }
        if Parser.test("\\b(spent|spend|spending|kharch|kharcha|expenses?|money go|went)\\b", t) || Parser.test("\\bbudget\\b", t) && !Parser.test("\\b(plan|planning)\\b", t) {
            let last = Parser.test("\\blast month\\b|\\bpichle\\b", t)
            var q = t.replacingOccurrences(of: "last month|this month|so far|till now|pichle mahine|is mahine", with: " ", options: .regularExpression)
            q = cleanName(q, drop: ["how", "much", "did", "do", "have", "what", "what's", "whats", "where", "spent", "spend", "spending", "total", "kitna", "kharch", "kharcha", "kiya", "tell", "me", "show",
                                    "this", "last", "so", "far", "expense", "expenses", "money", "go", "went", "budget", "s", "are", "was", "were", "hua", "hai", "mera", "meri", "mere"])
            return .spent(query: q.isEmpty ? nil : q.lowercased(), lastMonth: last)
        }
        if Parser.test("\\bgoals?\\b", t) {
            let q = cleanName(t, drop: ["how", "is", "are", "my", "goal", "goals", "doing", "going", "what", "status", "of", "the", "show", "tell", "me", "about"])
            return .goal(query: q.isEmpty ? nil : q.lowercased())
        }
        if Parser.test("\\b(plan|save|saving|invest|put|budget|money go)\\b", t) { return .plan }
        return nil
    }
}
