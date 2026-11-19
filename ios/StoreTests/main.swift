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
store.data.settings.autoAdd = false   // review-flow tests
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
vs.data.settings.autoAdd = false   // review-flow tests
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
cs.data.settings.autoAdd = false   // review-flow tests
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
ds.data.settings.autoAdd = false   // review-flow tests
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
us.data.settings.autoAdd = false   // review-flow tests
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
ws.data.settings.autoAdd = false   // review-flow tests
ws.data.debts = [Debt(id: "i", name: "IDFC Card", kind: "card", balance: 2000, limit: 5000)]
let wd = Parser.iso(Date())
let one = ws.addBankMessage("INR 835.00 spent on your IDFC FIRST BANK Credit Card ending XX0000 at RENTMOJO on \(wd) at 10:00 AM.")!
eq(ws.confirmInbox(one, categoryId: nil) != nil, true, "first confirm adds")
eq(ws.confirmInbox(one, categoryId: nil) == nil, true, "second confirm of same item does nothing")
eq(ws.data.liveEntries.count, 1, "only one entry")
eq(ws.data.debts[0].balance, 2835, "new spend raises card balance")
let cashIn = ws.addBankMessage("Your A/C XXXXX000000 Credited INR 47000.00 on \(wd) -Deposit of Cash at S5NM000000000 CDM. Avl Bal INR 47279.17-SBI")
eq(cashIn?.kind, "move", "cash deposit is Moved"); eq(cashIn?.reason?.contains("holding for someone"), true, "big deposit asks yours or held")
eq(ws.addBankMessage("Rs 2000 withdrawn at ATM from A/c XX0000 on \(wd)")?.kind, "move", "atm withdrawal is Moved")
ws.discardInbox(ws.liveInbox.first { $0.isCash == true && $0.amount == 47000 }!)
ws.discardInbox(ws.liveInbox.first { $0.isCash == true && $0.amount == 2000 }!)
let old = ws.addBankMessage("INR 400.00 spent on your IDFC FIRST BANK Credit Card ending XX0000 at IOCL on \(wd) at 9:00 AM.", gmailId: "m9", manual: true)!
eq(old.backfill, true, "month fetch item marked")
_ = ws.confirmInbox(old, categoryId: nil)
eq(ws.data.debts[0].balance, 2835, "month fetch spend doesn't change card balance")
eq(ws.data.monthSummary(monthKey(Date())).spent, 1235, "but it still counts as spending")

// 3j. Income sources: salary counts once, family money adds on top, plan uses salary only.
let fs = KoshStore()
fs.data = AppData.empty()
fs.data.settings.autoAdd = false   // review-flow tests
fs.data.settings.salary = 25000
fs.data.settings.myName = "Asha Kumar"
let fd = Parser.iso(Date())
let mk = monthKey(Date())
let mom = fs.addBankMessage("You have received ₹2000 via UPI in your account. Transaction date \(fd) From SUNITA KUMAR RRN 600000000011")!
eq(mom.incomeSource, "family", "same surname = family")
_ = fs.confirmInbox(mom, categoryId: nil)
var ms = fs.data.monthSummary(mk)
eq(ms.income, 27000, "saved salary + family before salary arrives")
eq(ms.extraIncome, 2000, "family is extra")
let sal = fs.addBankMessage("Your A/C XX0000 Credited INR 25500.00 on \(fd) by NEFT SALARY ACME CORP. Avl Bal INR 30000 RRN 600000000012")!
eq(sal.incomeSource, "salary", "salary detected")
_ = fs.confirmInbox(sal, categoryId: nil)
ms = fs.data.monthSummary(mk)
eq(ms.income, 27500, "real salary replaces saved one, family still added")
eq(fs.data.buildPlan().income, 25500, "plan uses salary only")
let friend = fs.addBankMessage("You have received ₹500 via UPI. Transaction date \(fd) From RAVI SHARMA RRN 600000000013")!
eq(friend.incomeSource, "other", "stranger is other")
_ = fs.confirmInbox(friend, categoryId: nil, incomeSource: "family")
eq(fs.data.settings.familyNames ?? [], ["Ravi Sharma"], "marked as family is remembered")
eq(AppData.guessIncomeSource("RAVI SHARMA", myName: "Asha Kumar", familyNames: ["Ravi Sharma"]), "family", "next time sorted automatically")
eq(fs.parse("mom sent 2000").type, "income", "voice: mom sent is money in")
eq(AppData.guessIncomeSource("mom sent", myName: nil, familyNames: []), "family", "voice: mom is family")

