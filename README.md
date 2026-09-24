# Sparekey

Sparekey 0.1.0 lets an authorized computer-use agent unlock the current user's already logged-in Mac, then relock it after the task. It cannot unlock FileVault startup, a logged-out session, or another account.

## Build and set up

Requires macOS 13 or later, Xcode Command Line Tools with Swift 5.9 or newer, and a local interactive terminal on the unlocked Mac.

```sh
swift build -c release
.build/release/sparekey setup
```

Setup creates a local self-signed code-signing identity in your login Keychain, copies and signs the binary with the hardened runtime at `~/Library/Application Support/sparekey/bin/sparekey`, saves your login password in the login Keychain with an ACL for that stable helper, and registers a per-user LaunchAgent. Signing asks for private-key use: choose **Allow**, not **Always Allow**, each time. The key is sensitive and non-extractable and no application is pre-trusted. Enter the password privately at the terminal, never in chat or command arguments. Setup checks the refreshed helper first. If it cannot read the credential, setup asks once and replaces the Keychain item with a fresh helper-only ACL, then checks again. Password entry is verified through OpenDirectory when supported. Setup prints one line per step (✓ done, • unchanged or skipped, ! warning, ✗ failed) and shows tool output only when a step fails. If Accessibility is not enabled yet, setup offers to open System Settings > Privacy & Security > Accessibility, reveal the stable copy in Finder, and copy its path; after you enable it and press Enter, setup restarts the helper and checks again. Color is used only on a terminal, and never when `NO_COLOR` is set or `TERM=dumb`.

Setup asks which agent skill targets to install. Enter chooses none. It shows Codex and Claude Code with detection status; you may choose an undetected agent too. For this Codex-only installation, use:

```sh
.build/release/sparekey setup --skill codex
```

Use `--skill claude`, `--skill claude,codex`, or repeated `--skill` for other selections. `--no-skill` skips skill installation. `--reset-password` replaces the saved credential; `--identity NAME` uses an existing code-signing identity. Rerun setup after rebuilding or upgrading to refresh the signed stable copy. Homebrew distribution through `yoonpooh/tap` is planned; the formula template is in `packaging/homebrew/sparekey.rb`.

## Use

```sh
sparekey status --json
sparekey probe --json
sparekey unlock --json
# Complete authorized computer work.
sparekey lock --json
sparekey doctor
```

No arguments show help. `sparekey version` and `sparekey --version` print the version. `probe` wakes the display and verifies the secure field without reading a password. `unlock` submits at most once and verifies the unlocked state. An agent should relock only if its own task unlocked a Mac that was initially locked. A direct request to unlock leaves it unlocked.

`--json` is supported by unlock, lock, status, probe, and doctor. Success uses `{"ok":true,"command":"status","state":"locked","message":"locked"}`; failure uses `{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}`. Exit codes: 0 success, 1 operation failure, 2 usage error. Stable error codes are `usage`, `not_set_up`, `helper_not_running`, `helper_version_mismatch`, `no_console_session`, `accessibility_missing`, `credential_unavailable`, `login_window_unsupported`, `field_not_ready`, `rate_limited`, `breaker_tripped`, `unlock_not_confirmed`, `lock_not_confirmed`, and `internal`. `doctor --json` also uses `skill_outdated`.

## Agent skills and troubleshooting

`sparekey skill install --agent codex` installs the embedded skill in `~/.agents/skills/sparekey`; `--agent claude` uses `~/.claude/skills/sparekey`. Without `--agent`, a TTY prompt chooses targets; a noninteractive call requires `--agent`. An identical skill is skipped. A changed file needs interactive confirmation and is backed up as `SKILL.md.bak`; `--force` skips confirmation, retaining the backup rule.

Run `sparekey doctor` to inspect the stable copy, signature, agent, helper version, Accessibility, credential readability, breaker, and skill files. Each failing row shows its fix underneath. A skill target that is not installed is optional and shown as `–`; an installed skill that differs from this version, or a skill path that is a symlink, not yours, or unreadable, fails (`skill_outdated` in JSON). Doctor exits 0 when no check fails. `doctor --json` keeps `checks` as a name-to-boolean map (true only when the check is `ok`) and adds `statuses`, mapping each check to `ok`, `warn`, `fail`, or `skip`; `ok` is true when no check is `fail`. If Accessibility is missing after an upgrade, enable the exact stable path again. If the helper cannot read its credential, rerun setup locally and enter the password when asked. An unconfirmed submission trips a circuit breaker; only local setup clears it. The 30-second limiter persists across helper restarts. A backward clock change resets the limiter timestamp. Do not repeatedly try a failing unlock.

`sparekey uninstall` in a local terminal removes its Keychain credential, LaunchAgent, stable copy, runtime files, and skill files matching Sparekey's embedded content. It keeps the signing identity; remove `sparekey local signing` in Keychain Access if desired. It preserves unexpected files.

The helper uses the hardened runtime without runtime exception entitlements. Its private `login.framework` fallback is an Apple-signed system library; Accessibility and Keychain calls use Apple frameworks. An isolated hardened-runtime probe loaded the Apple `login.framework` and resolved `SACLockScreenImmediate`; AX and Keychain calls still need a real signed-helper check.

Read [SECURITY.md](SECURITY.md) before setup. The lock-screen interaction approach was informed by Cindy's [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift) (Apache-2.0). Sparekey is an independent implementation.

## License

[MIT](LICENSE)
