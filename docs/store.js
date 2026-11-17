// State, persistence, merging (for sync) and money calculations. No DOM here.
import { DEFAULT_KEYWORDS, isoDate } from './parser.js';

export const KEY = 'paisa.v1';
export const COLLECTIONS = ['categories', 'entries', 'investments', 'goals', 'debts'];
export const CARDS = '__cards';

export const DEFAULT_CATEGORIES = [
  ['rent', 'Rent', '🏠'], ['bills', 'Electricity & Bills', '💡'], ['groceries', 'Groceries', '🛒'], ['food', 'Food & Dining', '🍽️'],
  ['transport', 'Transport', '🛺'], ['phone', 'Phone & Internet', '📱'], ['shopping', 'Shopping', '🛍️'], ['health', 'Health', '💊'],
  ['entertainment', 'Entertainment', '🎬'], ['debt', 'Card/Loan Payments', '💳'], ['other', 'Other', '📦'],
];

export function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 8); }

export function emptyState() {
  return {
    settings: { salary: null, rule: '', updatedAt: 0 },
    categories: DEFAULT_CATEGORIES.map(([id, name, icon], i) => ({ id, name, icon, budget: 0, keywords: DEFAULT_KEYWORDS[id] || [], order: i, updatedAt: 0 })),
    entries: [], investments: [], goals: [], debts: [],
  };
}

export function load(storage = globalThis.localStorage) {
  try {
    const raw = storage.getItem(KEY);
    if (!raw) return null;
    const s = JSON.parse(raw);
    const base = emptyState();
    for (const c of COLLECTIONS) if (!Array.isArray(s[c])) s[c] = base[c];
    s.settings = { ...base.settings, ...(s.settings || {}) };
    return s;
  } catch { return null; }
}
export function persist(state, storage = globalThis.localStorage) { storage.setItem(KEY, JSON.stringify(state)); }

// Merge two copies item-by-item: the newest edit of each item wins. Deleted items stay as tombstones.
export function merge(a, b) {
  if (!a) return b; if (!b) return a;
  const out = { settings: (b.settings?.updatedAt || 0) > (a.settings?.updatedAt || 0) ? b.settings : a.settings };
  for (const c of COLLECTIONS) {
    const m = new Map();
    for (const it of [...(a[c] || []), ...(b[c] || [])]) {
      const cur = m.get(it.id);
      if (!cur || (it.updatedAt || 0) > (cur.updatedAt || 0)) m.set(it.id, it);
    }
    out[c] = [...m.values()];
  }
  return out;
}

export const live = (arr) => arr.filter((x) => !x.deleted);
export const monthKey = (d) => (typeof d === 'string' ? d.slice(0, 7) : isoDate(d).slice(0, 7));
export const inr = (n, opts = {}) => {
  if (n === null || n === undefined || isNaN(n)) return '—';
  const v = Math.round(n);
  return (v < 0 ? '−' : '') + '₹' + Math.abs(v).toLocaleString('en-IN', opts);
};
const sum = (arr, f) => arr.reduce((t, x) => t + (Number(f(x)) || 0), 0);

export function monthSummary(state, mk) {
  const es = live(state.entries).filter((e) => monthKey(e.date) === mk);
  const incomeEntries = sum(es.filter((e) => e.type === 'income'), (e) => e.amount);
  const salary = Number(state.settings.salary) || 0;
  const income = incomeEntries > 0 ? incomeEntries : salary;
  const spent = sum(es.filter((e) => e.type === 'expense'), (e) => e.amount);
  const saved = sum(es.filter((e) => e.type === 'save'), (e) => e.amount);
  const invested = sum(es.filter((e) => e.type === 'invest'), (e) => e.amount);
  const byCat = {};
  for (const e of es.filter((x) => x.type === 'expense')) byCat[e.categoryId || 'other'] = (byCat[e.categoryId || 'other'] || 0) + Number(e.amount);
  return { entries: es, income, incomeKnown: income > 0, incomeFromEntries: incomeEntries > 0, spent, saved, invested, left: income - spent - saved - invested, byCat };
}