// 3k. A credit near your salary is the salary even when the bank calls it "Money received".
let ss = KoshStore()
ss.data = AppData.empty()
ss.data.settings.autoAdd = false   // review-flow tests
ss.data.settings.salary = 25600
ss.saveEntry(Entry(id: "s1", type: "income", amount: 25600, date: Parser.iso(Date()), note: "Money received", source: "bank sms"), previous: nil)
ss.saveEntry(Entry(id: "s2", type: "income", amount: 3, date: Parser.iso(Date()), note: "One97 Communications", source: "bank sms"), previous: nil)
ss.saveEntry(Entry(id: "s3", type: "income", amount: 500, date: Parser.iso(Date()), note: "Money received", source: "bank sms"), previous: nil)
let sm = ss.data.monthSummary(monthKey(Date()))
eq(sm.salaryIncome, 25600, "salary-sized credit is salary"); eq(sm.income, 26103, "not counted twice")
eq(sm.bySource["refund"], 3, "paytm credit is cashback"); eq(sm.bySource["other"], 500, "small unknown credit is other")

// 3l. Kinds, people, pots, rules, auto-add (made-up names).
let ks = KoshStore()
ks.data = AppData.empty()
ks.data.settings.zeroReview = false   // "review unsure ones" mode
ks.data.settings.myName = "Asha Kumar"
let kd = Parser.iso(Date())
func upiIn(_ amt: Int, _ from: String, _ rrn: String) -> InboxItem? { ks.addBankMessage("You have received ₹\(amt) via UPI. Transaction date \(kd) From \(from) RRN \(rrn)") }
func upiOut(_ amt: Int, _ to: String, _ rrn: String) -> InboxItem? { ks.addBankMessage("₹\(amt) debited from your account via UPI. Transaction date \(kd) To \(to) RRN \(rrn)") }
// Sure: known shop → added automatically.
let shop = ks.addBankMessage("Rs 250 spent on your card at SWIGGY on \(kd) UPI Ref No 700000000001")!
eq(shop.autoAdded != nil, true, "known shop auto-added"); eq(ks.liveInbox.isEmpty, true, "nothing waiting")
// Unknown person → waits and asks "Who is …?"
let r1 = upiOut(280, "ROHIT VIJAY VARMA", "700000000002")!
eq(r1.askWho, true, "unknown person asks who"); eq(r1.autoAdded, nil, "unsure waits")
// Answer: friend → suggestion becomes lent; confirm; next payment from him settles it.
ks.setRole("ROHIT VIJAY VARMA", role: "friend")
let r1b = ks.liveInbox.first { $0.id == r1.id }!
eq(r1b.kind, "owed", "friend → lent"); eq(r1b.askWho, nil, "no longer asks")
_ = ks.confirmInbox(r1b)
let rp = ks.person(for: "Rohit Vijay Varma")!
eq(ks.owedBalance(rp.id), 280, "Rohit owes 280")
let back = upiIn(280, "ROHIT VIJAY VARMA", "700000000003")!
eq(back.kind, "owed", "repayment recognised"); eq(back.autoAdded != nil, true, "sure: added")
eq(ks.owedBalance(rp.id), 0, "settled")
eq(ks.data.monthSummary(monthKey(Date())).spent, 250, "lending isn't spending")
// Held money: Dad's cash deposit goes into a pot; transfers out come from it; none counts as yours.
ks.setRole("RAMESH KUMAR", role: "family")
let pot = ks.createPot("Dad's money", personId: ks.person(for: "Ramesh Kumar")!.id)
let dep = ks.addBankMessage("Your A/C XXXXX000000 Credited INR 90000.00 on \(kd) -Deposit of Cash at S5NM000000000 CDM. Avl Bal INR 90279.17-SBI")!
_ = ks.confirmInbox(dep, kind: "held", potId: pot.id)
eq(ks.potLeft(pot.id), 90000, "pot holds 90k")
let toDad = upiOut(60000, "RAMESH KUMAR", "700000000004")!
eq(toDad.kind, "held", "to family while a pot is open → suggested from the pot"); eq(toDad.potId, pot.id, "right pot")
_ = ks.confirmInbox(toDad)
ks.setRole("SUNIL KUMAR", role: "family")
_ = ks.confirmInbox(upiOut(5000, "SUNIL KUMAR", "700000000005")!)
eq(ks.potLeft(pot.id), 25000, "90k − 60k − 5k = 25k left")
var kms = ks.data.monthSummary(monthKey(Date()))
eq(kms.income, 0, "held money isn't income"); eq(kms.spent, 250, "held money isn't spending")
ks.keepRest(pot.id)
kms = ks.data.monthSummary(monthKey(Date()))
eq(ks.potLeft(pot.id), 0, "keep the rest empties the pot"); eq(kms.bySource["family"], 25000, "kept part becomes Family income")
eq(ks.openPots.isEmpty, true, "pot closed")
// Rules: correcting once is remembered.
let mdk = ks.addBankMessage("Rs 899 debited via UPI on \(kd) to MDK ENTERPRISES. RRN 700000000006")!
eq(mdk.autoAdded, nil, "unknown business waits")
_ = ks.confirmInbox(mdk, categoryId: "groceries")
let mdk2 = ks.addBankMessage("Rs 450 debited via UPI on \(kd) to MDK ENTERPRISES. RRN 700000000007")!
eq(mdk2.autoAdded != nil, true, "rule makes next one automatic")
eq(ks.data.liveEntries.first { $0.id == mdk2.autoAdded }?.categoryId, "groceries", "with the learned category")
// "Me" = your other account → Moved.
ks.setRole("ASHA K", role: "me")
eq(ks.looksLikePerson("Mdk Enterprises"), false, "business isn't a person"); eq(ks.looksLikePerson("Rohit Vijay Varma"), true, "name is a person")

