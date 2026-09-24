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
  state.json            attempt limiter and circuit breaker
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

This assumption is unverified. See the spike below; it gates the rest of the
build. Where the identity is stored (login keychain vs a dedicated keychain)
and how many authentication prompts it costs are also spike outputs.

Fallback if the spike fails: require a free Apple ID personal-team
"Apple Development" certificate, as the MVP did.

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
{"v":1,"ok":true,"state":"locked","message":"locked","helperVersion":"0.1.0"}
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
  `state.json`, so restarting the helper cannot bypass it.
- **Circuit breaker.** An unconfirmed unlock trips the breaker. Later unlocks
  fail with `breaker_tripped` until the user runs `sparekey setup` locally.
  This stops a stale saved password from piling up failed logins.
- **Password check at setup.** Verify with `ODRecord.verifyPassword` before
  saving. Whether this counts toward failed-login limits is unverified; it runs
  once, interactively.
- **No-arg is help.** Unlock must be requested explicitly.

## Lock method

Keep Control-Command-Q plus lock-state verification. Whether it fails on
non-US layouts or remapped shortcuts is unverified. Evaluate
`SACLockScreenImmediate` (private, `dlopen`) as a fallback during v0.1 testing.

## Setup and upgrade flow

1. `sparekey setup` must run in a local interactive terminal, unlocked, not
   over SSH, not as root.
2. Create the local identity if missing.
3. Copy the running binary to the stable path, sign it, verify the signature.
4. If no credential exists or `--reset-password` is given, read the password
   twice with echo off, verify it, and save it. Otherwise keep the existing one.
5. Write the LaunchAgent plist, `bootout` then `bootstrap`.
6. Reset the circuit breaker.
7. Print the Accessibility step for the stable path if not yet granted.

After `brew upgrade`, rerunning `setup` refreshes the copy without asking for
the password again.

## Agent skill

The skill text ships inside the binary. `sparekey skill install` writes it to
`~/.claude/skills/sparekey/SKILL.md` or the Codex user skills directory
(currently documented as `~/.agents/skills`; verify before release). It
refuses to overwrite without `--force`. The skill keeps the MVP's ownership
rule: relock only if this task unlocked an initially locked Mac.

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
