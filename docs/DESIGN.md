# Sparekey design

Status: draft for v0.1. Supersedes the `unlock` MVP (github.com/yoonpooh/unlock).

## Purpose

Sparekey lets an AI agent that needs computer use or browser use unlock the
current user's already logged-in, locked Mac, do its work, and lock it again.

Non-goals: FileVault preboot, logged-out sessions, other users' accounts,
password recovery, remote access, or waking an unreachable Mac.

## Constraints that drive the design

- **No Apple Developer ID.** Prebuilt binaries cannot be notarized, so
  distribution builds from source on the user's Mac.
- **Code identity must be stable.** The Accessibility (TCC) grant and the
  Keychain item ACL are bound to the helper's code signature. An ad-hoc
  signature changes on every build, which would force a re-grant after every
  upgrade.
- **Data-protection keychain and `SMAppService` need an Apple team.** Without
  one, an app bundle buys little. v0.1 is a plain CLI with a launchd agent and
  the legacy file-based login keychain.

## Distribution

- Homebrew tap `yoonpooh/tap`, formula `sparekey`, built from a tagged source
  tarball with `swift build -c release`. Caveats tell the user to run
  `sparekey setup`.
- No npm, cask, or app bundle in v0.1. Revisit if a Developer ID is obtained;
  then a notarized cask becomes the preferred channel.

## Install layout

The Homebrew binary is only a client. Everything that needs a stable code
identity lives in one per-user location owned by `setup`:

```text
~/Library/Application Support/sparekey/
  bin/sparekey          helper copy, signed with the local identity
  run/control.sock      0600, directory 0700
  state.json            attempt limiter, circuit breaker, signer certificate SHA-1
~/Library/LaunchAgents/io.github.yoonpooh.sparekey.helper.plist
```

- Signing identifier: `io.github.yoonpooh.sparekey`.
- LaunchAgent label: `io.github.yoonpooh.sparekey.helper`, `ProgramArguments`
  pointing at the stable copy, `LimitLoadToSessionType = Aqua`.
- Keychain item: generic password, service `io.github.yoonpooh.sparekey`,
  account `uid:<uid>`, ACL trusting only the stable helper copy.

## Local signing identity

`setup` creates, once, a self-signed code-signing certificate named
`sparekey local signing` and signs the helper copy with it. Rebuilds signed by
the same certificate keep the same designated requirement, so TCC and the
Keychain ACL should keep trusting the helper across upgrades.

This assumption is unverified; the spike below tests it. v0.1 ships without
waiting for it, so setup must detect and recover from a lost grant or ACL.

- The identity lives in the login keychain. Its private key ACL does not
  pre-trust `/usr/bin/codesign`, so each signing asks the user to allow key
  use. Setup imports the PKCS#12 with `SecItemImport` using an empty trusted-app
  list and a sensitive, non-extractable private key. Users choose **Allow**,
  never **Always Allow**, at the signing prompt. A process that can sign
  silently with this key could build a binary the credential ACL trusts and
  read the password.
- `sparekey setup --identity <name>` signs with an existing identity instead,
  for example a free Apple ID personal-team "Apple Development" certificate.
- The credential ACL survives a rebuild (it matches the designated
  requirement), but the login keychain also partitions the item by the
  creating binary's `cdhash`, so a re-signed helper cannot read it. Before
  restarting the helper, setup runs the new stable copy's hidden
  `credential-handoff` command, stopped after about 30 seconds. It asks the running
  helper over the LaunchAgent's XPC Mach service
  `io.github.yoonpooh.sparekey.handoff`. Both connection ends set a
  code-signing requirement of the identifier plus the leaf certificate hash,
  which the helper captures at startup after verifying its running code, so
  macOS checks each peer rather than a pid looked up later. The helper answers
  only while the Mac is unlocked. The new copy saves the password only if
  OpenDirectory verifies it, deleting and re-adding the item under its own
  partition. This grants nothing beyond what the ACL already trusts: code
  signed by the pinned key. If the add fails after the delete, the restarted
  helper reports the credential unreadable and setup prompts as below.
