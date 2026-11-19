import Foundation

/// Built-in subcategories for each category, picked automatically from the merchant or note
/// (Swiggy → Food & Dining › Delivery). You can change one on any entry.
enum Subcats {
    typealias Sub = (id: String, name: String, words: [String])

    static let map: [String: [Sub]] = [
        "rent": [("house", "House rent", ["rent", "kiraya", "landlord", "house"]), ("pg", "PG / hostel", ["pg", "hostel", "mess"]),
                 ("maintenance", "Maintenance", ["maintenance", "society"]), ("deposit", "Deposit / brokerage", ["deposit", "brokerage", "broker"])],
        "bills": [("electricity", "Electricity", ["electricity", "electric", "bijli", "light bill", "msedcl", "bescom", "tata power", "adani"]),
                  ("water", "Water", ["water", "paani", "pani"]), ("gas", "Gas / LPG", ["gas", "lpg", "cylinder", "indane", "hp gas", "bharat gas"]),
                  ("society", "Society / maintenance", ["maintenance", "society"])],
        "groceries": [("online", "Online grocery", ["blinkit", "zepto", "instamart", "bigbasket", "big basket", "dmart", "jiomart", "swiggy instamart"]),
                      ("veg", "Vegetables & fruits", ["vegetables", "veggies", "sabzi", "sabji", "fruits", "fal", "tarkari"]),
                      ("dairy", "Milk & dairy", ["milk", "doodh", "dudh", "curd", "dahi", "paneer", "eggs", "anda"]),
                      ("kirana", "Kirana & staples", ["kirana", "ration", "atta", "chawal", "dal", "oil", "store", "mart", "shopee", "bhandar"])],
        "food": [("delivery", "Delivery", ["swiggy", "zomato", "eternal", "dunzo", "eatsure"]),
                 ("restaurant", "Restaurants & cafes", ["restaurant", "cafe", "dining", "dhaba", "hotel", "pizza", "burger", "biryani", "dominos", "mcdonalds", "kfc"]),
                 ("snacks", "Tea & snacks", ["tea", "chai", "coffee", "snacks", "samosa", "nashta", "pan", "paan", "chaat", "juice"]),
                 ("canteen", "Canteen / tiffin", ["canteen", "mess", "tiffin", "lunch", "dinner", "breakfast", "thali"])],
        "transport": [("fuel", "Fuel", ["petrol", "diesel", "fuel", "iocl", "hpcl", "bpcl", "indian oil", "bharat petroleum", "hindustan petroleum", "cng"]),
                      ("cab", "Cab & auto", ["uber", "ola", "rapido", "auto", "rickshaw", "cab", "taxi", "namma yatri"]),
                      ("public", "Bus / train / metro", ["bus", "metro", "train", "irctc", "railway", "local", "redbus"]),
                      ("parking", "Parking & toll", ["parking", "toll", "fastag"]),
                      ("travel", "Flights & trips", ["flight", "indigo", "air india", "makemytrip", "goibibo", "travel", "trip"]),
                      ("service", "Vehicle service", ["service", "puncture", "repair", "garage", "insurance"])],
        "phone": [("recharge", "Mobile recharge", ["recharge", "jio", "airtel", "vodafone", "vi ", "bsnl", "prepaid", "postpaid"]),
                  ("internet", "Internet / WiFi", ["wifi", "wi-fi", "broadband", "internet", "fiber", "act fibernet", "jiofiber"]),
                  ("dth", "DTH / cable", ["dth", "tata play", "dish tv", "cable"])],
        "shopping": [("online", "Online shopping", ["amazon", "flipkart", "myntra", "meesho", "ajio", "nykaa", "snapdeal"]),
                     ("clothes", "Clothes & shoes", ["clothes", "shirt", "jeans", "dress", "shoes", "kapde", "kapda", "joote", "footwear"]),
                     ("electronics", "Electronics", ["phone", "mobile", "laptop", "earphones", "charger", "gadget", "croma", "reliance digital"]),
                     ("home", "Home & personal care", ["soap", "shampoo", "detergent", "cosmetics", "home", "utensils", "decor"])],
        "health": [("medicine", "Medicines", ["medicine", "medicines", "pharmacy", "chemist", "medical", "medico", "medicose", "dawai", "dava", "apollo", "pharmeasy", "1mg", "netmeds"]),
                   ("doctor", "Doctor & tests", ["doctor", "clinic", "hospital", "lab", "test", "scan", "dentist"]),
                   ("fitness", "Gym & fitness", ["gym", "fitness", "yoga", "cult"]),
                   ("insurance", "Health insurance", ["insurance", "policy", "premium"])],
        "entertainment": [("ott", "OTT & subscriptions", ["netflix", "prime", "hotstar", "spotify", "youtube premium", "jiocinema", "sonyliv", "subscription"]),
                          ("movies", "Movies & events", ["movie", "movies", "pvr", "inox", "bookmyshow", "concert", "event", "picture"]),
                          ("outing", "Outings & parties", ["outing", "party", "trip", "club"]),
                          ("games", "Games", ["game", "games", "steam", "playstation"])],
        "debt": [("card", "Credit card bill", ["credit card", "card bill", "card payment", "sbi card", "onecard", "card"]),
                 ("gadget", "Phone / gadget EMI", ["phone emi", "mobile emi", "iphone", "laptop emi", "consumer durable"]),
                 ("vehicle", "Vehicle loan", ["bike loan", "car loan", "vehicle", "two wheeler", "tvs credit", "hero fincorp"]),
                 ("personal", "Personal / app loan", ["personal loan", "mpokket", "kreditbee", "navi", "moneyview", "bajaj finance", "home credit", "hdb", "fibe", "cashe"]),
                 ("paylater", "Pay later", ["simpl", "lazypay", "zestmoney", "paylater", "pay later", "slice", "amazon pay later"]),
                 ("education", "Education loan", ["education loan", "student loan"]),
                 ("home", "Home loan", ["home loan", "housing loan"])],
        "family": [("home", "Sent home", ["home", "ghar", "mom", "dad", "papa", "mummy", "maa"]), ("gifts", "Gifts", ["gift", "gifts", "shagun"]),
                   ("festival", "Festivals & functions", ["diwali", "rakhi", "festival", "wedding", "function", "puja"])],
    ]

