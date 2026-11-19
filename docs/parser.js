// Rule-based parser for spoken/typed entries like "spent 250 on groceries yesterday".
// Pure functions, no DOM — shared by the app and the Node tests.

export const DEFAULT_KEYWORDS = {
  rent: ['rent', 'house rent', 'room rent', 'landlord', 'pg', 'kiraya', 'kiraaya', 'bhada'],
  bills: ['electricity', 'electric', 'light bill', 'current bill', 'power bill', 'bill', 'water bill', 'gas', 'cylinder', 'lpg', 'maintenance', 'bijli', 'bijlee', 'paani', 'pani'],
  groceries: ['grocery', 'groceries', 'vegetables', 'veggies', 'sabzi', 'fruits', 'milk', 'kirana', 'dmart', 'd mart', 'blinkit', 'zepto', 'bigbasket', 'big basket', 'instamart', 'ration', 'eggs', 'bread', 'sabji', 'doodh', 'dudh', 'anda', 'ande', 'atta', 'chawal', 'dal', 'tarkari', 'fal', 'kirana store'],
  food: ['food', 'lunch', 'dinner', 'breakfast', 'snacks', 'tea', 'chai', 'coffee', 'swiggy', 'zomato', 'restaurant', 'cafe', 'pizza', 'burger', 'biryani', 'dining', 'eating out', 'canteen', 'mess', 'tiffin', 'khana', 'nashta', 'samosa', 'thali', 'dhaba', 'chaat', 'eternal', 'pan shop', 'paan', 'dominos', 'mcdonalds', 'kfc'],
  transport: ['uber', 'ola', 'rapido', 'auto', 'rickshaw', 'cab', 'taxi', 'bus', 'metro', 'train', 'petrol', 'diesel', 'fuel', 'parking', 'toll', 'travel', 'flight', 'ticket', 'tickets', 'gaadi', 'bike', 'iocl', 'hpcl', 'bpcl', 'indian oil', 'bharat petroleum', 'hindustan petroleum', 'petrol pump', 'fuel station', 'fastag'],
  phone: ['recharge', 'mobile', 'phone', 'jio', 'airtel', 'vodafone', 'internet', 'wifi', 'wi-fi', 'broadband', 'data pack'],
  shopping: ['shopping', 'clothes', 'shoes', 'amazon', 'flipkart', 'myntra', 'meesho', 'ajio', 'shirt', 'dress', 'gadget', 'kapde', 'kapda', 'joote'],
  health: ['medicine', 'medicines', 'doctor', 'pharmacy', 'chemist', 'hospital', 'medical', 'clinic', 'gym', 'tablets', 'apollo', 'pharmeasy', 'dawai', 'dawa', 'davai', 'dava'],
  entertainment: ['movie', 'movies', 'netflix', 'prime', 'hotstar', 'spotify', 'youtube premium', 'game', 'games', 'outing', 'party', 'concert', 'subscription', 'picture'],
  debt: ['credit card', 'card bill', 'card payment', 'card', 'sbi card', 'emi', 'loan', 'mpokket', 'repay', 'repaid', 'repayment'],
  other: [],
};

const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
const MONTH_RE = '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
const DAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

const ONES = { zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19 };
const TENS = { twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90 };
const SCALES = { hundred: 100, thousand: 1000, lakh: 100000, lakhs: 100000, lac: 100000, sau: 100, hazaar: 1000, hazar: 1000, hajar: 1000 };

const FILLER = new Set(['spent', 'spend', 'spending', 'paid', 'pay', 'paying', 'bought', 'buy', 'gave', 'give', 'for', 'on', 'at', 'in', 'to', 'of', 'rupees', 'rupee', 'rs', 'inr', 'bucks', 'the', 'a', 'an', 'i', 'my', 'just', 'and', 'towards', 'toward', 'worth', 'got', 'ordered', 'from', 'today', 'yesterday', 'received', 'invested', 'invest', 'saved', 'save', 'put', 'added', 'add', 'into', 'with', 'by', 'was', 'is', 'me', 'ke', 'liye', 'pe', 'par', 'mein', 'ka', 'ki', 'ko', 'se', 'diye', 'diya', 'kharcha', 'kharch', 'kiya', 'kiye', 'rupaye', 'rupay', 'rupiya', 'hai', 'tha', 'aaj', 'kal', 'parso', 'parson', 'wala', 'wale']);

export function pad(n) { return String(n).padStart(2, '0'); }
export function isoDate(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }
function addDays(d, n) { const x = new Date(d.getFullYear(), d.getMonth(), d.getDate()); x.setDate(x.getDate() + n); return x; }
function monthIndex(s) { return MONTHS.findIndex((m) => m.startsWith(s.slice(0, 3))); }

