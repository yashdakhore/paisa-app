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
let entry = store.confirmInbox(item!, categoryId: nil)!
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
let payEntry = store.confirmInbox(pay!, categoryId: nil)!
eq(payEntry.type, "expense", "payment saved as expense"); eq(payEntry.debtId, "sbi", "payment linked to card"); eq(payEntry.cardId, nil, "payment isn't a purchase")
eq(store.data.debts.first { $0.id == "sbi" }?.balance, sbiBefore - 500, "payment lowers card balance")
store.saveMyName("Asha Kumar")
eq(store.addBankMessage("Rs 2000 debited from your account via UPI on \(d) to Asha K. RRN 600000000000", now: now.addingTimeInterval(4900)) == nil, true, "money to yourself skipped")
eq(store.addBankMessage("Rs 200 debited from your account via UPI on \(d) to Asha Stores. RRN 600000000001", now: now.addingTimeInterval(5600)) != nil, true, "same first name, different payee kept")
let smsOne = store.addBankMessage("Rs 777 spent on your IDFC FIRST Bank Credit Card XX0000 at DMART on \(d)", now: now.addingTimeInterval(6300))
eq(smsOne?.maybeDuplicate, nil, "first alert not flagged")
let mailOne = store.addBankMessage("INR 777.00 spent on your IDFC FIRST BANK Credit Card ending XX0000 at D MART RETAIL on \(d). Available Limit: INR 1,000", now: now.addingTimeInterval(6400))
eq(mailOne?.maybeDuplicate, true, "email of the same spend flagged")

// 3d. Voice commands change the right things.
let vs = KoshStore()
vs.data = AppData.empty()
vs.data.debts = [Debt(id: "s", name: "SBI Card", kind: "card", balance: 1000, limit: 20000)]
func run(_ s: String) -> String? { Commands.parse(s).map { vs.perform($0) } }
_ = run("SBI card balance is 8500")
eq(vs.data.debts.first { $0.id == "s" }?.balance, 8500, "voice: card balance updated")
_ = run("add IDFC credit card limit 30000 due on 20th")
let idfc = vs.data.liveDebts.first { $0.name == "IDFC Card" }
eq(idfc?.limit, 30000, "voice: new card limit"); eq(idfc?.dueDay, 20, "voice: new card due"); eq(idfc?.kind, "card", "voice: new card kind")
_ = run("add sbi credit card limit 25000")
eq(vs.data.liveDebts.filter { $0.kind == "card" }.count, 2, "voice: same card updated, not duplicated")
eq(vs.data.debts.first { $0.id == "s" }?.limit, 25000, "voice: existing card limit changed")
_ = run("add bike loan 80000 emi 3500")
eq(vs.data.liveDebts.first { $0.name == "Bike loan" }?.emi, 3500, "voice: loan emi")
_ = run("new goal emergency fund 50000 by december 2027")
eq(vs.data.liveGoals.first?.target, 50000, "voice: goal target"); eq(vs.data.liveGoals.first?.deadline, "2027-12", "voice: goal deadline")
_ = run("start SIP 2000 in nifty index fund")
eq(vs.data.liveInvestments.first?.monthly, 2000, "voice: sip monthly")
_ = run("set food budget 6000")
eq(vs.data.categories.first { $0.id == "food" }?.budget, 6000, "voice: food budget")
_ = run("my salary is 30000")
eq(vs.data.settings.salary, 30000, "voice: salary")
_ = run("cibil score 760")
eq(vs.data.scores.first?.score, 760, "voice: score")
eq(vs.preview(Commands.parse("hdfc card balance 500")!).canSave, false, "voice: unknown card can't be saved")
// Answers use your numbers.
let ans = vs.answer(.owe)
eq(ans.hasPrefix("You owe ₹88,500"), true, "voice: owe total = 8500 + 80000")
eq(vs.answer(.canSpend).contains("left this month"), true, "voice: can spend answer")
eq(vs.answer(.afford(1_000_000)).hasPrefix("Not this month"), true, "voice: can't afford 10 lakh")
eq(vs.answer(.spent(query: "food", lastMonth: false)).contains("of your ₹6,000 budget"), true, "voice: spent vs budget")
eq(vs.answer(.score), "Your latest scores: CIBIL 760.", "voice: score answer")

