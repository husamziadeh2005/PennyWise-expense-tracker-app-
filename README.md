# PennyWise – Expense Tracker

A personal expense tracker: a **Flutter** app, a **Node.js** REST API, and **Supabase**
(database, auth, file storage, realtime).

This file documents the **Flutter app (frontend)** and how the three parts fit together.
The API has its own guide: **[backend/README.md](backend/README.md)**.

| Part | Folder | Docs |
|---|---|---|
| Mobile / desktop app (Flutter) | `lib/` | this file |
| REST API (Node.js + Express) | `backend/` | [backend/README.md](backend/README.md) |
| Database schema (Supabase SQL) | `backend/supabase/migrations/` | already applied to the project |
| Google / Apple / Facebook login setup | `docs/` | [docs/SOCIAL_LOGIN.md](docs/SOCIAL_LOGIN.md) |

---

## 1. Quick start

```bash
./scripts/dev.sh              # starts the API (if needed) + runs the app; asks which device
./scripts/dev.sh -d macos     # any `flutter run` argument works
./scripts/dev.sh -d <iphone>  # real phone: API_URL is set to your Mac's Wi-Fi IP automatically
```

`flutter devices` lists the device ids. Requirements: Flutter (Dart ≥ 3.11), Node.js ≥ 20.6.

Prefer two terminals? That works too:

```bash
cd backend && npm install && npm run dev     # terminal 1 – API on http://localhost:3000
flutter run                                   # terminal 2 – the app
```

---

## 2. Why do I get "Cannot reach the server … Try again"?

**The app cannot work without the Node.js API.** After login, the very first thing
the app does is load your profile and categories from `http://localhost:3000/api/…`.
If nothing answers, you get the `Try again` screen. There are three usual causes:

| Cause | How to recognise it | Fix |
|---|---|---|
| **The API isn't running.** Pressing ▶ Run in the IDE (or `flutter run`) starts **only** the app, never the server. This is the usual cause. | `curl localhost:3000/api/health` fails | Use `./scripts/dev.sh`, or run `cd backend && npm run dev` first |
| **Real phone + `localhost`.** On a phone, `localhost` means *the phone itself*, not your Mac. | Works in the simulator, fails on the iPhone | `./scripts/dev.sh -d <iphone>` passes `API_URL=http://<mac-ip>:3000` for you. The phone must be on the same Wi-Fi. |
| **Wrong / old `API_URL`.** Your Mac's IP changed (new Wi-Fi). | The debug box on the error screen shows the URL | Run again via the script, which reads the current IP |

What the app does about it now:

* **Auto-recovery.** While the server is unreachable the app retries every 3 seconds
  (`AppState.retryEvery`). Start the API and the app continues by itself, with no tap
  needed. Real server errors (500 etc.) are *not* retried in a loop.
* **Debug hint.** In debug builds the error screen shows the API URL it tried and
  the command to start it.

