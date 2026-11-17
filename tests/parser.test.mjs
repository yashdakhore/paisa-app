import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseEntry, wordsToDigits, parseMany } from '../docs/parser.js';

const now = new Date(2026, 10, 18); // Wed 18 Nov 2026
const ctx = {
  categories: ['rent', 'bills', 'groceries', 'food', 'transport', 'phone', 'shopping', 'health', 'entertainment', 'debt', 'other']
    .map((id) => ({ id, name: id })),
  debts: [{ id: 'sbi', name: 'SBI Card', keywords: ['sbi'] }, { id: 'mp', name: 'mPokket loan', keywords: ['mpokket'] }],
  goals: [{ id: 'ef', name: 'Emergency fund' }],
  investments: [{ id: 'sip1', name: 'Monthly SIP', type: 'SIP' }],
};
const p = (s) => parseEntry(s, ctx, now);

test('basic phrases', () => {
  let r = p('spent 250 on groceries');
  assert.equal(r.amount, 250); assert.equal(r.categoryId, 'groceries'); assert.equal(r.date, '2026-11-18'); assert.equal(r.type, 'expense');
  r = p('paid 9000 rent');
  assert.equal(r.amount, 9000); assert.equal(r.categoryId, 'rent'); assert.equal(r.note, 'Rent');
  r = p('Paid ₹9,000 rent');
  assert.equal(r.amount, 9000);
});

test('dates', () => {
  assert.equal(p('120 auto yesterday').date, '2026-11-17');
  assert.equal(p('spent 300 on swiggy day before yesterday').date, '2026-11-16');
  assert.equal(p('400 dinner on monday').date, '2026-11-16');
  assert.equal(p('500 medicine on 5th november').date, '2026-11-05');
  assert.equal(p('500 medicine on the 2nd').date, '2026-11-02');
  assert.equal(p('rent 9000 on 1st').date, '2026-11-01');
  assert.equal(p('600 shoes 3 days ago').date, '2026-11-15');
  assert.equal(p('900 flight on 20 dec').date, '2025-12-20');
  const r = p('500 medicine on 5th november'); assert.equal(r.amount, 500); assert.equal(r.categoryId, 'health');
});

test('amount formats', () => {
  assert.equal(p('2k on shopping').amount, 2000);
  assert.equal(p('1.5k petrol').amount, 1500);
  assert.equal(p('rs 99 jio recharge').amount, 99);
  assert.equal(p('two hundred fifty on vegetables').amount, 250);
  assert.equal(p('five thousand to sbi card').amount, 5000);
  assert.equal(p('spent a hundred on chai').amount, 100);
  assert.equal(p('spent 250 rupees on milk').amount, 250);
});

test('debt, income, invest, save', () => {
  let r = p('paid 5000 to SBI card');
  assert.equal(r.categoryId, 'debt'); assert.equal(r.debtId, 'sbi');
  r = p('repaid 4000 mpokket');
  assert.equal(r.categoryId, 'debt'); assert.equal(r.debtId, 'mp');
  r = p('got salary 30000');
  assert.equal(r.type, 'income'); assert.equal(r.amount, 30000);
  r = p('invested 2000 in SIP');
  assert.equal(r.type, 'invest'); assert.equal(r.investmentId, 'sip1');
  r = p('saved 3000 for emergency fund');
  assert.equal(r.type, 'save'); assert.equal(r.goalId, 'ef');
});

test('unknown category falls back to other', () => {
  const r = p('spent 70 on stationery');
  assert.equal(r.categoryId, 'other'); assert.equal(r.note, 'Stationery'); assert.equal(r.sure.category, false);
});

test('wordsToDigits', () => {
  assert.equal(wordsToDigits('two hundred and fifty rupees'), '250 rupees');
  assert.equal(wordsToDigits('one lakh twenty thousand'), '120000');
});

test('hinglish', () => {
  let r = p('kiraya 9000 diya'); assert.equal(r.categoryId, 'rent'); assert.equal(r.amount, 9000);
  assert.equal(p('bijli ka bill 750').categoryId, 'bills');
  r = p('sabzi 120 kal'); assert.equal(r.categoryId, 'groceries'); assert.equal(r.date, '2026-11-17');
  r = p('dawai 300 parso'); assert.equal(r.categoryId, 'health'); assert.equal(r.date, '2026-11-16');
  r = p('doodh 60 rupaye aaj'); assert.equal(r.amount, 60); assert.equal(r.categoryId, 'groceries');
  assert.equal(p('5 sau ka khana').amount, 500);
  assert.equal(p('2 hazaar ke kapde').amount, 2000); assert.equal(p('2 hazaar ke kapde').categoryId, 'shopping');
});

test('several items', () => {
  const pm = (s) => parseMany(s, ctx, now);
  let m = pm('250 groceries and 120 auto');
  assert.equal(m.length, 2); assert.equal(m[0].categoryId, 'groceries'); assert.equal(m[1].amount, 120); assert.equal(m[1].categoryId, 'transport');
  m = pm('spent 250 on groceries, 120 on auto and 60 chai yesterday');
  assert.equal(m.length, 3); assert.deepEqual(m.map((x) => x.date), ['2026-11-17', '2026-11-17', '2026-11-17']); assert.equal(m[2].categoryId, 'food');
  m = pm('paid 9,000 rent aur 750 bijli'); assert.equal(m.length, 2); assert.equal(m[0].amount, 9000); assert.equal(m[1].categoryId, 'bills');
  assert.equal(pm('two hundred and fifty on vegetables').length, 1);
  assert.equal(pm('500 medicine on 5th november').length, 1);
  assert.equal(pm('bread and butter 80').length, 1);
});
