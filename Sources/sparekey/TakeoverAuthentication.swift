import Foundation
import LocalAuthentication

// The system owns the password field. Sparekey never receives or stores the
// password supplied here, and a fresh context requires fresh authentication.
final class TakeoverAuthentication {
    private let context = LAContext()

    func begin(completion: @escaping (Bool) -> Void) {
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.localizedFallbackTitle = "Use Password"
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Unlock Mac to take control and reveal your screen.") { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    func cancel() { context.invalidate() }
}
