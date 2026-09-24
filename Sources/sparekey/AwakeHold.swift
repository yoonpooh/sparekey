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

    static func start() -> Bool {
        queue.sync {
            stop()
            let properties: [String: Any] = [
                kIOPMAssertionTypeKey: kIOPMAssertPreventUserIdleDisplaySleep,
                kIOPMAssertionNameKey: "sparekey unlocked for an agent task",
                kIOPMAssertionTimeoutKey: seconds,
                kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease,
            ]
            var id: IOPMAssertionID = 0
            guard IOPMAssertionCreateWithProperties(properties as CFDictionary, &id) == kIOReturnSuccess else { return false }
            assertion = id
            let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler {
                // Release as soon as the screen is locked by any means, or the state is unreadable.
                if ProcessInfo.processInfo.systemUptime >= deadline || (try? Screen.locked()) != false { stop() }
            }
            timer.resume()
            watcher = timer
            return true
        }
    }

    static func release() { queue.sync { stop() } }

    private static func stop() {
        watcher?.cancel()
        watcher = nil
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
    }
}