- If the handoff is unavailable (first install, a helper older than 0.1.2, or
  `--reset-password`), setup asks for the password again instead of failing.
- If Accessibility is missing after a refresh, setup offers to open the
  Accessibility pane, reveal the stable copy, and recheck after a helper
  restart; `doctor` prints the fix under the failing row.
- Setup failures and captured tool output go to stderr; progress goes to stdout.
- `doctor` fails only required checks. Skill targets that are not installed
  are `skip`; an installed skill that differs, or an unsafe skill path, is `fail`. `--json` adds
  `statuses` (`ok|warn|fail|skip`) beside the boolean `checks` map.

## Command surface

```text
sparekey                 help (never unlocks)
sparekey unlock          one password submission, verified
sparekey lock            lock and verify; already locked is a no-op
sparekey status          locked | unlocked
sparekey probe           wake display, verify the secure field, no password
sparekey setup           create/refresh identity, helper, credential, agent
sparekey doctor          check install, signature, agent, permission, keychain
sparekey skill install   --agent claude|codex [--force]
sparekey uninstall       remove helper, credential, agent, runtime files
sparekey help [command]  also --help, -h
sparekey --version       also `version`
```

- `--json` on `unlock`, `lock`, `status`, `probe`, `doctor`.
- Exit codes: `0` success, `1` operational failure, `2` usage error.
- JSON envelope, stdout only:

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

- Stable error codes: `usage`, `not_set_up`, `helper_not_running`,
  `helper_version_mismatch`, `no_console_session`, `accessibility_missing`,
  `credential_unavailable`, `login_window_unsupported`, `field_not_ready`,
  `rate_limited`, `breaker_tripped`, `unlock_not_confirmed`,
  `lock_not_confirmed`, `internal`.
- Diagnostics go to stderr. Honor `NO_COLOR` and non-TTY output.

## Helper protocol

Newline-delimited JSON over the Unix socket, one request per connection:

```json
{"v":1,"command":"status"}
{"v":1,"ok":true,"state":"locked","message":"locked","helperVersion":"0.1.2"}
```

Both sides check the peer UID. The client reports `helper_version_mismatch`
and asks for `sparekey setup` when versions differ.

## Safety rules carried over from the MVP

- Verify console user, Apple-signed `loginwindow`, own-account label, a single
  `UserPasswordTextField` secure field, and `LUIBUTTON_GO` before any input.
- Submit the password at most once per request. No clipboard, no global typing.
- Fail closed on dialogs, user lists, recovery screens, or layout changes.
- Never raise Keychain UI while reading (`SecKeychainSetUserInteractionAllowed(false)`).

## Safety changes

- **Persistent limiter.** The 30-second attempt interval lives in
  `state.json`, so restarting the helper cannot bypass it. If the wall clock
  moves backward, reset the timestamp instead of locking out indefinitely.
- **Circuit breaker.** An unconfirmed unlock trips the breaker. Later unlocks
  fail with `breaker_tripped` until the user runs `sparekey setup` locally.
  This stops a stale saved password from piling up failed logins.
- **Password check at setup.** Verify with `ODRecord.verifyPassword` before
  saving. Whether this counts toward failed-login limits is unverified; it runs
  once, interactively.
- **No-arg is help.** Unlock must be requested explicitly.
- **Awake hold.** Unlocking does not reset the HID idle time, so idle display
  sleep would relock the Mac minutes into the task. After a confirmed unlock
  the helper holds a `PreventUserIdleDisplaySleep` assertion. It is released
  on `lock`, within 5 seconds of any other relock, after 60 minutes, or when
  the helper exits. Sparekey does not lock on expiry: afterwards the Mac's own
  display sleep and password settings apply again, so an agent that never
  relocks leaves the Mac unlocked for up to an hour plus whatever those
  settings allow. If creating the assertion fails, unlock still succeeds and
  the message says the display could not be kept awake.

