# PennyWise API (Node.js + Supabase)

The backend for the PennyWise Flutter app. This guide explains **how it works**,
not just how to run it.

> Frontend (Flutter) docs: [../README.md](../README.md) · Social login setup: [../docs/SOCIAL_LOGIN.md](../docs/SOCIAL_LOGIN.md)

**Contents:** 1 Run · 2 Who does what · 3 Life of a request · 4 Security ·
5 Folder map · 6 Orchestration · 7 Endpoints · 8 Dashboard math · 9 E2E tests ·
10 Deploying · 11 Troubleshooting

---

## 1. Run it

**Easiest:** from the project root, `./scripts/dev.sh` starts this API (if it isn't
already running), waits until it's healthy, then runs the Flutter app with the
right `API_URL`. It stops the API again when you quit.

**By hand:**

```bash
cd backend
npm install
cp .env.example .env        # already filled with the project URL + publishable key
npm run dev                 # restarts automatically when you edit a file
```

Check it: open <http://localhost:3000/api/health> → `{"status":"ok"}`.

Then run the Flutter app:

| Where the app runs   | Command                                                      |
|----------------------|--------------------------------------------------------------|
| Chrome (Flutter web) | `flutter run -d chrome`  (uses `http://localhost:3000`; CORS allows any localhost port in development) |
| iOS simulator        | `flutter run`  (uses `http://localhost:3000`)                |
| Android emulator     | `flutter run`  (uses `http://10.0.2.2:3000`)                 |
| Real phone (same Wi-Fi) | `flutter run --dart-define=API_URL=http://<your-mac-ip>:3000` |

Find your Mac's IP with `ipconfig getifaddr en0`.

Tests:

```bash
npm test            # 40 unit + route tests, no network needed
npm run test:e2e    # full test against the real Supabase project (see §9)
```

---

## 2. Who does what

```
┌─────────────┐  1. log in (email / phone / Google…)   ┌────────────────────┐
│             │ ─────────────────────────────────────▶ │  Supabase Auth     │
│             │ ◀──── access token (JWT) + refresh ─── │                    │
│   Flutter   │                                        └────────────────────┘
│     app     │  2. REST calls + "Bearer <token>"      ┌────────────────────┐
│             │ ─────────────────────────────────────▶ │  Node.js API       │
│             │ ◀──────────── JSON ─────────────────── │  (this folder)     │
│             │                                        └─────────┬──────────┘
│             │  3. "something changed" (Realtime)                │ same token
│             │ ◀──────────────────────────────┐                 ▼
└─────────────┘                                │       ┌────────────────────┐
                                               └────── │ Supabase Postgres  │
                                                       │ + Storage (files)  │
                                                       │ + RLS policies     │
                                                       └────────────────────┘
```

| Supabase                                   | Node.js (this API)                                   |
|--------------------------------------------|------------------------------------------------------|
| **Database** – tables, constraints, triggers | **Custom REST API** – clean endpoints for the app    |
| **Authentication** – sign-up, login, tokens, email/SMS, OAuth | **Authentication logic** – verifies every token, attaches the user |
| **File Storage** – receipts, avatars        | **Transactions orchestration** – multi-step operations that must not leave half-done data |
| **Realtime** – pushes changes to the app    | Validation, friendly errors, statistics, rate limits |
| **Auto-generated APIs** (PostgREST) – what Node talks to | |

### Why login goes to Supabase directly, not through Node

Supabase's Flutter SDK already stores the session securely, **refreshes the token
automatically**, and handles deep links for email confirmation, password reset and
Google/Apple/Facebook. Re-building that in Node would add bugs, not remove them.
So the split is the standard production one:

* **Supabase Auth issues** the token.
* **Node verifies** the token on every request and decides what that user may do.

---

## 3. The life of one request

`POST /api/transactions` with `{ "type": "expense", "amount": "12.50", ... }`

```
app.js
 │ requestLogger   gives the request an id, logs "POST /api/transactions 201 34ms"
 │ helmet          adds security headers
 │ express.json    turns the body text into a JS object (max 100 KB)
 │ ipLimiter       max 300 requests/min per IP
 ▼
middleware/auth.js  requireAuth
 │   reads "Authorization: Bearer <token>"
 │   supabase.auth.getClaims(token)  → checks signature + expiry
 │   ✗ bad/expired → 401 { code: "invalid_token" }
 │   ✓ req.user = { id, email, ... }
 │     req.supabase = a Supabase client that acts AS this user
 ▼
middleware/rateLimit.js  userLimiter (120/min per user)
 ▼
routes/transactions.routes.js
 │   validate({ body: transactionSchemas.create })
 │   ✗ amount = -3 → 400 { code: "validation_failed", details: [...] }
 ▼
services/transactions.service.js  createTransaction()
 │   insert into transactions (NO user_id sent — the database fills it from the token)
 ▼
Supabase Postgres
 │   RLS policy: user_id must equal auth.uid()           ← security
 │   trigger: category type must match transaction type   ← data integrity
 ▼
response 201 { id, type, amount: 12.5, category: {...}, occurredOn, ... }
```

