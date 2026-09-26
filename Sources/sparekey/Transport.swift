import Foundation
import Darwin
import ApplicationServices
import SparekeyCore

enum Transport {
    private static let operations = DispatchQueue(label: "sparekey.operations")
    private static var coverAttempt: UInt64 = 0 // Accessed only on operations.
    static func address<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(Paths.socket.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw SparekeyError("Socket path is too long.") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
    static func configure(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }
    static func verifyPeer(_ fd: Int32) throws {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw SparekeyError("Socket peer is not this user.") }
    }
    static func send<T: Encodable>(_ value: T, to fd: Int32) throws {
        try (JSONEncoder().encode(value) + Data([10])).withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SparekeyError("Cannot write helper message.") }
                offset += count
            }
        }
    }
    static func receive(_ fd: Int32, limit: Int = 4096) throws -> Data {
        var frame = LineFrame(limit: limit)
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while ProcessInfo.processInfo.systemUptime < deadline {
            var byte: UInt8 = 0
            let count = Darwin.read(fd, &byte, 1)
            if count < 0 && errno == EINTR { continue }
            guard count == 1 else { throw SparekeyError("Helper disconnected or timed out.", code: "helper_not_running") }
            if let result = try frame.append(byte) { return result }
        }
        throw SparekeyError("Helper message too large.")
    }
    static func request(_ command: String, noCover: Bool = false) throws -> Reply {
        try Paths.checkedDirectory(Paths.base, create: false)
        try Paths.checkedDirectory(Paths.run, create: false)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SparekeyError("Cannot create socket.") }
        defer { close(fd) }
        configure(fd, seconds: 20)
        guard try address({ connect(fd, $0, $1) }) == 0 else { throw SparekeyError("Helper is not running. Run 'sparekey setup'.", code: "helper_not_running") }
        try verifyPeer(fd)
        try send(Request(command, noCover: noCover), to: fd)
        let reply = try JSONDecoder().decode(Reply.self, from: receive(fd))
        guard reply.v == 1, reply.helperVersion == "0.2.1" else { throw SparekeyError("Helper version differs. Run 'sparekey setup'.", code: "helper_version_mismatch") }
        if command == "unlock", reply.error?.code == "usage" {
            throw SparekeyError("The installed helper does not support covered unlocks. Run 'sparekey setup' to update it.", code: "helper_version_mismatch")
        }
        return reply
    }
    static func serve() throws {
        try Paths.checkedDirectory(Paths.base, create: true)
        try Paths.checkedDirectory(Paths.run, create: true)
        umask(0o077)
        let lock = open(Paths.run + "/service.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw SparekeyError("Cannot open helper lock.") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw SparekeyError("Helper already running.") }
        Handoff.listen()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SparekeyError("Cannot create helper socket.") }
        defer { close(fd) }
        var existing = stat()
        if lstat(Paths.socket, &existing) == 0 {
            guard existing.st_uid == getuid(), existing.st_mode & S_IFMT == S_IFSOCK, unlink(Paths.socket) == 0 else { throw SparekeyError("Unexpected socket path.") }
        }
        guard try address({ bind(fd, $0, $1) }) == 0 else { throw SparekeyError("Cannot bind helper socket.") }
        defer { unlink(Paths.socket) }
        guard chmod(Paths.socket, 0o600) == 0, listen(fd, 8) == 0 else { throw SparekeyError("Cannot listen on helper socket.") }
        while true {
            let peer = accept(fd, nil, nil)
            if peer < 0 && errno == EINTR { continue }
            guard peer >= 0 else { throw SparekeyError("Cannot accept helper connection.") }
            autoreleasepool {
                defer { close(peer) }
                configure(peer, seconds: 20)
                do {
                    try verifyPeer(peer)
                    let request = try JSONDecoder().decode(Request.self, from: receive(peer, limit: 256))
                    guard request.isSupportedByCoverHelper,
                          ["status", "probe", "unlock", "lock", "check"].contains(request.command) else {
                        throw SparekeyError("Unsupported helper request.", code: "usage")
                    }
                    let reply = try operations.sync { try handle(request.command, noCover: request.noCover) }
                    try send(reply, to: peer)
                } catch {
                    let issue = error as? SparekeyError ?? SparekeyError("Helper operation failed.")
                    try? send(Reply(code: issue.code, message: issue.description), to: peer)
                }
            }
        }
    }
    private static func showCover(attempt: UInt64) throws {
        let ordered = DispatchSemaphore(value: 0)
        var panelsOrdered = false
        CoverOverlay.schedulePendingShow(attempt: attempt) { result in
            panelsOrdered = result
            ordered.signal()
        }
        guard ordered.wait(timeout: .now() + 1) == .success, panelsOrdered else {
            throw SparekeyError("The privacy cover could not be shown. Try 'sparekey unlock --no-cover' if you want to proceed without it.", code: "cover_unavailable")
        }
    }
    private static func startHold() throws -> UInt64 {
        let hold = AwakeHold.start(onEnd: { token in CoverOverlay.scheduleHide(token: token) })
        guard hold.held else {
            AwakeHold.release()
            throw SparekeyError("The display could not be kept awake. No password was submitted.",
                                code: "display_hold_unavailable")
        }
        return hold.token
    }
    private static func bindHold(attempt: UInt64, token: UInt64) {
        AwakeHold.arm(token: token)
        CoverOverlay.scheduleBind(attempt: attempt, token: token)
    }
    static func handle(_ command: String, noCover: Bool) throws -> Reply {
        let locked = try Screen.locked()
        switch command {
        case "check":
            var readable = false
            if var password = try? Credentials.read() { readable = true; password.resetBytes(in: password.startIndex..<password.endIndex) }
            return Reply(state: locked ? "locked" : "unlocked", message: "Helper check completed.", accessibility: AXIsProcessTrusted(), credentialReadable: readable)
        case "status": return Reply(state: locked ? "locked" : "unlocked", message: locked ? "locked" : "unlocked")
        case "lock":
            try Screen.lock()
            AwakeHold.release()
            CoverOverlay.scheduleHide()
            return Reply(state: "locked", message: "Computer locked.")
        case "probe":
            if !locked { return Reply(state: "unlocked", message: "Already unlocked.") }
            coverAttempt &+= 1
            let probeAttempt = coverAttempt
            let probeToken: UInt64?
            do {
                probeToken = try ProbeDisplayTransaction.run(cover: {
                    try showCover(attempt: probeAttempt)
                }, acquire: {
                    try startHold()
                }, probe: {
                    do { _ = try Screen.prepare(); return try !Screen.locked() }
                    catch {
                        // loginwindow can disappear during any inspection step after a grace wake.
                        if (try? Screen.locked()) == false { return true }
                        throw error
                    }
                }, verifyUnlocked: {
                    try Screen.confirmDisplayReady()
                }, release: {
                    AwakeHold.release()
                })
            } catch {
                CoverOverlay.scheduleHide(attempt: probeAttempt)
                throw error
            }
            if let probeToken {
                bindHold(attempt: probeAttempt, token: probeToken)
                return Reply(state: "unlocked", message: "Already unlocked.")
            }
            CoverOverlay.scheduleHide(attempt: probeAttempt)
            return Reply(state: "locked", message: "Password field verified. No password was read or submitted.")
        case "unlock":
            if !locked {
                let currentToken = AwakeHold.currentToken()
                let covered = !noCover && (currentToken.map { CoverOverlay.isCovered(token: $0) } ?? false)
                if UnlockedRequestPolicy.canReuseHold(held: currentToken != nil,
                                                      covered: covered,
                                                      noCover: noCover) {
                    if noCover { CoverOverlay.scheduleHide() }
                    return Reply(state: "unlocked", message: "Already unlocked.")
                }
                coverAttempt &+= 1
                let unlockedAttempt = coverAttempt
                let token: UInt64
                do {
                    token = try UnlockDisplayTransaction.run(cover: {
                        if !noCover { try showCover(attempt: unlockedAttempt) }
                    }, acquire: {
                        try startHold()
                    }, submit: {}, verify: {
                        try Screen.confirmDisplayReady()
                    }, release: {
                        AwakeHold.release()
                    })
                } catch {
                    if !noCover { CoverOverlay.scheduleHide(attempt: unlockedAttempt) }
                    throw error
                }
                AwakeHold.arm(token: token)
                if !noCover { CoverOverlay.scheduleBind(attempt: unlockedAttempt, token: token) }
                return Reply(state: "unlocked", message: "Already unlocked. Display kept awake until lock, for up to \(AwakeHold.seconds / 60) minutes.")
            }
            var state = try StateFile.read()
            coverAttempt &+= 1
            let attempt = coverAttempt
            var submitted = false
            var holdToken: UInt64?
            do {
                try UnlockAttempt.run(state: &state, now: Date().timeIntervalSince1970,
                                      persist: StateFile.write, submit: {
                    holdToken = try UnlockDisplayTransaction.run(cover: {
                        if !noCover { try showCover(attempt: attempt) }
                    }, acquire: {
                        try startHold()
                    }, submit: {
                        do { try Screen.unlock(onSubmit: { submitted = true }) }
                        catch {
                            if (try? Screen.locked()) != false { throw error }
                        }
                    }, verify: {
                        try Screen.confirmDisplayReady()
                    }, release: {
                        AwakeHold.release()
                    })
                }, wasSubmitted: { submitted })
            } catch {
                if !noCover { CoverOverlay.scheduleHide(attempt: attempt) }
                throw error
            }
            if let holdToken {
                AwakeHold.arm(token: holdToken)
                if !noCover { CoverOverlay.scheduleBind(attempt: attempt, token: holdToken) }
            }
            return Reply(state: "unlocked", message: "Computer unlocked. Display kept awake until lock, for up to \(AwakeHold.seconds / 60) minutes.")
        default: throw SparekeyError("Unsupported helper request.", code: "usage")
        }
    }

    static func lockFromButton() {
        operations.async {
            do { _ = try handle("lock", noCover: false) }
            catch { FileHandle.standardError.write(Data(("Lock Mac failed: \(error)\n").utf8)) }
        }
    }
}