## Lock method

Keep Control-Command-Q plus lock-state verification. The helper is signed
with hardened runtime and no exception entitlements. The private fallback
loads an Apple-signed system framework; AX and Keychain use Apple frameworks.
An isolated hardened-runtime probe loaded the framework and resolved the
fallback symbol. AX and Keychain still need a real signed-helper run. Whether the shortcut
fails on non-US layouts or remapped shortcuts is unverified. If it does not
lock within the timeout, the helper resolves `SACLockScreenImmediate` from
`login.framework` with `dlopen` as a fallback, then verifies the lock state.

## Setup and upgrade flow

1. `sparekey setup` must run in a local interactive terminal, unlocked, not
   over SSH, not as root.
2. Create the local identity if missing.
3. Copy the running binary to the stable path, sign with hardened runtime,
   and verify identifier, selected certificate fingerprint, and runtime flag.
4. Write the LaunchAgent plist, `bootout` then bounded-retry `bootstrap`.
5. Ask the refreshed helper to `check`. An `ok:false` error aborts setup. If the
   helper reports an unreadable credential or `--reset-password` was given,
   the stable signed copy prompts once with echo off, verifies the password,
   deletes and re-adds the item with a fresh ACL, restarts the helper, and
   checks readability again. Otherwise keep the existing item.
6. Pin the signing certificate in state.json and reset the circuit breaker.
7. Prompt for skill targets (default: none) unless `--skill` or `--no-skill`
   selects them explicitly. A skill failure warns without hiding the
   Accessibility step.
8. Print the Accessibility step for the stable path if not yet granted.

After `brew upgrade`, rerunning `setup` refreshes the copy without asking for
the password again.

## Agent skill

The skill text ships inside the binary. Targets:

- Claude Code: `~/.claude/skills/sparekey/SKILL.md`, when `~/.claude` exists.
- Codex: `~/.agents/skills/sparekey/SKILL.md`, when `~/.agents` or `~/.codex`
  exists.

`setup` lists Claude Code and Codex, marks detected agents, and asks which
skill targets to install. Enter selects none. `setup --skill codex`,
`--skill claude`, or `--skill claude,codex` skips the prompt; `--skill` is
repeatable. `--no-skill` also skips the prompt and conflicts with `--skill`.
Undetected agents may be selected explicitly and their skill directory is
created. `sparekey skill install` prompts the same way on a TTY; without a
TTY it requires `--agent claude|codex`. An identical existing
file is left alone. A different one is replaced only after an interactive
yes, with the old file kept as `SKILL.md.bak`. `sparekey skill install
[--agent claude|codex] [--force]` does the same outside setup, and
`uninstall` removes only skill files whose content Sparekey wrote.

The skill keeps the MVP's ownership rule: relock only if this task unlocked
an initially locked Mac.

## Signing spike

Goal: prove a locally self-signed helper keeps its TCC grant and Keychain ACL
across a rebuild.

1. Create a throwaway self-signed code-signing identity.
2. Build two probe binaries that differ in code, sign both with that identity
   and identifier `io.github.yoonpooh.sparekey.spike`, and compare the
   designated requirements.
3. Install v1 at a fixed path. The user grants Accessibility to it manually.
4. Run v1 through a temporary LaunchAgent: report `AXIsProcessTrusted()` and
   save a dummy Keychain item that trusts only that path.
5. Replace it with v2 at the same path. Run through the LaunchAgent again:
   report `AXIsProcessTrusted()` and read the dummy item with user interaction
   disabled.
6. Record every authentication prompt seen.
7. Clean up the identity, dummy item, agent, files, and TCC entry.

Pass: v2 is trusted for Accessibility and reads the item without a prompt.

## Roadmap

- v0.1: spike, core port, commands above, tap formula, skill install, docs.
- Later: lease with auto-relock, `run -- <cmd>`, npm launcher, notarized cask
  once a Developer ID exists, MCP mode if agents need typed tools.
