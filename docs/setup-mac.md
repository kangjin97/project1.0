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

Pick `arm64` on Apple Silicon (`uname -m` prints `arm64`) or `amd64` on Intel:

```bash
v=2.119.0; arch=arm64
mkdir -p ~/.local/bin
curl -fL -o /tmp/supabase.tar.gz "https://github.com/supabase/cli/releases/download/v$v/supabase_${v}_darwin_${arch}.tar.gz"
shasum -a 256 /tmp/supabase.tar.gz     # compare with checksums.txt on the release page
tar -xzf /tmp/supabase.tar.gz -C ~/.local/bin supabase
```

`brew install supabase/tap/supabase` also works but installs the newest version rather than CI's.

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

Continue with [First run](development.md#first-run) in `development.md`; it's the same on both computers.

## Mac-only notes and troubleshooting

| Symptom | Cause and fix |
|---|---|
| `VM initialization failed: Current Mac OS X version 13.0 is lower than minimum supported version 14.0` | Current Dart needs macOS 14+. Upgrade macOS, or (stopgap, won't match CI) pin Flutter: `cd ~/dev/flutter && git fetch --depth 1 origin tag 3.38.10 && git checkout 3.38.10`. |
| Homebrew: `You have not agreed to the Xcode license` / `Your Xcode is too outdated` | Run `sudo xcodebuild -license accept`; update Xcode or run `xcode-select --install`. |
| Claude desktop preview: `flutter: Operation not permitted` | macOS privacy (TCC) blocks the preview launcher from reading `~/Documents`. Start the server from a terminal; `.claude/launch.json` then attaches to `http://127.0.0.1:3000`. Or grant the app access in System Settings → Privacy & Security → Files and Folders. |
| `flutter`/`supabase`: command not found | The Terminal window opened before `~/.zshrc` changed. Open a new one, or run `source ~/.zshrc`. |
| iOS builds | Need Xcode with an iOS runtime and CocoaPods; see [`deployment.md`](deployment.md) §5. Intel Macs are being phased out for app builds. |
