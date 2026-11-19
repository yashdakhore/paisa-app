import Foundation

/// Rule-based reader for phrases like "spent 250 on groceries yesterday".
/// A Swift port of the web app's parser.js; both are tested against the same phrases.
enum Parser {
    static let defaultKeywords: [String: [String]] = [
        "rent": ["rent", "house rent", "room rent", "landlord", "pg", "kiraya", "kiraaya", "bhada"],
        "bills": ["electricity", "electric", "light bill", "current bill", "power bill", "bill", "water bill", "gas", "cylinder", "lpg", "maintenance", "bijli", "bijlee", "paani", "pani"],
        "groceries": ["grocery", "groceries", "vegetables", "veggies", "sabzi", "fruits", "milk", "kirana", "dmart", "d mart", "blinkit", "zepto", "bigbasket", "big basket", "instamart", "ration", "eggs", "bread", "sabji", "doodh", "dudh", "anda", "ande", "atta", "chawal", "dal", "tarkari", "fal", "kirana store"],
        "food": ["food", "lunch", "dinner", "breakfast", "snacks", "tea", "chai", "coffee", "swiggy", "zomato", "restaurant", "cafe", "pizza", "burger", "biryani", "dining", "eating out", "canteen", "mess", "tiffin", "khana", "nashta", "samosa", "thali", "dhaba", "chaat", "eternal", "pan shop", "paan", "dominos", "mcdonalds", "kfc"],
        "transport": ["uber", "ola", "rapido", "auto", "rickshaw", "cab", "taxi", "bus", "metro", "train", "petrol", "diesel", "fuel", "parking", "toll", "travel", "flight", "ticket", "tickets", "gaadi", "bike", "iocl", "hpcl", "bpcl", "indian oil", "bharat petroleum", "hindustan petroleum", "petrol pump", "fuel station", "fastag"],
        "phone": ["recharge", "mobile", "phone", "jio", "airtel", "vodafone", "internet", "wifi", "wi-fi", "broadband", "data pack"],
        "shopping": ["shopping", "clothes", "shoes", "amazon", "flipkart", "myntra", "meesho", "ajio", "shirt", "dress", "gadget", "kapde", "kapda", "joote"],
        "health": ["medicine", "medicines", "doctor", "pharmacy", "chemist", "hospital", "medical", "clinic", "gym", "tablets", "apollo", "pharmeasy", "dawai", "dawa", "davai", "dava"],
        "entertainment": ["movie", "movies", "netflix", "prime", "hotstar", "spotify", "youtube premium", "game", "games", "outing", "party", "concert", "subscription", "picture"],
        "debt": ["credit card", "card bill", "card payment", "card", "sbi card", "emi", "loan", "mpokket", "repay", "repaid", "repayment",
                 "bajaj finance", "kreditbee", "navi", "moneyview", "home credit", "simpl", "lazypay", "zestmoney", "tvs credit", "hdb financial", "fibe"],
        "other": [],
    ]

    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    static let monthRE = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
    static let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let ones: [String: Double] = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19]
    static let tens: [String: Double] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
    static let scales: [String: Double] = ["hundred": 100, "thousand": 1000, "lakh": 100_000, "lakhs": 100_000, "lac": 100_000, "sau": 100, "hazaar": 1000, "hazar": 1000, "hajar": 1000]
    static let filler: Set<String> = ["spent", "spend", "spending", "paid", "pay", "paying", "bought", "buy", "gave", "give", "for", "on", "at", "in", "to", "of", "rupees", "rupee", "rs", "inr", "bucks", "the", "a", "an", "i", "my", "just", "and", "towards", "toward", "worth", "got", "ordered", "from", "today", "yesterday", "received", "invested", "invest", "saved", "save", "put", "added", "add", "into", "with", "by", "was", "is", "me", "ke", "liye", "pe", "par", "mein", "ka", "ki", "ko", "se", "diye", "diya", "kharcha", "kharch", "kiya", "kiye", "rupaye", "rupay", "rupiya", "hai", "tha", "aaj", "kal", "parso", "parson", "wala", "wale"]

    struct Item {
        let id: String
        let words: [String]
    }

    struct Result: Equatable {
        var type: String
        var amount: Double?
        var categoryId: String?
        var debtId: String?
        var goalId: String?
        var investmentId: String?
        var date: String
        var note: String
        var sureAmount: Bool
        var sureCategory: Bool
        var sureDate: Bool
    }

    // MARK: - helpers

    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static func iso(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    static func addDays(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d)! }

    /// First match of `pattern` in `s`: capture groups ("" when a group didn't match) and the whole-match range.
    static func match(_ pattern: String, _ s: String) -> (groups: [String], range: NSRange)? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var g: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            g.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return (g, m.range)
    }

    static func test(_ pattern: String, _ s: String) -> Bool { match(pattern, s) != nil }

    static func replacing(_ s: String, _ range: NSRange, with rep: String) -> String {
        (s as NSString).replacingCharacters(in: range, with: rep)
    }

    static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    // MARK: - words to digits ("two hundred fifty" -> "250")

    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var curIsSep: Bool? = nil
        for ch in s {
            let isSep = ch.isWhitespace || ch == "-"
            if curIsSep == nil || curIsSep == isSep { cur.append(ch) } else { out.append(cur); cur = String(ch) }
            curIsSep = isSep
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    static func isSep(_ t: String) -> Bool { t.allSatisfy { $0.isWhitespace || $0 == "-" } }

    static func wordsToDigits(_ text: String) -> String {
        let toks = tokens(text)
        var out: [String] = []
        var run: (total: Double, current: Double)? = nil
        var pending: [String] = []
        func flush() {
            if let r = run { out.append(fmt(r.total + r.current)); run = nil }
            out.append(contentsOf: pending)
            pending = []
        }
        var i = 0
        while i < toks.count {
            let raw = toks[i]
            let t = raw.lowercased()
            if isSep(raw) {
                if run != nil { pending.append(raw) } else { out.append(raw) }
                i += 1; continue
            }
            let nextWord = i + 2 < toks.count ? toks[i + 2].lowercased() : ""
            if t == "a", run == nil, scales[nextWord] != nil, nextWord != "lakhs" { run = (0, 1); i += 1; continue }
            if t == "and", run != nil { pending.append(raw); i += 1; continue }
            var isScale = false
            var val: Double? = nil
            if let v = ones[t] { val = v } else if let v = tens[t] { val = v } else if let v = scales[t] { val = v; isScale = true }
            else if let n = Double(t), scales[nextWord] != nil, run == nil, t.first?.isNumber == true { run = (0, n); i += 1; continue }
            guard let v = val else { flush(); out.append(raw); i += 1; continue }
            pending = []
            if run == nil { run = (0, 0) }
            if !isScale { run!.current += v }
            else if v == 100 { run!.current = (run!.current == 0 ? 1 : run!.current) * 100 }
            else { run!.total += (run!.current == 0 ? 1 : run!.current) * v; run!.current = 0 }
            i += 1
        }
        flush()
        return out.joined()
    }

    // MARK: - date

    static func monthIndex(_ s: String) -> Int? {
        let p = String(s.prefix(3))
        return months.firstIndex { $0.hasPrefix(p) }
    }

    static func fromDayMonth(_ today: Date, _ d: Int, _ mIdx: Int?) -> Date? {
        guard let mIdx else { return nil }
        let y = cal.component(.year, from: today)
        var date = day(y, mIdx + 1, d)
        if date > today { date = day(y - 1, mIdx + 1, d) }
        return date
    }

    static func extractDate(_ text: String, now: Date) -> (date: String, rest: String, found: Bool) {
        let today = cal.startOfDay(for: now)
        let tries: [(String, ([String]) -> Date?)] = [
            ("\\bday before yesterday\\b", { _ in addDays(today, -2) }),
            ("\\bparso[n]?\\b", { _ in addDays(today, -2) }),
            ("\\bkal\\b", { _ in addDays(today, -1) }),
            ("\\baaj\\b", { _ in today }),
            ("\\byesterday\\b", { _ in addDays(today, -1) }),
            ("\\b(today|tonight|this morning|this evening)\\b", { _ in today }),
            ("\\b(\\d{1,2}) days? ago\\b", { g in addDays(today, -(Int(g[1]) ?? 0)) }),
            ("\\blast week\\b", { _ in addDays(today, -7) }),
            ("\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?\(monthRE)\\b", { g in fromDayMonth(today, Int(g[1]) ?? 1, monthIndex(g[2])) }),
            ("\\b(?:on\\s+)?\(monthRE)\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b", { g in fromDayMonth(today, Int(g[2]) ?? 1, monthIndex(g[1])) }),
            ("\\b(\\d{1,2})[/-](\\d{1,2})(?:[/-](\\d{2,4}))?\\b", { g in
                var y: Int? = g[3].isEmpty ? nil : Int(g[3])
                if let yy = y, yy < 100 { y = yy + 2000 }
                var d = day(y ?? cal.component(.year, from: today), Int(g[2]) ?? 1, Int(g[1]) ?? 1)
                if y == nil, d > today { d = cal.date(byAdding: .year, value: -1, to: d)! }
                return d
            }),
            ("\\b(last\\s+|on\\s+|this\\s+)?(\(days.joined(separator: "|")))\\b", { g in
                guard let target = days.firstIndex(of: g[2]) else { return nil }
                let wd = cal.component(.weekday, from: today) - 1
                var diff = (wd - target + 7) % 7
                if diff == 0, g[1].trimmingCharacters(in: .whitespaces) == "last" { diff = 7 }
                return addDays(today, -diff)
            }),
            ("\\bon (?:the )?(\\d{1,2})(?:st|nd|rd|th)\\b", { g in
                let c = cal.dateComponents([.year, .month], from: today)
                var d = day(c.year!, c.month!, Int(g[1]) ?? 1)
                if d > today { d = cal.date(byAdding: .month, value: -1, to: d)! }
                return d
            }),
        ]
        for (pattern, fn) in tries {
            if let m = match(pattern, text), let d = fn(m.groups) {
                return (iso(d), replacing(text, m.range, with: " "), true)
            }
        }
        return (iso(today), text, false)
    }

    // MARK: - amount

    static func extractAmount(_ text: String) -> (amount: Double?, rest: String) {
        let pattern = "(₹|\\brs\\.?|\\binr)?\\s*(\\d+(?:\\.\\d+)?)\\s*(k\\b|thousand\\b|lakhs?\\b|lac\\b|hundred\\b)?\\s*(rupees?\\b|rupaye\\b|rupay\\b|rupiya\\b|rs\\b|bucks\\b|/-)?"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return (nil, text) }
        let ns = text as NSString
        struct Cand { let v: Double; let marked: Bool; let range: NSRange }
        var cands: [Cand] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let g = { (i: Int) -> String in let r = m.range(at: i); return r.location == NSNotFound ? "" : ns.substring(with: r) }
            guard var v = Double(g(2)) else { continue }
            let mult = g(3).lowercased()
            if mult == "k" || mult == "thousand" { v *= 1000 }
            else if mult.hasPrefix("lakh") || mult == "lac" { v *= 100_000 }
            else if mult == "hundred" { v *= 100 }
            cands.append(Cand(v: v, marked: !g(1).isEmpty || !g(4).isEmpty, range: m.range))
        }
        guard !cands.isEmpty else { return (nil, text) }
        let pick = cands.first(where: { $0.marked }) ?? cands.max(by: { $0.v < $1.v })!
        return ((pick.v * 100).rounded() / 100, replacing(text, pick.range, with: " "))
    }

    static func detectType(_ t: String) -> String {
        if test("\\b(salary|received|income|got paid|credited|bonus|refund|cashback|sent me|gave me|bheje|bheja|bhejе|mile|mila|mili)\\b", t) { return "income" }
        if test("\\b(mom|mum|mummy|maa|mother|dad|papa|pappa|father|bhai|bhaiya|didi|sister|brother|nana|nani|dada|dadi)\\s+(sent|gave|ne|transferred)\\b|\\bfrom\\s+(mom|mum|mummy|maa|mother|dad|papa|pappa|father|bhai|bhaiya|didi|sister|brother|nana|nani|dada|dadi)\\b", t) { return "income" }
        if test("\\b(invest(ed)?|sip|mutual fund|fd|fixed deposit|stocks?|shares|ppf|nps|gold)\\b", t) { return "invest" }
        if test("\\b(saved|save|emergency fund|savings)\\b", t) { return "save" }
        return "expense"
    }

    /// The item whose word gives the longest match in `text`.
    static func bestMatch(_ text: String, _ items: [Item]) -> Item? {
        var best: Item? = nil
        var bestLen = 0
        for it in items {
            for w in it.words {
                let word = w.lowercased().trimmingCharacters(in: .whitespaces)
                guard !word.isEmpty, word.count > bestLen else { continue }
                let p = "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: word) + "s?($|[^a-z0-9])"
                if test(p, text) { best = it; bestLen = word.count }
            }
        }
        return best
    }

    static func nameWords(_ name: String) -> [String] {
        [name] + name.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 3 }
    }

    // MARK: - learning

    /// Words worth remembering from a note or merchant name ("Rapido ride" -> ["rapido", "ride"]).
    static func learnableWords(_ text: String) -> [String] {
        let skip: Set<String> = ["ride", "bill", "payment", "paid", "purchase", "order", "store", "shop", "the", "and", "for", "india", "pvt", "ltd", "limited", "private", "services", "upi", "pay"]
        let words = text.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 && !filler.contains($0) && !skip.contains($0) }
        var out: [String] = []
        for w in words where !out.contains(w) { out.append(w) }
        return Array(out.prefix(2))
    }

    // MARK: - several items in one sentence

    static func normalize(_ input: String) -> String {
        var t = " " + input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + " "
        if let re = try? NSRegularExpression(pattern: "(\\d),(?=\\d)") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "$1")
        }
        return wordsToDigits(t)
    }

    /// "250 on groceries and 120 auto yesterday" -> ["250 on groceries", "120 auto yesterday"].
    /// A piece only counts as its own item if it still has a number once dates are taken out.
    static func splitItems(_ input: String) -> [String] {
        let t = normalize(input)
        guard let re = try? NSRegularExpression(pattern: "\\s*(?:,|;|&|\\band\\b|\\bplus\\b|\\baur\\b|\\bthen\\b)\\s*") else { return [input] }
        let marked = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "\u{1}")
        let hasAmount = { (seg: String) -> Bool in extractDate(" " + seg + " ", now: Date()).rest.contains(where: \.isNumber) }
        var groups: [String] = []
        for raw in marked.components(separatedBy: "\u{1}") {
            let seg = raw.trimmingCharacters(in: .whitespaces)
            if seg.isEmpty { continue }
            if hasAmount(seg) || groups.isEmpty { groups.append(seg) } else { groups[groups.count - 1] += " " + seg }
        }
        if groups.count > 1, !hasAmount(groups[0]) { groups[1] = groups[0] + " " + groups[1]; groups.removeFirst() }
        return groups.isEmpty ? [input] : groups
    }

    static func parseMany(_ input: String, categories: [Item], debts: [Item], goals: [Item], investments: [Item], now: Date = Date()) -> [Result] {
        let parts = splitItems(input)
        if parts.count <= 1 { return [parse(input, categories: categories, debts: debts, goals: goals, investments: investments, now: now)] }
        var rs = parts.map { parse($0, categories: categories, debts: debts, goals: goals, investments: investments, now: now) }
        if let dated = rs.first(where: { $0.sureDate }) {
            for i in rs.indices where !rs[i].sureDate { rs[i].date = dated.date }
        }
        return rs
    }

    // MARK: - main

    static func parse(_ input: String, categories: [Item], debts: [Item], goals: [Item], investments: [Item], now: Date = Date()) -> Result {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var t = " " + original.lowercased() + " "
        if let re = try? NSRegularExpression(pattern: "(\\d),(?=\\d)") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "$1")
        }
        t = t.replacingOccurrences(of: "!", with: " ").replacingOccurrences(of: "?", with: " ")
        t = wordsToDigits(t)
        let type = detectType(t)
        let d = extractDate(t, now: now)
        let a = extractAmount(d.rest)
        let rest = a.rest

        let cat = bestMatch(rest, categories)
        let debt = bestMatch(rest, debts)
        let goal = bestMatch(rest, goals)
        let inv = bestMatch(rest, investments)

        var categoryId = cat?.id
        if categoryId == nil, debt != nil, categories.contains(where: { $0.id == "debt" }) { categoryId = "debt" }
        if categoryId == nil, type == "expense" { categoryId = categories.contains(where: { $0.id == "other" }) ? "other" : nil }

        var noteText = rest
        if let re = try? NSRegularExpression(pattern: "[^a-z0-9₹'&-]+") {
            noteText = re.stringByReplacingMatches(in: rest, range: NSRange(location: 0, length: (rest as NSString).length), withTemplate: "\u{1}")
        }
        let words = noteText.components(separatedBy: "\u{1}").filter { w in
            !w.isEmpty && !filler.contains(w) && !w.allSatisfy(\.isNumber) && w != "₹" && w != "-"
        }
        var note = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if let f = note.first { note = f.uppercased() + note.dropFirst() }

        return Result(type: type, amount: a.amount, categoryId: categoryId, debtId: debt?.id, goalId: goal?.id, investmentId: inv?.id,
                      date: d.date, note: note, sureAmount: a.amount != nil, sureCategory: cat != nil, sureDate: d.found)
    }
}
