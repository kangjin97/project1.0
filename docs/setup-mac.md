# Setting up a Mac

Step-by-step setup for developing EasyPlan on macOS. The Windows equivalent is [`setup-windows.md`](setup-windows.md); everything after setup (running, testing, the git workflow, working on both computers) is shared and lives in [`development.md`](development.md).

## What you need

| Tool | Version | Where it goes | Why |
|---|---|---|---|
| macOS | **14 or newer** | | Current Dart refuses to run on macOS 13 |
| Homebrew | any recent | https://brew.sh | Installs the rest |
| Git, GitHub CLI (`gh`) | any recent | Homebrew | Issues, PRs, board (`scripts/board.sh`) |
| Flutter | **3.47.6** (Dart 3.13) | `~/dev/flutter` | Same version as CI |
| Supabase CLI | **2.119.0** | `~/.local/bin/supabase` | Same version as CI |
| Docker Desktop | any recent | Homebrew cask or docker.com | Runs the local Supabase stack |
| Xcode | 26.x, optional | App Store | Only for iOS builds ([`deployment.md`](deployment.md) §5) |
| Android Studio | optional | Homebrew cask or developer.android.com | Only for Android builds |

The versions to match are in `.github/workflows/ci.yml` (`flutter-version`, the Supabase CLI `version`). When CI's change, update both computers.

## Setup

Run these in **Terminal**.

### 1. Git and GitHub CLI

```bash
brew install git gh
gh auth login -h github.com -s project
```

The `project` scope lets `scripts/board.sh` move cards on the board.

### 2. Flutter (pinned to CI's version)

```bash
git clone --depth 1 --branch 3.47.6 https://github.com/flutter/flutter.git ~/dev/flutter
```

To upgrade later, delete the folder and clone the new tag. An existing Flutter install elsewhere is fine as long as `flutter --version` reports 3.47.6.

### 3. Supabase CLI (pinned to CI's version)

Pick `arm64` on Apple Silicon (`uname -m` prints `arm64`) or `amd64` on Intel (`uname -m` prints `x86_64`):

```bash
v=2.119.0; arch=arm64
mkdir -p ~/.local/bin
curl -fL -o /tmp/supabase.tar.gz "https://github.com/supabase/cli/releases/download/v$v/supabase_${v}_darwin_${arch}.tar.gz"
shasum -a 256 /tmp/supabase.tar.gz     # compare with the line for this file in checksums.txt on the release page
tar -xzf /tmp/supabase.tar.gz -C ~/.local/bin supabase
```

`brew install supabase/tap/supabase` also works but installs the newest version rather than CI's. If both are installed, `which supabase` shows which one runs; either is fine as long as `supabase --version` matches CI.

### 4. Add both to PATH

```bash
echo 'export PATH="$HOME/dev/flutter/bin:$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

Open a new Terminal window, then:

```bash
flutter config --no-analytics
flutter doctor
supabase --version
```

`flutter doctor` may warn "unknown channel" because the SDK is on a tag; that's expected. Xcode and Android warnings can be ignored for web work.

### 5. Docker Desktop

```bash
brew install --cask docker
```

Open Docker from Applications, accept the agreement and wait for **Engine running**.

> Docker Desktop is free for personal use and small businesses; larger companies need a paid subscription.

## First run

Continue with [First run](development.md#first-run) in `development.md`; it's the same on both computers. Then start the app:

```bash
cd app
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3000
```

Open http://127.0.0.1:3000. In the `flutter run` window: `r` hot-reloads, `R` restarts, `q` quits. **Docker Desktop must be running** whenever you use the app or the database tests.

### Optional: place search and Fill from link

These two features call outside APIs through Edge Functions, which need keys on each computer. Without them the app still works; those two features answer "isn't set up yet".

1. Create `supabase/functions/.env` (git-ignored) with:
   ```
   GOOGLE_MAPS_API_KEY=
   ANTHROPIC_API_KEY=
   ANTHROPIC_BASE_URL=https://api.aimlapi.com
   ```
   Type the keys in yourself, the same ones the other computer uses ([`deployment.md`](deployment.md#edge-functions-and-google-maps-73) says where each comes from). Never paste them into chat or commit them.
2. Run the functions alongside the stack. They read `.env` only when they start, so restart them after changing it:
   ```bash
   supabase functions serve --env-file supabase/functions/.env
   ```

## Cloud access (owner only)

Needed only for the owner's release steps: `supabase db push`, `supabase functions deploy`, `supabase migration list --linked`. Once per computer:

```bash
supabase login
supabase link --project-ref <project-ref>    # stored in git-ignored supabase/.temp
```

Web deploys don't run on your computer: `gh workflow run ci.yml --ref main` starts one on GitHub Actions ([`deployment.md`](deployment.md#deploying-the-web-app)). iOS builds need this Mac or a cloud build service ([`deployment.md`](deployment.md) §5).

## Checking an existing setup

After time away from the Mac, check it still matches CI before working:

```bash
git pull
flutter --version              # 3.47.6, as in .github/workflows/ci.yml
supabase --version             # 2.119.0, as in ci.yml
docker info > /dev/null && echo Docker running
supabase start
supabase migration up          # catches up on migrations merged from the other computer; keeps data
supabase test db
cd app && flutter pub get && flutter analyze && flutter test
```

If CI's versions moved on, upgrade Flutter (step 2) and the Supabase CLI (step 3) to match.

## Mac-only notes and troubleshooting

| Symptom | Cause and fix |
|---|---|
| `VM initialization failed: Current Mac OS X version 13.0 is lower than minimum supported version 14.0` | Current Dart needs macOS 14+. Upgrade macOS, or (stopgap, won't match CI) pin Flutter: `cd ~/dev/flutter && git fetch --depth 1 origin tag 3.38.10 && git checkout 3.38.10`. |
| Homebrew: `You have not agreed to the Xcode license` / `Your Xcode is too outdated` | Run `sudo xcodebuild -license accept`; update Xcode or run `xcode-select --install`. |
| Claude desktop preview: `flutter: Operation not permitted` | macOS privacy (TCC) blocks the preview launcher from reading `~/Documents`. Start the server from a terminal; `.claude/launch.json` then attaches to `http://127.0.0.1:3000`. Or grant the app access in System Settings → Privacy & Security → Files and Folders. |
| `flutter`/`supabase`: command not found | The Terminal window opened before `~/.zshrc` changed. Open a new one, or run `source ~/.zshrc`. |
| `supabase start` downloads a new Postgres image and says "Starting database from backup" | A linked computer runs the cloud project's Postgres version locally (`supabase/.temp/postgres-version`), so this happens after Supabase upgrades the cloud database. Harmless: it keeps the local data. Check with `supabase migration list --local`, then run `supabase migration up`. |
| iOS builds | Need Xcode with an iOS runtime and CocoaPods; see [`deployment.md`](deployment.md) §5. Intel Macs are being phased out for app builds. |
