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

// Bank SMS
func sms(_ s: String) -> BankSMS.Txn? { BankSMS.parse(s, now: now) }
var b = sms("Rs.250.00 spent on your SBI Credit Card ending 1234 at SWIGGY on 18/11/26. Not you? Call 1800...")
eq(b?.type, "expense", "sms1 type"); eq(b?.amount, 250, "sms1 amt"); eq(b?.merchant, "Swiggy", "sms1 merchant"); eq(b?.date, "2026-11-18", "sms1 date"); eq(b?.cardHint, "sbi", "sms1 card")
b = sms("Dear Customer, Rs 120.00 debited from A/c XX1234 on 17-11-26 to VPA rapido@ybl (UPI Ref No 612345678901). Not you? Call 1800")
eq(b?.amount, 120, "sms2 amt"); eq(b?.merchant, "Rapido", "sms2 merchant"); eq(b?.date, "2026-11-17", "sms2 date"); eq(b?.cardHint, nil, "sms2 no card")
b = sms("INR 1,840.00 spent on HDFC Bank Credit Card XX1234 at BLINKIT on 2026-11-16:10:22:01. Avl bal: INR 50,000.00")
eq(b?.amount, 1840, "sms3 amt"); eq(b?.merchant, "Blinkit", "sms3 merchant"); eq(b?.date, "2026-11-16", "sms3 date"); eq(b?.cardHint, "hdfc", "sms3 card")
b = sms("Your A/c XX1234 is credited with Rs 35,000.00 on 01-11-26 by NEFT from ACME CORP PVT LTD. Avl Bal Rs 40,123")
eq(b?.type, "income", "sms4 type"); eq(b?.amount, 35000, "sms4 amt"); eq(b?.date, "2026-11-01", "sms4 date")
eq(sms("123456 is your OTP for txn of Rs 500 at AMAZON. Do not share.") == nil, true, "otp ignored")
eq(sms("Total Amount Due Rs 18500 for XYZ Card is due on 15-12-26") == nil, true, "due ignored")
eq(sms("Txn of Rs 999 at FLIPKART declined due to insufficient balance") == nil, true, "declined ignored")
b = sms("Rs 299 paid to JIO via UPI on 18Nov26. UPI Ref 61234")
eq(b?.amount, 299, "sms5 amt"); eq(b?.merchant, "Jio", "sms5 merchant"); eq(b?.date, "2026-11-18", "sms5 date")
eq((b?.merchant ?? "").contains(where: \.isNumber), false, "no numbers kept")

b = sms("You have spent Rs.640 at ZOMATO using your OneCard on 18-11-26.")
eq(b?.cardHint, "onecard", "onecard hint"); eq(b?.merchant, "Zomato", "onecard merchant")
b = sms("Rs 999 spent on your IDFC FIRST Bank Credit Card XX4321 at AMAZON on 17/11/26")
eq(b?.cardHint, "idfc", "idfc hint")
b = sms("Rs.150 paid to RAPIDO via super.money RuPay credit card on 18-11-26")
eq(b?.cardHint, "supermoney", "supermoney hint")

