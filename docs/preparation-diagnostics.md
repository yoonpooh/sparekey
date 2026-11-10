# Preparation diagnostics

Preparation records the number of login-window snapshot inspections and elapsed monotonic milliseconds. Failed snapshot calls count as inspections. The measurement spans the existing wake, inspection, and optional recovery sequence. It excludes password reading/submission and later unlock confirmation.

Each completed or failed preparation emits one unified log entry in subsystem `io.github.yoonpooh.sparekey`, category `preparation`, at info level. The entire public log message is generated from an integer count and elapsed time. It accepts no snapshot, account name, password, token, key, or exception text. Error replies also append these two metrics to their existing safe error/recovery message.

Read recent entries without invoking a preparation operation:

```sh
log show --last 1h --info --style compact --predicate 'subsystem == "io.github.yoonpooh.sparekey" AND category == "preparation"'
```

Example:

```text
Preparation: inspections=3; elapsed_ms=200.
```

Unified logging controls retention of info entries. During an approved live investigation, `log stream --level info` with the same predicate can capture them. This change does not enable persistent debug logging, change permissions, or add any wake, snapshot, recovery, password submission, or unlock retry.

Local validation uses deterministic clock values and synthetic closures in `PreparationDiagnosticsTests`. It covers successful and failed inspections, absence of sensitive input/output in the report, and unchanged retry count/timing. Real lock-screen execution is deliberately outside this change's validation scope.
