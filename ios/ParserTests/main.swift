import Foundation

// Same cases as tests/parser.test.mjs for the web app. Run: ios/ParserTests/run.sh
var failures = 0
var checks = 0
func eq<T: Equatable>(_ a: T, _ b: T, _ label: String, line: Int = #line) {
    checks += 1
    if a != b { failures += 1; print("FAIL line \(line) [\(label)]: got \(a), expected \(b)") }
}

let now = Parser.day(2026, 11, 18) // Wed 18 Nov 2026
let cats = ["rent", "bills", "groceries", "food", "transport", "phone", "shopping", "health", "entertainment", "debt", "other"]
    .map { Parser.Item(id: $0, words: (Parser.defaultKeywords[$0] ?? []) + Parser.nameWords($0)) }
let debts = [Parser.Item(id: "sbi", words: Parser.nameWords("SBI Card") + ["sbi"]), Parser.Item(id: "mp", words: Parser.nameWords("mPokket loan") + ["mpokket"])]
let goals = [Parser.Item(id: "ef", words: Parser.nameWords("Emergency fund"))]
let invs = [Parser.Item(id: "sip1", words: Parser.nameWords("Monthly SIP") + ["SIP"])]
func p(_ s: String) -> Parser.Result { Parser.parse(s, categories: cats, debts: debts, goals: goals, investments: invs, now: now) }

// basic phrases
var r = p("spent 250 on groceries")
eq(r.amount, 250, "amount"); eq(r.categoryId, "groceries", "cat"); eq(r.date, "2026-11-18", "date"); eq(r.type, "expense", "type")
r = p("paid 9000 rent"); eq(r.amount, 9000, "amount"); eq(r.categoryId, "rent", "cat"); eq(r.note, "Rent", "note")
r = p("Paid ₹9,000 rent"); eq(r.amount, 9000, "amount ₹ comma")

// dates
eq(p("120 auto yesterday").date, "2026-11-17", "yesterday")
eq(p("spent 300 on swiggy day before yesterday").date, "2026-11-16", "day before")
eq(p("400 dinner on monday").date, "2026-11-16", "monday")
eq(p("500 medicine on 5th november").date, "2026-11-05", "5th nov")
eq(p("500 medicine on the 2nd").date, "2026-11-02", "the 2nd")
eq(p("rent 9000 on 1st").date, "2026-11-01", "1st")
eq(p("600 shoes 3 days ago").date, "2026-11-15", "3 days ago")
eq(p("900 flight on 20 dec").date, "2025-12-20", "20 dec last year")
r = p("500 medicine on 5th november"); eq(r.amount, 500, "amount w/ date"); eq(r.categoryId, "health", "health")

// amount formats
eq(p("2k on shopping").amount, 2000, "2k")
eq(p("1.5k petrol").amount, 1500, "1.5k")
eq(p("rs 99 jio recharge").amount, 99, "rs 99")
eq(p("two hundred fifty on vegetables").amount, 250, "words")
eq(p("five thousand to sbi card").amount, 5000, "five thousand")
eq(p("spent a hundred on chai").amount, 100, "a hundred")
eq(p("spent 250 rupees on milk").amount, 250, "rupees")

// debt, income, invest, save
r = p("paid 5000 to SBI card"); eq(r.categoryId, "debt", "debt cat"); eq(r.debtId, "sbi", "sbi")
r = p("repaid 4000 mpokket"); eq(r.categoryId, "debt", "debt cat2"); eq(r.debtId, "mp", "mp")
r = p("got salary 30000"); eq(r.type, "income", "income"); eq(r.amount, 30000, "salary")
r = p("invested 2000 in SIP"); eq(r.type, "invest", "invest"); eq(r.investmentId, "sip1", "sip")
r = p("saved 3000 for emergency fund"); eq(r.type, "save", "save"); eq(r.goalId, "ef", "ef")

// unknown category
r = p("spent 70 on stationery"); eq(r.categoryId, "other", "other"); eq(r.note, "Stationery", "note2"); eq(r.sureCategory, false, "unsure")

// words to digits
eq(Parser.wordsToDigits("two hundred and fifty rupees"), "250 rupees", "w2d 1")
eq(Parser.wordsToDigits("one lakh twenty thousand"), "120000", "w2d 2")

// Hinglish
r = p("kiraya 9000 diya"); eq(r.categoryId, "rent", "kiraya"); eq(r.amount, 9000, "kiraya amt")
r = p("bijli ka bill 750"); eq(r.categoryId, "bills", "bijli")
r = p("sabzi 120 kal"); eq(r.categoryId, "groceries", "sabzi"); eq(r.date, "2026-11-17", "kal")
r = p("dawai 300 parso"); eq(r.categoryId, "health", "dawai"); eq(r.date, "2026-11-16", "parso")
r = p("doodh 60 rupaye aaj"); eq(r.amount, 60, "rupaye"); eq(r.categoryId, "groceries", "doodh"); eq(r.date, "2026-11-18", "aaj")
eq(p("5 sau ka khana").amount, 500, "5 sau")
eq(p("2 hazaar ke kapde").amount, 2000, "2 hazaar"); eq(p("2 hazaar ke kapde").categoryId, "shopping", "kapde")

// several items
func pm(_ s: String) -> [Parser.Result] { Parser.parseMany(s, categories: cats, debts: debts, goals: goals, investments: invs, now: now) }
var m = pm("250 groceries and 120 auto")
eq(m.count, 2, "two items"); eq(m[0].amount, 250, "m0"); eq(m[0].categoryId, "groceries", "m0c"); eq(m[1].amount, 120, "m1"); eq(m[1].categoryId, "transport", "m1c")
m = pm("spent 250 on groceries, 120 on auto and 60 chai yesterday")
eq(m.count, 3, "three items"); eq(m.map(\.date), ["2026-11-17", "2026-11-17", "2026-11-17"], "shared date"); eq(m[2].categoryId, "food", "chai")
m = pm("paid 9,000 rent aur 750 bijli")
eq(m.count, 2, "aur"); eq(m[0].amount, 9000, "aur0"); eq(m[1].categoryId, "bills", "aur1")
eq(pm("two hundred and fifty on vegetables").count, 1, "and inside number")
eq(pm("500 medicine on 5th november").count, 1, "date not an item")
eq(pm("bread and butter 80").count, 1, "and without 2 amounts")

print(failures == 0 ? "PASS: all \(checks) checks" : "\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
