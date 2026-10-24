import Foundation

public enum DisplayRevealPolicy {
    /// Recover only from a verified layout that is still hiding the account. A layout that has not verified yet
    /// (for example loginwindow still re-raising the lock UI after wake) keeps polling instead of sleeping the display again.
    public static func shouldRecover(elapsed: TimeInterval, state: LoginPolicy.Preparation,
                                     sawOwnLabel: Bool, attempted: Bool, sawVerifiedLayout: Bool) -> Bool {
        elapsed >= 1.5 && sawVerifiedLayout && state == .waitingForAccount && !sawOwnLabel && !attempted
    }
}
