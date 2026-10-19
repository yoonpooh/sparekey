# Sparekey local signing spike

Test whether a locally signed probe retains Accessibility and login Keychain access after replacement.

This is a development experiment, separate from the installed Sparekey helper.
Return to the [project README](../../README.md) for normal installation, security, and development.

## Requirements and security

Use the Mac whose signing, Accessibility, and Keychain behavior you want to inspect, with a logged-in GUI session, Xcode Command Line Tools, and Python 3 available at `/usr/bin/python3`.
Run as your normal user. The script uses macOS `security`, `codesign`, `launchctl`, and `/usr/bin/openssl`.

The experiment changes local state:

- Signing material, a disposable Keychain, builds, a LaunchAgent plist, and logs are stored under the gitignored `scripts/spike/work/` directory.
- `identity` creates a disposable Keychain and imports a signing identity. It does not change the default Keychain or certificate trust settings, but the Keychain can enter the user search list.
- `kc-save` writes a dummy generic password to the **login Keychain**, with an ACL for the installed probe's resolved path. It does not use your login password.
- You manually grant Accessibility to the probe. Cleanup does not remove that permission entry.

Do not publish the work directory or substitute real credentials for the dummy item.

## Usage

Run from the repository root:

```sh
scripts/spike/spike.sh identity
scripts/spike/spike.sh build
scripts/spike/spike.sh install v1
```

In System Settings > Privacy & Security > Accessibility, add and enable the absolute probe path printed by `install`, ending in `scripts/spike/work/install/probe`.
Record signing, Keychain, and permission prompts without recording secret values.

```sh
scripts/spike/spike.sh agent-run whoami
scripts/spike/spike.sh agent-run ax
scripts/spike/spike.sh agent-run kc-save
scripts/spike/spike.sh install v2
scripts/spike/spike.sh agent-run whoami
scripts/spike/spike.sh agent-run ax
scripts/spike/spike.sh agent-run kc-read
```

Each `agent-run` loads a temporary one-shot LaunchAgent, waits for `work/agent.log`, prints the result, and unloads the agent.
`kc-read` disables Keychain UI and reports an OSStatus without printing the dummy value.

## Command reference

| Command | Purpose |
| --- | --- |
| `spike.sh identity` | Create the disposable signing identity, or reuse an existing complete spike identity. |
| `spike.sh build` | Build and sign v1 and v2; compare their designated requirements. |
| `spike.sh install v1` or `spike.sh install v2` | Replace the probe at its stable test path. |
| `spike.sh agent-run MODE` | Run `whoami`, `ax`, `kc-save`, `kc-read`, or `kc-delete` through launchd. |
| `spike.sh cleanup` | Attempt dummy-item deletion, remove the disposable Keychain and work directory, and print a permission-removal reminder. |

Use the full `scripts/spike/spike.sh` path from the repository root. The script has no `--help` option; its command dispatch is defined in [spike.sh](spike.sh).

## Results and troubleshooting

A passing experiment has matching v1 and v2 designated requirements, `AXIsProcessTrusted=true` for both, and `kc-read: success (OSStatus 0)` for v2 without a prompt.

- A signing error means the identity could not sign in this environment.
- Different designated requirements mean the certificate did not produce a stable code identity.
- Accessibility failure only after replacement means the grant did not survive that replacement.
- A nonzero Keychain read status means the item or its access policy did not allow the rebuilt probe. Record the exact status and prompts before drawing a conclusion.

These results test the probe, not production unlock or relock behavior.

## Cleanup

While the probe is still installed, run:

```sh
scripts/spike/spike.sh cleanup
```

If deletion through an installed probe fails, cleanup stops before removing the work directory. Inspect the error before retrying.
If the installed probe is missing, cleanup warns that it cannot delete a previously saved dummy item and continues; verify that item separately in Keychain Access.
Do not manually delete `work/` while a dummy item may remain.

Remove the `probe` Accessibility entry in System Settings, then inspect the user Keychain search list with `security list-keychains -d user`.
A bare probe binary is tracked by path; resetting permissions by bundle identifier does not target that entry.

## License

[MIT](../../LICENSE), as part of Sparekey.
