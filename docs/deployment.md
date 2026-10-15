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

## Current state (2026-10-15)

| Piece | Status |
|---|---|
| Web app | **Live at https://easyplan-hehe.netlify.app** (Netlify project `easyplan-hehe`; `easyplan` was taken). Last deployed 2026-10-15 from `main` at `e2534a6` (second on-request deploy, run 38697471184): everything on `main` up to then is live (recurring plans, #17, merged afterwards and isn't), including past plans (#11), invite management (#9), deleting groups / handing over ownership (#10), the link/photo filters (#53), logging re-pointed merge rules (#52), drag to reschedule (#12) and the #58 notification fix |
| Supabase cloud project | Created; linked from the Mac and the Windows PC; schema pushed with `supabase db push` (link once per computer: [`setup-windows.md`](setup-windows.md#deploying-from-windows)). Has every migration through `20261015064456_log_type_merge_updates.sql` (checked 2026-10-15). **Waiting for `supabase db push`** before the next deploy: `20261015083758_recurring_plans.sql` and `20261015083759_recurring_history.sql` (recurring plans, #17, merged to `main`). Check any time with `supabase migration list --linked` |
| Supabase Auth URLs | Site URL `https://easyplan-hehe.netlify.app`; redirect `https://easyplan-hehe.netlify.app/**` |
| `app/env/prod.json` | Filled in on the owner's Mac (git-ignored) |
| Auth emails | Sent through **Resend** from `no-reply@easyplanhehe.online` (custom SMTP in Supabase). Domain `easyplanhehe.online` at Namecheap; Resend region Tokyo, Japan (`ap-northeast-1`) |
| Auth email templates | EasyPlan templates from `supabase/templates/` pasted into the dashboard: **Confirm signup** (`confirmation.html`), **Reset password** (`recovery.html`), **Change email address** (`email_change.html`). Magic link, invite and reauthentication aren't used |
| Privacy policy | Live at `<APP_URL>/privacy.html`; names Supabase (Singapore), Netlify and Resend (Tokyo); contact easyplanhehe@gmail.com |
| Deploys | **On request only** (since 2026-10-15): merging to `main` doesn't deploy. The owner decides when; a manual run of CI deploys `main` after the checks pass (GitHub Actions → Netlify). See [Deploying the web app](#deploying-the-web-app). |
| Still to do | Phone smoke test (#5) and the two-phone live-updates test (#49); Android (#13) and iOS (#14) store builds |

The cloud database is separate from the local one: local accounts and test data don't exist there, and the local seed accounts are never pushed.

---

## 1. Backend: Supabase cloud project

1. **(you)** Create a project at supabase.com. Region: Southeast Asia (Singapore). Keep the database password somewhere safe.
2. Push the schema. This creates every table, rule, function and storage bucket from `supabase/migrations/`. It does **not** send `seed.sql`, so the test accounts stay local.
   ```bash
   supabase login        # the CLI may be at ~/.local/bin/supabase
   supabase link --project-ref <project-ref>
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
   - add the site to the home screen.

Friends can now use EasyPlan from the browser or the home-screen icon.

## 4. Android: Google Play (Stage B and C)

Toolchain first. `flutter doctor` currently reports Android SDK 30; Flutter needs SDK 36:
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
1. If anything merged since the last deploy adds migrations, run `supabase db push` on the cloud project **first** (owner). `supabase migration list --linked` shows which migrations the cloud has.
2. Start the deploy:
   ```bash
   gh workflow run ci.yml --ref main
   ```
   or GitHub → Actions → CI → **Run workflow** on `main`.
3. Watch it: `gh run watch` (or the Actions tab). It takes a few minutes.

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
2. `supabase db push` if there are new migrations, **before** deploying the web app or shipping app builds that need them.
3. Web: merge to `main`, then deploy ([Deploying the web app](#deploying-the-web-app)). Phones: `./scripts/build.sh android` / `ios` + upload.

## Checklist before inviting real users

- [x] Supabase cloud project, `db push` done, auth URLs set
- [x] SMTP connected (Resend, `easyplanhehe.online`)
- [x] `app/env/prod.json` filled in; web deployed to https://easyplan-hehe.netlify.app
- [ ] Smoke test passed on a phone
- [x] Privacy policy filled in and published (names Supabase, Netlify and Resend)
- [x] Email templates mention EasyPlan (confirm signup, reset password, change email)
- [ ] (Stores) upload key backed up; data safety / App Privacy answered; reviewer demo account ready
- [ ] (Optional) replace the placeholder icon (`app/assets/icon/`, then `dart run flutter_launcher_icons`)