If anything throws, Express 5 sends the error to `middleware/errorHandler.js`,
which always answers in one shape:

```json
{ "error": { "code": "not_found", "message": "Transaction not found.", "requestId": "a1b2c3d4" } }
```

The app shows `message` to the user. `code` is for logic (e.g. `already_exists`).
`requestId` matches the server log line, so you can find any error quickly.

---

## 4. Security: three layers

1. **Token check (Node).** No valid Supabase token → nothing runs. Tokens are
   verified with Supabase's public signing keys (ES256), so this is fast and
   needs no extra network call per request.
2. **Row Level Security (Postgres).** Every table has policies like
   `using (auth.uid() = user_id)`. Node forwards the user's token, so even if
   the API had a bug, Postgres would still refuse to return another user's
   rows. *The tests prove user B gets 404 for user A's transaction.*
3. **Column grants (Postgres).** The app can only write the columns it should.
   `user_id`, `id` and timestamps are never writable, and a category's `type`
   can't change after creation.

Also:

* **No admin key needed.** The server runs with the *publishable* key + the
  user's token. The optional secret key is used **only** for "Delete account".
* Uploaded files are checked by their **bytes** (magic numbers), not by name or
  Content-Type, so a script renamed to `.jpg` is rejected.
* Raw database errors are never sent to the app (only logged on the server).

---

## 5. Folder map

```
backend/
├─ src/
│  ├─ server.js              starts the HTTP server, graceful shutdown
│  ├─ app.js                 middleware chain + routes (read this first)
│  ├─ config.js              env variables, fails fast if missing
│  ├─ middleware/
│  │  ├─ auth.js             ★ token verification (authentication logic)
│  │  ├─ validate.js         runs zod schemas, returns 400 with details
│  │  ├─ errorHandler.js     one JSON error format for everything
│  │  ├─ rateLimit.js        per-IP, per-user and upload limits
│  │  └─ requestLogger.js    request id + one log line per request
│  ├─ schemas/               zod rules: what a valid request looks like
│  ├─ routes/                URL → service function (thin, no logic)
│  ├─ services/              ★ the actual business logic
│  │  ├─ transactions.service.js   CRUD + receipt orchestration
│  │  ├─ categories.service.js     CRUD + transactional delete
│  │  ├─ budgets.service.js
│  │  ├─ stats.service.js          dashboard math
│  │  ├─ profile.service.js        profile + avatar
│  │  ├─ account.service.js        reset data / delete account
│  │  ├─ storage.service.js        Supabase Storage helpers
│  │  └─ mappers.js                snake_case (DB) ⇄ camelCase (API)
│  └─ lib/
│     ├─ supabase.js         creates the per-user Supabase client
│     ├─ errors.js           ApiError + Postgres error → HTTP status
│     ├─ money.js            sums in cents (no 0.1 + 0.2 bugs)
│     ├─ dates.js            "YYYY-MM-DD" helpers (no time-zone bugs)
│     └─ files.js            upload handling + file-type detection
├─ supabase/migrations/      the SQL that built the database (already applied)
└─ test/
   ├─ unit/                  fast tests with a fake Supabase
   └─ e2e/                   real tests against the live project
```

**Rule of thumb:** *routes* say **what** URL does something, *services* say
**how**, *schemas* say **what input is allowed**.

---

## 6. Transactions orchestration (what that means here)

Some actions touch several things and must never be left half-finished.

| Action | How it stays consistent |
|---|---|
| **Delete a category** (optionally moving its transactions) | One SQL function `delete_category()` → runs as a single database transaction: all of it happens or none of it. |
| **Reset all data** | SQL function `reset_my_data()` (one transaction), then Node deletes the receipt files it returned. |
| **Attach a receipt** | Storage and the database can't share a transaction, so each step undoes the last on failure: upload → update row (only if nobody else changed it — *optimistic lock*) → if that fails, delete the new file → delete the old file. |
| **Delete a transaction** | Delete the row, then its receipt file. |
| **Change avatar** | Upload → save URL → if saving fails, delete the upload → remove old photos. |

---

## 7. Endpoints

All need `Authorization: Bearer <token>` except `/api/health`.
Amounts are numbers or strings with ≤ 2 decimals; dates are `YYYY-MM-DD`.

