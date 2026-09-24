enum EmbeddedSkill {
    static let content = #"""
---
name: sparekey
description: Unlock the current user's locked, logged-in Mac for authorized computer use, then restore its initial lock state.
---

# Sparekey

Use `sparekey` from PATH or the Homebrew installation. The stable signed helper lives at `~/Library/Application Support/sparekey/bin/sparekey` and serves a private local socket.

Before computer or browser use, run `sparekey status --json`. Record `initial_state` and `unlocked_for_task = false`. If already unlocked, use the computer without claiming this task unlocked it. A status-only request ends here.

If locked and the user authorized computer use that needs an unlock, run `sparekey probe --json`, then `sparekey unlock --json` once. Check `sparekey status --json` again and require `state: "unlocked"`. Set `unlocked_for_task = true` only after confirmed submission. Never loop on failure, type a password through generic automation, ask for it in chat, or bypass the helper's limiter or breaker. Report errors including `rate_limited`, `breaker_tripped`, and `unlock_not_confirmed`.

After this task's last computer action, run `sparekey lock --json` and then `sparekey status --json` only when this task unlocked an initially locked Mac. Require `state: "locked"` to report that the lock was restored. Do not relock when the Mac began unlocked, another actor unlocked it, the user requests it remain unlocked, or another known task still uses it. A direct request only to unlock leaves it unlocked.

If setup, Accessibility, or credential checks fail, ask the user to run `sparekey doctor` and `sparekey setup` locally as appropriate. Setup requires a local interactive terminal and private password entry. Never run setup automatically as a generic recovery step. Sparekey cannot handle FileVault preboot, logged-out sessions, other accounts, or an unreachable Mac.
"""# + "\n"
}