// 3e. Card bill payments don't count as spending; stuck "Other" bank entries get re-sorted.
let cs = KoshStore()
cs.data = AppData.empty()
cs.data.debts = [Debt(id: "c", name: "IDFC Card", kind: "card", balance: 5000), Debt(id: "l", name: "Bike loan", kind: "loan", balance: 50000)]
let today = Parser.iso(Date())
cs.saveEntry(Entry(id: "p1", type: "expense", amount: 400, date: today, note: "Eternal", categoryId: "other", source: "bank sms"), previous: nil)
cs.saveEntry(Entry(id: "p2", type: "expense", amount: 1500, date: today, categoryId: "debt", debtId: "c"), previous: nil)
cs.saveEntry(Entry(id: "p3", type: "expense", amount: 3000, date: today, categoryId: "debt", debtId: "l"), previous: nil)
eq(cs.data.monthSummary(monthKey(Date())).spent, 3400, "card payment not spending, loan EMI is")
eq(cs.recategorizeBankEntries(), 1, "one bank entry re-sorted")
eq(cs.data.entries.first { $0.id == "p1" }?.categoryId, "food", "eternal is food")

// 3f. Delete all transactions: entries and inbox go, balances go back, everything else stays.
let ds = KoshStore()
ds.data = AppData.empty()
ds.data.debts = [Debt(id: "c", name: "SBI Card", kind: "card", balance: 1000)]
ds.data.goals = [Goal(id: "g", name: "Bike", kind: "save", target: 50000, saved: 0)]
ds.data.settings.salary = 30000
var buy = Entry(id: "b", type: "expense", amount: 500, date: Parser.iso(Date()), categoryId: "food"); buy.cardId = "c"; buy.applied = true
ds.saveEntry(buy, previous: nil)
var sv = Entry(id: "s", type: "save", amount: 2000, date: Parser.iso(Date()), goalId: "g"); sv.applied = true
ds.saveEntry(sv, previous: nil)
_ = ds.addBankMessage("Rs 99 spent on your SBI Credit Card at KFC on \(Parser.iso(Date()))")
eq(ds.data.debts[0].balance, 1500, "before: card balance raised")
let cleared = ds.deleteAllTransactions()
eq(cleared.count, 2, "two entries deleted")
eq(ds.data.liveEntries.count, 0, "no entries left"); eq(ds.liveInbox.count, 0, "inbox empty")
eq(ds.data.debts[0].balance, 1000, "card balance back"); eq(ds.data.goals[0].saved, 0, "goal saved back")
eq(ds.data.settings.salary, 30000, "salary kept"); eq(ds.data.liveDebts.count, 1, "card kept"); eq(ds.data.liveGoals.count, 1, "goal kept")

// 3g. Budget suggestion.
let fx = [FixedCost(id: "1", name: "Rent", amount: 8000, categoryId: "rent"), FixedCost(id: "2", name: "WiFi", amount: 500, categoryId: "phone"),
          FixedCost(id: "3", name: "Recharge", amount: 300, categoryId: "phone")]
let sug = BudgetSuggest.suggest(income: 25000, fixed: fx, emis: 2000, cardDebt: 20000)
eq(sug.flexible, 14200, "flexible = 25000 - 8800 - 2000")
eq(sug.lines.first { $0.categoryId == "rent" }?.amount, 8000, "rent is just the fixed cost")
eq(sug.lines.first { $0.categoryId == "phone" }?.amount, 800, "phone fixed only (no extra share)")
eq(sug.lines.contains { $0.categoryId == "debt" }, false, "card payments aren't a budget line")
eq(sug.lines.allSatisfy { $0.amount.truncatingRemainder(dividingBy: 100) == 0 }, true, "round hundreds")
eq(sug.leftover > 14200 * 0.4 && sug.leftover < 14200 * 0.5, true, "with card debt about 45% kept back")
eq(abs(sug.income - sug.lines.reduce(0) { $0 + $1.amount } - sug.emis - sug.leftover) < 0.01, true, "everything adds up")
eq(sug.note.hasPrefix("Put ₹"), true, "card payoff advice")
let noDebt = BudgetSuggest.suggest(income: 25000, fixed: fx, emis: 0, cardDebt: 0)
eq(noDebt.note.hasPrefix("Save ₹"), true, "no debt: save and invest")
eq(BudgetSuggest.suggest(income: 10000, fixed: fx, emis: 3000, cardDebt: 0).note.hasPrefix("Your fixed costs"), true, "over income warning")

