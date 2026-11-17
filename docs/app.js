import { parseEntry, isoDate } from './parser.js';
import {
  load, persist, emptyState, merge, uid, live, monthKey, inr, monthSummary, cardUsage, goalStatus, buildPlan, CARDS,
} from './store.js';
import * as sync from './sync.js';

// ---------- state ----------
let state = load();
let tab = 'home';
let planSeg = 'plan';
let viewMonth = monthKey(new Date());
const $ = (s, el = document) => el.querySelector(s);
const view = $('#view');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pct = (x) => Math.round(Math.max(0, Math.min(1, x)) * 100);
const catById = (id) => state.categories.find((c) => c.id === id);
const TYPES = { expense: 'Expense', income: 'Income', save: 'Saving to a goal', invest: 'Investment' };

async function init() {
  if (!state) {
    state = emptyState();
    try {
      const r = await fetch('seed.json', { cache: 'no-store' });
      if (r.ok) state = merge(state, await r.json());
    } catch { /* no seed on hosted copies */ }
    persist(state);
  }
  bindChrome();
  render();
  if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('sw.js').catch(() => {});
  doSync();
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') doSync(); });
}

function commit(mutate) {
  mutate(state);
  persist(state);
  render();
  clearTimeout(commit.t);
  commit.t = setTimeout(doSync, 1500);
}
function upsert(coll, item) {
  item.updatedAt = Date.now();
  const i = state[coll].findIndex((x) => x.id === item.id);
  if (i >= 0) state[coll][i] = item; else state[coll].push(item);
}
function tombstone(coll, id) {
  const it = state[coll].find((x) => x.id === id);
  if (it) { it.deleted = true; it.updatedAt = Date.now(); }
}

async function doSync() {
  const dot = $('#syncDot');
  if (!sync.isConfigured()) { dot.className = 'sync-dot'; return; }
  try {
    if (!(await sync.currentUser())) { dot.className = 'sync-dot err'; dot.title = 'Sync: not signed in'; return; }
    dot.className = 'sync-dot busy';
    state = await sync.syncNow(state);
    persist(state);
    dot.className = 'sync-dot ok'; dot.title = 'Synced ' + new Date().toLocaleTimeString('en-IN');
    if ($('#sheet').classList.contains('hidden')) render();
  } catch (e) {
    dot.className = 'sync-dot err'; dot.title = 'Sync error: ' + e.message;
  }
}

function toast(msg) {
  const t = $('#toast'); t.textContent = msg; t.classList.remove('hidden');
  clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.add('hidden'), 2600);
}

// ---------- chrome ----------
function bindChrome() {
  document.querySelectorAll('.tabs [data-tab]').forEach((b) => b.addEventListener('click', () => { tab = b.dataset.tab; render(); window.scrollTo(0, 0); }));
  $('#micFab').addEventListener('click', () => openEntry(null, { listen: true }));
  $('#prevMonth').addEventListener('click', () => { viewMonth = shiftMonth(viewMonth, -1); render(); });
  $('#nextMonth').addEventListener('click', () => { viewMonth = shiftMonth(viewMonth, 1); render(); });
  $('.sheet-backdrop').addEventListener('click', closeSheet);
}
function shiftMonth(mk, n) { const [y, m] = mk.split('-').map(Number); return monthKey(new Date(y, m - 1 + n, 1)); }
function monthName(mk) { const [y, m] = mk.split('-').map(Number); return new Date(y, m - 1, 1).toLocaleDateString('en-IN', { month: 'long', year: 'numeric' }); }

function render() {
  document.querySelectorAll('.tabs [data-tab]').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
  const showMonth = tab === 'home' || tab === 'budget';
  $('#monthLabel').textContent = showMonth ? monthName(viewMonth) : { plan: 'Plan', more: 'More' }[tab];
  $('#prevMonth').style.visibility = $('#nextMonth').style.visibility = showMonth ? 'visible' : 'hidden';
  view.innerHTML = { home: homeView, budget: budgetView, plan: planView, more: moreView }[tab]();
  wire(view);
  if (tab === 'more') {
    fillSyncBox();
    $('#restoreFile').addEventListener('change', restore);
  }
}

// Delegate clicks: elements with data-act="name" and optional data-id.
const actions = {};
function wire(root) {
  root.querySelectorAll('[data-act]').forEach((el) => el.addEventListener('click', (ev) => {
    ev.stopPropagation(); ev.preventDefault();
    actions[el.dataset.act]?.(el.dataset.id, el);
  }));
}

// ---------- views ----------
function bar(fraction, cls = '', marks = []) {
  return `<div class="bar"><i class="${cls}" style="width:${pct(fraction)}%"></i>${marks.map((m) => `<span class="mark" style="left:${m}%"></span>`).join('')}</div>`;
}

function entryRow(e) {
  const c = catById(e.categoryId);
  const label = e.type === 'expense' ? `${c?.icon || ''} ${esc(c?.name || 'Other')}` : TYPES[e.type];
  const sign = e.type === 'income' ? '+' : '';
  const d = new Date(e.date + 'T00:00').toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
  return `<div class="list-entry" data-act="editEntry" data-id="${e.id}">
    <div><div>${esc(e.note || label)}</div><div class="muted">${d} · ${label}</div></div>
    <div class="amt ${e.type === 'income' ? 'good' : ''}">${sign}${inr(e.amount)}</div></div>`;
}

function cardUsageCard() {
  const cu = cardUsage(state);
  if (!cu.cards.length) return '';
  const cls = cu.pct > 30 ? 'bad' : cu.pct > 10 ? 'warn' : 'good';
  return `<div class="card" data-act="goPlan" data-id="debts">
    <h2>Credit card usage</h2>
    <div class="row"><b class="${cls}" style="font-size:22px">${Math.round(cu.pct)}% used</b><span class="muted">${inr(cu.balance)} of ${inr(cu.limit)}</span></div>
    ${bar(cu.pct / 100, cls, [10, 30])}
    <div class="muted">Goal: under 30% (${inr(cu.limit * 0.3)}), then under 10% (${inr(cu.limit * 0.1)}). Marks show 10% and 30%.</div>
  </div>`;
}

