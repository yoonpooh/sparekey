<p align="center">
  <img src="docs/assets/logo.png" alt="Sparekey logo" width="140">
</p>

<h1 align="center">Sparekey</h1>

<p align="center">
  <strong>A spare key to your Mac, for your AI agent.</strong><br>
  Unlock the screen, get the work done, lock it again.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black.svg" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
</p>

<p align="center">
  English · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a>
</p>

<p align="center">
  <sub>Latest release: <strong>0.2.1</strong>, which keeps the display awake when macOS turns it off right after an unlock. See the <a href="CHANGELOG.md">changelog</a>.</sub>
</p>

<p align="center">
  <img src="docs/assets/cover.png" alt="Sparekey screen cover on a Mac display" width="720">
</p>

## Why Sparekey

Computer-use and browser-use agents stall the moment your Mac locks. You either leave the Mac unlocked for hours or come back to a task that never ran.

Sparekey is a small macOS CLI that lets an agent unlock **your own, already logged-in** session with a password you saved locally, finish its task, and restore the lock. While the agent works, a black cover hides the physical displays from people nearby.

```sh
sparekey unlock   # let the agent get to work; cover the physical displays
sparekey lock     # restore the lock when it is done
```

With the bundled agent skill, you don't have to mention any of this. Ask for an ordinary GUI task on a locked Mac, and the agent checks the lock, unlocks, does the work, and locks the screen again on its own.

### What it is not

Sparekey is not a password bypass, recovery tool, or remote-access service. It cannot unlock FileVault at startup, a logged-out session, another user's account, or a sleeping Mac that is unreachable.

> [!WARNING]
> **Status: early (0.2.1).** Sparekey works on macOS 27.2 on Apple silicon, where two unprompted agent runs unlocked, worked, and relocked successfully. Other macOS versions are untested. It depends on the lock screen's Accessibility layout, not a public unlock API.

## Quick start

You need macOS 13 or later with a logged-in desktop session, Xcode Command Line Tools with Swift 5.9 or newer, and a local terminal on the Mac for the one-time setup. No Apple Developer account is needed.

**1. Install** with Homebrew (builds from source on your Mac):

```sh
brew install yoonpooh/tap/sparekey
```

**2. Set up** in a local terminal while the Mac is unlocked, not over SSH:

```sh
sparekey setup --skill codex   # or: --skill claude, --skill claude,codex, --no-skill
```

When macOS asks to use the signing key, click **Allow**, not **Always Allow**. When setup asks for your login password, type it at the hidden prompt.

**3. Use it.** Ask your agent for a GUI task, or run it yourself:

```sh
sparekey status   # locked or unlocked
sparekey doctor   # check the install
```

**Or ask your agent.** Paste this into Codex, Claude Code, or another agent. It installs Sparekey and hands you only the setup step, because the password prompt needs your own terminal:

```text
Install Sparekey on this Mac: https://github.com/yoonpooh/sparekey
1. Run `brew install yoonpooh/tap/sparekey`.
2. Setup asks for my login password, so don't run `sparekey setup` yourself.
   Tell me the exact command to run in my own terminal, with the --skill
   option for the agent you are, and wait until I say it's done.
3. Run `sparekey doctor` and report the result.
Never ask me for the password.
```

<details>
<summary><strong>Build from source instead</strong></summary>

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

Then put `sparekey` on your `PATH`:

```sh
ln -s "$HOME/Library/Application Support/sparekey/bin/sparekey" ~/.local/bin/sparekey
sparekey doctor
```

</details>

<details>
<summary><strong>What setup does</strong></summary>

1. Creates a `sparekey local signing` identity in your login Keychain (first run only).
2. Signs and installs the helper at `~/Library/Application Support/sparekey/bin/sparekey`.
   - When macOS asks to use the signing key, click **Allow**, not **Always Allow**.
3. Asks for your login password twice. Input is hidden and checked against macOS.
   - Never paste it into chat, a command argument, or an environment variable.