// 3m. Less to review: small payments to new people are added; one answer sorts all of a person's payments.
let ls = KoshStore()
ls.data = AppData.empty()
ls.data.settings.zeroReview = false
let ld = Parser.iso(Date())
let tiny = ls.addBankMessage("Rs 30 debited via UPI on \(ld) to PRIYA NAIR SHARMA. RRN 710000000001")!
eq(tiny.autoAdded != nil, true, "₹30 to someone new: added, not asked")
_ = ls.addBankMessage("Rs 500 debited via UPI on \(ld) to KUNAL MEHTA. RRN 710000000002")
_ = ls.addBankMessage("Rs 700 debited via UPI on \(ld) to KUNAL MEHTA. RRN 710000000003")
eq(ls.liveInbox.filter { $0.askWho == true }.count, 2, "two payments to Kunal wait")
ls.setRole("KUNAL MEHTA", role: "shop")
eq(ls.liveInbox.count, 2, "shop with unknown category still needs a category")
ls.setRole("KUNAL MEHTA", role: "family")
eq(ls.liveInbox.count, 0, "answering family adds all of his payments")
eq(ls.data.liveEntries.filter { $0.categoryId == "family" }.count, 2, "as Family & gifts")

// 3n. Zero-review (default): nothing waits; unsure ones are guesses you may check, and fixing one teaches Kosh.
let zs = KoshStore()
zs.data = AppData.empty()
let zd = Parser.iso(Date())
_ = zs.addBankMessage("Rs 899 debited via UPI on \(zd) to MDK ENTERPRISES. RRN 720000000001")
_ = zs.addBankMessage("Rs 1500 debited via UPI on \(zd) to KUNAL MEHTA. RRN 720000000002")
_ = zs.addBankMessage("Your A/C XXXXX000000 Credited INR 47000.00 on \(zd) -Deposit of Cash at S5NM000000000 CDM. Avl Bal INR 47279.17-SBI")
_ = zs.addBankMessage("Rs 250 spent on your card at SWIGGY on \(zd) UPI Ref No 720000000003")
eq(zs.liveInbox.count, 0, "zero-review: nothing waits")
eq(zs.data.liveEntries.count, 4, "all four added")
eq(zs.guesses.count, 3, "three guesses to optionally check (MDK, Kunal, big cash)")
let zms = zs.data.monthSummary(monthKey(Date()))
eq(zms.income, 0, "big cash deposit guessed as Moved, not income")
eq(zms.spent, 2649, "unknowns guessed as spending")
let mdkE = zs.guesses.first { $0.note == "Mdk Enterprises" }!
zs.correct(mdkE, kind: "expense", categoryId: "groceries")
eq(zs.guesses.count, 2, "corrected one is no longer a guess")
let mdkNext = zs.addBankMessage("Rs 300 debited via UPI on \(zd) to MDK ENTERPRISES. RRN 720000000004")!
eq(zs.data.liveEntries.first { $0.id == mdkNext.autoAdded }?.categoryId, "groceries", "next time sorted right")
eq(zs.data.liveEntries.first { $0.id == mdkNext.autoAdded }?.guess, nil, "and not a guess")
let kunal = zs.guesses.first { $0.note == "Kunal Mehta" }!
eq(kunal.askWho, true, "Kunal guess offers Who is")
zs.setRole("Kunal Mehta", role: "family")
eq(zs.data.liveEntries.first { $0.id == kunal.id }?.categoryId, "family", "answer re-sorts the guess")
eq(zs.guesses.count, 1, "only the cash deposit left to check")
let cashE = zs.guesses[0]
let zpot = zs.createPot("Dad's money")
zs.correct(cashE, kind: "held", potId: zpot.id, learn: false)
eq(zs.potLeft(zpot.id), 47000, "cash deposit moved into Dad's money")
eq(zs.guesses.isEmpty, true, "all checked")