**The permanent fix for real users** is to deploy the API to a host (Render,
Railway, Fly.io…) and build the app with its `https://` URL
(`--dart-define=API_URL=https://…`). Then the app no longer depends on your laptop
being on. See *Deploying* in [backend/README.md](backend/README.md#10-deploying).

### Running from Android Studio / IntelliJ / VS Code

The IDE's ▶ button doesn't start the API. Either keep `npm run dev` running in a
terminal, or for a real phone add this to the run configuration's
*Additional run args*:

```
--dart-define=API_URL=http://<your-mac-ip>:3000
```

(`ipconfig getifaddr en0` prints the IP.)

---

## 3. How the pieces talk to each other

```
                ┌──────────────────────── Flutter app (lib/) ───────────────────────┐
                │                                                                    │
  login/signup  │  features/auth/auth_service.dart ──────────────▶ Supabase Auth     │
  Google/Apple/ │     (supabase_flutter SDK: stores + refreshes the session)          │
  Facebook      │                         │ access token (JWT)                       │
                │                         ▼                                          │
  all data      │  core/network/api_client.dart ── HTTPS + "Bearer <JWT>" ──▶ Node API│──▶ Supabase Postgres
                │     ▲  adds token, refreshes on 401, turns errors into text        │    (RLS: only your rows)
                │  data/api/expense_api.dart  (one function per endpoint)            │    + Storage (receipts,
                │     ▲                                                              │      avatars)
                │  state/app_state.dart  ◀──── Realtime "row changed" ───────────────│◀── Supabase Realtime
                │     ▲  profile, categories, dataVersion                            │
                │  features/*/…_page.dart  (screens)                                 │
                └────────────────────────────────────────────────────────────────────┘
```

1. **Login goes straight to Supabase Auth** (email, phone, Google, Apple, Facebook).
   The SDK keeps the session on the device and refreshes the token by itself.
2. **Every data request goes to the Node API** with `Authorization: Bearer <token>`.
   The API verifies the token and queries Postgres *as that user*, so Row Level
   Security guarantees nobody sees anyone else's data.
3. **Realtime**: the app subscribes to changes on its own rows. Something changed
   on another phone → `AppState.dataVersion++` → open screens reload.

The reasons for this split (why login doesn't go through Node, and so on) are
explained in [backend/README.md §2](backend/README.md#2-who-does-what).

---

## 4. Folder structure (`lib/`)

```
lib/
├─ main.dart                      entry point: init Supabase, load theme, runApp
├─ app.dart                       PennyWiseApp: MaterialApp, themes, AuthGate as home
│
├─ core/                          shared by every feature, knows no screens
│  ├─ config/
│  │  ├─ api_config.dart          ★ API URL (API_URL dart-define, emulator defaults)
│  │  └─ supabase_config.dart     Supabase URL, publishable key, deep-link redirect
│  ├─ network/
│  │  └─ api_client.dart          ★ HTTP client: token, retry on 401, ApiException
│  ├─ theme/
│  │  └─ app_theme.dart           Material 3 theme (light + dark)
│  └─ widgets/
│     └─ common.dart              money/date formatting, ErrorView, EmptyView, cards…
│
├─ data/                          talking to the API
│  ├─ api/expense_api.dart        typed functions: transactions(), createBudget()…
│  └─ models/models.dart          Transaction, Category, Budget, Profile, MonthlySummary
│
├─ state/
│  └─ app_state.dart              app-wide state (ChangeNotifier) + realtime + auto-retry
│                                 ThemeController (light/dark/system, saved on device)
│
└─ features/                      one folder per area of the app
   ├─ auth/
   │  ├─ auth_service.dart        ★ all Supabase Auth calls + friendly error messages
   │  ├─ auth_validators.dart     email / phone (E.164) / password rules
   │  ├─ auth_gate.dart           picks the screen: login · verify · reset · home
   │  ├─ login_page.dart          login + social buttons
   │  ├─ sign_up_page.dart        create account
   │  └─ auth_pages.dart          verify email, verify phone (OTP), reset password
   ├─ home/main_shell.dart        bottom navigation, first data load, error screen
   ├─ dashboard/                  monthly summary, charts, budgets at a glance
   ├─ transactions/               list (paged, grouped by day) + add/edit form
   ├─ budgets/                    monthly limits per category
   ├─ categories/                 manage income / expense categories
   └─ settings/                   profile, avatar, currency, theme, reset, delete account
```

**Rules of thumb**

* **Screens never call `http` or Supabase tables directly.** They call
  `ExpenseApi` (data) or `AuthService` (auth) and show the result.
* **`core/` must not import from `features/`.** Features may use `core/`, `data/`
  and `state/`.
* Imports use the `package:expense_tracker/…` form, so moving a file means
  updating only its import paths.
* A new screen goes in `features/<area>/<name>_page.dart`.

---

## 5. Life of a screen load (example: Dashboard)

```
DashboardPage.initState
  → ExpenseApi.summary(month)                       data/api/expense_api.dart
    → ApiClient.get('/stats/summary?month=…')       core/network/api_client.dart
      → token = Supabase session (refreshed if expired)
      → GET http://localhost:3000/api/stats/summary  (Bearer token)
      ← 200 JSON  → MonthlySummary.fromJson          data/models/models.dart
      ← 401       → refresh token once, retry; still 401 → sign out → login screen
      ← no server → ApiException("Cannot reach the server…") → ErrorView + Try again
  → setState → charts render
```

---

## 6. Configuration

| Setting | Where | Default |
|---|---|---|
| API URL | `--dart-define=API_URL=…` (see `core/config/api_config.dart`) | Android emulator `http://10.0.2.2:3000`, everything else `http://localhost:3000` |
| Supabase project | `core/config/supabase_config.dart` | PennyWise project (publishable key is safe in the app; RLS protects data) |
| Auth deep link | `io.supabase.pennywise://login-callback/` | registered in iOS/macOS `Info.plist` and `AndroidManifest.xml` |

Platform notes:

* **iOS**: `NSAllowsLocalNetworking` in `Info.plist` allows plain `http://` to your Mac
  during development. The release build must use `https://`.
* **Android**: cleartext `http://` is allowed only in the **debug** manifest.
* **macOS**: the sandbox has `network.client` enabled.

---

## 7. Social login (Google · Apple · Facebook)

The buttons and the code are complete. **Each provider must be switched on in
Supabase** with credentials from Google, Apple and Meta. Until then the app says
*"Google sign-in is turned off in Supabase"* (debug) or *"not available yet"*
(release), and never opens a broken browser page.

Step-by-step setup: **[docs/SOCIAL_LOGIN.md](docs/SOCIAL_LOGIN.md)**.

How it works in code (`features/auth/auth_service.dart`):

* **Apple on iPhone** uses the native Apple sheet → Apple identity token → `signInWithIdToken`.
* **Google, Facebook (and Apple on Android/macOS/web)** open the provider's page in the
  browser → provider redirects to Supabase → Supabase redirects to
  `io.supabase.pennywise://login-callback/` → the app receives the session →
  `AuthGate` shows the home screen.
* Before opening anything, the app asks Supabase (`/auth/v1/settings`) whether
  that provider is enabled.

---

## 8. Tests

```bash
flutter test                    # models, validators, auto-retry, every screen at 2 phone sizes
flutter analyze                 # lints (should print "No issues found!")
cd backend && npm test          # API unit + route tests
cd backend && npm run test:e2e  # live tests against Supabase (see backend README §9)
```

---

## 9. Repository layout

```
expense_tracker/
├─ lib/            Flutter source (above)
├─ test/           Flutter tests
├─ assets/         images / animations used by the app
├─ backend/        Node.js API + Supabase migrations  →  backend/README.md
├─ docs/           extra guides (social login setup)
├─ scripts/dev.sh  one-command local development
├─ android/ ios/ macos/ web/ windows/ linux/   platform projects (generated by Flutter)
└─ pubspec.yaml    Flutter dependencies
```
