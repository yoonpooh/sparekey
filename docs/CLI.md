# Sparekey CLI reference

Public command syntax and behavior for the CLI in this checkout.
Return to the [project README](../README.md) for installation, security, and development.

## Commands and options

Brackets indicate optional arguments. `TOKEN` and `NAME` are placeholders.

| Command | Options | Behavior |
| --- | --- | --- |
| `sparekey unlock` | `--json`, `--no-cover` | Unlock once and verify. Cover physical displays by default. |
| `sparekey lock` | `--json`, either `--lock-token TOKEN` or `--force` | Verify the lock, release the display hold, and turn off displays. |
| `sparekey status` | `--json` | Read the current lock state. |
| `sparekey probe` | `--json` | Wake and verify the login field without reading or submitting the password. Can unlock during the password grace period. |
| `sparekey setup` | `--identity NAME`, `--reset-password`, `--skill TARGETS`, `--no-skill` | Install or refresh the signed helper, saved credential, and selected skills. Requires a local interactive terminal. |
| `sparekey doctor` | `--json` | Check installation, signature, helper, Accessibility, credential readability, and skills. |
| `sparekey skill install` | `--agent AGENT`, `--force` | Install a standalone agent skill. Without `--agent`, prompt for a selection. |
| `sparekey uninstall` | None | Remove the managed installation and matching skills. Requires a local interactive terminal. |
| `sparekey help [command]` | None | Show help. Also available as `--help`, `-h`, or `<command> --help`. |
| `sparekey version` | None | Print the version. Also available as `--version`. |

Running `sparekey` without arguments shows help. Internal helper and test commands are not a public interface.

### Setup and skill selection

- `TARGETS` accepts `claude`, `codex`, or a comma-separated selection such as `claude,codex`. Repeated `--skill` options merge their selections.
- `--skill` and `--no-skill` cannot be combined. If neither is set, setup prompts for a selection.
- `AGENT` accepts one of `claude` or `codex`.
- `setup --identity NAME` uses an existing code-signing identity. Without it, setup creates or reuses `sparekey local signing` in the login Keychain.
- `setup --reset-password` replaces the saved credential. Passwords are entered at hidden local prompts, never through a CLI option.
- `skill install --force` backs up and replaces a differing skill without interactive confirmation. An existing `SKILL.md.bak` blocks replacement.
- `setup` does not accept `--force`. The only commands accepting `--force` are `skill install` and `lock`, with different meanings.

### Relock authority

`lock --lock-token TOKEN` requires a valid UUID token returned by `unlock --json`, or by `probe --json` when waking during the password grace period.
A successful command does not always return a token. A session that was already unlocked does not grant new relock authority.

Keep the token only for the current task. Authenticated takeover through **Unlock Mac**, a system lock event, the end of the display hold, or a helper restart invalidates it.
On `relock_revoked`, leave the Mac as it is.

`lock --force` is for an explicit manual lock request. Agents must never use it as a cleanup fallback.
`--force` and `--lock-token` are mutually exclusive. A lock request without either is rejected by the helper.

## JSON output

Only `unlock`, `lock`, `status`, `probe`, and `doctor` accept `--json`.
A status response has this form:

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
```

An operational failure has this form:

```json
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"Wait 30 seconds before another unlock attempt."}}
```

Optional fields are omitted when absent. Unlock and probe responses can include `lockToken`.
Check `ok` and `state` before acting. A successful `status` can report either `locked` or `unlocked`.
`doctor --json` adds `checks` and `statuses` maps. The status values are `ok`, `warn`, `fail`, and `skip`.

| Exit code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Operational failure |
| `2` | Invalid usage |

Errors include installation and helper failures, account or login-field verification failures, rate limiting, and revoked relock authority. See [troubleshooting](../README.md#troubleshooting) for common codes and actions.
`doctor` validates the installation, not the current loginwindow layout or an actual unlock.
