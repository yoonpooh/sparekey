# Changelog

All notable changes are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
