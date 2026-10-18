# Changelog

All notable changes are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.3.7] - 2026-10-18

- Limit inbound helper request frames to two seconds so a stalled connection cannot hold the serial request loop for twenty seconds or longer. The limit ends before screen operations begin.
- Enforce one monotonic deadline across partial socket reads and interrupted calls. Read into a fixed buffer while preserving newline framing, message size limits, and one request per connection.
- Add eleven real-socket regression checks, including slow partial input, idle clients, fragmented messages, exact size limits, disconnects, and request/reply round trips.

## [0.3.6] - 2026-10-18

- Include the observed loginwindow window count in unsupported-layout errors. A leftover Force Quit Applications dialog can otherwise look like an unsupported lock screen.
- Teach agents to distinguish a failed probe from a failed unlock. After a multi-window probe failure, allow one repair: positively identify the leftover Force Quit Applications dialog from native window metadata, close only that dialog, and rerun probe once before unlocking.
- Keep the single-window requirement, account and field verification, password handling, and failed-unlock stops unchanged. Unknown, authentication, and security dialogs must not be dismissed automatically.

## [0.3.5] - 2026-10-18

- Distinguish a later locked screen from confirmed user takeover in the agent skill. Continue authorized desktop work with a fresh probe, one unlock, verification, and a fresh cleanup token; do not reuse expired tokens or loop unlocks when desktop work cannot resume.
- Allow a new desktop request after the agent's cleanup lock. Keep user stop requests, confirmed takeover, failed unlocks, and `relock_revoked` as stop conditions; explicit user reauthorization can resume access after takeover or revoked authority.
- Add installed-skill regression checks for both Codex and Claude Code. Helper lock/unlock behavior and credential handling are unchanged.

## [0.3.4] - 2026-10-16

- Install Codex and Claude Code as standalone skills using the same file installer. Fresh Codex installs no longer need Codex CLI or marketplace registration.
- Remove and verify previously registered local Sparekey plugins before writing the Codex skill. Preserve unrelated marketplace entries, original plugin sources, recovery backups, and customized skills.
- Check skill files directly in `doctor`, preserving the `codex_skill` JSON key. Remove bundled plugin assets and update all installation documentation.
- Keep lock, unlock, credential, and display behavior unchanged.

## [0.3.3] - 2026-10-12

- Fix the Codex plugin source at `~/.codex/plugins/sparekey`, alongside other personal plugins.
- Migrate existing `~/plugins/sparekey` registrations without changing other marketplace entries or their order. Verify the new installed path/version and activation before moving the legacy source to a unique backup.
- Preserve customized destination packages with the existing confirmation and backup flow. Reject symlinked package trees and restore our marketplace update on failed installation without overwriting concurrent changes.
- Refresh release versions and bundled agent assets. Screen lock, credential, and unlock behavior are unchanged.

## [0.3.2] - 2026-10-12

- Treat a missing or empty FocusedUser account label as temporary preparation state, using the existing bounded wait and single display recovery before stopping. Never accept an unverified account or broaden name matching.
- Distinguish a populated name mismatch (`login_account_mismatch`) from duplicate labels, unsupported element roles, and unreadable labels. Do not expose account names in errors.
- Clarify skill error reporting and that a healthy `doctor` result does not verify the lock screen. Retain fail-closed password checks and the no-retry rule after a failed probe or unlock.
- Require matching 0.3.2 CLI/helper versions and refresh the bundled agent assets.

## [0.3.1] - 2026-10-10

- Turn off the displays after a verified relock and release the display recovery watcher before sleeping. Report unconfirmed display sleep without retrying the lock.
- Replace the cover Lock Mac button with Unlock Mac. Require fresh native macOS authentication, then reveal the screen and revoke the agent task's relock authority; keep the cover on cancellation or stale authentication.
- Restrict the Sparekey skill to actual macOS desktop computer use; exclude headless and DOM/CDP browser automation and webpage screenshots.
- Return a relock token from unlock (and grace-period probe). Require it for task cleanup and revoke it immediately on authenticated cover takeover, system screen-lock notification, or hold expiry. Reject stale and tokenless cleanup requests; explicit manual locking uses `lock --force`.
- Require matching 0.3.1 CLI/helper versions. Regenerate embedded skills and the Codex plugin cache version.

## [0.3.0] - 2026-09-27

- Install a Codex plugin with the existing logo through `setup --skill codex` and `skill install --agent codex`. Verify activation before backing up and removing the old standalone skill; preserve Claude Code's skill installer.
- Report Codex plugin status in `doctor`, remove installed plugins through Codex CLI during uninstall, and embed plugin assets with a content-based cache version.

## [0.2.1] - 2026-09-26

- Place the cover and acquire the display wake hold before any `probe` or covered `unlock` wake, retain both when a grace-period wake unlocks the session, and create a cover before retrying an unexpected display wake. Reset submission tracking per attempt and force an immediate lock action even when display-sleep grace has set the lock flag.

## [0.2.0] - 2026-09-25

- Recover once from an awake login screen that has no account label or password field by cycling display sleep and remote wake before giving up.

- Place a black cover on every physical display before password submission, with a one-click Lock Mac button and an embedded logo. The cover is excluded from screen capture and allows input to reach apps underneath. `unlock --no-cover` skips it.

## [0.1.2] - 2026-09-24

- Keep the saved password across upgrades. Setup has the running helper hand it to the re-signed helper, which re-saves it under its own Keychain partition. Upgrading from 0.1.1 or earlier still asks once.

## [0.1.1] - 2026-09-24

- Retry transient login-screen inspection failures during the existing five-second preparation window, with distinct inspection-limit diagnostics and unchanged security checks.
- Keep the display awake after a confirmed unlock until `sparekey lock`, any other relock, or 60 minutes. Before, idle display sleep could relock the Mac minutes into an agent task because unlocking does not reset the idle timer.

## [0.1.0] - 2026-09-24

First public release.

- Signed per-user helper with verified screen unlock and lock, and a JSON CLI: `unlock`, `lock`, `status`, `probe`, `setup`, `doctor`, `skill install`, `uninstall`.
- Local setup that signs a stable helper copy with a pinned local certificate and the hardened runtime, imports a non-extractable signing key with no pre-trusted apps, and saves the login password in the login Keychain with a helper-only ACL.
- Persistent 30-second attempt limiter and a circuit breaker that stops retries after an unconfirmed unlock.
- Selectable agent skills for Codex and Claude Code. The skill checks the lock before GUI work, unlocks once, and relocks only what it unlocked.
- Step-by-step setup output that hides tool noise unless a step fails, with guided Accessibility setup.
- `doctor` with aligned checks, fix hints, and `statuses` in `--json`. Respects `NO_COLOR` and `TERM=dumb`.
- Homebrew formula that builds from source.
