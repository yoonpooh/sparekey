# Security policy

Sparekey stores your Mac login password in your login Keychain and submits it
to the lock screen on request. Please report vulnerabilities privately.

## Reporting

Use GitHub's private vulnerability reporting on this repository
(Security → Report a vulnerability). Do not open a public issue.

Include the macOS version, the Sparekey version, and reproduction steps. Never
include a real password.

## Trust boundary

- Any process running as your user can ask the helper to unlock. Sparekey is
  for a trusted personal account, not protection from malware already running
  as you.
- Unlocking makes the physical screen visible to anyone nearby.
- The password briefly exists in helper memory. Full zeroization of Swift and
  CoreFoundation copies cannot be guaranteed.
- The helper listens only on a user-private Unix socket, never on the network.

## Supported versions

Only the latest release receives fixes.
