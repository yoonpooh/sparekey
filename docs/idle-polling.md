# Idle polling measurement

The one-second watcher in `AwakeHold` exists only while Sparekey holds a display-sleep assertion. A helper without a hold has no watcher timer. Changing its cadence could delay external lock recognition or display recovery, so measurement precedes any change.

## Reproduce safely

```sh
SPAREKEY_IDLE_BENCHMARK_SECONDS=30 swift test --filter IdlePollingBenchmarkTests
```

The opt-in XCTest runs three sequential pairs. Each pair has a one-second timer-only control, then a one-second read-only watcher. Each sample lasts 30 seconds, for about 180 seconds total. The ordinary test suite skips this benchmark. The environment variable accepts whole seconds from 5 through 300.

The watcher sample calls the production `Screen.locked()`, `Screen.displayAsleep()`, and `DisplayContinuityPolicy.watcher` functions once per tick. It never calls `AwakeHold.start`, connects to the installed helper, reads a credential, inspects the accessibility tree, installs a cover, wakes a display, or locks/unlocks the Mac. It counts policy decisions but does not execute their actions. A representative idle sample requires every decision to be `keep` and every console read to succeed. The `representative_hold_idle` flag marks eligible samples; all others must be excluded from an idle baseline. Failed console reads also fail the test.

Each `IDLE_BENCHMARK` JSON line includes actual duration, tick/query count and frequency, process user+system CPU delta from `getrusage`, CPU percentage of one core, process peak RSS in Darwin bytes, and voluntary/involuntary context-switch deltas. Context switches are not a hardware wake-up count. RSS is a cumulative process high-water mark, not the marginal allocation of polling. The XCTest host and timer callbacks contribute to both CPU samples.

The control isolates timer/framework overhead. It is not a proposed implementation without monitoring. This harness covers the steady idle branch only; the cover UI, shimmer, display assertion, notification handling, real recovery and whole installed helper energy use are excluded. No system-wide power or battery saving claim follows from these measurements.

## Result on 2026-11-10

Environment was Apple M4, arm64, macOS 27.3 (26C5035r), Swift 6.4.2, debug XCTest. Production polling code is unchanged from base commit `3af0c64`. [Raw measurements](measurements/per-8-2026-11-10.json) preserve all six samples.

| Pair | Sample | Duration (s) | Queries | CPU (ms) | CPU (% of one core) | Peak RSS (MiB) | Eligibility |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | timer-control | 30.0031 | 0 | 1.590 | 0.00530 | 19.59 | control |
| 1 | read-only-watcher | 30.0052 | 30 | 14.607 | 0.04868 | 19.59 | idle, 30 keep |
| 2 | timer-control | 30.0038 | 0 | 1.632 | 0.00544 | 19.59 | control |
| 2 | read-only-watcher | 30.0107 | 30 | 11.294 | 0.03763 | 19.59 | excluded, 30 end |
| 3 | timer-control | 30.0042 | 0 | 1.808 | 0.00603 | 32.92 | control |
| 3 | read-only-watcher | 30.0101 | 30 | 12.235 | 0.04077 | 32.92 | excluded, 30 end |

The eligible watcher sample issued 30 queries in 30.0052 seconds, or 0.999826 queries/second. It consumed 14.607 ms of process CPU (0.04868% of one core), with process peak RSS 19.59 MiB. The paired timer control consumed 1.590 ms. This is one eligible pair, not enough to establish statistical confidence or a stable marginal memory cost. Context-switch deltas are included in the raw data but are not power measurements.

The first run lasted about 180 seconds. Samples 2 and 3 observed the locked-state `end` decision on every query; they are not representative of the held, unlocked idle branch. The initial harness exited with two keep-only assertion failures. The final harness explicitly marks sample eligibility instead. No recovery or locking action ran, and the Mac was not unlocked to obtain more samples.

Decision: retain the one-second production watcher without changes. The valid sample shows low CPU cost, while the small sample size and excluded samples provide no basis to trade away prompt lock recognition or display recovery. Broader installed-helper energy measurements would require a separately approved active-hold/live session. No battery, hardware wake-up, or full-helper memory improvement is claimed.

Final harness validation used `SPAREKEY_IDLE_BENCHMARK_SECONDS=5 swift test --filter IdlePollingBenchmarkTests` and passed (30 seconds total). All three query samples observed `wake` decisions with the display asleep, and `representative_hold_idle` was false. These validate exclusion reporting only; they are not extra idle samples and no wake actions ran. The raw file includes these records separately.