    static func subs(_ categoryId: String?) -> [Sub] { map[categoryId ?? ""] ?? [] }

    /// The first subcategory whose word is in the text (longest word wins on ties).
    static func detect(_ categoryId: String?, _ text: String) -> String? {
        let t = " " + text.lowercased() + " "
        var best: (String, Int)? = nil
        for s in subs(categoryId) {
            for w in s.words where w.count > (best?.1 ?? 0) {
                if Parser.test("(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: w.trimmingCharacters(in: .whitespaces)) + "($|[^a-z0-9])", t) { best = (s.id, w.count) }
            }
        }
        return best?.0
    }

    static func name(_ categoryId: String?, _ subId: String?) -> String? {
        guard let subId else { return nil }
        return subs(categoryId).first { $0.id == subId }?.name
    }

    static let investmentTypes = ["SIP", "Mutual fund", "ELSS (tax saver)", "Index fund", "FD", "RD", "PPF", "EPF / VPF", "NPS", "Stocks", "ETF",
                                  "Gold / SGB", "Digital gold", "Bonds", "LIC / insurance plan", "Sukanya Samriddhi", "Real estate", "Crypto", "Chit fund", "Other"]
}

extension AppData {
    /// An entry's subcategory: the one you picked, or the one its note/merchant points to.
    func subcategory(_ e: Entry) -> String? {
        guard e.type == "expense" else { return nil }
        return e.sub ?? Subcats.detect(e.categoryId, (e.note ?? "") + " " + (e.source ?? ""))
    }
}
