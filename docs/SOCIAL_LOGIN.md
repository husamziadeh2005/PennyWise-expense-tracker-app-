# Enabling Google, Facebook and Apple sign-in

The app side is finished: buttons, deep links, error handling. What's missing is
the **provider credentials**. Each company (Google, Meta, Apple) has to issue
them to *your* developer account, and then you paste them into Supabase.

Check the current state at any time:

```bash
curl -s -H "apikey: <publishable key>" \
  https://dwvqxftefejqxcopbvfz.supabase.co/auth/v1/settings | grep -E '"(google|apple|facebook)"'
```

(The publishable key is in `lib/core/config/supabase_config.dart`.) `true` means
the provider is switched on.

## Values you will need

| Name | Value |
|---|---|
| **Supabase callback URL** (paste into Google / Meta / Apple) | `https://dwvqxftefejqxcopbvfz.supabase.co/auth/v1/callback` |
| **App redirect URL** (paste into Supabase) | `io.supabase.pennywise://login-callback/` |
| iOS / macOS bundle id | `com.example.expenseTracker`, see the Apple note below |
| Android package | `com.example.expense_tracker` |

## How the app reacts (no code change needed)

The login page asks Supabase which providers are switched on when it opens and
every time the app returns to the foreground:

| Provider in Supabase | Debug build | Release build |
|---|---|---|
| **On** | normal button → real sign-in | normal button → real sign-in |
| **Off** | dimmed button; tapping says what to enable | hidden |
| All off | dimmed buttons | the whole "OR CONTINUE WITH" section is hidden |

So: enable a provider in the dashboard, switch back to the app, and its button
works. Nothing needs rebuilding.

## Step 0: Supabase redirect URLs (once, for all providers)

Supabase Dashboard → **Authentication → URL Configuration → Redirect URLs** → add:

| URL | Needed for |
|---|---|
| `io.supabase.pennywise://login-callback/` | iPhone, Android, macOS app |
| `http://localhost:5000/**` | Flutter web in Chrome (`./scripts/dev.sh -d chrome` always uses port 5000) |

Without this, Supabase refuses to send the user back to the app after login.
On web the app returns to the page it is running on, not the deep link, because
a browser can't open an app link.

---

## Google (free, ~10 min)

1. <https://console.cloud.google.com> → create/select a project.
2. **APIs & Services → OAuth consent screen**: choose *External*, set the app name,
   support email and developer email, then save. Add yourself as a *Test user*
   while the app is in "Testing".
3. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   * Application type: **Web application** (yes, Web, even for the mobile app,
     because the browser flow goes through Supabase)
   * Authorised redirect URIs: the **Supabase callback URL**
4. Copy the **Client ID** and **Client secret**.
5. Switch Google on in Supabase, either:
   * **with the script** (also adds the Redirect URLs from Step 0 for you):
     ```bash
     node scripts/google-login.mjs enable
     ```
     It asks for the Client ID, the secret and a Supabase access token
     (create one at <https://supabase.com/dashboard/account/tokens>). Input is hidden
     and nothing is saved.
   * **or by hand:** Supabase → **Authentication → Sign In / Providers → Google** →
     enable → paste both → Save.
6. Check everything at any time (no secrets needed):
   ```bash
   node scripts/google-login.mjs check
   ```
   It tests Supabase **and** asks Google directly, so it catches a wrong Client ID
   (`invalid_client`) or a missing callback URL (`redirect_uri_mismatch`) before
   you try it in the app.

## Facebook (free, ~15 min)

1. <https://developers.facebook.com> → **My Apps → Create app** → use case
   *"Authenticate and request data from users with Facebook Login"*.
2. **Facebook Login → Settings → Valid OAuth Redirect URIs**: the **Supabase callback URL**.
3. **Use cases → Customise → Permissions**: make sure `email` and `public_profile` are added.
4. **App settings → Basic**: copy **App ID** and **App Secret**. Add a privacy
   policy URL; Meta needs one before the app can go *Live*.
5. Supabase → **Providers → Facebook** → enable → paste App ID (as Client ID)
   and App Secret → Save.

While the Meta app is in **Development** mode, only people listed under *App roles*
(you, testers) can log in. Switch it to **Live** for everyone.

## Apple (needs the paid Apple Developer Program, $99/year)

> ⚠️ **Change the bundle id first.** `com.example.expenseTracker` is a placeholder.
> Apple won't let you register `com.example…` identifiers for your team, and the
> App Store rejects them. Pick something unique like `com.<yourname>.pennywise`
> and set it in Xcode (Runner target → Signing & Capabilities) for iOS and macOS.

### iPhone / iPad (native sheet, what the app uses on iOS)

1. <https://developer.apple.com/account> → **Identifiers → App IDs** → your bundle id
   → tick **Sign in with Apple** → Save. (`ios/Runner/Runner.entitlements` already
   requests the capability.)
2. Supabase → **Providers → Apple** → enable → in **Client IDs** enter your
   **bundle id** → Save.

That's all native iOS needs; no secret key is involved.

### Android / macOS / web (browser flow), optional

1. **Identifiers → Services IDs → +**, e.g. `com.<yourname>.pennywise.signin` →
   enable *Sign in with Apple* → Configure: domain `dwvqxftefejqxcopbvfz.supabase.co`,
   return URL = the **Supabase callback URL**.
2. **Keys → +** → enable *Sign in with Apple* → download the `.p8` file (once only!).
3. Supabase → **Providers → Apple**: add the Services ID to **Client IDs** (comma-separated
   with the bundle id), and generate the **Secret Key** from the `.p8`, your Team ID and
   Key ID (the dashboard links to a generator).
4. **The secret expires every 6 months.** Put a reminder in your calendar to regenerate it.

---

## Test it

1. Run the app (`./scripts/dev.sh`).
2. Tap the provider button. You should leave the app, log in, and come back signed in.
3. If it fails, check the error text first. In debug builds it names the setting to
   fix. Then check Supabase Dashboard → **Logs → Auth**.

| Symptom | Cause |
|---|---|
| "… sign-in is turned off in Supabase" | Provider not enabled (step 5 of that provider) |
| Browser shows `redirect_uri_mismatch` (Google) / "URL blocked" (Facebook) | Supabase callback URL not added at the provider |
| Login succeeds in the browser but the app never opens | `io.supabase.pennywise://login-callback/` missing from Supabase Redirect URLs |
| Apple: "invalid client" / audience error | Bundle id (iOS) or Services ID (others) not in Supabase *Client IDs* |
