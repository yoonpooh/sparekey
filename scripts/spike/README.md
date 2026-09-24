# Local signing spike

Run these commands on the Mac whose Accessibility and login Keychain behavior you want to test. The script uses a dedicated, disposable Keychain at `work/spike.keychain-db`. Its password, private key, certificate, binaries, logs, and agent plist stay under the gitignored `work/` directory. It does not change the default Keychain or certificate trust settings. `security create-keychain` may add the disposable Keychain to your search list until `cleanup` deletes it; if you abandon the spike midway, still run `cleanup`, then check `security list-keychains -d user`.

From the repository root:

```sh
scripts/spike/spike.sh identity
scripts/spike/spike.sh build
scripts/spike/spike.sh install v1
```

In System Settings → Privacy & Security → Accessibility, manually add and enable the absolute path printed by `install`: `scripts/spike/work/install/probe`. Record any authentication prompts from identity creation, signing, and this grant.

```sh
scripts/spike/spike.sh agent-run whoami
scripts/spike/spike.sh agent-run ax
scripts/spike/spike.sh agent-run kc-save
scripts/spike/spike.sh install v2
scripts/spike/spike.sh agent-run whoami
scripts/spike/spike.sh agent-run ax
scripts/spike/spike.sh agent-run kc-read
```

Record any Keychain or Accessibility prompts during each step. `kc-save` writes one dummy generic password to the **login Keychain** with a legacy `SecAccess` ACL trusting only the installed probe's resolved path. The dummy value is never printed. `kc-read` disables Keychain UI and reports success or an OSStatus. Each `agent-run` creates a temporary one-shot LaunchAgent, waits for its result in `work/agent.log`, prints it, and boots the agent out.

Pass: both signed builds have identical designated requirements, v1 and v2 report `AXIsProcessTrusted=true`, and v2 reports `kc-read: success (OSStatus 0)` without a prompt. A signing failure means an untrusted local identity cannot sign this way. Different designated requirements mean this certificate does not provide stable code identity. `AXIsProcessTrusted=false` on v1 suggests the grant or LaunchAgent context is wrong; false only on v2 means the grant did not survive replacement. A nonzero `kc-read` status on v2 means the login Keychain item or ACL did not survive or allow the rebuilt helper. A likely cause is the item's partition list: code without a Team ID may be partitioned by `cdhash`, which changes on every rebuild even when the designated requirement matches. Record the exact status and prompts before cleanup.

Finally, while v2 remains installed, run:

```sh
scripts/spike/spike.sh cleanup
```

Cleanup boots out the agent, runs `kc-delete` through it, removes the dedicated Keychain and `work/`, and reminds you to remove the Accessibility entry. A bare binary is recorded by path, so `tccutil reset` by identifier does not match it; remove the `probe` entry in System Settings instead. If cleanup cannot delete the dummy item, it stops before removing the probe; inspect the error and retry. Do not remove `work/` manually while the dummy item remains.