// "two hundred fifty" -> "250", "five thousand" -> "5000", "a hundred" -> "100"
export function wordsToDigits(text) {
  const tokens = text.split(/(\s+|-)/);
  const out = [];
  let run = null; // {total, current}
  let pending = []; // whitespace/hyphen tokens inside a run
  const flush = () => {
    if (run) { out.push(String(run.total + run.current)); run = null; }
    out.push(...pending); pending = [];
  };
  for (let i = 0; i < tokens.length; i++) {
    const raw = tokens[i];
    const t = raw.toLowerCase();
    if (/^(\s+|-)$/.test(raw)) { if (run) pending.push(raw); else out.push(raw); continue; }
    const nextWord = (tokens[i + 2] || '').toLowerCase();
    if (t === 'a' && !run && SCALES[nextWord] && nextWord !== 'lakhs') { run = { total: 0, current: 1 }; continue; }
    if (t === 'and' && run) { pending.push(raw); continue; }
    let v = null;
    if (t in ONES) v = ['o', ONES[t]];
    else if (t in TENS) v = ['o', TENS[t]];
    else if (t in SCALES) v = ['s', SCALES[t]];
    else if (/^\d+(\.\d+)?$/.test(t) && SCALES[nextWord] && !run) { run = { total: 0, current: parseFloat(t) }; continue; }
    if (v === null) { flush(); out.push(raw); continue; }
    pending = [];
    if (!run) run = { total: 0, current: 0 };
    if (v[0] === 'o') run.current += v[1];
    else if (v[1] === 100) run.current = (run.current || 1) * 100;
    else { run.total += (run.current || 1) * v[1]; run.current = 0; }
  }
  flush();
  return out.join('');
}

function extractDate(text, now) {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const tries = [
    [/\bday before yesterday\b/, () => addDays(today, -2)],
    [/\bparson?\b/, () => addDays(today, -2)],
    [/\bkal\b/, () => addDays(today, -1)],
    [/\baaj\b/, () => today],
    [/\byesterday\b/, () => addDays(today, -1)],
    [/\b(today|tonight|this morning|this evening)\b/, () => today],
    [/\b(\d{1,2}) days? ago\b/, (m) => addDays(today, -parseInt(m[1], 10))],
    [/\blast week\b/, () => addDays(today, -7)],
    [new RegExp(`\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?${MONTH_RE}\\b`), (m) => fromDayMonth(today, parseInt(m[1], 10), monthIndex(m[2]))],
    [new RegExp(`\\b(?:on\\s+)?${MONTH_RE}\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b`), (m) => fromDayMonth(today, parseInt(m[2], 10), monthIndex(m[1]))],
    [/\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b/, (m) => {
      let y = m[3] ? parseInt(m[3], 10) : null; if (y !== null && y < 100) y += 2000;
      const d = new Date(y ?? today.getFullYear(), parseInt(m[2], 10) - 1, parseInt(m[1], 10));
      if (y === null && d > today) d.setFullYear(d.getFullYear() - 1);
      return d;
    }],
    [new RegExp(`\\b(last\\s+|on\\s+|this\\s+)?(${DAYS.join('|')})\\b`), (m) => {
      const target = DAYS.indexOf(m[2]);
      let diff = (today.getDay() - target + 7) % 7;
      if (diff === 0 && m[1] && m[1].trim() === 'last') diff = 7;
      return addDays(today, -diff);
    }],
    [/\bon (?:the )?(\d{1,2})(?:st|nd|rd|th)\b/, (m) => {
      const d = new Date(today.getFullYear(), today.getMonth(), parseInt(m[1], 10));
      if (d > today) d.setMonth(d.getMonth() - 1);
      return d;
    }],
  ];
  for (const [re, fn] of tries) {
    const m = text.match(re);
    if (m) {
      const d = fn(m);
      if (d && !isNaN(d)) return { date: isoDate(d), rest: text.replace(m[0], ' '), found: true };
    }
  }
  return { date: isoDate(today), rest: text, found: false };
}

function fromDayMonth(today, day, month) {
  if (month < 0) return null;
  const d = new Date(today.getFullYear(), month, day);
  if (d > today) d.setFullYear(d.getFullYear() - 1);
  return d;
}

function extractAmount(text) {
  const re = /(₹|\brs\.?|\binr)?\s*(\d+(?:\.\d+)?)\s*(k\b|thousand\b|lakhs?\b|lac\b|hundred\b)?\s*(rupees?\b|rupaye\b|rupay\b|rupiya\b|rs\b|bucks\b|\/-)?/g;
  const cands = [];
  let m;
  while ((m = re.exec(text))) {
    let v = parseFloat(m[2]);
    const mult = (m[3] || '').toLowerCase();
    if (mult === 'k' || mult === 'thousand') v *= 1000;
    else if (mult.startsWith('lakh') || mult === 'lac') v *= 100000;
    else if (mult === 'hundred') v *= 100;
    cands.push({ v, marked: !!(m[1] || m[4]), idx: m.index, len: m[0].length });
  }
  if (!cands.length) return { amount: null, rest: text };
  const pick = cands.find((c) => c.marked) || cands.reduce((a, b) => (b.v > a.v ? b : a));
  return { amount: Math.round(pick.v * 100) / 100, rest: text.slice(0, pick.idx) + ' ' + text.slice(pick.idx + pick.len) };
}

