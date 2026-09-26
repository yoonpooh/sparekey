public enum DisplayContinuityPolicy {
    public enum Action: Equatable { case keep, wake, end }

    // A lock flag while the display is asleep can be macOS's password grace period.
    // Retry a failed wake after a cooldown; only a persistent awake lock proves a relock.
    public static func watcher(locked: Bool, displayAsleep: Bool, canWake: Bool) -> Action {
        if displayAsleep { return canWake ? .wake : .keep }
        return locked ? .end : .keep
    }

    public static func needsPostUnlockWake(locked: Bool, displayAsleep: Bool) -> Bool {
        locked || displayAsleep
    }

    public static func isReady(locked: Bool, displayAsleep: Bool) -> Bool {
        !locked && !displayAsleep
    }
}

public enum LockCommandPolicy {
    // A pre-existing lock flag may only describe display-sleep grace. The immediate
    // lock action is required even after sending the normal lock shortcut.
    public static func needsImmediateLock(initiallyLocked: Bool, shortcutConfirmed: Bool) -> Bool {
        initiallyLocked || !shortcutConfirmed
    }

    public static func run(initiallyLocked: Bool, sendShortcut: () throws -> Void,
                           confirm: () throws -> Bool, immediate: () throws -> Void) throws {
        try sendShortcut()
        let shortcutConfirmed = initiallyLocked ? false : (try confirm())
        guard needsImmediateLock(initiallyLocked: initiallyLocked,
                                 shortcutConfirmed: shortcutConfirmed) else { return }
        try immediate()
        guard try confirm() else { throw SparekeyError("Lock was not confirmed.", code: "lock_not_confirmed") }
    }
}

public enum UnlockedRequestPolicy {
    public static func canReuseHold(held: Bool, covered: Bool, noCover: Bool) -> Bool {
        held && (noCover || covered)
    }
}

public enum UnlockDisplayTransaction {
    public static func run(cover: () throws -> Void, acquire: () throws -> UInt64,
                           submit: () throws -> Void, verify: () throws -> Void,
                           release: () -> Void) throws -> UInt64 {
        try cover()
        let token = try acquire()
        do {
            try submit()
            try verify()
            return token
        } catch {
            release()
            throw error
        }
    }
}

public enum ProbeDisplayTransaction {
    // probe only inspects the login field. A grace-period wake retains the cover
    // and hold; a still-locked result releases both without reading a password.
    public static func run(cover: () throws -> Void, acquire: () throws -> UInt64,
                           probe: () throws -> Bool, verifyUnlocked: () throws -> Void,
                           release: () -> Void) throws -> UInt64? {
        try cover()
        let token = try acquire()
        do {
            if try probe() {
                try verifyUnlocked()
                return token
            }
            release()
            return nil
        } catch {
            release()
            throw error
        }
    }
}
