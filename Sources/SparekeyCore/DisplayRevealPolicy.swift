import Foundation

public enum DisplayRevealPolicy {
    public static func shouldRecover(elapsed: TimeInterval, state: LoginPolicy.Preparation,
                                     sawOwnLabel: Bool, attempted: Bool) -> Bool {
        elapsed >= 1.5 && state == .waitingForAccount && !sawOwnLabel && !attempted
    }
}