// learnable words
// Gmail API messages → text.
func b64url(_ s: String) -> String { Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
let gjson = """
{"id":"m1","internalDate":"1794983400000","payload":{"mimeType":"multipart/alternative","headers":[{"name":"Subject","value":"Debit Alert"}],
 "parts":[{"mimeType":"text/html","body":{"data":"\(b64url("<p>INR 310.40 spent on your <b>IDFC FIRST BANK Credit Card</b> at IOCL on 18 NOV 2026</p>"))"}}]}}
"""
let gm = try! JSONDecoder().decode(GmailMessage.Message.self, from: Data(gjson.utf8))
let gtext = GmailMessage.text(gm)
eq(gtext.hasPrefix("Debit Alert\n"), true, "gmail subject first")
b = sms(gtext)
eq(b?.amount, 310.40, "gmail html amt"); eq(b?.merchant, "Iocl", "gmail html merchant"); eq(b?.cardHint, "idfc", "gmail html card")
eq(GmailMessage.date(gm).map { Parser.iso($0) }, "2026-11-18", "gmail internal date")
let gjson2 = """
{"id":"m2","payload":{"mimeType":"multipart/alternative","headers":[],"parts":[
 {"mimeType":"text/plain","body":{"data":"\(b64url("Rs 99 debited via UPI to Chai Point on 18-11-26"))"}},
 {"mimeType":"text/html","body":{"data":"\(b64url("<p>ignored html</p>"))"}}]}}
"""
let gm2 = try! JSONDecoder().decode(GmailMessage.Message.self, from: Data(gjson2.utf8))
eq(GmailMessage.text(gm2).contains("ignored html"), false, "plain text preferred")
eq(sms(GmailMessage.text(gm2))?.merchant, "Chai Point", "gmail plain merchant")
eq(GmailMessage.query(senders: ["a.com", " b.in ", ""], days: 3), "from:(a.com OR b.in) newer_than:3d", "gmail query")

// Bank emails (made-up names and numbers, real layouts).
b = sms("Dear Customer, INR 310.40 spent on your IDFC FIRST BANK Credit Card ending XX0000 at IOCL on 18 NOV 2026 at 10:15 AM. Available Limit: INR 12,345.00. If not done by you, call us. Never share your OTP with anyone.")
eq(b?.type, "expense", "idfc mail type"); eq(b?.amount, 310.40, "idfc mail amt"); eq(b?.merchant, "Iocl", "idfc mail merchant"); eq(b?.date, "2026-11-18", "idfc mail date"); eq(b?.cardHint, "idfc", "idfc mail card")
b = sms("Dear Customer,\nPayment of Rs. 2400.00 was received on your Rewards Credit Card ending with XX0000 on 17 Nov 2026.\nThank you.\nDo not share your card details or OTP with anyone.\nTeam IDFC FIRST Bank")
eq(b?.type, "payment", "card payment type"); eq(b?.amount, 2400, "card payment amt"); eq(b?.cardHint, "idfc", "card payment bank"); eq(b?.date, "2026-11-17", "card payment date")
b = sms("Hi Asha,\n| ₹1 debited from your slice account xx0000 via UPI. |\n| Transaction date | 18-Nov-26 |\n| To | Sharma General Store |\n| RRN | 600000000000 |\nNot you? [Contact us](https://example.com)")
eq(b?.type, "expense", "slice type"); eq(b?.amount, 1, "slice amt"); eq(b?.merchant, "Sharma General Store", "slice merchant"); eq(b?.date, "2026-11-18", "slice date")
b = sms("<p>Dear Customer,</p><table><tr><td>Terminal Owner Name</td><td>PYU*Zomato Limited</td></tr><tr><td>Terminal Id</td><td>00000000</td></tr><tr><td>Date &amp; Time</td><td>Nov 18, 2026, 13:12</td></tr><tr><td>Amount (INR)</td><td>845.50</td></tr><tr><td>Transaction Type</td><td>PURCHASE</td></tr></table><p>Your SBI Debit Card was used.</p>")
eq(b?.type, "expense", "sbi table type"); eq(b?.amount, 845.50, "sbi table amt"); eq(b?.merchant, "Zomato", "sbi table merchant"); eq(b?.date, "2026-11-18", "sbi table date"); eq(b?.cardHint, nil, "debit card is not a credit card")
b = sms("Dear Customer, Your A/C XXXXX000000 has credit for MREF of Rs 611.25 on 16/11/26. Avl Bal Rs 1,000.00 -SBI")
eq(b?.type, "income", "sbi cbs credit type"); eq(b?.amount, 611.25, "sbi cbs credit amt"); eq(b?.date, "2026-11-16", "sbi cbs date")
b = sms("Dear Customer, Your A/C XXXXX000000 Credited INR 4200.00 on 13/11/26 -Deposit by transfer from Asha Kumar. Avl Bal INR 4,000.00-SBI")
eq(b?.type, "income", "sbi cbs credited"); eq(b?.amount, 4200, "sbi cbs credited amt")
b = sms("Dear Customer, Thank you for making payment towards your SBI Credit Card XXXX0000 using BillDesk. Amount Paid: Rs. 500.00 Payment Date: 13 Nov 2026 Transaction Ref: ABC123")
eq(b?.type, "payment", "billdesk type"); eq(b?.amount, 500, "billdesk amt"); eq(b?.cardHint, "sbi", "billdesk card"); eq(b?.date, "2026-11-13", "billdesk date")
eq(sms("Get up to Rs 500 cashback on your SBI Credit Card! Shop now. T&C apply.") == nil, true, "promo mail ignored")
eq(sms("Your SBI Card statement is ready. Total Amount Due: Rs 4,321.00. Minimum Amount Due: Rs 300. Due date 05 Dec 2026.") == nil, true, "statement mail ignored")
eq(BankSMS.cleanMerchant("PTM*ZOMATO LIMITED"), "Zomato", "gateway prefix stripped")
eq(BankSMS.cleanMerchant("XX1234"), nil, "card number never a merchant")

eq(Parser.learnableWords("Rapido ride"), ["rapido"], "learn rapido")
eq(Parser.learnableWords("Big Bazaar Pvt Ltd"), ["big", "bazaar"], "learn bazaar")

print(failures == 0 ? "PASS: all \(checks) checks" : "\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
