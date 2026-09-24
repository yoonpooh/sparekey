---
name: sparekey
description: Use at the start of any computer-use, browser-use, screenshot, or GUI app task on this Mac, and whenever app or window access fails, times out, returns no windows, or the screen looks locked. Checks the lock state, unlocks the current user's locked session with the local sparekey helper, and relocks it when the task is done.
---

# Sparekey

Run `sparekey` from PATH. If it is missing, use `~/Library/Application Support/sparekey/bin/sparekey`.

## 1. Check first

Before the first GUI action of a task, run `sparekey status --json`. Record `initial_state` and set `unlocked_for_task = false`.

If a GUI tool fails, times out, or sees no windows, run `sparekey status --json` before retrying anything else. Do not keep retrying apps, Finder, or other windows on a locked Mac.

If `state` is `unlocked`, continue the task. This task did not unlock it.

## 2. Unlock when needed

A user request for a task that needs computer use or browser use on this Mac authorizes unlocking for that task. Do not unlock if the user said to leave the Mac locked or asked only for status.

When `state` is `locked`:

1. `sparekey probe --json` and require `ok: true`.
2. `sparekey unlock --json` once.
3. `sparekey status --json` and require `state: "unlocked"`.
4. Set `unlocked_for_task = true`, then continue the original task.

For a covered unlock, the helper places a black cover beneath the lock screen before password submission, so it is already in place when the lock screen dismisses. It is intentionally invisible in screenshots, and clicks and typing still reach the apps underneath. The helper keeps the display awake until `sparekey lock` or 60 minutes, whichever comes first, so idle display sleep does not relock the Mac mid-task. If the Mac relocks later in the task, stop and report it. The user may have clicked the cover's Lock Mac button; do not unlock again for this task.

Never retry a failed unlock, type a password through UI automation, ask for the password in chat, or restart the helper to get around its limits.

## 3. Relock when done

If `unlocked_for_task` is true and `sparekey status --json` still says `unlocked`, run `sparekey lock --json` and then `sparekey status --json` after the last GUI action and before the final response. Do this even when the task failed or was abandoned. Report the lock as restored only when `state` is `locked`.

Do not relock when the Mac was already unlocked at the start, the user asked to keep it unlocked, a request was only to unlock, or another known task is still using the screen.

## Errors

Stop, report the `error.code`, and tell the user what to do:

- `not_set_up`, `helper_not_running`, `helper_version_mismatch`, `accessibility_missing`, `credential_unavailable`: ask the user to run `sparekey doctor`, then `sparekey setup` in a local terminal. Never run setup yourself.
- `breaker_tripped`, `unlock_not_confirmed`: the saved password may be wrong. Ask the user to run `sparekey setup --reset-password` locally.
- `rate_limited`: an attempt ran in the last 30 seconds. Check status instead of retrying.
- `login_window_unsupported`, `field_not_ready`: the lock screen is in an unexpected state. Ask the user to check the Mac.

Sparekey cannot help with FileVault startup, logged-out sessions, other accounts, or a sleeping Mac that is unreachable.
