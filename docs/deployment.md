# Deploying EasyPlan

How to take EasyPlan from your computer to people's phones. Everything here also works from the Windows PC except iOS builds; see [`setup-windows.md`](setup-windows.md#deploying-from-windows). Steps marked **(you)** need your accounts, payments or passwords. Everything else is already set up in the repo.

| Item | Value |
|---|---|
| App name | EasyPlan |
| App ID (Android `applicationId`, iOS bundle ID) | `com.kangjin.easyplan`. **Never change it after the first store upload.** |
| Web host | Netlify |
| Production config | `app/env/prod.json` (git-ignored; copy from `prod.example.json`) |
| Build script | `./scripts/build.sh web|android|ios` |

Order: **1 → 2 → 3** gets friends using it on their phones via the browser. **4 / 5** are the store apps.

## Current state (2026-10-21)

| Piece | Status |
|---|---|
| Web app | **Live at https://easyplan-hehe.netlify.app** (Netlify project `easyplan-hehe`; `easyplan` was taken). Last deployed **2026-10-20** from `main` at `2027967` (fifth on-request deploy, run 39376082876; earlier ones `4891b08`, `64de21b`, `e2534a6`, `5fb615c`): everything on `main` up to then is live, including the "Near…" distance filter (#94), the itinerary export (#96), Google Calendar (#97) and its fixes (#99), Sign in with Google (#87), the sign-up name counter (#83), Fill from link (#74), Google Maps locations (#73) and recurring plans (#17). The owner checked on a phone (2026-10-21) that "Near… → Use my location", Add to Google Calendar and opening an exported calendar file work. Anything merged later: `git log --oneline 2027967..origin/main` |
| Supabase cloud project | Created; linked from the Mac and the Windows PC; schema pushed with `supabase db push` (link once per computer: [`setup-windows.md`](setup-windows.md#deploying-from-windows)). Has every migration through `20261019114043_place_coordinates.sql` (checked 2026-10-20; it also enabled `pg_cron` for the daily `expire-place-coordinates` job); nothing waiting. Check any time with `supabase migration list --linked` |
| Supabase Auth URLs | Site URL `https://easyplan-hehe.netlify.app`; redirect `https://easyplan-hehe.netlify.app/**` |
| `app/env/prod.json` | Filled in on the owner's Mac (git-ignored) |
| Auth emails | Sent through **Resend** from `no-reply@easyplanhehe.online` (custom SMTP in Supabase). Domain `easyplanhehe.online` at Namecheap; Resend region Tokyo, Japan (`ap-northeast-1`) |
| Auth email templates | EasyPlan templates from `supabase/templates/` pasted into the dashboard: **Confirm signup** (`confirmation.html`), **Reset password** (`recovery.html`), **Change email address** (`email_change.html`). Magic link, invite and reauthentication aren't used |
| Privacy policy | Live at `<APP_URL>/privacy.html`; names Supabase (Singapore), Netlify and Resend (Tokyo); Google (place search, #73; place IDs for "Near…" distances, coordinates kept at most 30 days, device location stays on the device, #94) and AIML API → Anthropic ("Fill from link", #74); contact easyplanhehe@gmail.com; Google sign-in (#87); last updated 22 October 2026 |
| Deploys | **On request only** (since 2026-10-15): merging to `main` doesn't deploy. The owner decides when; a manual run of CI deploys `main` after the checks pass (GitHub Actions → Netlify). See [Deploying the web app](#deploying-the-web-app). |
| Edge Functions | `username-sign-in` (sign in with a username, #107): **not deployed yet**; deploy it, after `supabase db push`, before the web deploy that ships #107. It needs no secrets (it uses the service role key Supabase provides). `place-coordinates` (distances for "Near…", #94): **deployed** version 1 (2026-10-19), using the same `GOOGLE_MAPS_API_KEY`. `places` (Google Maps place search, #73) and `fill-activity` ("Fill from link", #74): **deployed**: `places` version 1 (2026-10-16), `fill-activity` version 2 (2026-10-19, the #79 label fix). Both have `verify_jwt` on. Secrets `GOOGLE_MAPS_API_KEY`, `ANTHROPIC_API_KEY` (AIML API key) and `ANTHROPIC_BASE_URL=https://api.aimlapi.com` set with `supabase secrets set --env-file supabase/functions/.env`. Redeploy whenever `supabase/functions/` changes; check with `supabase functions list` / `supabase secrets list`. See [Edge Functions and Google Maps](#edge-functions-and-google-maps-73) |
| Sign in with Google | Built (#87). Google OAuth client and consent screen (EasyPlan, In production) set up by the owner on 2026-10-19; Google provider **on** in the cloud project (checked 2026-10-19); the Mac's `supabase/.env` filled in (the Windows PC still needs it). **Live since 2026-10-19 and checked by the owner on a phone**: Continue with Google works end to end, and signing up with an email that already has an account says "already registered". See [Sign in with Google](#sign-in-with-google-87) |
| Still to do | The phone smoke test (#5) and the two-phone live-updates test (#49); Android (#13) and iOS (#14) store builds |

The cloud database is separate from the local one: local accounts and test data don't exist there, and the local seed accounts are never pushed.

---

## 1. Backend: Supabase cloud project

1. **(you)** Create a project at supabase.com. Region: Southeast Asia (Singapore). Keep the database password somewhere safe.
2. Push the schema. This creates every table, rule, function and storage bucket from `supabase/migrations/`. It does **not** send `seed.sql`, so the test accounts stay local.
   ```bash
   supabase login        # the CLI may be at ~/.local/bin/supabase
   supabase link --project-ref xxdbjszumfwbipniimbd
   supabase db push
   ```
   Later migrations: run `supabase db push` again after merging them.
3. **(you)** In the Supabase dashboard → **Authentication**:
   - **URL Configuration**:
     - Site URL: `https://easyplan-hehe.netlify.app`
     - Redirect URLs: add `https://easyplan-hehe.netlify.app/**`. Password-reset links return here.
   - **Sign In / Providers → Email**: keep **Confirm email** and **Secure email change** on. The app tells people to open the links sent to both their old and new address; with secure email change off that message would be wrong.
   - **Emails → SMTP Settings**: connect a real email provider; the built-in sender is limited to a few emails an hour and is only for testing. Ours is **Resend**:
     - Resend → Domains: `easyplanhehe.online`, region Tokyo (`ap-northeast-1`). Receiving and click/open tracking stay **off** (tracking rewrites links, which can break password-reset links).
     - DNS at Namecheap (Advanced DNS → Host Records; Host is the part before `.easyplanhehe.online`; Mail Settings stays on Email Forwarding):

       | Type | Host | Value |
       |---|---|---|
       | TXT | `resend._domainkey` | DKIM key from Resend's domain page |
       | CNAME | `rsend` | `rsend-apne1.forge.rmta.net` |
       | CNAME | `send` | `send.forge.rmta.net` (Resend's bounce handling; don't also add an MX on `send`) |
       | TXT | `_dmarc` | `v=DMARC1; p=none;` |

     - Resend → API Keys: sending access only, limited to that domain. The key is the SMTP password; it goes straight into Supabase and nowhere else.
     - Supabase SMTP: sender `no-reply@easyplanhehe.online`, name `EasyPlan`, host `smtp.resend.com`, port `465`, username `resend`, password = the API key.
     - **Authentication → Rate Limits**: raise emails per hour (e.g. 30); the default assumes the built-in sender.
     - Changing provider later: update these settings and name the new provider in the privacy policy.
   - **Emails → Templates**: templates kept in the repo live in `supabase/templates/` (the local stack uses them through `supabase/config.toml`). The cloud copy is set by hand: open the template, set the subject from `config.toml`, paste the file's contents into the body (the HTML comment at the top can stay), and save. Re-paste whenever the file changes.
     - **Change email address** → `supabase/templates/email_change.html`, subject "Confirm your EasyPlan email change". Sent to both the old and new address; says both links are needed.
     - **Confirm signup** → `supabase/templates/confirmation.html`, subject "Confirm your EasyPlan account". Only sent while **Confirm email** is on (cloud; off locally).
     - **Reset password** → `supabase/templates/recovery.html`, subject "Reset your EasyPlan password". The link opens `/reset-password`.
     - Magic link, Invite user and Reauthentication aren't used by the app; their defaults are fine.
4. **(you)** Copy **Project URL** and the **Publishable key** (Project Settings → API keys) into `app/env/prod.json`.
5. Plan: the free plan pauses a project after a week without activity and has small storage limits. Fine for a trial with friends; move to Pro before a public launch. Turn on backups (Pro includes daily backups).

### Sign in with Google (#87)

"Continue with Google" uses Supabase Auth's Google provider. It needs an OAuth client from Google, and both the cloud project and each computer need its ID and secret. All steps are **(you)**.

1. **Google Cloud** (the project that already has the Maps key) → **Google Auth Platform** (APIs & Services → OAuth consent screen):
   - **Branding:** app name `EasyPlan`, support email `easyplanhehe@gmail.com`, home page `https://easyplan-hehe.netlify.app`, privacy policy `https://easyplan-hehe.netlify.app/privacy.html`, developer contact `easyplanhehe@gmail.com`. Skip the logo: uploading one makes Google review the app first. Add any domain Google asks you to authorise.
   - **Audience:** External, then **Publish app** (In production). While it's in Testing, only the test users you list (up to 100) can sign in.
   - **Data access:** only the default `openid`, `…/auth/userinfo.email` and `…/auth/userinfo.profile`. These are non-sensitive, so no verification is needed.
   - **Clients → Create client → Web application** (e.g. "EasyPlan"):
     - Authorized JavaScript origins: `https://easyplan-hehe.netlify.app`, `http://127.0.0.1:3000`
     - Authorized redirect URIs: `https://xxdbjszumfwbipniimbd.supabase.co/auth/v1/callback` (cloud) and `http://127.0.0.1:54321/auth/v1/callback` (local stack)
     - Keep the **Client ID** and **Client secret** (the secret is shown once; never paste it into chat or git).
2. **Supabase dashboard → Authentication → Sign In / Providers → Google:** turn it on, paste the Client ID and Client secret, save. The callback URL it shows must match the cloud redirect URI above. **URL Configuration** needs no change: Google sends people back to `<APP_URL>/?next=…`, which `https://easyplan-hehe.netlify.app/**` already allows. Keep **Allow manual linking** off; Supabase links a Google sign-in to an existing account with the same verified email by itself.
3. **Each computer:** create the git-ignored `supabase/.env` with the two lines below if it doesn't exist (git doesn't carry it), then `supabase stop` and `supabase start` (keeps data):
   ```
   SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID=<client id>
   SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET=<client secret>
   ```
   `supabase/config.toml` (`[auth.external.google]`) reads them. Without them the button opens a Google error page.
4. **Release:** `supabase db push` (adds `20261019022546_google_sign_in.sql`), then deploy the web app.

Phone apps (#13, #14) need their own Google client IDs later, and the iOS app will also need Sign in with Apple once it offers Google (App Store rule).

### Edge Functions and Google Maps (#73)

Place search runs in the `places` Edge Function (`supabase/functions/places/index.ts`), which calls Google's Places API (New) with a secret key.

**Google Cloud (owner, once):**
1. At console.cloud.google.com, create a project (e.g. "EasyPlan").
2. Link a **billing account**. Google requires one even within its free monthly allowance; current prices are on Google's Places pricing page.
3. In APIs & Services → Library, enable **Places API (New)**.
4. In Credentials, create an **API key** and restrict it (API restrictions) to **Places API (New)** only. There's no application restriction to set: the key is used server-side from Supabase.
5. In Billing → **Budgets & alerts**, set a small monthly budget with email alerts. Optionally cap requests per day in the API's **Quotas**. The app also caps each person at 100 searches a day in the database.

**The key** (owner; never in chat, never committed):
- **Locally:** `supabase/functions/.env` (git-ignored, one per computer):
  ```
  GOOGLE_MAPS_API_KEY=AIza...
  ```
  Serve the function with `supabase functions serve places --env-file supabase/functions/.env` while the local stack runs.
- **Cloud:**
  ```bash
  supabase secrets set GOOGLE_MAPS_API_KEY=AIza...
  ```
  Type it straight into your terminal. `supabase secrets list` shows the name, never the value.

**Distances (#94):** the `place-coordinates` function uses the same key for **Place Details** (only the `location` field), which is part of Places API (New), so the key's restriction already covers it (checked 2026-10-19). Coordinates are cached for at most 30 days (Google's limit) and each person can trigger 200 lookups a day. The cache is written with the service role key that Supabase gives every function; nothing to set.

### Claude for "Fill from link" (#74)

The `fill-activity` function calls Claude Haiku 5.5 (`claude-haiku-5-5`) through the official Anthropic SDK. It also uses the Google key above to match places. Two settings choose where the request goes:

| Setting | Meaning |
|---|---|
| `ANTHROPIC_API_KEY` | The key for whichever provider is used |
| `ANTHROPIC_BASE_URL` | Optional. `https://api.aimlapi.com` sends the request through AIML API; leave it out to go straight to Anthropic |

**Now: AIML API** (owner's choice, 2026-10-16). The owner bought $20 of prepaid credits at aimlapi.com, a reseller with an Anthropic-style endpoint. It works with the function unchanged (tested locally 2026-10-16), but:
- it adds a markup: a test call cost about 40% more than Anthropic's own price (still well under a cent per fill);
- credits aren't refundable;
- its privacy policy says nothing about how API requests (screenshots, captions) are used or kept. The company is Boiler Labs FZ-LLC (UAE).

Setup (owner, once):
1. At aimlapi.com, top up credits and create an API key. AIML API keys don't start with `sk-ant-`.
2. **Locally:** in `supabase/functions/.env`, set `ANTHROPIC_API_KEY=<the AIML key>` and `ANTHROPIC_BASE_URL=https://api.aimlapi.com`, then restart `supabase functions serve` (it reads `.env` only at start).
3. **Cloud:** type it into your terminal, never into chat:
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=... ANTHROPIC_BASE_URL=https://api.aimlapi.com
   ```

**When the AIML API credits run out: switch to Anthropic directly** (recommended). It's cheaper (no reseller markup; Claude Haiku 5.5 is $0.10 / $0.50 per million input / output tokens, about $0.0005 per fill, so $5 lasts around 10,000 fills), and Anthropic doesn't use API data to train its models (check Anthropic's commercial terms when switching). No code change:
1. At **console.anthropic.com** (an API account; separate from any Claude.ai subscription, which can't be used for this), add credit under Billing and set a **monthly spend limit** (Settings → Limits).
2. Create an API key (starts `sk-ant-api`).
3. **Locally:** in `supabase/functions/.env`, replace `ANTHROPIC_API_KEY` with the new key and **delete the `ANTHROPIC_BASE_URL` line**; restart `supabase functions serve`.
4. **Cloud:**
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   supabase secrets unset ANTHROPIC_BASE_URL
   ```
   No redeploy is needed for a secret change.
5. **Privacy page** (`app/web/privacy.html`, "Fill from link" sentence): remove "through AIML API" and its link, so it names only Anthropic. It may say again that Anthropic doesn't use this data to train its models, once you've checked their terms. Then deploy the web app.

When credits run out, fills fail, usually with "Fill from link is unavailable right now." (HTTP 502; the function log, Supabase dashboard → Edge Functions → `fill-activity` → Logs, shows the provider's error). Check the balance on aimlapi.com now and then. The rest of the app keeps working.

### Deploying the functions

Owner, whenever `supabase/functions/` changes (including `_shared/`), before the web deploy that needs it:
```bash
supabase functions deploy places
supabase functions deploy fill-activity
supabase functions deploy place-coordinates
supabase functions deploy username-sign-in
```
`verify_jwt = true` for `places`, `fill-activity` and `place-coordinates` comes from `supabase/config.toml`, so only signed-in users can call them; `username-sign-in` has `verify_jwt = false` because it runs before sign-in (it limits failed attempts per username itself). Without their secrets they say so ("… isn't set up yet."; "Distances aren't set up yet." for `place-coordinates`). `supabase functions serve --env-file supabase/functions/.env` serves all of them locally.

## 2. Production config

```bash
cd app && cp env/prod.example.json env/prod.json   # then edit the three values
```

`APP_URL` is the public web address. Invite links (`<APP_URL>/join/<code>`), password-reset links and the privacy policy link all use it.

Release builds refuse to start if they would point at the local database. Instead they show "This build has no server configured", so a misconfigured build is obvious.

## 3. Web app on Netlify (Stage A: phones via the browser)

1. **(you)** Create a Netlify account. Create the project by dropping the built `app/build/web` folder (Projects → Add new project → Deploy manually), then rename it. Ours is `easyplan-hehe` → `https://easyplan-hehe.netlify.app`; that address goes in `APP_URL`.
2. Build and deploy:
   ```bash
   ./scripts/build.sh web
   ```
   Then in Netlify open the project → **Deploys** and drag the `app/build/web` folder onto the drop area. Drop it on the project's **Deploys** page; dropping on the Projects list creates a new project instead.
   - This was the first deploy. Later deploys run from GitHub Actions when the owner asks for one (see [Deploying the web app](#deploying-the-web-app)); drag-and-drop remains the manual fallback. (`netlify-cli` locally needs Node 18 or newer; this Mac has Node 15.)
   - `netlify.toml` publishes `app/build/web`. `web/_redirects` makes every path load the app; that's needed because the app uses clean URLs like `/join/abc`.
   - Quick check after deploying: `curl -s https://easyplan-hehe.netlify.app/main.dart.js | grep -c easyplan-hehe` should print `1`, and `/join/x` should return 200.
3. Privacy policy: `app/web/privacy.html`, live at `<APP_URL>/privacy.html` (the stores need this URL). Contact address: easyplanhehe@gmail.com. When you change what the app stores or add a provider (e.g. a new email sender), update the page and its date, merge to `main`, then deploy.
4. Smoke test on a phone:
   - sign up and confirm the email;
   - create a group and copy its invite link;
   - open the link on a second phone and join;
   - reset a password;
   - continue with Google (first time: pick a username; check the photo and name);
   - sign up with an email that already has an account: it should say "already registered";
   - add the site to the home screen.

Friends can now use EasyPlan from the browser or the home-screen icon.

## 4. Android: Google Play (Stage B and C)

Toolchain first. On the Mac (2026-10), `flutter doctor` reports Android SDK 30; Flutter needs SDK 36:
- Install Android Studio, then open SDK Manager → install Android SDK Platform 36 and the latest Build-Tools and Command-line Tools.
- Run `flutter doctor --android-licenses`.

1. **(you)** Create an upload key. Keep the `.jks` file and its passwords backed up somewhere safe; without them you can't publish updates.
   ```bash
   keytool -genkey -v -keystore ~/keys/easyplan-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Copy `app/android/key.properties.example` → `app/android/key.properties` and fill it in. That file and `*.jks` are git-ignored.
3. Build: `./scripts/build.sh android` → `app/build/app/outputs/bundle/release/app-release.aab`.
4. **(you)** Google Play Console (one-time US$25):
   - Create the app EasyPlan and turn on Play App Signing.
   - Upload the `.aab` to **Testing → Internal testing**.
   - Add testers' emails and share the opt-in link.
5. Before going to production, fill in **App content**:
   - Privacy policy URL.
   - **Data safety**: account info (email, name), photos, user content, app activity. Collected; not shared with third parties; encrypted in transit; users can request deletion (in-app: Profile → Delete account).
   - Content rating, target audience, and store listing (icon 512×512, feature graphic, screenshots).
   - New personal developer accounts must run a closed test with testers for 14 days before production access.
6. **Invite links that open the app (App Links):**
   - Copy the **SHA-256 certificate fingerprint** from Play Console → Setup → App signing into `app/deploy/well-known/assetlinks.json`.
   - Copy that file to `app/web/.well-known/assetlinks.json`, merge to `main`, then deploy the web app.
   - The manifest already declares `https://<APP_URL host>/join/*`; the host comes from `APP_URL` at build time.

## 5. iPhone: App Store (Stage B and C)

Toolchain first:
- Xcode is 26.5, but `flutter doctor` reports missing simulator runtimes and an old CocoaPods. Open Xcode → Settings → Components to install an iOS runtime, then run `sudo gem install cocoapods` (or `brew install cocoapods`).
- Flutter warns that Intel Macs are being phased out for app builds; plan for an Apple Silicon Mac, or a cloud build service such as Codemagic.

1. **(you)** Apple Developer Program (US$99/year).
2. **(you)** In Xcode, open `app/ios/Runner.xcworkspace` → Runner → **Signing & Capabilities**:
   - Choose your team; the bundle ID is already `com.kangjin.easyplan`.
   - Add **Associated Domains** with `applinks:<APP_URL host>`, so invite links open the app.
3. **(you)** In App Store Connect, create the app EasyPlan with that bundle ID.
4. Build: `./scripts/build.sh ios` → `app/build/ios/ipa/`. Upload with Xcode Organizer or the Transporter app.
5. **(you)** **TestFlight**: add testers by email. External testers need a short beta review.
6. Before release, fill in:
   - **App Privacy** answers (same data as the Play data safety form) and the privacy policy URL.
   - Screenshots and a demo account for App Review. Give reviewers a test login; they will try **Delete account**, which Apple requires.
7. **Universal Links:** put your Team ID into `app/deploy/well-known/apple-app-site-association`, copy it to `app/web/.well-known/`, merge to `main`, then deploy the web app. `netlify.toml` serves it as JSON.

## Deploying the web app

Deploys happen **only when the owner asks**: typically at the end of a day of work, or whenever the live app needs the latest `main`. Every production deploy costs Netlify credits, so merging a pull request doesn't deploy (until 2026-10-15 it did, and several merges a day used the credits up too fast). Develop and test on the local stack; merge to `main` as often as you like.

**To deploy** (the owner, or an agent when the owner says so):
1. Check what merged since the last deploy: `git diff --name-only <last-deploy-sha>..origin/main -- supabase/migrations supabase/functions supabase/templates` (the SHA is in "Current state" at the top of this file). If it adds migrations, run `supabase db push` on the cloud project **first** (owner). `supabase migration list --linked` shows which migrations the cloud has. If it changed an Edge Function (`supabase/functions/`), also run `supabase functions deploy <name>` (owner), after setting any new secret ([Edge Functions and Google Maps](#edge-functions-and-google-maps-73)).
2. Start the deploy:
   ```bash
   gh workflow run ci.yml --ref main
   ```
   or GitHub → Actions → CI → **Run workflow** on `main`.
3. Watch it: `gh run list --workflow ci.yml --event workflow_dispatch --limit 1` for the run ID, then `gh run watch <id> --exit-status` (or the Actions tab). It takes a few minutes.
4. Afterwards, record it: a `documentation` issue and PR that update the date, `main` SHA, run ID and what went live in "Current state" at the top of this file, `docs/ai/handover.md` → Current state and the README status table, after re-checking `supabase migration list --linked` and `supabase functions list`.

`.github/workflows/ci.yml` has a **Deploy web (Netlify)** job that runs only on that manual run, on `main`, after the **App** and **Database** checks pass. It then:
1. writes `app/env/prod.json` from GitHub settings;
2. runs `./scripts/build.sh web`;
3. deploys `app/build/web` to Netlify as the live version;
4. checks that the live site serves the new build.

Pull requests and pushes to `main` run the checks but never deploy.

**Settings it needs** (GitHub repo → Settings → Secrets and variables → Actions). Set them from a terminal; each `gh secret set` prompts for the value, so nothing is pasted into chats or files:

| Name | Kind | Value |
|---|---|---|
| `SUPABASE_URL` | secret | Supabase Project URL (same as in `prod.json`) |
| `SUPABASE_PUBLISHABLE_KEY` | secret | Supabase **publishable** key (never the `sb_secret_` one) |
| `NETLIFY_AUTH_TOKEN` | secret | Netlify → User settings → Applications → Personal access tokens → New |
| `NETLIFY_SITE_ID` | secret | Netlify → easyplan-hehe → Project configuration → General → Project ID |
| `APP_URL` | variable | `https://easyplan-hehe.netlify.app` |

```bash
gh secret set SUPABASE_URL --repo kangjin97/project1.0
gh secret set SUPABASE_PUBLISHABLE_KEY --repo kangjin97/project1.0
gh secret set NETLIFY_AUTH_TOKEN --repo kangjin97/project1.0
gh secret set NETLIFY_SITE_ID --repo kangjin97/project1.0
gh variable set APP_URL --repo kangjin97/project1.0 --body https://easyplan-hehe.netlify.app
```

If any are missing, the deploy job fails with a message naming them, and nothing is published.

**Redeploy without a code change** (e.g. after updating a secret): the same manual run.

**Roll back**: Netlify → easyplan-hehe → Deploys → pick an earlier deploy → **Publish deploy**. Then fix forward on `main` and deploy again.

**Database changes are not automatic.** Run `supabase db push` on the cloud project **before** the deploy that ships the app code needing them. Otherwise the live app may call tables or functions that don't exist yet. Merging alone is safe: nothing reaches the live site until the deploy. Pushing migrations early is fine as long as they don't break the app that's currently live (adding tables or functions doesn't; dropping or renaming does).

**Manual fallback**: `./scripts/build.sh web`, then drag `app/build/web` onto the project's **Deploys** page.

## 6. Each release

1. Bump `version:` in `app/pubspec.yaml` (e.g. `1.0.1+2`; the number after `+` must increase for every store upload).
2. `supabase db push` if there are new migrations, and `supabase functions deploy <name>` if an Edge Function changed, **before** deploying the web app or shipping app builds that need them.
3. Web: merge to `main`, then deploy ([Deploying the web app](#deploying-the-web-app)). Phones: `./scripts/build.sh android` / `ios` + upload.

## Checklist before inviting real users

- [x] Supabase cloud project, `db push` done, auth URLs set
- [x] Sign in with Google: OAuth client published, Google provider on in Supabase
- [x] SMTP connected (Resend, `easyplanhehe.online`)
- [x] `app/env/prod.json` filled in; web deployed to https://easyplan-hehe.netlify.app
- [ ] Smoke test passed on a phone
- [x] Privacy policy filled in and published (names Supabase, Netlify, Resend, Google, and AIML API → Anthropic)
- [x] Email templates mention EasyPlan (confirm signup, reset password, change email)
- [ ] (Stores) upload key backed up; data safety / App Privacy answered; reviewer demo account ready
- [ ] (Optional) replace the placeholder icon (`app/assets/icon/`, then `dart run flutter_launcher_icons`)
