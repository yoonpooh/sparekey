---
name: sparekey
description: Use only when a task requires computer use on the actual macOS desktop: native app/window interaction, desktop input, or capture of the actual Mac screen. Do not use for headless browsers, DOM/CDP browser automation, webpage screenshots, APIs, CLIs, or connectors. Checks the lock state, unlocks the current user's locked session with the local sparekey helper, and relocks it when the task is done.
---

# Sparekey

Run `sparekey` from PATH. If it is missing, use `~/Library/Application Support/sparekey/bin/sparekey`.

## Scope: actual desktop access only

Headless agent-browser and Playwright, DOM/CDP operations (even with a visible browser), and browser-rendered webpage screenshots do not require Sparekey. Browser login failures, timeouts, and missing DOM elements do not justify checking or unlocking the Mac. Only apply this skill when switching to actual macOS desktop computer use. Use `status` for an explicit Sparekey status request without unlocking.

## 1. Check first

Before the first GUI action of a task, run `sparekey status --json`. Record `initial_state` and set `lock_token = null`. Never infer relock authority from the current lock state.

If a GUI tool fails, times out, or sees no windows, run `sparekey status --json` before retrying anything else. Do not keep retrying apps, Finder, or other windows on a locked Mac.

If `state` is `unlocked`, continue the task. This task did not unlock it.

## 2. Unlock when needed

A user request for a task that needs actual macOS desktop computer use authorizes unlocking for that task. Do not unlock if the user said to leave the Mac locked or asked only for status.

When `state` is `locked`:

1. `sparekey probe --json` and require `ok: true`. Save its `lockToken` if present; a probe can wake a grace-period session into an unlocked state.
2. `sparekey unlock --json` once.
3. `sparekey status --json` and require `state: "unlocked"`.
4. Save the returned `lockToken` (or the probe token if the same hold was reused), then continue the original task. If no token was returned, do not relock at completion.

For a covered unlock, the helper places a black cover beneath the lock screen before password submission, so it is already in place when the lock screen dismisses. It is intentionally invisible in screenshots, and clicks and typing still reach the apps underneath. The helper keeps the display awake until `sparekey lock` or 60 minutes, whichever comes first, so idle display sleep does not relock the Mac mid-task.

A later locked state alone is not evidence of user takeover. If desktop work is still authorized, there is no evidence of user takeover or a request to stay locked, and no earlier failed unlock or `relock_revoked` stop applies, discard the previous lock token and repeat steps 1–4 once for this lock, then continue the task. This also applies to a new desktop request after the agent's own cleanup lock. Do not loop unlock attempts if the Mac locks again before desktop work can resume. If the user took control through the cover's Unlock Mac button or otherwise explicitly stopped desktop access, leave the Mac as it is unless the user explicitly authorizes resuming desktop work.

Never retry a failed unlock, type a password through UI automation, ask for the password in chat, or restart the helper to get around its limits.

## 3. Relock when done

If this task received a `lockToken`, run `sparekey lock --lock-token TOKEN --json` after the last GUI action and before the final response, including failure or abandonment. Never use a token from another task, and never fall back to tokenless `lock` or `lock --force`. Tokenless lock is rejected; `lock --force` is only for an explicit user request to lock the Mac, never task cleanup. The helper invalidates authority when the user authenticates through the cover Unlock Mac button, an external screen lock is observed, or the display hold ends. A subsequent manual unlock does not restore it. If `error.code` is `relock_revoked`, leave the Mac as it is and do not retry, unlock, or obtain another token unless the user explicitly authorizes resuming desktop work. A successful lock also turns off the displays. If `error.code` is `display_sleep_not_confirmed`, the Mac may already be locked; check status and report that display sleep was not confirmed without retrying the lock. After a successful lock, run `sparekey status --json` and report restoration only when `state` is `locked`.

Do not relock when the Mac was already unlocked at the start, the user asked to keep it unlocked, a request was only to unlock, or another known task is still using the screen.

## Errors

Stop, report the `error.code`, and tell the user what to do, except for the single bounded probe repair described below. A failed probe is not a failed unlock: report which command failed and do not claim a password was submitted when only probe ran.

- `not_set_up`, `helper_not_running`, `helper_version_mismatch`, `accessibility_missing`, `credential_unavailable`: ask the user to run `sparekey doctor`, then `sparekey setup` in a local terminal. Never run setup yourself.
- `breaker_tripped`, `unlock_not_confirmed`: the saved password may be wrong. Ask the user to run `sparekey setup --reset-password` locally.
- `rate_limited`: an attempt ran in the last 30 seconds. Check status instead of retrying.
- `login_account_mismatch`: a populated account label did not exactly match the current user's short or full name. Ask the user to check the selected account on the Mac. This is a label mismatch, not proof that the active session changed.
- `login_window_unsupported`: the lock screen could not be safely verified. Report the specific `error.message`; do not call it an account mismatch unless the message says so. If probe reports more than one loginwindow window and no unlock has failed, inspect only native loginwindow window metadata, even while locked. If exactly one leftover Force Quit Applications dialog is positively identified by its system-dialog role, localized title, and process list, close only that dialog using its standard close button, then rerun `sparekey probe --json` once. Require `ok: true` before continuing to unlock. Never terminate an application or dismiss an authentication or security dialog, change accounts, or bypass account/field checks. If the dialog cannot be positively identified or closed, or the repaired probe still fails, stop and ask the user to check the Mac. For all other layout failures, stop without this repair.
- `field_not_ready`: the helper already waited within its bounded preparation period and may have tried one display sleep/wake recovery. The account label or password field is still not ready. Report what could not be verified; do not claim that another account is selected. Ask the user to check the Mac. Do not rerun probe or unlock to bypass this stop.

`doctor` checks installation, permissions, and helper health. A successful doctor does not verify the lock-screen account or prove that unlock will succeed.

Sparekey cannot help with FileVault startup, logged-out sessions, other accounts, or a sleeping Mac that is unreachable.
