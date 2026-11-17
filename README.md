# Paisa

A small personal-finance web app (installable PWA) for one person, with amounts in ₹. It has:

- **Voice or typed entry:** "spent 250 on groceries yesterday" or "paid 5000 to SBI card" is read into amount, category, date and note. You confirm before it saves. Simple built-in rules do the reading, so no AI service is involved.
- **Monthly budget** per category, with spending against each.
- **Goals** (saving up, paying off a debt, bringing card usage under a %), showing what's needed each month and progress so far.
- **Debts and EMIs**, including credit card usage.
- **Investments** (SIP, mutual fund, FD, PPF, stocks and more), with monthly contribution, amount invested, current value and gain.
- **Dashboard and monthly plan:** where the money went, what's left, and what to put toward each goal next.
- Works offline. Optional sync through your own free Supabase project. JSON backup and restore, and CSV export.

The app is plain HTML, CSS and JavaScript in `docs/`. There's no build step, and GitHub Pages serves it from `docs/`.

- Install and sync steps: see [SETUP.md](SETUP.md)
- Tests: `node --test tests/`
- Run locally: `python3 -m http.server 8777 --directory docs`, then open http://localhost:8777
