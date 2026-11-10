# PER-6, PER-7, PER-8 local results

Completed within the approved local scope on 2026-11-10. No installed binary, security setting, real lock/unlock state, issue status, PR, or thread lifecycle was changed by this work.

## PER-6

Helper absence/refused connection, timeout, disconnect, other socket failure, and complete replies are distinct. Doctor and setup startup checks preserve those distinctions. Timeout/disconnect guidance recommends a status check, warns against repeating unlock, and does not recommend reinstalling. Setup retries only helper absence during its existing bounded startup wait.

Socketpair tests reproduce complete replies, EOF with partial data, a slow partial frame, and a stalled connection. A unique nonexistent Unix socket reproduces helper absence. Doctor tests cover codes and hints; setup tests verify retry count and immediate propagation. Unlock execution and authority policy are unchanged.

Testing also exposed that macOS refuses `SO_NOSIGPIPE` configuration after a peer has already closed. Sending with `MSG_NOSIGNAL` now prevents process termination in that race. The unconfigured, closed-peer test reproduces it without touching the installed helper.

## PER-7

[Preparation diagnostics](preparation-diagnostics.md) record inspection counts and elapsed monotonic milliseconds, once per preparation, including failures. Success metrics go to unified logging; errors also include them in the reply. A typed numeric accumulator never stores inspected values or error payloads. Deterministic tests include successful and failed inspections and unchanged retry timing/count. The existing recovery, privilege, and password-submission flow is unchanged.

## PER-8

[Method and measurements](idle-polling.md) and [raw samples](measurements/per-8-2026-11-10.json) document the read-only experiment. The valid 30-second sample made 30 queries at 0.999826 Hz and used 14.607 ms CPU, or 0.04868% of one core. Peak process RSS was 19.59 MiB. Two later locked-state samples were excluded. The final eligibility-reporting harness passed a separate 30-second check with all display-asleep samples correctly marked ineligible.

Retain the existing one-second cadence. One low-cost eligible pair does not justify changing timely lock detection or recovery. These are XCTest host measurements, not full-helper power use or marginal memory. The benchmark executes no recovery actions.

## Validation

- `swift test` passed. Core 88 tests; transport 23 tests including one opt-in benchmark skip. Total 110 passed, one skipped, zero failures.
- `SPAREKEY_IDLE_BENCHMARK_SECONDS=5 swift test --filter IdlePollingBenchmarkTests` passed. One test, 30 seconds, six samples. These samples validate exclusion reporting and are not an idle baseline.
- `swift build -c release` passed. Existing deprecated Keychain API warnings remain.
- `python3 scripts/smoke.py` passed with temporary runtime/home directories. Public CLI help, JSON usage errors, missing setup, and temporary skill installation were checked without contacting the real helper.
- `python3 scripts/embed-agent-assets.py --check` passed.
- `git diff --check` passed.

Initial failures and their resolutions are preserved above: socket shutdown alone did not reproduce a closed peer; an actually closed peer exposed the SIGPIPE race; the first benchmark's keep-only assertions rejected locked-state samples. The final test suite is green. Real preparation/unlock execution, installed-helper replacement, full-helper power profiling, and persistent info-log availability were not tested.

## Changed files

- [Sources/SparekeyCore/Output.swift](../Sources/SparekeyCore/Output.swift)
- [Sources/SparekeyCore/PreparationDiagnostics.swift](../Sources/SparekeyCore/PreparationDiagnostics.swift)
- [Sources/sparekey/Doctor.swift](../Sources/sparekey/Doctor.swift)
- [Sources/sparekey/EmbeddedSkill.swift](../Sources/sparekey/EmbeddedSkill.swift)
- [Sources/sparekey/Screen.swift](../Sources/sparekey/Screen.swift)
- [Sources/sparekey/Setup.swift](../Sources/sparekey/Setup.swift)
- [Sources/sparekey/Transport.swift](../Sources/sparekey/Transport.swift)
- [Tests/SparekeyCoreTests/OutputTests.swift](../Tests/SparekeyCoreTests/OutputTests.swift)
- [Tests/SparekeyCoreTests/PreparationDiagnosticsTests.swift](../Tests/SparekeyCoreTests/PreparationDiagnosticsTests.swift)
- [Tests/SparekeyTransportTests/IdlePollingBenchmarkTests.swift](../Tests/SparekeyTransportTests/IdlePollingBenchmarkTests.swift)
- [Tests/SparekeyTransportTests/SetupCheckTests.swift](../Tests/SparekeyTransportTests/SetupCheckTests.swift)
- [Tests/SparekeyTransportTests/TransportTests.swift](../Tests/SparekeyTransportTests/TransportTests.swift)
- [docs/CLI.md](CLI.md)
- [docs/idle-polling.md](idle-polling.md)
- [docs/measurements/per-8-2026-11-10.json](measurements/per-8-2026-11-10.json)
- [docs/per-6-8-results.md](per-6-8-results.md)
- [docs/preparation-diagnostics.md](preparation-diagnostics.md)
- [skills/sparekey/SKILL.md](../skills/sparekey/SKILL.md)
