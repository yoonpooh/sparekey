# Changelog

## [Unreleased]

- Restyle setup as one status line per step, hide openssl, codesign, and launchctl output unless a step fails, and allow up to three password attempts.
- Offer to open the Accessibility pane, reveal the helper, copy its path, and recheck after a helper restart during setup.
- Restyle doctor with aligned rows, fix hints, and a summary; skill targets that are not installed no longer fail doctor.
- Add `statuses` to `doctor --json` and the `skill_outdated` error code.
- Respect `NO_COLOR` and `TERM=dumb`; color only on a terminal.

## [0.1.0] - 2026-09-24

- Add signed per-user helper, verified screen unlock and lock, JSON CLI, local setup and uninstall.
- Add persistent attempt limiter and circuit breaker, doctor checks, and selectable agent skills.
- Pin the signing certificate and hardened runtime, import a non-extractable signing key with no pre-trusted apps, and verify credential refresh through the helper.
- Add source-build Homebrew formula template and non-destructive smoke checks.
