import Foundation

// Lives only in the helper. A restarted helper cannot accept an old task token.
public final class RelockAuthority {
    private let mutex = NSLock()
    private var token: String?
    private var hold: UInt64?
    private var epoch: UInt64 = 0
    public init() {}
    public func checkpoint() -> UInt64 {
        mutex.lock(); defer { mutex.unlock() }; return epoch
    }
    public func grant(hold: UInt64, checkpoint: UInt64) -> String? {
        mutex.lock(); defer { mutex.unlock() }
        guard checkpoint == epoch else { return nil }
        if self.hold == hold { return token }
        self.hold = hold; token = UUID().uuidString
        return token
    }
    public func existing(hold: UInt64) -> String? {
        mutex.lock(); defer { mutex.unlock() }
        return self.hold == hold ? token : nil
    }
    public func revoke() {
        mutex.lock(); defer { mutex.unlock() }
        epoch &+= 1; token = nil; hold = nil
    }
    public func end(hold: UInt64) {
        mutex.lock(); defer { mutex.unlock() }
        guard self.hold == hold else { return }
        epoch &+= 1; token = nil; self.hold = nil
    }
    // Validate and act together so a concurrent revocation cannot pass between them.
    public func lock(token requested: String?, action: () throws -> Void) throws {
        mutex.lock(); defer { mutex.unlock() }
        guard let requested, let token, requested == token else {
            throw SparekeyError("Relock authority expired or the user took control. Leave the Mac as it is.", code: "relock_revoked")
        }
        try action()
        self.token = nil; hold = nil; epoch &+= 1
    }
}