function detectType(t) {
  if (/\b(salary|received|income|got paid|credited|bonus|refund)\b/.test(t)) return 'income';
  if (/\b(invest(ed)?|sip|mutual fund|fd|fixed deposit|stocks?|shares|ppf|nps|gold)\b/.test(t)) return 'invest';
  if (/\b(saved|save|emergency fund|savings)\b/.test(t)) return 'save';
  return 'expense';
}

function escapeRe(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

// Return the item whose keywords/name give the longest match in text.
export function bestMatch(text, items, getWords) {
  let best = null; let bestLen = 0;
  for (const it of items) {
    for (const w of getWords(it)) {
      const word = (w || '').toLowerCase().trim();
      if (!word) continue;
      if (new RegExp(`(^|[^a-z0-9])${escapeRe(word)}s?($|[^a-z0-9])`).test(text) && word.length > bestLen) {
        best = it; bestLen = word.length;
      }
    }
  }
  return best;
}

/**
 * Parse an entry.
 * ctx: { categories:[{id,name,keywords}], debts:[{id,name}], goals:[{id,name}], investments:[{id,name,type}] }
 */
export function parseEntry(input, ctx = {}, now = new Date()) {
  const original = (input || '').trim();
  let t = ' ' + original.toLowerCase().replace(/(\d),(?=\d)/g, '$1').replace(/[!?]/g, ' ') + ' ';
  t = wordsToDigits(t);
  const type = detectType(t);

  const d = extractDate(t, now);
  const a = extractAmount(d.rest);
  const rest = a.rest;

  const cats = ctx.categories || [];
  const nameWords = (x) => [x.name, ...(x.name || '').split(/[^a-zA-Z]+/).filter((w) => w.length > 3)];
  const cat = bestMatch(rest, cats, (c) => [...(c.keywords || []), ...(DEFAULT_KEYWORDS[c.id] || []), ...nameWords(c)]);
  const debt = bestMatch(rest, ctx.debts || [], (x) => nameWords(x).concat(x.keywords || []));
  const goal = bestMatch(rest, ctx.goals || [], (x) => nameWords(x));
  const inv = bestMatch(rest, ctx.investments || [], (x) => nameWords(x).concat([x.type || '']));

  let categoryId = cat ? cat.id : null;
  if (!categoryId && debt && cats.some((c) => c.id === 'debt')) categoryId = 'debt';
  if (!categoryId && type === 'expense') categoryId = cats.some((c) => c.id === 'other') ? 'other' : null;

  const noteWords = rest.split(/[^a-z0-9₹'&-]+/i).filter((w) => w && !FILLER.has(w) && !/^\d+$/.test(w) && w !== '₹' && w !== '-');
  let note = noteWords.join(' ').trim();
  if (note) note = note.charAt(0).toUpperCase() + note.slice(1);

  return {
    type,
    amount: a.amount,
    categoryId,
    debtId: debt ? debt.id : null,
    goalId: goal ? goal.id : null,
    investmentId: inv ? inv.id : null,
    date: d.date,
    note,
    sure: { amount: a.amount !== null, category: !!cat, date: d.found },
    text: original,
  };
}

// Several items in one sentence: "250 groceries and 120 auto yesterday".
// A piece only counts as its own item if it still has a number once dates are taken out.
export function splitItems(input, now = new Date()) {
  let t = ' ' + (input || '').trim().toLowerCase().replace(/(\d),(?=\d)/g, '$1') + ' ';
  t = wordsToDigits(t);
  const hasAmount = (seg) => /\d/.test(extractDate(' ' + seg + ' ', now).rest);
  const groups = [];
  for (const raw of t.split(/\s*(?:,|;|&|\band\b|\bplus\b|\baur\b|\bthen\b)\s*/)) {
    const seg = raw.trim();
    if (!seg) continue;
    if (hasAmount(seg) || !groups.length) groups.push(seg); else groups[groups.length - 1] += ' ' + seg;
  }
  if (groups.length > 1 && !hasAmount(groups[0])) { groups[1] = groups[0] + ' ' + groups[1]; groups.shift(); }
  return groups.length ? groups : [input];
}

export function parseMany(input, ctx = {}, now = new Date()) {
  const parts = splitItems(input, now);
  if (parts.length <= 1) return [parseEntry(input, ctx, now)];
  const rs = parts.map((p) => parseEntry(p, ctx, now));
  const dated = rs.find((r) => r.sure.date);
  if (dated) for (const r of rs) if (!r.sure.date) r.date = dated.date;
  return rs;
}