4. Starts the background helper and installs the agent skill you chose.
5. Helps you turn on **Accessibility** for the helper. It opens the settings pane, shows the file in Finder, and copies its path, then checks again after you enable it.

</details>

### Upgrading

After `brew upgrade sparekey` or rebuilding, run `sparekey setup` again. Until you do, the new CLI reports `helper_version_mismatch`. Setup refreshes the signed helper without asking for the password, unless the helper can no longer read it.

## Features

- **Verified unlock and lock.** `unlock` submits the password once and confirms the new state; `lock` locks and confirms. Already locked is a no-op.
- **Screen cover.** Inspired by Codex's Locked Computer Use. A black cover with the Sparekey logo, “Your agent is using this Mac,” and a **Lock Mac** button hides the physical displays while the agent works.
  - It appears beneath the lock screen **before** password submission, so the desktop never flashes.
  - Screenshots and screen recordings exclude it, so the agent still sees the real screen, and its clicks and typing pass through.
  - One click on **Lock Mac** locks the Mac. `sparekey lock` or any relock removes the cover.
  - `sparekey unlock --no-cover` skips it. The cover hides the screen but does not lock it.
- **Stays awake.** After a confirmed unlock, the display stays awake until `sparekey lock`, any other relock, or 60 minutes, so idle sleep does not relock the Mac mid-task.
- **Lock-screen recovery.** If an awake locked screen shows only the wallpaper and clock instead of your account, Sparekey performs one display sleep→wake cycle to bring the account back. It never types into an unverified screen.
- **Fails closed.** One password submission at most, a 30-second limiter, and a circuit breaker after an unconfirmed unlock.
- **Agent skills** for Codex and Claude Code, plus `--json` output for scripts.

## How it works

```text
agent ──▶ sparekey CLI ──(private Unix socket, same-user check)──▶ helper (LaunchAgent)
                                                                     │
                     verifies console user, Apple-signed loginwindow,│
                     your account, and a single secure password field│
                                                                     ▼
                         login Keychain ──▶ one submission ──▶ state check
```

- `setup` copies the binary to a fixed location, signs it with a local code-signing identity, and runs it as a per-user background helper.
- The password lives in your login Keychain. Only that signed helper is allowed to read it.
- The helper fills only a verified password field, submits **at most once**, and fails closed on anything unexpected: other accounts, dialogs, recovery screens, or layout changes.
- A persistent 30-second limiter and a circuit breaker stop a stale password from piling up failed logins.

Design notes are in [docs/DESIGN.md](docs/DESIGN.md).

## Agent skills

Setup can install a skill for **Codex** (`~/.agents/skills/sparekey`) and **Claude Code** (`~/.claude/skills/sparekey`). You can also install it later:

```sh
sparekey skill install --agent codex   # or: --agent claude
```

The skill tells the agent to:

- check the lock state before GUI work, or as soon as app or window access fails;
- unlock once, verify it, and do the task;
- relock afterwards, but only if it was the one that unlocked the Mac, even when the task fails;
- stop and report errors instead of retrying.

Asking for GUI work counts as permission to unlock for that task. Tell the agent if you want the Mac left locked or left unlocked.

### Pre-authorize it in your agent instructions

In multi-agent setups, an orchestrator may tell its workers to leave the lock alone, or an agent may stop to ask first. To avoid that, add this to your `CLAUDE.md`, `AGENTS.md`, or orchestrator system prompt:

```text
Screen lock: I pre-authorize unlocking this Mac with the sparekey skill
for any task that needs the screen. Use it without asking, and never
restrict this when delegating to other agents.
```

Without it, the skill still unlocks for the GUI tasks you ask for. The line keeps that permission from being dropped or questioned along the way.

## Commands

