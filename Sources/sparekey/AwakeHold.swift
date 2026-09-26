import Foundation
import IOKit.pwr_mgt
import SparekeyCore

// After an unlock the HID idle time still reflects the unattended period, so idle display
// sleep (and "require password after display sleep") would relock the Mac mid-task.
// Hold a display-sleep assertion until lock, a confirmed relock, or a hard time limit.
enum AwakeHold {
    static let seconds = 3600
    private static let queue = DispatchQueue(label: "sparekey.awake-hold")
    private static var assertion: IOPMAssertionID = 0
    private static var watcher: DispatchSourceTimer?
    private static var generation: UInt64 = 0
    private static var onEnd: ((UInt64) -> Void)?
    private static var armed = false

    static func start(onEnd: @escaping (UInt64) -> Void) -> (held: Bool, token: UInt64) {
        queue.sync {
            stop()
            generation &+= 1
            self.onEnd = onEnd
            armed = false
            let properties: [String: Any] = [
                kIOPMAssertionTypeKey: kIOPMAssertPreventUserIdleDisplaySleep,
                kIOPMAssertionNameKey: "sparekey unlocked for an agent task",
                kIOPMAssertionTimeoutKey: seconds,
                kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease,
            ]
            var id: IOPMAssertionID = 0
            let held = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id) == kIOReturnSuccess
            guard held else { return (false, generation) }
            assertion = id
            let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
            var nextWakeAt: TimeInterval = 0
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler {
                if ProcessInfo.processInfo.systemUptime >= deadline { stop(); return }
                guard armed else { return }
                // Neither an unreadable session nor an asleep display proves a password lock.
                guard let locked = try? Screen.locked() else { return }
                let asleep = Screen.displayAsleep()
                switch DisplayContinuityPolicy.watcher(locked: locked, displayAsleep: asleep,
                                                       canWake: ProcessInfo.processInfo.systemUptime >= nextWakeAt) {
                case .keep:
                    if !asleep { nextWakeAt = 0 }
                case .end:
                    // loginwindow can briefly retain the grace flag after the display wakes.
                    Thread.sleep(forTimeInterval: 0.5)
                    if (try? Screen.locked()) == true && !Screen.displayAsleep() { stop() }
                case .wake:
                    // Recovery from --no-cover first creates a bound cover. Never wake a bare desktop.
                    guard CoverOverlay.ensureCovered(token: generation) else { break }
                    nextWakeAt = ProcessInfo.processInfo.systemUptime + 5
                    guard let activity = Screen.wakeDisplay() else { break }
                    let wakeDeadline = ProcessInfo.processInfo.systemUptime + 1.5
                    repeat {
                        Thread.sleep(forTimeInterval: 0.1)
                        guard let after = try? Screen.locked() else { break }
                        if !after && !Screen.displayAsleep() { break }
                    } while ProcessInfo.processInfo.systemUptime < wakeDeadline
                    IOPMAssertionRelease(activity)
                    if (try? Screen.locked()) == true && !Screen.displayAsleep() { stop() }
                }
            }
            timer.resume()
            watcher = timer
            return (held, generation)
        }
    }

    static func release() { queue.sync { stop() } }

    static func arm(token: UInt64) {
        queue.sync { if generation == token, assertion != 0 { armed = true } }
    }

    static func currentToken() -> UInt64? {
        queue.sync { assertion != 0 && armed ? generation : nil }
    }

    private static func stop() {
        watcher?.cancel()
        watcher = nil
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        armed = false
        let callback = onEnd
        onEnd = nil
        callback?(generation)
    }
}
