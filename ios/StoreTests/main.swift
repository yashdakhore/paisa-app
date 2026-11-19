import Foundation
// Store logic tests: learning, card purchases, bank SMS inbox, payoff maths. Run: ios/StoreTests/run.sh
var failures = 0, checks = 0
func eq<T: Equatable>(_ a: T, _ b: T, _ label: String, line: Int = #line) {
    checks += 1
    if a != b { failures += 1; print("FAIL line \(line) [\(label)]: got \(a), expected \(b)") }
}
BudgetAlerts.enabled = false
let store = KoshStore()
store.data = AppData.empty()
store.data.debts = [Debt(id: "sbi", name: "SBI Card", kind: "card", balance: 30000, limit: 50000, keywords: ["sbi"]),
                    Debt(id: "mp", name: "mPokket loan", kind: "loan", balance: 5000, keywords: ["mpokket"])]

// 1. Learning: "porter" isn't known → Other; after a correction to Transport it's learned.
eq(store.parse("150 porter").categoryId, "other", "porter unknown")
eq(store.learn(from: "Porter", categoryId: "transport"), ["porter"], "learn returns word")
eq(store.parse("150 porter").categoryId, "transport", "porter learned")
// A learned word beats a built-in word of another category ("milk" is built into Groceries).
store.learn(from: "milk", categoryId: "food")
eq(store.parse("60 milk").categoryId, "food", "learned beats built-in")
// Re-teaching moves it.
store.learn(from: "milk", categoryId: "groceries")
eq(store.parse("60 milk").categoryId, "groceries", "re-taught")
eq(store.data.categories.first { $0.id == "food" }?.learned?.contains("milk"), false, "removed from old")

// 2. Card purchase raises the card balance; deleting it lowers it back.
var e = Entry(id: "c1", type: "expense", amount: 500, date: Parser.iso(Date()), categoryId: "food")
e.cardId = "sbi"; e.applied = true
store.saveEntry(e, previous: nil)
eq(store.data.debts.first { $0.id == "sbi" }?.balance, 30500, "card purchase adds")
store.deleteEntry(store.data.entries.first { $0.id == "c1" }!)
eq(store.data.debts.first { $0.id == "sbi" }?.balance, 30000, "delete reverses")

// 3. Bank SMS → inbox → confirm.
let now = Date()
let item = store.addBankMessage("Rs.250.00 spent on your SBI Credit Card ending 1234 at SWIGGY on \(Parser.iso(now)).", now: now)
eq(item?.categoryId, "food", "sms category from merchant")
eq(item?.cardId, "sbi", "sms matched card")
eq(store.addBankMessage("Rs.250.00 spent on your SBI Credit Card ending 1234 at SWIGGY on \(Parser.iso(now)).", now: now) == nil, true, "duplicate skipped")
eq(store.liveInbox.count, 1, "one in inbox")
let entry = store.confirmInbox(item!, categoryId: nil)
eq(entry.cardId, "sbi", "entry keeps card")
eq(store.data.debts.first { $0.id == "sbi" }?.balance, 30250, "confirmed card spend adds to balance")
eq(store.liveInbox.count, 0, "inbox cleared")
// Changing the category when confirming teaches the merchant.
let item2 = store.addBankMessage("Rs 120 debited from A/c XX1234 to VPA zingbus@ybl on \(Parser.iso(now)).", now: now.addingTimeInterval(700))!
eq(item2.categoryId, "other", "unknown merchant")
_ = store.confirmInbox(item2, categoryId: "transport")
eq(store.parse("300 zingbus").categoryId, "transport", "learned from inbox correction")
eq(store.addBankMessage("Your OTP is 123456 for Rs 500", now: now) == nil, true, "otp ignored")

// 3b. Several cards: the right one is picked from the message.
store.data.debts += [Debt(id: "one", name: "OneCard", kind: "card", balance: 0, limit: 20000),
                     Debt(id: "idfc", name: "IDFC First Card", kind: "card", balance: 0, limit: 30000),
                     Debt(id: "sm", name: "Supermoney Card", kind: "card", balance: 0, limit: 10000)]
