import { parseEntry, parseMany, isoDate } from './parser.js';
import {
  load, persist, emptyState, merge, uid, live, monthKey, inr, monthSummary, cardUsage, goalStatus, buildPlan, CARDS,
} from './store.js';
import * as sync from './sync.js';
import { icon, catIcon } from './icons.js';

export const VERSION = '1.4 (18 Nov 2026)';

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

function toast(msg, undo) {
  const t = $('#toast');
  t.innerHTML = icon('check', 18) + `<span>${esc(msg)}</span>` + (undo ? '<button type="button" class="toast-undo">Undo</button>' : '');
  t.classList.remove('hidden');
  if (undo) t.querySelector('.toast-undo').onclick = () => { undo(); toast('Undone'); };
  clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.add('hidden'), undo ? 8000 : 2600);
}

function undoEntries(ids) {
  commit(() => {
    for (const id of ids) {
      const e = state.entries.find((x) => x.id === id && !x.deleted);
      if (e) { applyEffects(e, -1); tombstone('entries', id); }
    }
  });
}

// ---------- chrome ----------
function bindChrome() {
  document.querySelectorAll('[data-icon]').forEach((el) => { el.outerHTML = icon(el.dataset.icon, el.closest('.fab') ? 28 : 22); });
  $('#prevMonth').innerHTML = icon('chevL', 18); $('#nextMonth').innerHTML = icon('chevR', 18);
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
  { const [y, m] = viewMonth.split('-').map(Number); $('#monthLabel').textContent = new Date(y, m - 1, 1).toLocaleDateString('en-IN', { month: 'short', year: 'numeric' }); }
  $('#monthNav').classList.toggle('hidden', !showMonth);
  $('#pageTitle').textContent = { home: 'Kosh', budget: 'Budget', plan: 'Plan', more: 'Settings' }[tab];
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

// Ring gauge. fraction 0..1; marks are fractions shown as small ticks.
function ring(fraction, { size = 112, stroke = 12, color = 'url(#gOrange)', label = '', sub = '', marks = [] } = {}) {
  const r = (size - stroke) / 2; const c = 2 * Math.PI * r; const f = Math.max(0, Math.min(1, fraction));
  const ticks = marks.map((m) => {
    const a = m * 2 * Math.PI; const x1 = size / 2 + (r - stroke / 2 - 2) * Math.cos(a); const y1 = size / 2 + (r - stroke / 2 - 2) * Math.sin(a);
    const x2 = size / 2 + (r + stroke / 2 + 2) * Math.cos(a); const y2 = size / 2 + (r + stroke / 2 + 2) * Math.sin(a);
    return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="var(--text)" stroke-opacity=".7" stroke-width="2" stroke-linecap="round"/>`;
  }).join('');
  return `<div class="ring" style="width:${size}px;height:${size}px" role="img" aria-label="${esc(label + ' ' + sub)}">
    <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
      <defs><linearGradient id="gOrange" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffb37a"/><stop offset=".5" stop-color="#ff7a2f"/><stop offset="1" stop-color="#c93a0e"/></linearGradient></defs>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="var(--surface-2)" stroke-width="${stroke}"/>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round"
        stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - f)}" style="transition:stroke-dashoffset .8s var(--ease)"/>
      ${ticks}
    </svg>
    <div class="lbl"><div>${label}${sub ? `<small>${sub}</small>` : ''}</div></div></div>`;
}

// Packed bubble chart: circle area ∝ value. Positions are % of a 340×260 box so it scales.
function bubbleChart(items, onAct = 'editCat') {
  const W = 340, H = 260;
  const vals = items.filter((x) => x.value > 0).sort((a, b) => b.value - a.value).slice(0, 7);
  if (!vals.length) return '';
  const total = vals.reduce((t, x) => t + x.value, 0); const vmax = vals[0].value;
  let rs = vals.map((x) => Math.max(26, 88 * Math.sqrt(x.value / vmax)));
  const area = rs.reduce((t, r) => t + Math.PI * r * r, 0); const k = Math.min(1, Math.sqrt((0.55 * W * H) / area));
  rs = rs.map((r) => Math.max(24, r * k));
  // Place largest first, spiralling out from the centre; if one doesn't fit, shrink all and retry.
  let placed = [];
  for (let attempt = 0; attempt < 8; attempt++) {
    placed = [];
    const scale = Math.pow(0.9, attempt);
    const ok = vals.every((x, i) => {
      const r = Math.max(22, rs[i] * scale);
      for (let d = 0; d < 260; d += 2) {
        for (let a = 0; a < 360; a += 10) {
          const t = (a + i * 47) * Math.PI / 180;
          const cx = W / 2 + d * Math.cos(t) * 1.3; const cy = H / 2 + d * Math.sin(t);
          if (cx - r < 0 || cx + r > W || cy - r < 0 || cy + r > H) continue;
          if (placed.every((p) => Math.hypot(p.cx - cx, p.cy - cy) >= p.r + r + 4)) { placed.push({ cx, cy, r, x, i }); return true; }
        }
      }
      return false;
    });
    if (ok) break;
  }
  return `<div class="bubbles">${placed.map(({ cx, cy, r, x, i }) => {
    const p = Math.round((x.value / total) * 100);
    const big = r >= 44;
    return `<button class="bubble ${i === 0 ? 'top' : i === 1 ? 'second' : ''} ${x.over ? 'over' : ''}" data-act="${onAct}" data-id="${x.id}"
      style="left:${((cx - r) / W) * 100}%;top:${((cy - r) / H) * 100}%;width:${((2 * r) / W) * 100}%;height:${((2 * r) / H) * 100}%;animation-delay:${i * 0.05}s"
      aria-label="${esc(x.label)} ${p}%">${x.iconHtml}${big ? `<span class="bn">${esc(x.label)}</span>` : ''}<span class="bp">${p}%</span></button>`;
  }).join('')}</div>`;
}

function splitAmt(n) { return `<span class="cur">₹</span>${Math.abs(Math.round(n)).toLocaleString('en-IN')}`; }
const dshort = (iso) => new Date(iso + 'T00:00').toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });

function entryRow(e) {
  const c = catById(e.categoryId);
  const meta = {
    expense: [catIcon(c, 20), '', c?.name || 'Other'],
    income: [icon('arrowDL', 20), 'in', 'Income'],
    save: [icon('wallet', 20), 'save', 'Saving · ' + (state.goals.find((g) => g.id === e.goalId)?.name || 'goal')],
    invest: [icon('trend', 20), 'inv', 'Investment · ' + (state.investments.find((i) => i.id === e.investmentId)?.name || '')],
  }[e.type] || [icon('tag'), '', ''];
  const sign = e.type === 'income' ? '+' : e.type === 'expense' ? '−' : '';
  return `<div class="li" data-act="editEntry" data-id="${e.id}" role="button" tabindex="0">
    <div class="tile ${meta[1]}">${meta[0]}</div>
    <div class="grow"><div class="t">${esc(e.note || meta[2])}</div><div class="s">${dshort(e.date)} · ${esc(meta[2])}</div></div>
    <div class="amt ${e.type === 'income' ? 'good' : ''}">${sign}${inr(e.amount)}</div></div>`;
}

function cardUsageCard(clickable = true) {
  const cu = cardUsage(state);
  if (!cu.cards.length) return '';
  const p = cu.pct; const tone = p > 30 ? 'bad' : p > 10 ? 'warn' : 'good';
  const color = p > 30 ? 'url(#gOrange)' : p > 10 ? 'var(--warn)' : 'var(--good)';
  return `<div class="card" ${clickable ? 'data-act="goPlan" data-id="debts" role="button" tabindex="0"' : ''}>
    <div class="card-head"><h2>Credit card usage</h2>${clickable ? `<span class="link">Debts ${icon('chevR', 16)}</span>` : ''}</div>
    <div class="gauge">
      ${ring(p / 100, { label: `${Math.round(p)}%`, sub: 'used', color, marks: [0.1, 0.3] })}
      <div>
        <div class="num" style="font-size:22px;font-weight:600">${inr(cu.balance)}</div>
        <div class="muted">of ${inr(cu.limit)} limit</div>
        <div class="chips"><span class="chip">Under 30% <b>${inr(cu.limit * 0.3)}</b></span><span class="chip">Under 10% <b>${inr(cu.limit * 0.1)}</b></span></div>
      </div>
    </div>
    ${p > 30 ? `<div class="faint" style="margin-top:12px">Ticks on the ring mark 10% and 30%. Pay down <b class="${tone}">${inr(cu.balance - cu.limit * 0.3)}</b> to get under 30%.</div>` : ''}
  </div>`;
}

function ruleBanner() {
  return state.settings.rule ? `<div class="banner">${icon('shield', 18)}<span>${esc(state.settings.rule)}</span></div>` : '';
}

function homeView() {
  const ms = monthSummary(state, viewMonth);
  const cats = live(state.categories);
  const totalBudget = cats.filter((c) => c.id !== 'debt').reduce((t, c) => t + (Number(c.budget) || 0), 0);
  const recent = [...ms.entries].sort((a, b) => (b.date + (b.createdAt || '')).localeCompare(a.date + (a.createdAt || ''))).slice(0, 6);
  const plan = buildPlan(state);
  const next = plan.goals.filter((g) => !g.st.done && g.want > 0).slice(0, 3);
  const due = live(state.debts).filter((d) => d.dueDay && d.balance > 0);
  const isNew = !live(state.goals).length && !live(state.debts).length && !live(state.entries).length;
  const spentAny = ms.spent > 0;
  const bubbleItems = cats.map((c) => {
    const s = ms.byCat[c.id] || 0;
    return { id: c.id, label: c.name, value: spentAny ? s : (Number(c.budget) || 0), over: c.budget > 0 && s > c.budget, iconHtml: catIcon(c, 18) };
  });

  const welcome = isNew ? `<div class="card"><h2>Welcome to Kosh</h2>
    <p class="muted" style="margin-top:0">New device? Load your budget, goals and debts by signing in to sync, or by restoring a backup or starting-plan file.</p>
    <button class="btn primary block" data-act="goMore">Set up sync or restore</button></div>` : '';

  const hero = `<section class="hero">
    <div class="eyebrow">Left this month</div>
    ${ms.incomeKnown
      ? `<p class="hero-amt">${ms.left < 0 ? '−' : ''}${splitAmt(ms.left)}</p>
         <span class="hero-chip">${icon(ms.left < 0 ? 'arrowDL' : 'arrowUR', 14)} Spent ${inr(ms.spent)} of ${inr(totalBudget)} budget</span>`
      : `<p class="hero-amt">—</p><span class="hero-chip"><a href="#" data-act="editSalary">Add your take-home salary</a></span>`}
    <div class="hero-stats">
      <div class="hero-stat"><span>Income</span><b>${inr(ms.income)}</b></div>
      <div class="hero-stat"><span>Spent</span><b>${inr(ms.spent)}</b></div>
      <div class="hero-stat"><span>Saved</span><b>${inr(ms.saved + ms.invested)}</b></div>
    </div></section>`;

  const quick = `<div class="quick">
    <button data-act="voice">${icon('mic', 22)}Speak</button>
    <button data-act="addTyped">${icon('keyboard', 22)}Type</button>
    <button data-act="goPlan" data-id="plan">${icon('target', 22)}Plan</button></div>`;

  return `<div class="rise">${ruleBanner()}${welcome}${hero}${quick}
  ${cardUsageCard()}
  ${due.length ? `<div class="card"><h2>Pay on time</h2>${due.map((d) => `<div class="li" data-act="editDebt" data-id="${d.id}"><div class="tile">${icon('calendar')}</div><div class="grow"><div class="t">${esc(d.name)}</div><div class="s">Due on the ${d.dueDay}${ordinal(d.dueDay)}</div></div><div class="amt">${inr(d.balance)}</div></div>`).join('')}</div>` : ''}
  <div class="card">
    <div class="card-head"><h2>${spentAny ? 'Where the money went' : 'Your budget plan'}</h2><button class="link" data-act="goBudget">Budget ${icon('chevR', 16)}</button></div>
    ${bubbleChart(bubbleItems) || '<p class="muted">Set category budgets on the Budget tab.</p>'}
    <div class="faint">${spentAny ? 'Bubble size shows each category’s share of spending. A red ring means over budget.' : 'Nothing spent yet this month. Bubbles show how your budget is split.'}</div>
  </div>
  ${next.length ? `<div class="card" data-act="goPlan" data-id="plan" role="button" tabindex="0"><div class="card-head"><h2>Save next</h2><span class="link">Plan ${icon('chevR', 16)}</span></div>
    ${next.map((g) => `<div class="li"><div class="tile">${icon(g.goal.kind === 'save' ? 'wallet' : 'card')}</div><div class="grow"><div class="t">${esc(g.goal.name)}</div><div class="s">${pct(g.st.progress)}% done</div></div><div class="amt">${inr(g.want)}<small>this month</small></div></div>`).join('')}</div>` : ''}
  <div class="card"><div class="card-head"><h2>Recent</h2><button class="link" data-act="goBudget">All ${icon('chevR', 16)}</button></div>
    ${recent.length ? recent.map(entryRow).join('') : `<p class="muted" style="margin:0">No entries yet. Tap the mic and say “spent 250 on groceries”.</p>`}</div></div>`;
}
const ordinal = (n) => (n % 10 === 1 && n !== 11 ? 'st' : n % 10 === 2 && n !== 12 ? 'nd' : n % 10 === 3 && n !== 13 ? 'rd' : 'th');

function budgetView() {
  const ms = monthSummary(state, viewMonth);
  const cats = live(state.categories).sort((a, b) => (a.order ?? 99) - (b.order ?? 99));
  const totalBudget = cats.filter((c) => c.id !== 'debt').reduce((t, c) => t + (Number(c.budget) || 0), 0);
  const all = [...ms.entries].sort((a, b) => b.date.localeCompare(a.date));
  const f = totalBudget ? ms.spent / totalBudget : 0;
  return `<div class="rise"><div class="card"><h2>Monthly budget</h2>
    <div class="gauge">${ring(f, { size: 124, label: `${pct(f)}%`, sub: 'spent', color: f > 1 ? 'var(--bad)' : 'url(#gOrange)' })}
      <div><div class="num" style="font-size:26px;font-weight:700">${inr(ms.spent)}</div><div class="muted">of ${inr(totalBudget)}</div>
      <div class="chips"><span class="chip">${totalBudget - ms.spent >= 0 ? 'Left' : 'Over'} <b>${inr(Math.abs(totalBudget - ms.spent))}</b></span></div></div></div></div>
  <div class="card"><div class="card-head"><h2>Categories</h2><button class="link" data-act="addCat">${icon('plus', 16)} Add</button></div>
  ${cats.map((c) => {
    const s = ms.byCat[c.id] || 0; const left = (c.budget || 0) - s; const r = c.budget ? s / c.budget : 0;
    return `<div class="li" data-act="editCat" data-id="${c.id}" role="button" tabindex="0" style="align-items:flex-start">
      <div class="tile">${catIcon(c)}</div>
      <div class="grow"><div class="row"><span class="t">${esc(c.name)}</span><span class="amt">${inr(s)}</span></div>
      ${c.budget ? bar(r, r > 1 ? 'bad' : r > 0.85 ? 'warn' : '') + `<div class="row" style="margin-top:6px"><span class="s">${left >= 0 ? inr(left) + ' left' : `<span class="bad">${inr(-left)} over</span>`}</span><span class="s">of ${inr(c.budget)}</span></div>` : '<div class="s">No budget set</div>'}</div></div>`;
  }).join('')}</div>
  <div class="card"><h2>All entries · ${monthName(viewMonth)}</h2>${all.length ? all.map(entryRow).join('') : '<p class="muted" style="margin:0">No entries.</p>'}
    <div class="btns"><button class="btn" data-act="addTyped">${icon('keyboard', 18)} Type an entry</button></div></div></div>`;
}

function planView() {
  const segs = [['plan', 'This month'], ['goals', 'Goals'], ['debts', 'Debts'], ['invest', 'Investments']];
  const head = `<div class="seg" role="tablist">${segs.map(([k, l]) => `<button role="tab" aria-selected="${planSeg === k}" class="${planSeg === k ? 'active' : ''}" data-act="seg" data-id="${k}">${l}</button>`).join('')}</div>`;
  return head + `<div class="rise">${{ plan: planTab, goals: goalsTab, debts: debtsTab, invest: investTab }[planSeg]()}</div>`;
}

function planTab() {
  const p = buildPlan(state);
  const goalsList = (rows) => rows.map((g, i) => `<div class="li" data-act="editGoal" data-id="${g.goal.id}" role="button" tabindex="0">
      <div class="tile">${i + 1}</div>
      <div class="grow"><div class="t">${esc(g.goal.name)}</div>
      <div class="s">${inr(g.st.perMonth)}/mo for ${g.st.months} mo${g.st.thisMonth ? ` · ${inr(g.st.thisMonth)} done` : ''}${p.incomeKnown && g.give < g.want ? ` · <span class="warn">short ${inr(g.want - g.give)}</span>` : ''}</div></div>
      <div class="amt">${g.want === 0 ? '<small>covered by<br>the goal above</small>' : inr(p.incomeKnown ? g.give : g.want)}</div></div>`).join('');
  const open = p.goals.filter((g) => !g.st.done);
  if (!p.incomeKnown) {
    return `<div class="card"><h2>Monthly plan</h2><p class="muted" style="margin-top:0">Add your monthly take-home salary to see how much you can put toward each goal.</p>
      <button class="btn primary block" data-act="editSalary">${icon('briefcase', 18)} Add salary</button></div>
      <div class="card"><h2>Monthly need per goal</h2>${goalsList(open)}</div>`;
  }
  return `<section class="hero" style="padding-bottom:20px"><div class="eyebrow">Free for goals this month</div>
    <p class="hero-amt">${p.free < 0 ? '−' : ''}${splitAmt(p.free)}</p>
    <div class="hero-stats"><div class="hero-stat"><span>Income</span><b>${inr(p.income)}</b></div><div class="hero-stat"><span>Budget</span><b>${inr(p.budgeted)}</b></div><div class="hero-stat"><span>SIPs${p.emis ? ' + EMIs' : ''}</span><b>${inr(p.sips + p.emis)}</b></div></div></section>
  <div class="card"><h2>Put this toward your goals</h2>
    ${goalsList(open) || '<p class="muted">All goals done.</p>'}
    ${p.leftover > 0 ? `<div class="banner" style="margin:14px 0 0">${icon('bulb', 18)}<span>After goals, ${inr(p.leftover)} is spare. Put it toward your first unfinished goal to finish sooner, or increase your SIP.</span></div>` : ''}
    ${p.free < 0 ? `<div class="banner" style="margin:14px 0 0">${icon('info', 18)}<span>Your budgets are more than your income. Lower a category budget on the Budget tab.</span></div>` : ''}
  </div>`;
}

function goalsTab() {
  const gs = live(state.goals).sort((a, b) => (a.priority || 99) - (b.priority || 99));
  return gs.map((g) => {
    const st = goalStatus(g, state);
    const line = g.kind === 'save' ? `${inr(st.current)} of ${inr(st.target)} saved` : `${inr(st.current)} owed → ${inr(st.target)}`;
    const by = g.deadline ? new Date(g.deadline + '-01T00:00').toLocaleDateString('en-IN', { month: 'short', year: 'numeric' }) : '';
    return `<div class="card"><div class="goal">
      ${ring(st.progress, { size: 84, stroke: 9, label: st.done ? icon('check', 26) : `${pct(st.progress)}%`, color: st.done ? 'var(--good)' : 'url(#gOrange)' })}
      <div class="grow"><h3>${esc(g.name)}</h3><div class="muted">${line}</div>
        <div class="chips">${st.done ? '<span class="pill ok">Done</span>' : `<span class="pill hot">${inr(st.perMonth)}/month</span>`}${by ? `<span class="pill">${icon('calendar', 13)} ${by}</span>` : ''}</div></div></div>
      <div class="btns">${g.kind === 'save' ? `<button class="btn primary" data-act="addToGoal" data-id="${g.id}">${icon('plus', 18)} Add money</button>` : `<button class="btn primary" data-act="payGoalDebt" data-id="${g.id}">Log payment</button>`}
      <button class="btn" data-act="editGoal" data-id="${g.id}">${icon('pencil', 16)} Edit</button></div></div>`;
  }).join('') + `<button class="btn block" data-act="addGoal">${icon('plus', 18)} New goal</button>`;
}

function debtsTab() {
  const ds = live(state.debts);
  return ruleBanner() + cardUsageCard(false) + ds.map((d) => {
    const usage = d.kind === 'card' && d.limit ? d.balance / d.limit : null;
    const rows = [
      usage !== null ? ['Limit', `${inr(d.limit)} · ${Math.round(usage * 100)}% used`] : null,
      d.emi ? ['EMI', `${inr(d.emi)}/month`] : null,
      d.rate ? ['Interest', `${d.rate}% a year`] : null,
      d.dueDay ? ['Due', `${d.dueDay}${ordinal(d.dueDay)} of each month`] : null,
    ].filter(Boolean);
    return `<div class="card">
      <div class="li" style="padding-top:0;cursor:default"><div class="tile">${icon(d.kind === 'card' ? 'card' : 'bank')}</div>
        <div class="grow"><div class="t">${esc(d.name)}</div><div class="s">${{ card: 'Credit card', loan: 'Loan', emi: 'EMI' }[d.kind] || d.kind}</div></div>
        <div class="amt">${inr(d.balance)}<small>owed</small></div></div>
      ${usage !== null ? bar(usage, usage > 0.3 ? 'bad' : usage > 0.1 ? 'warn' : 'good', [10, 30]) : ''}
      ${rows.map(([k, v]) => `<div class="row" style="margin-top:10px"><span class="muted">${k}</span><span>${v}</span></div>`).join('')}
      ${d.note ? `<p class="faint" style="margin:12px 0 0">${esc(d.note)}</p>` : ''}
      <div class="btns"><button class="btn primary" data-act="payDebt" data-id="${d.id}">Log payment</button><button class="btn" data-act="editDebt" data-id="${d.id}">${icon('pencil', 16)} Edit</button></div></div>`;
  }).join('') + `<button class="btn block" data-act="addDebt">${icon('plus', 18)} Add debt, EMI or card</button>`;
}

function investTab() {
  const is = live(state.investments);
  const tot = is.reduce((t, i) => ({ m: t.m + (+i.monthly || 0), inv: t.inv + (+i.invested || 0), v: t.v + (+i.value || 0) }), { m: 0, inv: 0, v: 0 });
  const gain = tot.v - tot.inv;
  return `<section class="hero" style="padding-bottom:20px"><div class="eyebrow">Portfolio value</div>
    <p class="hero-amt">${splitAmt(tot.v)}</p>
    <span class="hero-chip">${icon(gain >= 0 ? 'arrowUR' : 'arrowDL', 14)} ${gain >= 0 ? '+' : '−'}${inr(Math.abs(gain))}${tot.inv ? ` (${((gain / tot.inv) * 100).toFixed(1)}%)` : ''}</span>
    <div class="hero-stats"><div class="hero-stat"><span>Invested</span><b>${inr(tot.inv)}</b></div><div class="hero-stat"><span>Monthly</span><b>${inr(tot.m)}</b></div><div class="hero-stat"><span>Holdings</span><b>${is.length}</b></div></div></section>` +
    is.map((i) => {
      const g = (+i.value || 0) - (+i.invested || 0);
      return `<div class="card">
        <div class="li" style="padding-top:0;cursor:default"><div class="tile inv">${icon('trend')}</div>
          <div class="grow"><div class="t">${esc(i.name)}</div><div class="s">${esc(i.type)}${i.monthly ? ` · ${inr(i.monthly)}/month` : ''}</div></div>
          <div class="amt">${inr(i.value || 0)}${i.invested ? `<small class="${g >= 0 ? 'good' : 'bad'}">${g >= 0 ? '+' : '−'}${inr(Math.abs(g))}</small>` : ''}</div></div>
        <div class="row" style="margin-top:6px"><span class="muted">Invested so far</span><span>${inr(i.invested || 0)}</span></div>
        ${i.maturity ? `<div class="row" style="margin-top:8px"><span class="muted">Matures</span><span>${esc(i.maturity)}</span></div>` : ''}
        ${i.note ? `<p class="faint" style="margin:12px 0 0">${esc(i.note)}</p>` : ''}
        <div class="btns"><button class="btn primary" data-act="addToInv" data-id="${i.id}">${icon('plus', 18)} Add money</button><button class="btn" data-act="editInv" data-id="${i.id}">${icon('pencil', 16)} Update</button></div></div>`;
    }).join('') + `<button class="btn block" data-act="addInv">${icon('plus', 18)} Add investment</button>`;
}

function setRow(ic, title, sub, act, extra = '') {
  return `<div class="li" ${act ? `data-act="${act}" role="button" tabindex="0"` : ''}><div class="tile">${icon(ic)}</div>
    <div class="grow"><div class="t">${title}</div>${sub ? `<div class="s">${sub}</div>` : ''}</div>${extra}${act ? icon('chevR', 18, 'chev') : ''}</div>`;
}

function moreView() {
  const cfg = sync.getConfig();
  return `<div class="rise">
  <div class="card set">${setRow('briefcase', 'Monthly take-home salary', state.settings.salary ? inr(state.settings.salary) : 'Not set', 'editSalary')}
    ${setRow('shield', 'Reminder on Home', esc(state.settings.rule || 'None'), 'editSalary')}</div>
  <div class="card"><h2>Sync between devices</h2><div id="syncBox" class="muted">Checking…</div></div>
  <div class="card set">
    ${setRow('download', 'Backup file', 'Save everything as one file', 'exportJson')}
    ${setRow('download', 'Entries as CSV', 'Open in Excel or Google Sheets', 'exportCsv')}
    <label class="li" role="button" tabindex="0"><div class="tile">${icon('upload')}</div><div class="grow"><div class="t">Restore from backup</div><div class="s">Merges with data on this device</div></div>${icon('chevR', 18, 'chev')}<input type="file" id="restoreFile" accept="application/json,.json" hidden></label>
  </div>
  <div class="card"><h2>Voice tips</h2><p class="muted" style="margin:0">Say things like “spent 250 on groceries”, “paid 9000 rent”, “120 auto yesterday”, “paid 5000 to SBI card”, “saved 2000 for emergency fund”, “invested 1000 in SIP” or “got salary 30000”.<br><br>On iPhone, if the mic button doesn’t listen, tap the text box and use the microphone key on the keyboard.</p></div>
  <div class="card"><h2>About</h2><p class="muted" style="margin:0">Kosh keeps your data on this device${cfg.url ? ' and in your own Supabase database' : ''}. It never asks for card numbers, account numbers or PAN.</p>
  <p class="faint" style="margin:10px 0 0">Version ${VERSION}${IS_IOS ? ' · iPhone mode: keyboard dictation' : ''}</p>
  <div class="btns"><button class="btn danger" data-act="resetAll">${icon('trash', 18)} Erase data on this device</button></div></div></div>`;
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

// Speech recognition. Chrome/Edge: one recognizer reused for every entry. iPhone/iPad Safari: a fresh
// recognizer per entry (WebKit tends to go silent when one is reused). Late events from an older
// recognizer are ignored, a watchdog resets things if the browser never reports the end, and if no
// audio starts within a few seconds the user is offered keyboard dictation instead.
const IS_IOS = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const voice = { rec: null, active: false, h: null, pending: null, watchdog: null, audioTimer: null, heard: false };

function recognizer(fresh = IS_IOS) {
  if (voice.rec && !fresh) return voice.rec;
  const r = new (getSR())();
  r.lang = 'en-IN'; r.interimResults = true; r.continuous = false; r.maxAlternatives = 1;
  const mine = () => r === voice.rec;
  const gotAudio = () => { if (mine()) { voice.heard = true; clearTimeout(voice.audioTimer); voice.h?.audio?.(); } };
  r.onaudiostart = gotAudio; r.onspeechstart = gotAudio;
  r.onresult = (ev) => {
    if (!mine()) return;
    gotAudio(); voice.h?.result(ev);
    if (ev.results[ev.results.length - 1]?.isFinal) { try { r.stop(); } catch { /* already stopping */ } }
  };
  r.onerror = (ev) => { if (mine() && ev.error !== 'aborted') { clearTimeout(voice.audioTimer); voice.h?.error(ev.error); voice.h && (voice.h.errored = true); } };
  r.onend = () => {
    if (!mine()) return;
    voice.active = false; clearTimeout(voice.watchdog); clearTimeout(voice.audioTimer);
    const h = voice.h; voice.h = null;
    if (h && !h.errored && !h.gotResult) h.error('no-result');
    h?.end();
    if (voice.pending) { const go = voice.pending; voice.pending = null; go(); }
  };
  voice.rec = r;
  return r;
}

function resetVoice() {
  try { voice.rec?.abort(); } catch { /* ignore */ }
  voice.rec = null; voice.active = false; clearTimeout(voice.watchdog); clearTimeout(voice.audioTimer);
  const h = voice.h; voice.h = null; h?.end();
}

function startVoice(handlers) {
  const armTimers = () => {
    clearTimeout(voice.watchdog); clearTimeout(voice.audioTimer); voice.heard = false;
    voice.watchdog = setTimeout(() => { if (voice.active) resetVoice(); }, 15000);
    // No microphone audio within 4s: this browser's voice engine isn't working here.
    voice.audioTimer = setTimeout(() => {
      if (voice.active && !voice.heard && voice.h === handlers) { handlers.errored = true; handlers.error('no-audio'); resetVoice(); }
    }, 4000);
  };
  const go = () => {
    voice.h = handlers; voice.active = true;
    try { recognizer().start(); } catch {
      // Recognizer stuck in a bad state: throw it away and try once with a fresh one.
      voice.rec = null;
      try { recognizer().start(); } catch { voice.active = false; voice.h = null; handlers.error('start-failed'); handlers.end(); return; }
    }
    armTimers();
  };
  if (!voice.active) { go(); return; }
  // A previous session is still winding down. Start right away (while still inside the user's tap,
  // which iPhone requires) on a fresh recognizer; the old one is abandoned and its late events ignored.
  const old = voice.rec;
  voice.h = null; voice.rec = null; voice.active = false; clearTimeout(voice.watchdog);
  try { old.abort(); } catch { /* ignore */ }
  try {
    voice.h = handlers; voice.active = true;
    recognizer(true).start();
    armTimers();
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
  const SR = IS_IOS ? null : getSR();
  const e = existing ? { ...existing } : { type: 'expense', amount: null, categoryId: 'other', date: isoDate(new Date()), note: '', reduceDebt: true };
  const cats = live(state.categories).sort((a, b) => (a.order ?? 99) - (b.order ?? 99));
  const opt = (arr, sel, none) => (none ? `<option value="">${none}</option>` : '') + arr.map((x) => `<option value="${x.id}" ${x.id === sel ? 'selected' : ''}>${esc(x.name)}</option>`).join('');
  openSheet(`<h3>${existing ? 'Edit entry' : 'New entry'}</h3>
    ${existing ? '' : `<div class="voice-box"><textarea id="vText" rows="2" placeholder='Say or type: "spent 250 on groceries"'>${esc(text)}</textarea>
      <button type="button" class="mic-btn" id="vMic" aria-label="${SR ? 'Speak' : 'Dictate with the keyboard'}">${icon('mic', 26)}</button></div>
      <div class="hint" id="vHint">${SR ? 'Tap the mic and speak, or type. You can say several things: “250 groceries and 120 auto”.' : 'Tap the <b>mic key on your keyboard</b> (bottom right) and say e.g. “spent 250 on groceries”. Then check the details and tap Save.'}</div>
      <button type="button" class="btn block hidden" id="vKbd" style="margin:-4px 0 16px">${icon('keyboard', 18)} Use keyboard dictation</button>`}
    <div id="multi" class="hidden"></div>
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

  let drafts = [];
  const multi = $('#multi');
  const renderMulti = () => {
    const total = drafts.reduce((t, d) => t + (Number(d.amount) || 0), 0);
    multi.innerHTML = `<h2 class="eyebrow" style="margin:4px 0 10px">${drafts.length} items heard</h2>` + drafts.map((d, i) => `
      <div class="card" style="padding:14px;margin-bottom:10px">
        <div class="row">
          <div class="tile">${d.type === 'expense' ? catIcon(catById(d.categoryId), 20) : icon(d.type === 'income' ? 'arrowDL' : d.type === 'save' ? 'wallet' : 'trend', 20)}</div>
          <label class="f" style="flex:1;margin:0">Amount (₹)<input data-i="${i}" data-k="amount" type="number" inputmode="decimal" value="${d.amount ?? ''}"></label>
          <button type="button" class="icon-btn" data-rm="${i}" aria-label="Remove this item">${icon('x', 18)}</button>
        </div>
        ${d.type === 'expense' ? `<label class="f" style="margin:10px 0 0">Category<select data-i="${i}" data-k="categoryId">${opt(cats, d.categoryId)}</select></label>` : ''}
        <div class="faint" style="margin-top:8px">${esc(d.note || '')} · ${new Date(d.date + 'T00:00').toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}</div>
      </div>`).join('') + `<div class="btns"><button type="button" class="btn" id="mCancel">Cancel</button><button type="button" class="btn primary" id="mSave">Save all · ${inr(total)}</button></div>`;
    multi.querySelectorAll('[data-k]').forEach((el) => { el.onchange = el.oninput = () => { drafts[el.dataset.i][el.dataset.k] = el.value; if (el.dataset.k === 'amount') $('#mSave').textContent = `Save all · ${inr(drafts.reduce((t, d) => t + (Number(d.amount) || 0), 0))}`; }; });
    multi.querySelectorAll('[data-rm]').forEach((el) => { el.onclick = () => { drafts.splice(Number(el.dataset.rm), 1); if (drafts.length > 1) renderMulti(); else { showSingle(); } }; });
    $('#mCancel').onclick = closeSheet;
    $('#mSave').onclick = () => {
      const ids = [];
      commit(() => {
        for (const d of drafts) {
          const amount = Number(d.amount);
          if (!(amount > 0)) continue;
          const item = { id: uid(), createdAt: new Date().toISOString(), source: $('#vText')?.value || '', type: d.type, amount, date: d.date, note: d.note,
            categoryId: d.type === 'expense' ? d.categoryId : null, debtId: d.type === 'expense' && d.categoryId === 'debt' ? d.debtId : null,
            goalId: d.type === 'save' ? d.goalId : null, investmentId: d.type === 'invest' ? d.investmentId : null };
          item.applied = !!(item.debtId || item.goalId || item.investmentId);
          applyEffects(item, +1); upsert('entries', item); ids.push(item.id);
        }
      });
      if (!ids.length) { toast('Add an amount to at least one item'); return; }
      closeSheet();
      toast(`Saved ${ids.length} items · ${inr(drafts.reduce((t, d) => t + (Number(d.amount) || 0), 0))}`, () => undoEntries(ids));
    };
  };
  const showSingle = () => { multi.classList.add('hidden'); form.classList.remove('hidden'); };

  const applyParse = (txt) => {
    if (!txt.trim()) return;
    const many = parseMany(txt, parseCtx());
    if (many.length > 1) {
      drafts = many.map((m) => ({ amount: m.amount, type: m.type, categoryId: m.categoryId || 'other', debtId: m.debtId, goalId: m.goalId, investmentId: m.investmentId, date: m.date, note: m.note }));
      form.classList.add('hidden'); multi.classList.remove('hidden');
      renderMulti();
      $('#vHint').textContent = 'Check each item, then tap Save all.';
      return;
    }
    showSingle();
    const p = many[0];
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
      mic.classList.add('listening');
      const h = {
        audio: () => { $('#vHint').textContent = 'Listening… say e.g. "spent 250 on groceries"'; },
        result: (ev) => {
          h.gotResult = true;
          let interim = ''; let finalText = '';
          for (const r of ev.results) (r.isFinal ? (finalText += r[0].transcript) : (interim += r[0].transcript));
          vt.value = (finalText || interim).trim();
          applyParse(vt.value);
        },
        error: (code) => {
          $('#vKbd').classList.remove('hidden');
          $('#vHint').textContent = code === 'not-allowed' || code === 'service-not-allowed'
            ? (IS_IOS ? 'iPhone blocked voice here. Use keyboard dictation below, or allow Microphone and Speech Recognition for Safari in Settings.' : 'Microphone blocked. Allow it in settings, or use keyboard dictation below.')
            : code === 'no-audio' ? 'The mic didn’t start on this device. Use keyboard dictation below (tap it, then the mic key on the keyboard).'
              : code === 'no-speech' || code === 'no-result' ? "Didn't catch that. Tap the mic to try again, or use keyboard dictation."
                : code === 'start-failed' ? 'Voice could not start. Tap the mic again, or use keyboard dictation.'
                  : 'Voice error (' + code + '). Tap the mic to try again, or use keyboard dictation.';
        },
        end: () => mic.classList.remove('listening'),
      };
      $('#vHint').textContent = 'Starting the mic…';
      startVoice(h);
    };
    const dictate = () => { stopListening(); vt.focus(); $('#vHint').innerHTML = 'Now tap the <b>mic key on your keyboard</b> (bottom right) and speak.'; };
    mic.onclick = (ev) => { ev.preventDefault(); if (!SR) { dictate(); return; } if (mic.classList.contains('listening')) stopListening(); else startListening(); };
    $('#vKbd').onclick = dictate;
    // Focus must happen inside the user's tap, or iPhone won't open the keyboard.
    if (listen && SR) startListening(); else if (text) setTimeout(() => form.amount.focus(), 50); else vt.focus();
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
    const savedMsg = `Saved ${inr(amount)}${item.categoryId ? ' · ' + (catById(item.categoryId)?.name || '') : ''}`;
    if (existing) toast(savedMsg); else toast(savedMsg, () => undoEntries([item.id]));
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
  voice: () => openEntry(null, { listen: true }),
  goBudget: () => { tab = 'budget'; render(); window.scrollTo(0, 0); },
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
    if (!confirm('Erase all Kosh data on this device? (Your synced copy and backup files are not affected.)')) return;
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
    if (!data.categories || !data.entries) throw new Error('Not a Kosh backup');
    if (!confirm('Combine this backup with the data on this device? (The newest version of each item is kept.)')) return;
    commit(() => { state = merge(state, data); });
    toast('Backup restored');
  } catch (e) { toast('Restore failed: ' + e.message); }
}

init();