// 3h. Unique references: the SMS and email of one payment count once; re-fetches don't duplicate.
let us = KoshStore()
us.data = AppData.empty()
let dd = Parser.iso(Date())
let upiSMS = "Rs 450.00 debited from A/c XX0000 on \(dd) to VPA chaipoint@ybl (UPI Ref No 612345678901)."
let upiMail = "Hi, ₹450 debited from your account via UPI. | Transaction date | \(dd) | To | Chai Point | RRN | 612345678901 |"
eq(us.addBankMessage(upiSMS) != nil, true, "sms added")
eq(us.addBankMessage(upiMail, gmailId: "g1"), nil, "email with same RRN skipped")
eq(us.liveInbox.count, 1, "one in review")
let it = us.liveInbox[0]
let ent = us.confirmInbox(it, categoryId: "food")!
eq(ent.txnKey != nil && ent.txnKey!.hasPrefix("r"), true, "entry keeps scrambled key")
eq(ent.txnKey!.contains("612345678901"), false, "raw reference not stored")
eq(us.addBankMessage(upiMail, gmailId: "g1", manual: true), nil, "re-fetch of confirmed one skipped")
// Card spends with a time: same minute = same spend.
let c1 = "INR 310.40 spent on your IDFC FIRST BANK Credit Card ending XX0000 at IOCL on \(dd) at 10:15 AM."
let c2 = "Rs.310.40 spent on IDFC FIRST Bank Credit Card XX0000 at IOCL PETROL on \(dd) 10:15"
eq(us.addBankMessage(c1, gmailId: "g2") != nil, true, "card email added")
eq(us.addBankMessage(c2), nil, "card sms same minute skipped")
eq(us.addBankMessage("INR 310.40 spent on your IDFC FIRST BANK Credit Card ending XX0000 at IOCL on \(dd) at 6:40 PM.", gmailId: "g3") != nil, true, "same amount later is a new spend")
// Deleted ones: automatic checks never bring them back; a fetch you start can.
us.discardInbox(us.liveInbox.first { $0.gmailId == "g2" }!)
eq(us.addBankMessage(c1, gmailId: "g2"), nil, "discarded stays gone on auto check")
eq(us.addBankMessage(c1, gmailId: "g2", manual: true) != nil, true, "manual fetch brings it back")
_ = us.deleteAllTransactions()
eq(us.addBankMessage(upiMail, gmailId: "g1") , nil, "after delete-all, auto check doesn't re-add")
eq(us.addBankMessage(upiMail, gmailId: "g1", manual: true) != nil, true, "after delete-all, fetch this month re-adds")

// 3i. Double "Add all", cash deposits, and month fetches vs card balances.
let ws = KoshStore()
ws.data = AppData.empty()
ws.data.debts = [Debt(id: "i", name: "IDFC Card", kind: "card", balance: 2000, limit: 5000)]
let wd = Parser.iso(Date())
let one = ws.addBankMessage("INR 835.00 spent on your IDFC FIRST BANK Credit Card ending XX0000 at RENTMOJO on \(wd) at 10:00 AM.")!
eq(ws.confirmInbox(one, categoryId: nil) != nil, true, "first confirm adds")
eq(ws.confirmInbox(one, categoryId: nil) == nil, true, "second confirm of same item does nothing")
eq(ws.data.liveEntries.count, 1, "only one entry")
eq(ws.data.debts[0].balance, 2835, "new spend raises card balance")
eq(ws.addBankMessage("Your A/C XXXXX000000 Credited INR 47000.00 on \(wd) -Deposit of Cash at S5NM000000000 CDM. Avl Bal INR 47279.17-SBI"), nil, "cash deposit skipped")
eq(ws.addBankMessage("Rs 2000 withdrawn at ATM from A/c XX0000 on \(wd)"), nil, "atm withdrawal skipped")
let old = ws.addBankMessage("INR 400.00 spent on your IDFC FIRST BANK Credit Card ending XX0000 at IOCL on \(wd) at 9:00 AM.", gmailId: "m9", manual: true)!
eq(old.backfill, true, "month fetch item marked")
_ = ws.confirmInbox(old, categoryId: nil)
eq(ws.data.debts[0].balance, 2835, "month fetch spend doesn't change card balance")
eq(ws.data.monthSummary(monthKey(Date())).spent, 1235, "but it still counts as spending")

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