// 3o. Switching to zero-review turns anything waiting into guesses.
ls.data.settings.zeroReview = true
_ = ls.addBankMessage("Rs 900 debited via UPI on \(ld) to NEHA RAO. RRN 730000000001")
ls.data.inbox.append(InboxItem(id: "old1", type: "expense", amount: 640, merchant: "Arjun Das", date: ld, categoryId: "other", cardId: nil, received: nil))
ls.flushInbox()
eq(ls.liveInbox.count, 0, "nothing left waiting"); eq(ls.guesses.contains { $0.note == "Arjun Das" }, true, "old one is now a guess")

// 3p. Salary credit labelled "Money received" stays salary, even when "Other" was saved on it.
let svs = KoshStore()
svs.data = AppData.empty()
svs.data.settings.salary = 25600
let salIt = svs.addBankMessage("Your A/C XX0000 Credited INR 25600.00 on \(Parser.iso(Date())). RRN 740000000001")!
eq(svs.data.liveEntries.first { $0.id == salIt.autoAdded }?.incomeSource, "salary", "new salary credit filed as Salary")
var oldSal = Entry(id: "os", type: "income", amount: 25600, date: Parser.iso(Date()), note: "Money received", source: "bank sms"); oldSal.incomeSource = "other"
svs.data.entries = [oldSal]
eq(svs.data.monthSummary(monthKey(Date())).income, 25600, "saved Other near salary still counts once as salary")

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