eq(store.addBankMessage("You have spent Rs.640 at ZOMATO using your OneCard on \(Parser.iso(now)).", now: now.addingTimeInterval(1400))?.cardId, "one", "onecard matched")
eq(store.addBankMessage("Rs 999 spent on your IDFC FIRST Bank Credit Card XX4321 at AMAZON on \(Parser.iso(now))", now: now.addingTimeInterval(2100))?.cardId, "idfc", "idfc matched")
eq(store.addBankMessage("Rs.150 paid to RAPIDO via super.money RuPay credit card on \(Parser.iso(now))", now: now.addingTimeInterval(2800))?.cardId, "sm", "supermoney matched")
eq(store.addBankMessage("Rs.250.00 spent on your SBI Credit Card ending 1234 at BLINKIT on \(Parser.iso(now)).", now: now.addingTimeInterval(3500))?.cardId, "sbi", "sbi still matched")

// 3c. Emails: card bill payments, money to yourself, SMS + email for the same spend.
let d = Parser.iso(now)
let sbiBefore = store.data.debts.first { $0.id == "sbi" }!.balance!
let pay = store.addBankMessage("Thank you for making payment towards your SBI Credit Card XXXX0000 using BillDesk. Amount Paid: Rs. 500.00 Payment Date: \(d)", now: now.addingTimeInterval(4200))
eq(pay?.type, "payment", "bill payment queued"); eq(pay?.cardId, "sbi", "bill payment card"); eq(pay?.categoryId, "debt", "bill payment category")
let payEntry = store.confirmInbox(pay!, categoryId: nil)
eq(payEntry.type, "expense", "payment saved as expense"); eq(payEntry.debtId, "sbi", "payment linked to card"); eq(payEntry.cardId, nil, "payment isn't a purchase")
eq(store.data.debts.first { $0.id == "sbi" }?.balance, sbiBefore - 500, "payment lowers card balance")
store.saveMyName("Asha Kumar")
eq(store.addBankMessage("Rs 2000 debited from your account via UPI on \(d) to Asha K. RRN 600000000000", now: now.addingTimeInterval(4900)) == nil, true, "money to yourself skipped")
eq(store.addBankMessage("Rs 200 debited from your account via UPI on \(d) to Asha Stores. RRN 600000000001", now: now.addingTimeInterval(5600)) != nil, true, "same first name, different payee kept")
let smsOne = store.addBankMessage("Rs 777 spent on your IDFC FIRST Bank Credit Card XX0000 at DMART on \(d)", now: now.addingTimeInterval(6300))
eq(smsOne?.maybeDuplicate, nil, "first alert not flagged")
let mailOne = store.addBankMessage("INR 777.00 spent on your IDFC FIRST BANK Credit Card ending XX0000 at D MART RETAIL on \(d). Available Limit: INR 1,000", now: now.addingTimeInterval(6400))
eq(mailOne?.maybeDuplicate, true, "email of the same spend flagged")

// 4. Payoff maths.
// One debt, 10,000 at 12% a year (1% a month), paying 5,000: month 1: 10,100 → 5,100; month 2: 5,151 → 151; month 3: 152.51 → 0.
let r = simulatePayoff([(balance: 10000, apr: 12)], monthly: 5000, avalanche: true)
eq(r.months, 3, "paid off in 3 months")
eq(abs(r.interest - 152.51) < 0.01, true, "interest by hand = 100 + 51 + 1.51")
let never = simulatePayoff([(balance: 30000, apr: 42)], monthly: 1000, avalanche: true)
eq(never.months, nil, "1k never pays 42% on 30k")
let r2 = simulatePayoff([(balance: 30000, apr: 42), (balance: 5000, apr: 36)], monthly: 6000, avalanche: true)
let snow = simulatePayoff([(balance: 30000, apr: 42), (balance: 5000, apr: 36)], monthly: 6000, avalanche: false)
eq(snow.interest >= r2.interest, true, "avalanche saves at least as much")

print(failures == 0 ? "PASS: all \(checks) checks" : "\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
