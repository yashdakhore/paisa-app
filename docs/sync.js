// Optional sync through Supabase (free tier). The whole data set is one JSON row per user,
// protected by row-level security so only the signed-in user can read or write it.
import { merge } from './store.js';

const CFG_KEY = 'paisa.sync';
const SUPABASE_JS = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
let client = null;

export function getConfig() {
  try { return JSON.parse(localStorage.getItem(CFG_KEY)) || {}; } catch { return {}; }
}
export function setConfig(cfg) { localStorage.setItem(CFG_KEY, JSON.stringify(cfg)); client = null; }
export function isConfigured() { const c = getConfig(); return !!(c.url && c.key); }

async function getClient() {
  if (client) return client;
  const { url, key } = getConfig();
  if (!url || !key) throw new Error('Sync is not set up');
  const { createClient } = await import(SUPABASE_JS);
  client = createClient(url.trim(), key.trim(), { auth: { persistSession: true, storageKey: 'paisa.auth' } });
  return client;
}

export async function currentUser() {
  if (!isConfigured()) return null;
  const c = await getClient();
  const { data } = await c.auth.getSession();
  return data.session?.user || null;
}

export async function signUp(email, password) {
  const c = await getClient();
  const { data, error } = await c.auth.signUp({ email, password });
  if (error) throw error;
  return data;
}
export async function signIn(email, password) {
  const c = await getClient();
  const { data, error } = await c.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data.user;
}
export async function signOut() { const c = await getClient(); await c.auth.signOut(); }

// Pull remote, merge with local, push the merged copy back. Returns the merged state.
export async function syncNow(localState) {
  const c = await getClient();
  const user = await currentUser();
  if (!user) throw new Error('Not signed in');
  const { data, error } = await c.from('finance_docs').select('data').eq('user_id', user.id).maybeSingle();
  if (error) throw error;
  const merged = merge(localState, data?.data || null);
  const { error: e2 } = await c.from('finance_docs').upsert({ user_id: user.id, data: merged, updated_at: new Date().toISOString() });
  if (e2) throw e2;
  return merged;
}

export const SETUP_SQL = `create table if not exists finance_docs (
  user_id uuid primary key references auth.users on delete cascade default auth.uid(),
  data jsonb not null,
  updated_at timestamptz not null default now()
);
alter table finance_docs enable row level security;
create policy "own row" on finance_docs for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);`;
