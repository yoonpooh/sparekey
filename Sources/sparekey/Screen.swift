import AppKit
import ApplicationServices
import IOKit.pwr_mgt
import Security
import SystemConfiguration
import SparekeyCore

enum Screen {
    static var submitted = false
    struct Snapshot {
        let pid: pid_t
        let started: UInt64
        let microseconds: UInt64
        let elements: [AXUIElement]
        let nodes: [LoginNode]
        let ownLabel: Bool
    }

    static func locked() throws -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        guard SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) != nil, uid == getuid(),
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              (session[kCGSessionUserIDKey as String] as? NSNumber)?.uint32Value == getuid(),
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true else {
            throw SparekeyError("Cannot verify the current GUI session. A logged-in console user is required.", code: "no_console_session")
        }
        return try LockState.parseValidatedSessionFlag(session["CGSSessionScreenIsLocked"])
    }

    static func lock() throws {
        if try locked() { return }
        guard AXIsProcessTrusted() else {
            throw SparekeyError("Accessibility permission is missing. Enable the stable Sparekey copy in System Settings.", code: "accessibility_missing")
        }
        // Apple's documented Lock Screen shortcut. Never read a credential here.
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false) else {
            throw SparekeyError("Could not create the lock-screen shortcut.")
        }
        down.flags = [.maskControl, .maskCommand]
        up.flags = [.maskControl, .maskCommand]
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        repeat {
            if try locked() { return }
            Thread.sleep(forTimeInterval: 0.1)
        } while ProcessInfo.processInfo.systemUptime < deadline
        if let framework = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW) {
            defer { dlclose(framework) }
            if let symbol = dlsym(framework, "SACLockScreenImmediate") {
                typealias LockFunction = @convention(c) () -> Void
                unsafeBitCast(symbol, to: LockFunction.self)()
                let fallbackDeadline = ProcessInfo.processInfo.systemUptime + 5
                repeat {
                    if try locked() { return }
                    Thread.sleep(forTimeInterval: 0.1)
                } while ProcessInfo.processInfo.systemUptime < fallbackDeadline
            }
        }
        throw SparekeyError("Lock was not confirmed.", code: "lock_not_confirmed")
    }

    static func value(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &result)
        if status == .noValue || status == .attributeUnsupported { return nil }
        guard status == .success else { throw SparekeyError("Cannot inspect the login screen (AXError \(status.rawValue)).", transient: true) }
        return result
    }

    static func snapshot() throws -> Snapshot {
        guard AXIsProcessTrusted() else {
            throw SparekeyError("Accessibility permission is missing. Add the stable Sparekey copy in System Settings > Privacy & Security > Accessibility.", code: "accessibility_missing")
        }
        guard try locked() else { throw SparekeyError("The screen is already unlocked.") }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.apple.loginwindow"
                && $0.executableURL?.path == "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"
        }
        guard apps.count == 1, let app = apps.first else { throw SparekeyError("Cannot identify Apple's loginwindow.", code: "login_window_unsupported") }
        var info = proc_bsdinfo()
        guard proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &info,
                          Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid(), info.pbi_start_tvsec > 0 else {
            throw SparekeyError("The login process does not match the current user.", code: "login_window_unsupported")
        }
        var code: SecCode?, requirement: SecRequirement?
        SecRequirementCreateWithString("identifier \"com.apple.loginwindow\" and anchor apple" as CFString, [], &requirement)
        guard let requirement,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: app.processIdentifier] as CFDictionary, [], &code) == errSecSuccess,
              let code, SecCodeCheckValidity(code, [], requirement) == errSecSuccess else {
            throw SparekeyError("The login process signature could not be verified.", code: "login_window_unsupported")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let windows = try value(root, kAXWindowsAttribute) as? [AXUIElement], windows.count == 1 else {
            throw SparekeyError("Unsupported login window layout.", code: "login_window_unsupported", transient: true)
        }
        var elements: [AXUIElement] = [], nodes: [LoginNode] = []
        var ownLabel = false, labelCount = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        func visit(_ element: AXUIElement, parent: Int?, depth: Int) throws {
            guard depth < 12 else {
                throw SparekeyError("Login screen inspection exceeded its depth limit.", code: "login_window_unsupported", transient: true)
            }
            guard nodes.count < 256 else {
                throw SparekeyError("Login screen inspection exceeded its node count limit.", code: "login_window_unsupported", transient: true)
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw SparekeyError("Login screen inspection exceeded its time budget.", code: "login_window_unsupported", transient: true)
            }
            guard !elements.contains(where: { CFEqual($0, element) }) else {
                throw SparekeyError("Login screen inspection encountered a duplicate element.", code: "login_window_unsupported", transient: true)
            }
            AXUIElementSetMessagingTimeout(element, 0.2)
            let role = try value(element, kAXRoleAttribute) as? String ?? ""
            let subrole = try value(element, kAXSubroleAttribute) as? String ?? ""
            let identifier = try value(element, kAXIdentifierAttribute) as? String ?? ""
            guard try value(element, kAXModalAttribute) as? Bool != true else {
                throw SparekeyError("A modal login dialog is open. Unlock manually.", code: "login_window_unsupported")
            }
            if identifier == "FocusedUser" {
                labelCount += 1
                guard labelCount == 1, role == kAXStaticTextRole,
                      let label = try value(element, kAXValueAttribute) as? String,
                      [NSUserName(), NSFullUserName()].contains(label) else {
                    throw SparekeyError("The visible login account does not match this user.", code: "login_window_unsupported")
                }
                ownLabel = true
            }
            var writable: DarwinBoolean = false
            if identifier == "UserPasswordTextField" {
                guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &writable) == .success else {
                    throw SparekeyError("The secure password field is not writable.", code: "field_not_ready", transient: true)
                }
            }
            var actions: CFArray?
            let actionStatus = AXUIElementCopyActionNames(element, &actions)
            guard [.success, .noValue, .attributeUnsupported].contains(actionStatus) else {
                throw SparekeyError("Cannot inspect login actions.", transient: true)
            }
            let index = nodes.count
            nodes.append(LoginNode(role: role, subrole: subrole, identifier: identifier, parent: parent,
                                   enabled: try value(element, kAXEnabledAttribute) as? Bool == true,
                                   writable: writable.boolValue,
                                   pressable: (actions as? [String])?.contains(kAXPressAction) == true))
            elements.append(element)
            if let children = try value(element, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children { try visit(child, parent: index, depth: depth + 1) }
            }
        }
        try visit(windows[0], parent: nil, depth: 0)
        return Snapshot(pid: app.processIdentifier, started: info.pbi_start_tvsec,
                        microseconds: info.pbi_start_tvusec, elements: elements, nodes: nodes, ownLabel: ownLabel)
    }

    static func sameWindow(_ a: Snapshot, _ b: Snapshot) -> Bool {
        a.pid == b.pid && a.started == b.started && a.microseconds == b.microseconds
            && CFEqual(a.elements[0], b.elements[0])
    }

    static func prepare() throws -> Snapshot {
        var activity: IOPMAssertionID = 0
        guard IOPMAssertionDeclareUserActivity("sparekey remote unlock" as CFString, kIOPMUserActiveRemote, &activity) == kIOReturnSuccess else {
            throw SparekeyError("Could not wake the display.")
        }
        defer { IOPMAssertionRelease(activity) }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var previous: Snapshot?
        var consecutive = false
        var revealed = false
        var lastState = LoginPolicy.Preparation.waitingForAccount
        // Keep window identity across failures, but require fresh consecutive observations for Return.
        if let ready = try PreparationRetry.run(deadline: deadline, onTransient: { consecutive = false }, attempt: {
            let current = try snapshot()
            let state = try LoginPolicy.preparation(in: current.nodes, ownLabel: current.ownLabel)
            if let previous, !sameWindow(previous, current) {
                throw SparekeyError("The login window changed during preparation. No password was submitted.", code: "login_window_unsupported")
            }
            if state == .ready { return current }
            // Require two matching, verified collapsed snapshots before sending Return.
            // Never send Return to a disabled field or an unrecognized account screen.
            if state == .collapsed, !revealed, consecutive, let previous,
               previous.ownLabel, previous.nodes.count == current.nodes.count,
               zip(previous.nodes, current.nodes).allSatisfy({
                   $0.identifier == $1.identifier && $0.role == $1.role && $0.subrole == $1.subrole
               }),
               try LoginPolicy.preparation(in: previous.nodes, ownLabel: previous.ownLabel) == .collapsed {
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else {
                    throw SparekeyError("Could not prepare the non-secret wake key.")
                }
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                revealed = true
            }
            previous = current
            consecutive = true
            lastState = state
            return nil
        }) { return ready }
        switch lastState {
        case .waitingForAccount:
            throw SparekeyError("The current-account label did not become available within 5 seconds. No password was submitted.", code: "field_not_ready")
        case .waitingForField:
            throw SparekeyError("The secure password field remained disabled or read-only for 5 seconds. No password was submitted.", code: "field_not_ready")
        default:
            throw SparekeyError("The password field did not appear after preparing the verified account screen within 5 seconds. No password was submitted.", code: "field_not_ready")
        }
    }

    static func validate(_ target: Snapshot, field: Int) throws -> Snapshot {
        let next = try snapshot()
        guard target.ownLabel, next.ownLabel else { throw SparekeyError("Current-account label changed.", code: "login_window_unsupported") }
        let nextField = try LoginPolicy.field(in: next.nodes)
        guard sameWindow(target, next), CFEqual(target.elements[field], next.elements[nextField]) else {
            throw SparekeyError("The password field changed. No further input was sent.", code: "login_window_unsupported")
        }
        return next
    }

    static func unlock(beforeFill: () throws -> Void = {}) throws {
        submitted = false
        let target = try prepare()
        let field = try LoginPolicy.field(in: target.nodes)
        _ = try validate(target, field: field)
        try beforeFill()
        var password = try Credentials.read()
        defer { password.resetBytes(in: password.startIndex..<password.endIndex) }
        guard !password.isEmpty else { throw SparekeyError("The saved credential is invalid.", code: "credential_unavailable") }
        defer {
            if (try? validate(target, field: field)) != nil {
                _ = AXUIElementSetAttributeValue(target.elements[field], kAXValueAttribute as CFString, "" as CFString)
            }
        }
        let fillStatus: AXError
        do {
            guard let text = String(data: password, encoding: .utf8), !text.isEmpty else {
                throw SparekeyError("The saved credential is invalid.", code: "credential_unavailable")
            }
            _ = try validate(target, field: field)
            fillStatus = AXUIElementSetAttributeValue(target.elements[field], kAXValueAttribute as CFString, text as CFString)
        }
        guard fillStatus == .success else { throw SparekeyError("Could not fill the verified password field.", code: "field_not_ready") }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var candidate: Snapshot?
        repeat {
            let next = try validate(target, field: field)
            if (try? LoginPolicy.submit(in: next.nodes)) != nil { candidate = next; break }
            Thread.sleep(forTimeInterval: 0.05)
        } while ProcessInfo.processInfo.systemUptime < deadline
        guard let candidate else { throw SparekeyError("The login button did not become ready.", code: "field_not_ready") }
        let button = try LoginPolicy.submit(in: candidate.nodes)
        let final = try validate(target, field: field)
        let finalButton = try LoginPolicy.submit(in: final.nodes)
        guard CFEqual(candidate.elements[button], final.elements[finalButton]) else {
            throw SparekeyError("The login button changed.", code: "login_window_unsupported")
        }
        submitted = true
        let result = AXUIElementPerformAction(final.elements[finalButton], kAXPressAction as CFString)
        guard result == .success || result == .cannotComplete else { throw SparekeyError("Login submission failed.") }
        let unlockDeadline = ProcessInfo.processInfo.systemUptime + 7
        repeat {
            if try !locked() { return }
            Thread.sleep(forTimeInterval: 0.1)
        } while ProcessInfo.processInfo.systemUptime < unlockDeadline
        throw SparekeyError("Unlock was not confirmed. No retry was submitted; check the password locally.", code: "unlock_not_confirmed")
    }
}