function homeView() {
  const ms = monthSummary(state, viewMonth);
  const rule = state.settings.rule ? `<div class="banner">📌 ${esc(state.settings.rule)}</div>` : '';
  const leftCls = ms.left < 0 ? 'bad' : 'good';
  const cats = live(state.categories).sort((a, b) => (ms.byCat[b.id] || 0) - (ms.byCat[a.id] || 0)).filter((c) => (ms.byCat[c.id] || 0) > 0 || c.budget > 0);
  const recent = [...ms.entries].sort((a, b) => (b.date + b.createdAt).localeCompare(a.date + a.createdAt)).slice(0, 8);
  const plan = buildPlan(state);
  const next = plan.goals.filter((g) => !g.st.done).slice(0, 3);
  const due = live(state.debts).filter((d) => d.dueDay && d.balance > 0);
  const isNew = !live(state.goals).length && !live(state.debts).length && !live(state.entries).length;
  const welcome = isNew ? `<div class="card"><h2>Welcome to Paisa</h2>
    <p>New device? Load your budget, goals and debts by signing in to sync, or by restoring a backup or starting-plan file.</p>
    <button class="btn primary block" data-act="goMore">Set up sync or restore</button></div>` : '';
  return `${rule}${welcome}
  <div class="card">
    <h2>Left this month</h2>
    ${ms.incomeKnown ? `<div class="big ${leftCls}">${inr(ms.left)}</div>` : `<div class="big">—</div><div class="muted"><a href="#" data-act="goMore">Add your take-home salary</a> to see what's left.</div>`}
    <div class="stats">
      <div class="stat"><b>${inr(ms.income)}</b><span>Income${ms.incomeFromEntries ? '' : ' (salary)'}</span></div>
      <div class="stat"><b>${inr(ms.spent)}</b><span>Spent</span></div>
      <div class="stat"><b>${inr(ms.saved + ms.invested)}</b><span>Saved + invested</span></div>
    </div>
  </div>
  ${cardUsageCard()}
  ${due.length ? `<div class="card"><h2>Pay on time</h2>${due.map((d) => `<div class="row"><span>${esc(d.name)}</span><span class="muted">due on the ${d.dueDay}${ordinal(d.dueDay)}</span></div>`).join('')}</div>` : ''}
  <div class="card">
    <h2>Where the money went</h2>
    ${cats.length ? cats.map((c) => {
      const s = ms.byCat[c.id] || 0; const over = c.budget > 0 && s > c.budget;
      return `<div class="item" data-act="editCat" data-id="${c.id}"><div class="row"><span>${c.icon || ''} ${esc(c.name)}</span><span>${inr(s)}${c.budget ? ` <span class="muted">/ ${inr(c.budget)}</span>` : ''}</span></div>
        ${c.budget ? bar(s / c.budget, over ? 'bad' : s / c.budget > 0.85 ? 'warn' : '') : ''}</div>`;
    }).join('') : '<div class="muted">Nothing yet. Tap 🎤 and say "spent 250 on groceries".</div>'}
  </div>
  ${next.length ? `<div class="card" data-act="goPlan" data-id="plan"><h2>Save next</h2>${next.map((g) => `<div class="row"><span>${esc(g.goal.name)}</span><b>${inr(g.want)}</b></div>`).join('')}<div class="muted" style="margin-top:6px">Still needed this month. Tap for the full plan.</div></div>` : ''}
  <div class="card"><h2>Recent</h2>${recent.length ? recent.map(entryRow).join('') : '<div class="muted">No entries this month.</div>'}
    <div class="btns"><button class="btn" data-act="addTyped">⌨️ Type an entry</button></div></div>`;
}
const ordinal = (n) => (n % 10 === 1 && n !== 11 ? 'st' : n % 10 === 2 && n !== 12 ? 'nd' : n % 10 === 3 && n !== 13 ? 'rd' : 'th');

function budgetView() {
  const ms = monthSummary(state, viewMonth);
  const cats = live(state.categories).sort((a, b) => (a.order ?? 99) - (b.order ?? 99));
  const totalBudget = cats.reduce((t, c) => t + (Number(c.budget) || 0), 0);
  const all = [...ms.entries].sort((a, b) => b.date.localeCompare(a.date));
  return `<div class="card"><h2>Monthly budget</h2>
    <div class="row"><span>Spent</span><b>${inr(ms.spent)} <span class="muted">of ${inr(totalBudget)}</span></b></div>
    ${bar(totalBudget ? ms.spent / totalBudget : 0, ms.spent > totalBudget ? 'bad' : '')}
    <div class="muted">Tap a category to change its budget, name or voice keywords.</div></div>
  <div class="card">${cats.map((c) => {
    const s = ms.byCat[c.id] || 0; const left = (c.budget || 0) - s;
    return `<div class="item" data-act="editCat" data-id="${c.id}">
      <div class="row"><span>${c.icon || ''} ${esc(c.name)}</span><span>${inr(s)} <span class="muted">/ ${c.budget ? inr(c.budget) : 'no budget'}</span></span></div>
      ${c.budget ? bar(s / c.budget, s > c.budget ? 'bad' : s / c.budget > 0.85 ? 'warn' : '') + `<div class="muted">${left >= 0 ? inr(left) + ' left' : inr(-left) + ' over'}</div>` : ''}</div>`;
  }).join('')}
  <div class="btns"><button class="btn" data-act="addCat">＋ Add category</button></div></div>
  <div class="card"><h2>All entries · ${monthName(viewMonth)}</h2>${all.length ? all.map(entryRow).join('') : '<div class="muted">No entries.</div>'}</div>`;
}

function planView() {
  const segs = [['plan', 'This month'], ['goals', 'Goals'], ['debts', 'Debts'], ['invest', 'Investments']];
  const head = `<div class="seg">${segs.map(([k, l]) => `<button class="${planSeg === k ? 'active' : ''}" data-act="seg" data-id="${k}">${l}</button>`).join('')}</div>`;
  return head + { plan: planTab, goals: goalsTab, debts: debtsTab, invest: investTab }[planSeg]();
}

function planTab() {
  const p = buildPlan(state);
  if (!p.incomeKnown) {
    return `<div class="card"><h2>Monthly plan</h2><p>Add your monthly take-home salary to see how much you can put toward each goal.</p>
      <button class="btn primary block" data-act="editSalary">Add salary</button></div>${goalsNeeded(p)}`;
  }
  return `<div class="card"><h2>Monthly plan</h2>
    <table class="plan">
      <tr><td>Take-home income</td><td>${inr(p.income)}</td></tr>
      <tr><td>− Budgeted spending</td><td>${inr(p.budgeted)}</td></tr>
      <tr><td>− SIPs / investments</td><td>${inr(p.sips)}</td></tr>
      ${p.emis ? `<tr><td>− EMIs</td><td>${inr(p.emis)}</td></tr>` : ''}
      <tr class="total"><td>Free for goals</td><td class="${p.free < 0 ? 'bad' : 'good'}">${inr(p.free)}</td></tr>
    </table></div>
  <div class="card"><h2>Put this toward your goals this month</h2>
    ${p.goals.filter((g) => !g.st.done).map((g, i) => `<div class="item" data-act="editGoal" data-id="${g.goal.id}">
      <div class="row"><span>${i + 1}. ${esc(g.goal.name)}</span><b>${inr(g.give)}</b></div>
      <div class="muted">Needs ${inr(g.st.perMonth)}/month for ${g.st.months} month${g.st.months > 1 ? 's' : ''}${g.st.thisMonth ? ` · ${inr(g.st.thisMonth)} done this month` : ''}${g.give < g.want ? ` · <span class="warn">short by ${inr(g.want - g.give)}</span>` : ''}</div></div>`).join('') || '<div class="muted">All goals done 🎉</div>'}
    ${p.leftover > 0 ? `<div class="banner" style="margin:10px 0 0">After goals, ${inr(p.leftover)} is spare. Put it toward your first unfinished goal to finish sooner, or increase your SIP.</div>` : ''}
    ${p.free < 0 ? `<div class="banner" style="margin:10px 0 0">Your budgets are more than your income. Lower a category budget on the Budget tab.</div>` : ''}
  </div>`;
}
function goalsNeeded(p) {
  return `<div class="card"><h2>Monthly need per goal</h2>${p.goals.map((g) => `<div class="row"><span>${esc(g.goal.name)}</span><b>${inr(g.st.perMonth)}</b></div>`).join('')}</div>`;
}

function goalsTab() {
  const gs = live(state.goals).sort((a, b) => (a.priority || 99) - (b.priority || 99));
  return gs.map((g) => {
    const st = goalStatus(g, state);
    const line = g.kind === 'save'
      ? `${inr(st.current)} saved of ${inr(st.target)}`
      : `Balance ${inr(st.current)} → target ${inr(st.target)}`;
    return `<div class="card">
      <div class="row"><b>${esc(g.name)}</b><span class="pill">${st.done ? 'Done ✓' : pct(st.progress) + '%'}</span></div>
      ${bar(st.progress, st.done ? 'good' : '')}
      <div class="muted">${line}${g.deadline ? ` · by ${new Date(g.deadline + '-01T00:00').toLocaleDateString('en-IN', { month: 'short', year: 'numeric' })}` : ''}</div>
      ${st.done ? '' : `<div style="margin-top:6px">Needs <b>${inr(st.perMonth)}/month</b> for ${st.months} month${st.months > 1 ? 's' : ''}</div>`}
      <div class="btns">${g.kind === 'save' ? `<button class="btn primary" data-act="addToGoal" data-id="${g.id}">＋ Add money</button>` : `<button class="btn primary" data-act="payGoalDebt" data-id="${g.id}">Record payment</button>`}
      <button class="btn" data-act="editGoal" data-id="${g.id}">Edit</button></div></div>`;
  }).join('') + `<button class="btn block" data-act="addGoal">＋ New goal</button>`;
}

function debtsTab() {
  const ds = live(state.debts);
  const rule = state.settings.rule ? `<div class="banner">📌 ${esc(state.settings.rule)}</div>` : '';
  return rule + cardUsageCard() + ds.map((d) => {
    const usage = d.kind === 'card' && d.limit ? d.balance / d.limit : null;
    return `<div class="card">
      <div class="row"><b>${esc(d.name)}</b><span class="pill">${{ card: 'Credit card', loan: 'Loan', emi: 'EMI' }[d.kind] || d.kind}</span></div>
      <div class="row"><span class="muted">Balance</span><b>${inr(d.balance)}</b></div>
      ${usage !== null ? `<div class="row"><span class="muted">Limit</span><span>${inr(d.limit)} · ${Math.round(usage * 100)}% used</span></div>${bar(usage, usage > 0.3 ? 'bad' : usage > 0.1 ? 'warn' : 'good', [10, 30])}` : ''}
      ${d.emi ? `<div class="row"><span class="muted">EMI</span><span>${inr(d.emi)}/month</span></div>` : ''}
      ${d.rate ? `<div class="row"><span class="muted">Interest</span><span>${d.rate}% a year</span></div>` : ''}
      ${d.dueDay ? `<div class="row"><span class="muted">Due</span><span>${d.dueDay}${ordinal(d.dueDay)} of each month</span></div>` : ''}
      ${d.note ? `<div class="muted">${esc(d.note)}</div>` : ''}
      <div class="btns"><button class="btn primary" data-act="payDebt" data-id="${d.id}">Record payment</button><button class="btn" data-act="editDebt" data-id="${d.id}">Edit</button></div></div>`;
  }).join('') + `<button class="btn block" data-act="addDebt">＋ Add debt / EMI / card</button>`;
}

function investTab() {
  const is = live(state.investments);
  const tot = is.reduce((t, i) => ({ m: t.m + (+i.monthly || 0), inv: t.inv + (+i.invested || 0), v: t.v + (+i.value || 0) }), { m: 0, inv: 0, v: 0 });
  const gain = tot.v - tot.inv;
  return `<div class="card"><h2>All investments</h2>
    <div class="stats"><div class="stat"><b>${inr(tot.v)}</b><span>Current value</span></div><div class="stat"><b>${inr(tot.inv)}</b><span>Invested</span></div>
    <div class="stat"><b class="${gain >= 0 ? 'good' : 'bad'}">${inr(gain)}</b><span>Gain</span></div></div>
    <div class="muted" style="margin-top:8px">${inr(tot.m)} a month going in</div></div>` +
    is.map((i) => {
      const g = (+i.value || 0) - (+i.invested || 0);
      return `<div class="card"><div class="row"><b>${esc(i.name)}</b><span class="pill">${esc(i.type)}</span></div>
        <div class="row"><span class="muted">Monthly</span><span>${i.monthly ? inr(i.monthly) : '—'}</span></div>
        <div class="row"><span class="muted">Invested so far</span><span>${inr(i.invested || 0)}</span></div>
        <div class="row"><span class="muted">Current value</span><b>${inr(i.value || 0)}</b></div>
        ${i.invested ? `<div class="row"><span class="muted">Gain</span><span class="${g >= 0 ? 'good' : 'bad'}">${inr(g)} (${((g / i.invested) * 100).toFixed(1)}%)</span></div>` : ''}
        ${i.maturity ? `<div class="row"><span class="muted">Matures</span><span>${esc(i.maturity)}</span></div>` : ''}
        ${i.note ? `<div class="muted">${esc(i.note)}</div>` : ''}
        <div class="btns"><button class="btn primary" data-act="addToInv" data-id="${i.id}">＋ Add money</button><button class="btn" data-act="editInv" data-id="${i.id}">Edit / update value</button></div></div>`;
    }).join('') + `<button class="btn block" data-act="addInv">＋ Add investment</button>`;
}

function moreView() {
  const cfg = sync.getConfig();
  return `<div class="card"><h2>Income</h2>
    <div class="row"><span>Monthly take-home salary</span><b>${state.settings.salary ? inr(state.settings.salary) : 'not set'}</b></div>
    <div class="muted">If you log income entries (say "got salary 30000"), those are used for that month instead.</div>
    <div class="btns"><button class="btn" data-act="editSalary">Edit income & reminder</button></div></div>
  <div class="card"><h2>Sync between devices</h2><div id="syncBox" class="muted">Checking…</div></div>
  <div class="card"><h2>Backup</h2>
    <div class="muted">Save a copy of everything, or move data to another device without sync.</div>
    <div class="btns"><button class="btn" data-act="exportJson">⬇️ Backup file</button><button class="btn" data-act="exportCsv">⬇️ Entries as CSV</button></div>
    <div class="btns"><label class="btn">⬆️ Restore from backup<input type="file" id="restoreFile" accept="application/json,.json" hidden></label></div></div>
  <div class="card"><h2>Voice tips</h2><div class="muted">Say things like:<br>“spent 250 on groceries” · “paid 9000 rent” · “120 auto yesterday” · “paid 5000 to SBI card” · “saved 2000 for emergency fund” · “invested 1000 in SIP” · “got salary 30000”.<br><br>On iPhone, if the 🎤 button doesn't listen, tap the text box and use the microphone key on the keyboard.</div></div>
  <div class="card"><h2>About</h2><div class="muted">Paisa keeps your data on this device${cfg.url ? ' and in your own Supabase database' : ''}. It never asks for card numbers, account numbers or PAN.</div>
  <div class="btns"><button class="btn danger" data-act="resetAll">Erase data on this device</button></div></div>`;
}

async function fillSyncBox() {
  const box = $('#syncBox'); if (!box) return;
  if (!sync.isConfigured()) {
    box.innerHTML = `Not set up. Data stays on this device only.<div class="btns"><button class="btn primary" data-act="setupSync">Set up sync</button></div>`;
  } else {
    let user = null; try { user = await sync.currentUser(); } catch (e) { box.textContent = 'Error: ' + e.message; return; }
    box.innerHTML = user
      ? `Signed in as <b>${esc(user.email)}</b>. Changes sync automatically.<div class="btns"><button class="btn primary" data-act="syncNow">Sync now</button><button class="btn" data-act="signOut">Sign out</button></div>`
      : `Connected to your database, but not signed in.<div class="btns"><button class="btn primary" data-act="signIn">Sign in / create login</button><button class="btn" data-act="setupSync">Change settings</button></div>`;
  }
  wire(box);
}

// ---------- sheet / forms ----------
function openSheet(html) { $('#sheetBody').innerHTML = html; $('#sheet').classList.remove('hidden'); }
function closeSheet() { stopListening(); $('#sheet').classList.add('hidden'); $('#sheetBody').innerHTML = ''; }

/** fields: [{k, label, type:'text'|'number'|'date'|'month'|'select'|'check'|'textarea', options:[[v,l]], hint}] */
function openForm({ title, fields, value = {}, onSave, onDelete, saveLabel = 'Save' }) {
  const f = (fd) => {
    const v = value[fd.k] ?? '';
    if (fd.type === 'select') return `<label class="f">${fd.label}<select name="${fd.k}">${fd.options.map(([o, l]) => `<option value="${esc(o)}" ${String(o) === String(v) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></label>`;
    if (fd.type === 'check') return `<label class="f check"><input type="checkbox" name="${fd.k}" ${v ? 'checked' : ''}> ${fd.label}</label>`;
    if (fd.type === 'textarea') return `<label class="f">${fd.label}<textarea name="${fd.k}" rows="2">${esc(v)}</textarea></label>`;
    return `<label class="f">${fd.label}<input name="${fd.k}" type="${fd.type || 'text'}" ${fd.type === 'number' ? 'inputmode="decimal" step="any"' : ''} value="${esc(v)}" placeholder="${esc(fd.placeholder || '')}"></label>${fd.hint ? `<div class="hint">${fd.hint}</div>` : ''}`;
  };
  openSheet(`<h3>${esc(title)}</h3><form id="gform">${fields.map(f).join('')}
    <div class="btns"><button type="button" class="btn" id="fCancel">Cancel</button><button class="btn primary" type="submit">${saveLabel}</button></div>
    ${onDelete ? '<div class="btns"><button type="button" class="btn danger" id="fDelete">Delete</button></div>' : ''}</form>`);
  $('#fCancel').onclick = closeSheet;
  if (onDelete) $('#fDelete').onclick = () => { if (confirm('Delete this?')) { onDelete(); closeSheet(); } };
  $('#gform').onsubmit = (ev) => {
    ev.preventDefault();
    const out = {};
    for (const fd of fields) {
      const el = ev.target.elements[fd.k];
      out[fd.k] = fd.type === 'check' ? el.checked : fd.type === 'number' ? (el.value === '' ? null : Number(el.value)) : el.value.trim();
    }
    const err = onSave(out);
    if (err) { toast(err); return; }
    closeSheet();
  };
}

// ---------- entry (voice) sheet ----------
const getSR = () => window.SpeechRecognition || window.webkitSpeechRecognition;

// One speech recognizer, reused for every entry (Safari on iPhone misbehaves when a new one is
// created each time). Each listen() call is a session; late events from an older recognizer or
// session are ignored, and a watchdog resets things if the browser never reports the end.
const voice = { rec: null, active: false, h: null, pending: null, watchdog: null };

function recognizer() {
  if (voice.rec) return voice.rec;
  const r = new (getSR())();
  r.lang = 'en-IN'; r.interimResults = true; r.continuous = false; r.maxAlternatives = 1;
  r.onresult = (ev) => {
    if (r !== voice.rec) return;
    voice.h?.result(ev);
    if (ev.results[ev.results.length - 1]?.isFinal) { try { r.stop(); } catch { /* already stopping */ } }
  };
  r.onerror = (ev) => { if (r === voice.rec && ev.error !== 'aborted') voice.h?.error(ev.error); };
  r.onend = () => {
    if (r !== voice.rec) return;
    voice.active = false; clearTimeout(voice.watchdog);
    const h = voice.h; voice.h = null; h?.end();
    if (voice.pending) { const go = voice.pending; voice.pending = null; go(); }
  };
  voice.rec = r;
  return r;
}

function resetVoice() {
  try { voice.rec?.abort(); } catch { /* ignore */ }
  voice.rec = null; voice.active = false; clearTimeout(voice.watchdog);
  const h = voice.h; voice.h = null; h?.end();
}

function startVoice(handlers) {
  const go = () => {
    voice.h = handlers; voice.active = true;
    try { recognizer().start(); } catch {
      // Recognizer stuck in a bad state: throw it away and try once with a fresh one.
      voice.rec = null;
      try { recognizer().start(); } catch { voice.active = false; voice.h = null; handlers.error('start-failed'); handlers.end(); return; }
    }
    clearTimeout(voice.watchdog);
    voice.watchdog = setTimeout(() => { if (voice.active) resetVoice(); }, 15000);
  };
  if (!voice.active) { go(); return; }
  // A previous session is still winding down. Start right away (while still inside the user's tap,
  // which iPhone requires) on a fresh recognizer; the old one is abandoned and its late events ignored.
  const old = voice.rec;
  voice.h = null; voice.rec = null; voice.active = false; clearTimeout(voice.watchdog);
  try { old.abort(); } catch { /* ignore */ }
  try {
    voice.h = handlers; voice.active = true;
    recognizer().start();
    voice.watchdog = setTimeout(() => { if (voice.active) resetVoice(); }, 15000);
  } catch {
    // Browser allows only one at a time: wait for the old one to finish, then start.
    voice.rec = old; voice.active = true; voice.h = null; voice.pending = go;
    setTimeout(() => { if (voice.pending === go) { voice.pending = null; voice.rec = null; voice.active = false; go(); } }, 800);
  }
}

function stopListening() {
  voice.pending = null;
  const h = voice.h; voice.h = null; h?.end();
  if (voice.active) { try { voice.rec.abort(); } catch { resetVoice(); } }
}

function parseCtx() {
  return { categories: live(state.categories), debts: live(state.debts), goals: live(state.goals), investments: live(state.investments) };
}

function openEntry(existing, { listen = false, text = '' } = {}) {
  const SR = getSR();
  const e = existing ? { ...existing } : { type: 'expense', amount: null, categoryId: 'other', date: isoDate(new Date()), note: '', reduceDebt: true };
  const cats = live(state.categories).sort((a, b) => (a.order ?? 99) - (b.order ?? 99));
  const opt = (arr, sel, none) => (none ? `<option value="">${none}</option>` : '') + arr.map((x) => `<option value="${x.id}" ${x.id === sel ? 'selected' : ''}>${esc((x.icon ? x.icon + ' ' : '') + x.name)}</option>`).join('');
  openSheet(`<h3>${existing ? 'Edit entry' : 'New entry'}</h3>
    ${existing ? '' : `<div class="voice-box"><textarea id="vText" rows="2" placeholder='Say or type: "spent 250 on groceries"'>${esc(text)}</textarea>
      ${SR ? '<button class="mic-btn" id="vMic" aria-label="Speak">🎤</button>' : ''}</div>
      <div class="hint" id="vHint">${SR ? 'Tap 🎤 and speak, or type. Check the details below, then Save.' : 'Tap the box and use the 🎤 key on your keyboard to dictate, or type. Check the details below, then Save.'}</div>`}
    <form id="eform">
      <div class="grid2">
        <label class="f">Amount (₹)<input name="amount" type="number" inputmode="decimal" step="any" value="${e.amount ?? ''}" required></label>
        <label class="f">Date<input name="date" type="date" value="${e.date}" required></label>
      </div>
      <label class="f">Type<select name="type">${Object.entries(TYPES).map(([k, l]) => `<option value="${k}" ${k === e.type ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
      <label class="f" data-for="expense">Category<select name="categoryId">${opt(cats, e.categoryId)}</select></label>
      <label class="f" data-for="debt">Which card/loan?<select name="debtId">${opt(live(state.debts), e.debtId, '— not linked —')}</select></label>
      ${existing ? '' : '<label class="f check" data-for="debt"><input type="checkbox" name="reduceDebt" checked> Also lower that balance</label>'}
      <label class="f" data-for="save">Goal<select name="goalId">${opt(live(state.goals).filter((g) => g.kind === 'save'), e.goalId, '— choose —')}</select></label>
      <label class="f" data-for="invest">Investment<select name="investmentId">${opt(live(state.investments), e.investmentId, '— choose —')}</select></label>
      <label class="f">Note<input name="note" value="${esc(e.note)}" placeholder="optional"></label>
      <div class="btns"><button type="button" class="btn" id="eCancel">Cancel</button><button class="btn primary" type="submit">Save</button></div>
      ${existing ? '<div class="btns"><button type="button" class="btn danger" id="eDelete">Delete</button></div>' : ''}
    </form>`);
  const form = $('#eform');
  const showFields = () => {
    const t = form.type.value;
    form.querySelectorAll('[data-for]').forEach((el) => {
      const f = el.dataset.for;
      el.classList.toggle('hidden', !(f === t || (f === 'debt' && t === 'expense' && form.categoryId.value === 'debt')));
    });
  };
  form.type.onchange = showFields; form.categoryId.onchange = showFields; showFields();
  $('#eCancel').onclick = closeSheet;

  const applyParse = (txt) => {
    if (!txt.trim()) return;
    const p = parseEntry(txt, parseCtx());
    if (p.amount !== null) form.amount.value = p.amount;
    form.date.value = p.date;
    form.type.value = p.type;
    if (p.categoryId) form.categoryId.value = p.categoryId;
    form.debtId.value = p.debtId || '';
    if (p.goalId) form.goalId.value = p.goalId;
    if (p.investmentId) form.investmentId.value = p.investmentId;
    form.note.value = p.note;
    form.amount.classList.toggle('unsure', !p.sure.amount);
    form.categoryId.classList.toggle('unsure', p.type === 'expense' && !p.sure.category);
    showFields();
    $('#vHint').textContent = p.sure.amount ? 'Check the details, then tap Save. Orange boxes are guesses.' : "Couldn't hear an amount. Type it in below.";
  };

  if (!existing) {
    const vt = $('#vText');
    vt.addEventListener('input', () => { clearTimeout(vt.t); vt.t = setTimeout(() => applyParse(vt.value), 250); });
    if (text) applyParse(text);
    const mic = $('#vMic');
    const startListening = () => {
      if (!SR) return;
      mic.classList.add('listening'); $('#vHint').textContent = 'Listening… say e.g. "spent 250 on groceries"';
      startVoice({
        result: (ev) => {
          let interim = ''; let finalText = '';
          for (const r of ev.results) (r.isFinal ? (finalText += r[0].transcript) : (interim += r[0].transcript));
          vt.value = (finalText || interim).trim();
          applyParse(vt.value);
        },
        error: (code) => {
          $('#vHint').textContent = code === 'not-allowed' || code === 'service-not-allowed'
            ? 'Microphone blocked. Allow it in settings, or tap the box and use the keyboard 🎤.'
            : code === 'no-speech' ? "Didn't catch that. Tap 🎤 to try again."
              : code === 'start-failed' ? 'Voice could not start. Tap 🎤 again, or use the keyboard 🎤.'
                : 'Voice error: ' + code + '. Tap 🎤 to try again, or type instead.';
        },
        end: () => mic.classList.remove('listening'),
      });
    };
    if (mic) mic.onclick = (ev) => { ev.preventDefault(); if (mic.classList.contains('listening')) stopListening(); else startListening(); };
    if (listen && SR) startListening(); else setTimeout(() => (text ? form.amount : vt).focus(), 50);
  } else {
    $('#eDelete').onclick = () => {
      if (!confirm('Delete this entry?')) return;
      commit(() => { applyEffects(existing, -1); tombstone('entries', existing.id); });
      closeSheet(); toast('Deleted');
    };
  }

  form.onsubmit = (ev) => {
    ev.preventDefault();
    const amount = Number(form.amount.value);
    if (!(amount > 0)) { toast('Enter an amount'); return; }
    const type = form.type.value;
    const item = {
      ...(existing || { id: uid(), createdAt: new Date().toISOString(), source: $('#vText')?.value || '' }),
      type, amount, date: form.date.value, note: form.note.value.trim(),
      categoryId: type === 'expense' ? form.categoryId.value : null,
      debtId: type === 'expense' && form.categoryId.value === 'debt' ? form.debtId.value || null : null,
      goalId: type === 'save' ? form.goalId.value || null : null,
      investmentId: type === 'invest' ? form.investmentId.value || null : null,
    };
    if (!existing) item.applied = type === 'expense' ? !!(item.debtId && form.reduceDebt.checked) : !!(item.goalId || item.investmentId);
    commit(() => {
      if (existing) applyEffects(existing, -1);
      applyEffects(item, +1);
      upsert('entries', item);
    });
    closeSheet();
    toast(`Saved ${inr(amount)}${item.categoryId ? ' · ' + (catById(item.categoryId)?.name || '') : ''}`);
  };
}

// Entries can move balances: debt payments lower a debt, savings raise a goal, investments raise an investment.
function applyEffects(e, sign) {
  if (!e.applied) return;
  const bump = (coll, id, fields) => {
    const it = state[coll].find((x) => x.id === id && !x.deleted); if (!it) return;
    for (const [f, mult] of fields) it[f] = Math.max(0, Math.round(((Number(it[f]) || 0) + sign * mult * e.amount) * 100) / 100);
    it.updatedAt = Date.now();
  };
  if (e.type === 'expense' && e.debtId) bump('debts', e.debtId, [['balance', -1]]);
  if (e.type === 'save' && e.goalId) bump('goals', e.goalId, [['saved', 1]]);
  if (e.type === 'invest' && e.investmentId) bump('investments', e.investmentId, [['invested', 1], ['value', 1]]);
}

// ---------- actions ----------
Object.assign(actions, {
  editEntry: (id) => openEntry(state.entries.find((e) => e.id === id)),
  addTyped: () => openEntry(null),
  goMore: () => { tab = 'more'; render(); },
  goPlan: (seg) => { tab = 'plan'; planSeg = seg || 'plan'; render(); },
  seg: (k) => { planSeg = k; render(); },

  editCat: (id) => catForm(state.categories.find((c) => c.id === id)),
  addCat: () => catForm(null),

  editSalary: () => openForm({
    title: 'Income & reminder',
    fields: [
      { k: 'salary', label: 'Monthly take-home salary (₹)', type: 'number', placeholder: 'e.g. 30000' },
      { k: 'rule', label: 'Reminder shown on Home', type: 'text' },
    ],
    value: state.settings,
    onSave: (v) => commit((s) => { s.settings = { ...s.settings, salary: v.salary, rule: v.rule, updatedAt: Date.now() }; }),
  }),

  addGoal: () => goalForm(null), editGoal: (id) => goalForm(state.goals.find((g) => g.id === id)),
  addToGoal: (id) => openEntry(null, { text: `saved  for ${state.goals.find((g) => g.id === id).name}` }),
  payGoalDebt: (id) => {
    const g = state.goals.find((x) => x.id === id);
    const d = g.debtId === CARDS || g.kind === 'cardUsage' ? cardUsage(state).cards[0] : state.debts.find((x) => x.id === g.debtId);
    openEntry(null, { text: d ? `paid  to ${d.name}` : 'paid ' });
  },
  addDebt: () => debtForm(null), editDebt: (id) => debtForm(state.debts.find((d) => d.id === id)),
  payDebt: (id) => openEntry(null, { text: `paid  to ${state.debts.find((d) => d.id === id).name}` }),
  addInv: () => invForm(null), editInv: (id) => invForm(state.investments.find((i) => i.id === id)),
  addToInv: (id) => openEntry(null, { text: `invested  in ${state.investments.find((i) => i.id === id).name}` }),

  exportJson: () => download(`paisa-backup-${isoDate(new Date())}.json`, JSON.stringify(state, null, 2), 'application/json'),
  exportCsv: () => {
    const rows = [['date', 'type', 'amount', 'category', 'note']].concat(live(state.entries).sort((a, b) => a.date.localeCompare(b.date))
      .map((e) => [e.date, e.type, e.amount, catById(e.categoryId)?.name || '', e.note || '']));
    download(`paisa-entries-${isoDate(new Date())}.csv`, rows.map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n'), 'text/csv');
  },
  resetAll: () => {
    if (!confirm('Erase all Paisa data on this device? (Your synced copy and backup files are not affected.)')) return;
    localStorage.removeItem('paisa.v1'); location.reload();
  },

  setupSync: () => {
    const cfg = sync.getConfig();
    openSheet(`<h3>Set up sync</h3>
      <div class="muted">One-time setup on each device. See <b>SETUP.md</b> (step 3) for how to get these two values from your free Supabase project.</div><br>
      <form id="sform">
        <label class="f">Project URL<input name="url" value="${esc(cfg.url || '')}" placeholder="https://xxxx.supabase.co" autocapitalize="off" autocorrect="off"></label>
        <label class="f">Publishable (anon) key<input name="key" value="${esc(cfg.key || '')}" placeholder="eyJ… or sb_publishable_…" autocapitalize="off" autocorrect="off"></label>
        <div class="hint">This key is safe to put in an app: your data is protected by your login.</div>
        <details><summary class="muted">Database setup code (paste once into Supabase → SQL Editor)</summary><textarea readonly rows="8" style="width:100%;font-size:12px">${esc(sync.SETUP_SQL)}</textarea></details>
        <div class="btns"><button type="button" class="btn" id="sCancel">Cancel</button><button class="btn primary">Save</button></div>
        ${cfg.url ? '<div class="btns"><button type="button" class="btn danger" id="sOff">Turn off sync on this device</button></div>' : ''}
      </form>`);
    $('#sCancel').onclick = closeSheet;
    if ($('#sOff')) $('#sOff').onclick = () => { sync.setConfig({}); closeSheet(); render(); doSync(); };
    $('#sform').onsubmit = (ev) => {
      ev.preventDefault();
      const url = ev.target.url.value.trim(); const key = ev.target.key.value.trim();
      if (!/^https:\/\/.+/.test(url) || key.length < 20) { toast('Check the URL and key'); return; }
      sync.setConfig({ url, key }); closeSheet(); render(); actions.signIn();
    };
  },
  signIn: () => {
    openSheet(`<h3>Sign in to sync</h3><div class="muted">Use the same email and password on every device. First time? Tap "Create login".</div><br>
      <form id="lform">
        <label class="f">Email<input name="email" type="email" autocomplete="username" required></label>
        <label class="f">Password<input name="password" type="password" autocomplete="current-password" minlength="6" required></label>
        <div class="btns"><button type="button" class="btn" id="lNew">Create login</button><button class="btn primary">Sign in</button></div>
        <div class="hint" id="lMsg"></div></form>`);
    const f = $('#lform'); const msg = $('#lMsg');
    const go = async (fn) => {
      if (!f.reportValidity()) return;
      msg.textContent = 'Working…';
      try {
        const r = await fn(f.email.value.trim(), f.password.value);
        if (fn === sync.signUp && !r.session) { msg.textContent = 'Check your email and tap the confirm link, then come back and tap Sign in.'; return; }
        closeSheet(); toast('Signed in. Syncing…'); await doSync(); render();
      } catch (e) { msg.textContent = e.message; }
    };
    $('#lNew').onclick = () => go(sync.signUp);
    f.onsubmit = (ev) => { ev.preventDefault(); go(sync.signIn); };
  },
  syncNow: async () => { await doSync(); toast($('#syncDot').title); },
  signOut: async () => { await sync.signOut(); render(); doSync(); },
});

function catForm(c) {
  openForm({
    title: c ? 'Edit category' : 'New category',
    fields: [
      { k: 'icon', label: 'Emoji', placeholder: '📦' },
      { k: 'name', label: 'Name' },
      { k: 'budget', label: 'Monthly budget (₹)', type: 'number' },
      { k: 'keywords', label: 'Voice keywords (comma separated)', hint: 'Words that mean this category, e.g. "swiggy, zomato, lunch".' },
    ],
    value: c ? { ...c, keywords: (c.keywords || []).join(', ') } : { icon: '📦' },
    onSave: (v) => {
      if (!v.name) return 'Enter a name';
      commit(() => upsert('categories', { ...(c || { id: uid(), order: state.categories.length }), ...v, budget: v.budget || 0, keywords: v.keywords.split(',').map((x) => x.trim().toLowerCase()).filter(Boolean) }));
    },
    onDelete: c && c.id !== 'other' ? () => commit(() => tombstone('categories', c.id)) : null,
  });
}

function goalForm(g) {
  const debtOpts = [[CARDS, 'All credit cards together'], ...live(state.debts).map((d) => [d.id, d.name])];
  openForm({
    title: g ? 'Edit goal' : 'New goal',
    fields: [
      { k: 'name', label: 'Goal name' },
      { k: 'kind', label: 'Kind', type: 'select', options: [['save', 'Save up an amount'], ['debt', 'Pay off a debt fully'], ['cardUsage', 'Bring card usage under a %']] },
      { k: 'target', label: 'Target amount (₹) — for "Save up"', type: 'number' },
      { k: 'saved', label: 'Saved so far (₹) — for "Save up"', type: 'number' },
      { k: 'debtId', label: 'Debt — for "Pay off"', type: 'select', options: debtOpts },
      { k: 'targetPct', label: 'Target card usage % — for "card usage"', type: 'number' },
      { k: 'deadline', label: 'Finish by (month)', type: 'month' },
      { k: 'priority', label: 'Priority (1 = first)', type: 'number' },
    ],
    value: g || { kind: 'save', priority: live(state.goals).length + 1 },
    onSave: (v) => {
      if (!v.name) return 'Enter a name';
      const base = g || { id: uid() };
      const item = { ...base, ...v };
      if (v.kind !== 'save' && !base.startBalance) {
        item.startBalance = v.kind === 'cardUsage' || v.debtId === CARDS ? cardUsage(state).balance : Number(state.debts.find((d) => d.id === v.debtId)?.balance) || 0;
      }
      commit(() => upsert('goals', item));
    },
    onDelete: g ? () => commit(() => tombstone('goals', g.id)) : null,
  });
}

function debtForm(d) {
  openForm({
    title: d ? 'Edit debt' : 'New debt / card / EMI',
    fields: [
      { k: 'name', label: 'Name (e.g. SBI Card, mPokket)' },
      { k: 'kind', label: 'Kind', type: 'select', options: [['card', 'Credit card'], ['loan', 'Loan'], ['emi', 'EMI']] },
      { k: 'balance', label: 'Amount owed now (₹)', type: 'number' },
      { k: 'limit', label: 'Credit limit (₹) — cards only', type: 'number' },
      { k: 'emi', label: 'EMI per month (₹) — loans/EMIs', type: 'number' },
      { k: 'rate', label: 'Interest % per year (optional)', type: 'number' },
      { k: 'dueDay', label: 'Due day of month (1–31)', type: 'number' },
      { k: 'note', label: 'Note', type: 'textarea' },
    ],
    value: d || { kind: 'card' },
    onSave: (v) => {
      if (!v.name) return 'Enter a name';
      commit(() => upsert('debts', { ...(d || { id: uid() }), ...v, keywords: v.name.toLowerCase().split(/\s+/).filter((w) => w.length > 2 && !['card', 'loan', 'other', 'cards'].includes(w)) }));
    },
    onDelete: d ? () => commit(() => tombstone('debts', d.id)) : null,
  });
}

function invForm(i) {
  openForm({
    title: i ? 'Edit investment' : 'New investment',
    fields: [
      { k: 'name', label: 'Name (e.g. Parag Parikh Flexi Cap SIP)' },
      { k: 'type', label: 'Type', type: 'select', options: ['SIP', 'Mutual fund', 'FD', 'RD', 'PPF', 'NPS', 'Stocks', 'Gold', 'Other'].map((x) => [x, x]) },
      { k: 'monthly', label: 'Monthly contribution (₹)', type: 'number' },
      { k: 'invested', label: 'Total invested so far (₹)', type: 'number' },
      { k: 'value', label: 'Current value (₹)', type: 'number', hint: 'Update this from your fund app once a month.' },
      { k: 'maturity', label: 'Maturity date (FDs, optional)', type: 'date' },
      { k: 'note', label: 'Note', type: 'textarea' },
    ],
    value: i || { type: 'SIP' },
    onSave: (v) => { if (!v.name) return 'Enter a name'; commit(() => upsert('investments', { ...(i || { id: uid() }), ...v })); },
    onDelete: i ? () => commit(() => tombstone('investments', i.id)) : null,
  });
}

function download(name, text, type) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([text], { type }));
  a.download = name; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

async function restore(ev) {
  const file = ev.target.files[0]; if (!file) return;
  try {
    const data = JSON.parse(await file.text());
    if (!data.categories || !data.entries) throw new Error('Not a Paisa backup');
    if (!confirm('Combine this backup with the data on this device? (The newest version of each item is kept.)')) return;
    commit(() => { state = merge(state, data); });
    toast('Backup restored');
  } catch (e) { toast('Restore failed: ' + e.message); }
}

init();