| Method | Path | Body / query | Notes |
|---|---|---|---|
| GET | `/api/health` | | public |
| GET | `/api/auth/me` | | user + profile + enabled features |
| GET | `/api/profile` | | |
| PATCH | `/api/profile` | `fullName?, country?, gender?, currency?` | |
| PUT | `/api/profile/avatar` | multipart `file` (jpg/png/webp ≤ 2 MB) | |
| DELETE | `/api/profile/avatar` | | |
| GET | `/api/categories` | `?type=income\|expense` | |
| POST | `/api/categories` | `name, type, icon?, color?` | 409 if name exists |
| PATCH | `/api/categories/:id` | `name?, icon?, color?` | type can't change |
| DELETE | `/api/categories/:id` | `?reassignTo=<id>` | returns `affectedTransactions` |
| GET | `/api/transactions` | `from, to, type, categoryId (or "none"), q, limit (≤100), offset` | newest first, `{items,total,hasMore}` |
| GET | `/api/transactions/:id` | | |
| POST | `/api/transactions` | `type, amount, categoryId?, note?, occurredOn?` | |
| PATCH | `/api/transactions/:id` | any of the above | |
| DELETE | `/api/transactions/:id` | | also deletes receipt |
| PUT | `/api/transactions/:id/receipt` | multipart `file` (jpg/png/webp/heic/pdf ≤ 5 MB) | |
| GET | `/api/transactions/:id/receipt` | | `{url, expiresIn}` 5-minute link |
| DELETE | `/api/transactions/:id/receipt` | | |
| GET | `/api/budgets` | | |
| POST | `/api/budgets` | `categoryId (null = overall), amount` | expense categories only |
| PATCH | `/api/budgets/:id` | `amount` | |
| DELETE | `/api/budgets/:id` | | |
| GET | `/api/stats/summary` | `?month=YYYY-MM&today=YYYY-MM-DD` | dashboard numbers |
| POST | `/api/account/reset` | | wipe data, restore default categories |
| DELETE | `/api/account` | | needs `SUPABASE_SECRET_KEY` |

Try one with curl (get a token by logging in with the app, or via Supabase):

```bash
curl -H "Authorization: Bearer $TOKEN" "http://localhost:3000/api/stats/summary?month=2026-11"
```

---

## 8. The dashboard math (`stats.service.js`)

Kept deliberately simple:

```
balance          = income − expenses
savings rate     = (income − expenses) ÷ income × 100
vs last month    = (this month − last month) ÷ last month × 100
daily average    = expenses ÷ days passed this month
category share   = category total ÷ all expenses × 100
budget used      = spent ÷ limit × 100   → ok < 80% ≤ warning < 100% ≤ over
```

Money is added in **cents** (whole numbers) and converted back at the end, so
`0.10 + 0.20` is exactly `0.30`.

---

## 9. End-to-end tests (real Supabase)

`npm run test:e2e` runs ~15 scenarios against the live project with **two test
accounts**, including the isolation check (user B can't read/edit/delete user
A's data or use A's categories).

1. Create two accounts in Supabase Dashboard → Authentication → Users →
   *Add user* (tick "Auto confirm"). **Don't use your real account** — the test
   resets their data.
2. Add to `backend/.env`:
   ```
   E2E_EMAIL_A=test-a@yourmail.com
   E2E_PASSWORD_A=...
   E2E_EMAIL_B=test-b@yourmail.com
   E2E_PASSWORD_B=...
   ```
3. `npm run test:e2e`

---

## 10. Deploying

Any Node host works (Render, Railway, Fly.io, a VPS):

* Start command `npm start`, set the env variables from `.env.example`.
* Set `NODE_ENV=production` and `TRUST_PROXY=1` (they run behind a proxy).
* Build the app with the **https** URL:
  `flutter build apk --dart-define=API_URL=https://your-api.example.com`
* Optional: add `SUPABASE_SECRET_KEY` to enable "Delete account" (Apple and
  Google require account deletion for apps that have sign-up).

---

## 11. Troubleshooting

| What you see | Why | Fix |
|---|---|---|
| App: **"Cannot reach the server … Try again"** | This API isn't running, or the phone can't reach it (`localhost` on a real phone = the phone) | `npm run dev`, or `./scripts/dev.sh` from the root. On a real phone use your Mac's IP (the script does it for you). The app retries every 3 s, so it recovers on its own once the API is up. |
| `Missing required environment variable SUPABASE_URL` at start | No `.env` | `cp .env.example .env` |
| `EADDRINUSE :3000` | API already running (maybe in another terminal) | Reuse it, or `lsof -ti:3000 \| xargs kill` |
| App: "Authentication service is unavailable" (503) | This server can't reach Supabase to verify the token | Check the Mac's internet; check `SUPABASE_URL` |
| App: "Your session has expired" (401) | Token expired and refresh failed, or it belongs to another project | Log in again |
| Browser (Flutter web) blocked by CORS | Origin not allowed | Development: any `localhost` port is allowed. Production: set `CORS_ORIGINS` |

Quick check: <http://localhost:3000/api/health> must return `{"status":"ok"}`.
Every error response has a `requestId` that matches a line in the server log.

