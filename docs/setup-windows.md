# Setting up a Windows PC

Step-by-step setup for developing EasyPlan on Windows 11. The Mac equivalent is [`setup-mac.md`](setup-mac.md); everything after setup (running, testing, the git workflow, working on both computers) is shared and lives in [`development.md`](development.md). A Windows PC can do everything the Mac does except iOS builds, with the same workflow (issues, board, branches, pull requests, deploys on request).

## What you need

| Tool | Version | Where it goes | Why |
|---|---|---|---|
| Git for Windows | any recent | system install | Git, plus **Git Bash** for `scripts/*.sh` |
| GitHub CLI (`gh`) | any recent | winget, per user | Issues, PRs, board (`scripts/board.sh`) |
| Flutter | **3.47.6** (Dart 3.13) | `%USERPROFILE%\dev\flutter` | Same version as CI |
| Supabase CLI | **2.119.0** | `%USERPROFILE%\.local\bin\supabase.exe` | Same version as CI |
| WSL 2 + Docker Desktop | any recent | system install (admin) | Runs the local Supabase stack |
| Android Studio | optional | system install | Only for Android builds (#13) |

The versions to match are in `.github/workflows/ci.yml` (`flutter-version`, the Supabase CLI `version`). When CI's change, update both computers. Visual Studio is **not** needed; `flutter doctor` asks for it only to build Windows desktop apps, which EasyPlan doesn't ship.

## Setup

Steps 1–4 need no admin rights. Run them in **PowerShell**.

### 1. Git and GitHub CLI

```powershell
winget install --id Git.Git -e
winget install --id GitHub.cli -e --scope user
```

Open a **new** terminal, then sign in. The `project` scope lets `scripts/board.sh` move cards:

```powershell
gh auth login -h github.com -s project
```

### 2. Flutter (pinned to CI's version)

Clone the release tag rather than a channel, so this PC matches CI exactly:

```powershell
git -c core.autocrlf=false clone --depth 1 --branch 3.47.6 https://github.com/flutter/flutter.git "$env:USERPROFILE\dev\flutter"
```

`core.autocrlf=false` keeps the SDK's own scripts intact. To upgrade later, when CI's `flutter-version` changes, delete the folder and clone the new tag.

### 3. Supabase CLI (pinned to CI's version)

```powershell
$v = "2.119.0"
$bin = "$env:USERPROFILE\.local\bin"
New-Item -ItemType Directory -Force $bin | Out-Null
Invoke-WebRequest "https://github.com/supabase/cli/releases/download/v$v/supabase_${v}_windows_amd64.tar.gz" -OutFile "$env:TEMP\supabase.tar.gz"
(Get-FileHash "$env:TEMP\supabase.tar.gz").Hash   # compare with checksums.txt on the release page
tar -xzf "$env:TEMP\supabase.tar.gz" -C $bin supabase.exe
```

The CLI will say a newer version is available; stay on the one CI uses (`.github/workflows/ci.yml`).

### 4. Add both to PATH

```powershell
$add = "$env:USERPROFILE\dev\flutter\bin;$env:USERPROFILE\.local\bin"
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ";$add", 'User')
```

Terminals only read PATH when they open. Open a new Command Prompt window; for terminals inside an app (VS Code, Windows Terminal, the Claude app), quit and reopen the **whole app**. Then:

```powershell
flutter config --no-analytics
flutter doctor
supabase --version
```

`flutter doctor` warns "unknown channel" because the SDK is on a tag; that's expected. Android and Visual Studio warnings can be ignored for web work.

### 5. WSL 2 and Docker Desktop (admin)

Docker Desktop runs its engine inside WSL 2. In an **admin** PowerShell:

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
winget install --id Microsoft.WSL -e --source winget
```

Then **restart** (Start → Power → Restart; "Shut down" may skip finishing the update). `wsl --version` should now print version numbers. No Linux distribution is needed; Docker creates its own (`docker-desktop`).

Install Docker Desktop from the Microsoft Store or with `winget install --id Docker.DockerDesktop -e`. Open it, accept the agreement, and wait for **Engine running**.

- **Windows Home:** WSL 2 is Docker's only engine, so there's no engine setting to look for.
- **Windows Pro or Enterprise:** check that **Settings → General → Use the WSL 2 based engine** is ticked.
- To confirm either way, run `wsl -l -v`: it should list `docker-desktop` with VERSION `2`.

Like the tools in step 4, the `docker` command only reaches terminals and apps opened after the install: reopen them (for the Claude app, quit it fully, see [Troubleshooting](#troubleshooting)).

> Docker Desktop is free for personal use and small businesses; larger companies need a paid subscription. On a company PC, Docker's settings (e.g. firewall) may be managed by IT; that doesn't affect EasyPlan, which only uses `127.0.0.1`.

## First run

Continue with [First run](development.md#first-run) in `development.md`; it's the same on both computers. Use Command Prompt, or run each line separately in PowerShell. Then start the app:

```powershell
cd app
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3000
```

Open http://127.0.0.1:3000. In the `flutter run` window: `r` hot-reloads, `R` restarts, `q` quits. **Docker Desktop must be running** whenever you use the app or the database tests.

Place search and Fill from link also need `supabase/functions/.env` with your keys on this PC and `supabase functions serve`; the steps are the same as on the Mac ([`setup-mac.md`](setup-mac.md#optional-place-search-and-fill-from-link)).

Continue with Google also needs the git-ignored `supabase/.env` on this PC (two lines: the Google OAuth client ID and secret), then `supabase stop` and `supabase start`; the steps are the same as on the Mac ([`setup-mac.md`](setup-mac.md#optional-continue-with-google)).

## Which terminal

| Terminal | Use it for | Watch out for |
|---|---|---|
| **Command Prompt** | `flutter`, `supabase`, `gh`, `git` | Commands from the docs work as written, including `cd app && ...` |
| **PowerShell** (Windows' built-in 5.1) | Setup steps above, everyday commands | No `&&`: run `cd app` and the next command as separate lines |
| **Git Bash** | `./scripts/board.sh`, `./scripts/build.sh` | The scripts are bash; run them here. `bash` in Command Prompt may start WSL instead. |

Git on Windows checks files out with Windows line endings (`core.autocrlf=true`) and converts them back on commit, so commits from either PC look the same. Git Bash runs the scripts fine with those endings.

## Working on both computers

See [Working on both computers](development.md#working-on-both-computers): GitHub is the source of truth, each computer has its own local database, and a few git-ignored files live only where they're needed.

## Deploying from Windows

Deploys don't run on your PC: GitHub Actions builds and publishes the web app on Linux when you start a deploy. So it works the same from either PC.

| Step | On Windows |
|---|---|
| Web app to Netlify | **Same.** Merging doesn't deploy; when you want the live site updated, run `gh workflow run ci.yml --ref main` and the `deploy-web` job deploys after the checks pass ([`deployment.md`](deployment.md#deploying-the-web-app)). |
| Database migrations to the cloud | **Same commands**, once per PC: `supabase login`, then `supabase link --project-ref <project-ref>` (stored in git-ignored `supabase/.temp`). After that, `supabase db push` before deploying app code that needs new migrations. |
| Deploy settings (secrets) | **Same:** `gh secret set NAME --repo kangjin97/project1.0` prompts for the value. |
| Roll back | **Same:** Netlify → Deploys → publish an earlier deploy. |
| Manual web build (fallback) | Copy `app/env/prod.json` to this PC by hand, then in Git Bash: `./scripts/build.sh web`, and drag `app/build/web` onto Netlify's Deploys page. |
| Android build | **Possible** after installing Android Studio (#13). `keytool` ships with Android Studio (`<Android Studio>\jbr\bin\keytool.exe`); `./scripts/build.sh android` runs in Git Bash (it calls `python3`, which Windows doesn't include: install Python 3 first, e.g. `winget install --id Python.Python.3.12 -e`). |
| iOS build | **Mac only.** Xcode doesn't run on Windows; use the Mac or a cloud build service (#14). |

Full release steps: [`deployment.md`](deployment.md).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `'gh'` / `'flutter'` / `'supabase'` / `'docker'` is not recognized | The terminal opened before PATH changed. Open a new window, or restart the whole app that hosts the terminal. Closing the Claude app's window isn't enough: it keeps running in the system tray, so right-click its tray icon (by the clock) → **Quit**, then reopen it. |
| Can't find **Use the WSL 2 based engine** in Docker Desktop | Expected on Windows Home: WSL 2 is the only engine. Check with `wsl -l -v` (`docker-desktop`, VERSION `2`). |
| PowerShell: `The token '&&' is not a valid statement separator` | Windows PowerShell 5.1 has no `&&`. Run the commands on separate lines, or use Command Prompt. |
| `wsl`: `Wsl/CallMsi/Install/REGDB_E_CLASSNOTREG` ("installation appears to be corrupted") | WSL was never installed and Windows' built-in installer stub is broken. Run the three admin commands in step 5 and restart; don't use "repair". |
| `wsl`: `Wsl/CallMsi/Install/0x80070652`, "exit code 1618" | Another installer is still running (often the `winget install Microsoft.WSL`). Wait a few minutes, then restart. |
| `wsl --version` works but Docker says the engine won't start, or `docker version` hangs | Virtual Machine Platform isn't active until a restart. Restart; if Docker then reports virtualization disabled, enable it in the BIOS (IT may need to on a company PC). |
| `supabase_vector_group-planner` keeps restarting | Known on Windows; it only ships logs to Studio's log viewer. Harmless. To skip it: `supabase start -x vector`. |
| `flutter doctor`: "Currently on an unknown channel" | Expected: the SDK is on the `3.47.6` tag, not a channel. |
