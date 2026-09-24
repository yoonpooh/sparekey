// Main-thread cover ownership. Attempts are pending until a verified unlock binds
// them to an AwakeHold token; endings from older tokens cannot hide a new attempt.
public struct CoverOwnership {
    public enum BindResult: Equatable { case missing, ended, bound }
    private var currentAttempt: UInt64?
    private var currentToken: UInt64?
    private var lastCanceledAttempt: UInt64 = 0
    private var lastEndedToken: UInt64 = 0

    public init() {}

    public mutating func begin(attempt: UInt64) -> Bool {
        guard attempt > lastCanceledAttempt else { return false }
        currentToken = nil
        currentAttempt = attempt
        return true
    }

    public mutating func bind(attempt: UInt64, token: UInt64) -> BindResult {
        guard currentAttempt == attempt else { return .missing }
        currentAttempt = nil
        guard token > lastEndedToken else { return .ended }
        currentToken = token
        return .bound
    }

    public mutating func cancel(attempt: UInt64) -> Bool {
        lastCanceledAttempt = max(lastCanceledAttempt, attempt)
        guard currentAttempt == attempt else { return false }
        currentAttempt = nil
        return true
    }

    public mutating func end(token: UInt64) -> Bool {
        lastEndedToken = max(lastEndedToken, token)
        guard currentToken == token else { return false }
        currentToken = nil
        return true
    }

    public mutating func clear() {
        currentAttempt = nil
        currentToken = nil
    }
}
