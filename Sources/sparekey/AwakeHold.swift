import Foundation
import IOKit.pwr_mgt

// After an unlock the HID idle time still reflects the unattended period, so idle display
// sleep (and "require password after display sleep") would relock the Mac mid-task.
// Hold a display-sleep assertion until lock, any other relock, or a hard time limit.
enum AwakeHold {
    static let seconds = 3600
    private static let queue = DispatchQueue(label: "sparekey.awake-hold")
    private static var assertion: IOPMAssertionID = 0
    private static var watcher: DispatchSourceTimer?
    private static var generation: UInt64 = 0
    private static var onEnd: ((UInt64) -> Void)?

    static func start(onEnd: @escaping (UInt64) -> Void) -> (held: Bool, token: UInt64) {
        queue.sync {
            stop()
            generation &+= 1
            self.onEnd = onEnd
            let properties: [String: Any] = [
                kIOPMAssertionTypeKey: kIOPMAssertPreventUserIdleDisplaySleep,
                kIOPMAssertionNameKey: "sparekey unlocked for an agent task",
                kIOPMAssertionTimeoutKey: seconds,
                kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease,
            ]
            var id: IOPMAssertionID = 0
            let held = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id) == kIOReturnSuccess
            if held { assertion = id }
            let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler {
                // An unreadable state is not proof of a lock; keep the cover up.
                if ProcessInfo.processInfo.systemUptime >= deadline || (try? Screen.locked()) == true { stop() }
            }
            timer.resume()
            watcher = timer
            return (held, generation)
        }
    }

    static func release() { queue.sync { stop() } }

    private static func stop() {
        watcher?.cancel()
        watcher = nil
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        let callback = onEnd
        onEnd = nil
        callback?(generation)
    }
}