export function cardUsage(state) {
  const cards = live(state.debts).filter((d) => d.kind === 'card');
  const balance = sum(cards, (d) => d.balance);
  const limit = sum(cards, (d) => d.limit);
  return { cards, balance, limit, pct: limit > 0 ? (balance / limit) * 100 : 0 };
}

export function monthsUntil(deadline, today = new Date()) {
  if (!deadline) return 12;
  const [y, m] = deadline.split('-').map(Number);
  const n = (y - today.getFullYear()) * 12 + (m - 1 - today.getMonth()) + 1;
  return Math.max(1, n);
}

export function goalStatus(goal, state, today = new Date()) {
  const mk = monthKey(today);
  const monthEntries = live(state.entries).filter((e) => monthKey(e.date) === mk);
  let target, current, start, remaining, progress, thisMonth;
  if (goal.kind === 'save') {
    target = Number(goal.target) || 0; current = Number(goal.saved) || 0;
    remaining = Math.max(0, target - current); progress = target > 0 ? current / target : 0;
    thisMonth = sum(monthEntries.filter((e) => e.type === 'save' && e.goalId === goal.id), (e) => e.amount);
  } else {
    let debtIds;
    if (goal.debtId === CARDS || goal.kind === 'cardUsage') {
      const cu = cardUsage(state); current = cu.balance; debtIds = cu.cards.map((d) => d.id);
      target = goal.kind === 'cardUsage' ? Math.round((cu.limit * (Number(goal.targetPct) || 0)) / 100) : 0;
    } else {
      const d = live(state.debts).find((x) => x.id === goal.debtId);
      current = d ? Number(d.balance) || 0 : 0; debtIds = d ? [d.id] : []; target = 0;
    }
    start = Math.max(Number(goal.startBalance) || current, current);
    remaining = Math.max(0, current - target);
    progress = start > target ? Math.min(1, Math.max(0, (start - current) / (start - target))) : (remaining === 0 ? 1 : 0);
    thisMonth = sum(monthEntries.filter((e) => e.type === 'expense' && debtIds.includes(e.debtId)), (e) => e.amount);
  }
  const months = monthsUntil(goal.deadline, today);
  // Monthly need is based on what was still left at the start of this month.
  const perMonth = remaining === 0 ? 0 : Math.ceil((remaining + thisMonth) / months);
  return { target, current, remaining, progress, months, perMonth, thisMonth, done: remaining === 0 };
}

export function buildPlan(state, today = new Date()) {
  const mk = monthKey(today);
  const ms = monthSummary(state, mk);
  const cats = live(state.categories).filter((c) => c.id !== 'debt');
  const budgeted = sum(cats, (c) => c.budget);
  const sips = sum(live(state.investments), (i) => i.monthly);
  const emis = sum(live(state.debts).filter((d) => d.kind !== 'card'), (d) => d.emi);
  const free = ms.income - budgeted - sips - emis;
  let pool = free;
  // Several goals can target the same debt (e.g. cards under 30%, then under 10%).
  // Money given to an earlier one already counts toward the later one.
  const givenTo = {};
  const goals = live(state.goals).sort((a, b) => (a.priority || 99) - (b.priority || 99)).map((g) => {
    const st = goalStatus(g, state, today);
    const key = g.kind === 'save' ? 'goal:' + g.id : (g.kind === 'cardUsage' || g.debtId === CARDS ? CARDS : g.debtId);
    const want = st.done ? 0 : Math.max(0, st.perMonth - st.thisMonth - (givenTo[key] || 0));
    const give = Math.max(0, Math.min(want, pool));
    pool -= give;
    givenTo[key] = (givenTo[key] || 0) + want;
    return { goal: g, st, want, give };
  });
  return { income: ms.income, incomeKnown: ms.incomeKnown, budgeted, sips, emis, free, goals, leftover: pool };
}
