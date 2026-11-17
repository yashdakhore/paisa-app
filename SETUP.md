# Kosh: install and sync guide

App address: **https://yashdakhore.github.io/paisa-app/**

Kosh is a web app you install from the browser. It works offline. It needs no app store, and the same app runs on your iPhone, Mac and Windows PC.

---

## 1. Install on the MacBook (Chrome)

1. Open **Google Chrome** and go to https://yashdakhore.github.io/paisa-app/
2. Click the **Install** icon at the right end of the address bar (a small screen with a down arrow). You can also open the **⋮** menu and choose **Cast, save and share → Install page as app…**.
3. Click **Install**. Kosh opens in its own window and appears in Launchpad and the Dock.
4. **First device only:** in Paisa, go to **More (Settings) → Restore from backup** and choose `paisa-starting-plan.json` from your **Downloads** folder. This loads your starting budget, debts, goals and SIP placeholder.
5. Click 🎤. Chrome asks to use the microphone. Click **Allow**.

> Safari works too: open the address, then **File → Add to Dock**.

## 2. Install on the iPhone (Safari)

1. Open **Safari** (it must be Safari) and go to https://yashdakhore.github.io/paisa-app/
2. Tap the **Share** button (the square with an arrow) → **Add to Home Screen** → **Add**.
3. Open **Kosh** from the Home Screen.
4. Go to **More → Sync → Sign in** (see section 4) and your data appears.

**Voice on iPhone:** tap the big 🎤. If iPhone doesn't start listening inside the home-screen app, tap the text box instead and press the **🎤 key on the keyboard** (iPhone's own dictation). Kosh reads what you say in the same way either way.

## 3. Install on the Windows PC (Edge or Chrome)

1. Open **Microsoft Edge** (or Chrome) and go to https://yashdakhore.github.io/paisa-app/
2. Edge: click the **App available / Install** icon in the address bar. You can also open **⋯ → Apps → Install Kosh**. Chrome: same as on the Mac.
3. Click **Install**. You can pin it to the taskbar and Start menu.
4. Go to **More → Sync → Sign in**.
5. Click 🎤 and allow the microphone.

---

## 4. Turn on automatic sync (one-time, about 10 minutes)

Sync uses **Supabase**, a free online database. You create your own free project, so your data sits in your own account and only your login can read it.

### On the Supabase website (do this once)
1. Go to **https://supabase.com** → **Start your project** → sign up. "Continue with GitHub" using your personal account is easiest.
2. Click **New project**: name it `paisa`, pick a strong database password (save it in your password manager; Kosh never needs it), choose region **Mumbai**, and stay on the **Free** plan. Click **Create**. Wait about 2 minutes.
3. In the left menu open **SQL Editor** → **New query**. Paste this code and click **Run**:

   ```sql
   create table if not exists finance_docs (
     user_id uuid primary key references auth.users on delete cascade default auth.uid(),
     data jsonb not null,
     updated_at timestamptz not null default now()
   );
   alter table finance_docs enable row level security;
   create policy "own row" on finance_docs for all
     using (auth.uid() = user_id) with check (auth.uid() = user_id);
   ```
   You should see "Success. No rows returned".
4. Optional, but saves a step: open **Authentication → Sign In / Providers → Email** and turn **off** "Confirm email". Then click **Save**.
5. Open **Project Settings → API Keys** (or **Data API**) and copy two values:
   - the **Project URL** (looks like `https://abcd1234.supabase.co`)
   - the **publishable** key (also called the **anon public** key). Do **not** use the `service_role` / secret key.

### In Kosh (do this on each device)
1. **More → Sync between devices → Set up sync**. Paste the **Project URL** and the **publishable key**, then tap **Save**.
2. **First device (the Mac):** type your email and choose a new password just for Kosh, then tap **Create login**. If you left "Confirm email" on, click the link in the email, come back, and tap **Sign in**.
3. **Other devices:** enter the same email and password and tap **Sign in**.
4. The small dot at the top right turns **green** when the device is synced. Changes sync automatically when you save something and when you open the app.

> **Tip:** The free Supabase plan pauses a project after about a week with no use. If sync stops working, sign in at supabase.com and click **Restore project**. Your data is kept.

---

## 5. Backups (recommended monthly)

**More → Backup file** saves everything as one `.json` file. Keep it in iCloud Drive or Google Drive. **More (Settings) → Restore from backup** loads it on any device. A restore merges with what's already there: the newest version of each item wins, so nothing is lost. **Entries as CSV** opens in Excel or Google Sheets.

## 6. Privacy

- Kosh never asks for card numbers, bank account numbers or your PAN. Don't put them in notes.
- Your entries are kept in the browser on each device and, if you turn on sync, in your own Supabase project.
- **Voice:** Kosh itself uses no AI and sends your words nowhere. The browser turns speech into text: Chrome sends audio to Google, Edge to Microsoft, and iPhone dictation to Apple. If you'd rather avoid that, type the entry instead.

## 7. Updating the app

When the app is updated on GitHub, each device picks up the new version the next time it opens with internet. Close the app and open it again if needed.
