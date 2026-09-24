# Sparekey

**A locked Mac should not be the end of your agent's task.**

Sparekey is a macOS command-line tool that lets a computer-use or browser-use
agent unlock your existing desktop session, finish the task, and lock it again.

```sh
sparekey unlock   # let the agent get to work
sparekey lock     # restore the lock when it is done
```

> Status: early development. Nothing is released yet. See
> [docs/DESIGN.md](docs/DESIGN.md) for the plan.

## Scope

Sparekey uses a password you registered locally in your login Keychain to
unlock the same user's screen. It is not a password bypass, recovery tool, or
remote-access service. FileVault startup, logged-out sessions, and other
users' accounts are out of scope.

## Security

Read [SECURITY.md](SECURITY.md) before installing. In short: any process
running as your user can request an unlock.

## Credits

The lock-screen interaction approach was informed by Cindy's
[MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift)
(Apache-2.0). Sparekey is an independent implementation.

## License

[MIT](LICENSE)