| Command | What it does |
| --- | --- |
| `sparekey unlock [--no-cover]` | Unlock once, confirm the state, cover the physical displays by default, and keep the display awake until `lock` or 60 minutes |
| `sparekey lock` | Lock and confirm; already locked is a no-op |
| `sparekey status` | Print `locked` or `unlocked` |
| `sparekey probe` | Wake the display and check the password field without reading the password |
| `sparekey setup` | Install or refresh the helper, credential, and skills. Options: `--skill`, `--no-skill`, `--reset-password`, `--identity NAME` |
| `sparekey doctor` | Check the install, signature, helper, Accessibility, credential, and skills |
| `sparekey skill install` | Install the agent skill. Options: `--agent claude\|codex`, `--force` |
| `sparekey uninstall` | Remove the helper, credential, LaunchAgent, and Sparekey-written skills |
| `sparekey help [command]` | Show help |
| `sparekey version` | Print the version |

Running `sparekey` with no arguments shows help; it never unlocks.

<details>
<summary><strong>JSON output, exit codes, and error codes</strong></summary>

`unlock`, `lock`, `status`, `probe`, and `doctor` accept `--json`:

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

Exit codes: `0` success, `1` operational failure, `2` usage error. A successful `status` can report either state, so check `state`.

Error codes: `usage`, `not_set_up`, `helper_not_running`, `helper_version_mismatch`, `no_console_session`, `accessibility_missing`, `credential_unavailable`, `login_window_unsupported`, `field_not_ready`, `cover_unavailable`, `rate_limited`, `breaker_tripped`, `unlock_not_confirmed`, `lock_not_confirmed`, `internal`. `doctor --json` can also report `skill_outdated`, and adds a per-check `statuses` map (`ok`, `warn`, `fail`, `skip`).

</details>

## FAQ and troubleshooting

Start with `sparekey doctor`. Every failing row shows how to fix it.

**Does the cover lock my Mac?**
No. It hides the screen but does not lock it. Click **Lock Mac** on the cover, or run `sparekey lock`.

**Why don't I see the cover in the agent's screenshots?**
That is by design. Screenshots and screen recordings exclude the cover, so the agent sees the real screen.

**The lock screen shows only the wallpaper and clock.**
Sparekey performs one display sleep→wake cycle to bring the account back. It never types into an unverified screen.

**`helper_version_mismatch`**
The CLI was upgraded or rebuilt, but the helper was not. Run `sparekey setup` again.

**Accessibility missing**
Enable `~/Library/Application Support/sparekey/bin/sparekey` in System Settings → Privacy & Security → Accessibility. If you just enabled it, run `setup` again or restart the helper:

```sh
launchctl kickstart -k "gui/$(id -u)/io.github.yoonpooh.sparekey.helper"
```

**`breaker_tripped` or `unlock_not_confirmed`**
The saved password may be wrong, for example after you changed it. Run `sparekey setup --reset-password` locally.

**`credential_unavailable` after an upgrade**
Run `sparekey setup` again and enter the password when asked.

**`rate_limited`**
An attempt ran in the last 30 seconds. Don't loop on it.

## Security

Please read [SECURITY.md](SECURITY.md) before installing. In short:

- **Any process running as your user can ask the helper to unlock.** Sparekey is for a trusted personal account. It does not protect you from malware that is already running as you.
- The default cover hides the physical displays during agent work. Screenshots omit the cover, and the agent can still operate apps underneath it.
- The helper uses the hardened runtime and listens only on a private local socket, never on the network.
- The signing key cannot be exported and no app is pre-trusted to use it. Clicking **Always Allow** would change that.
- Never paste your login password into chat, a command argument, or an environment variable. Enter it only at setup's hidden prompt.

Report vulnerabilities privately through GitHub's security advisories.

## Uninstall

```sh
sparekey uninstall
```

This removes the saved credential, helper, LaunchAgent, runtime files, and the skill files Sparekey wrote. It does not remove:

- the `sparekey local signing` identity (delete it in Keychain Access if you want);
- the Accessibility entry (remove it in System Settings);
- the `~/.local/bin/sparekey` link.

## Credits

The lock-screen interaction approach was informed by Cindy's [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift) (Apache-2.0). Sparekey is an independent implementation.

## License

[MIT](LICENSE) © yoonpooh
