import Foundation

public enum Command: String, Codable, CaseIterable {
    case unlock, lock, status, probe, setup, doctor, skill, uninstall, help, version, serve, continueSetup = "setup-continue", ttyProbe = "tty-probe", ttyProbeChild = "tty-probe-child", testImport = "test-import", credentialHandoff = "credential-handoff"
}

public struct SparekeyError: Error, CustomStringConvertible {
    public let code: String
    public let description: String
    public let transient: Bool
    public init(_ description: String, code: String = "internal", transient: Bool = false) {
        self.description = description; self.code = code; self.transient = transient
    }
}

public enum PreparationRetry {
    public static func run<T>(deadline: TimeInterval,
                              now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                              sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                              onTransient: () -> Void, attempt: () throws -> T?) throws -> T? {
        var lastError: SparekeyError?
        repeat {
            do {
                if let result = try attempt() { return result }
                lastError = nil
            } catch let error as SparekeyError where error.transient {
                lastError = error
                onTransient()
            }
            let remaining = deadline - now()
            if remaining > 0 { sleep(min(0.1, remaining)) }
        } while now() < deadline
        if let lastError { throw lastError }
        return nil
    }
}

public struct Invocation {
    public let command: Command
    public let json: Bool
    public let helpFor: Command?
    public let identity: String?
    public let resetPassword: Bool
    public let noSkill: Bool
    public let skillTargets: [String]?
    public let agent: String?
    public let force: Bool
    public static func parse(_ args: [String]) throws -> Invocation {
        func usage(_ message: String = "Invalid arguments. Run 'sparekey help'.") -> SparekeyError { SparekeyError(message, code: "usage") }
        var words = args
        if words.isEmpty { words = ["help"] }
        if words == ["--version"] { words = ["version"] }
        if words == ["--help"] || words == ["-h"] { words = ["help"] }
        if words.count == 2, ["--help", "-h"].contains(words[1]) { words = ["help", words[0]] }
        guard let command = Command(rawValue: words.removeFirst().lowercased()) else { throw usage() }
        if command == .help {
            guard words.count <= 1 else { throw usage() }
            let target = words.first.flatMap { Command(rawValue: $0.lowercased()) } ?? .help
            if words.count == 1 && target == .help && words[0].lowercased() != "help" { throw usage() }
            guard ![.serve, .continueSetup, .ttyProbe, .ttyProbeChild, .testImport, .credentialHandoff].contains(target) else { throw usage() }
            return Invocation(command: .help, json: false, helpFor: target, identity: nil, resetPassword: false, noSkill: false, skillTargets: nil, agent: nil, force: false)
        }
        var json = false, reset = false, noSkill = false, force = false
        var identity: String?, agent: String?
        var skillTargets: [String]?
        var position = 0
        if command == .skill {
            guard words.first == "install" else { throw usage("Usage: sparekey skill install [--agent claude|codex] [--force]") }
            words.removeFirst()
        }
        while position < words.count {
            let word = words[position]
            switch word {
            case "--json" where [.unlock, .lock, .status, .probe, .doctor].contains(command) && !json: json = true
            case "--reset-password" where (command == .setup || command == .continueSetup) && !reset: reset = true
            case "--no-skill" where command == .setup && !noSkill: noSkill = true
            case "--skill" where command == .setup:
                position += 1; guard position < words.count, let chosen = SkillSelection.parseFlag(words[position]) else { throw usage() }
                skillTargets = Array(Set((skillTargets ?? []) + chosen)).sorted()
            case "--force" where command == .skill && !force: force = true
            case "--identity" where command == .setup && identity == nil:
                position += 1; guard position < words.count, !words[position].hasPrefix("--") else { throw usage() }; identity = words[position]
            case "--agent" where command == .skill && agent == nil:
                position += 1; guard position < words.count, ["claude", "codex"].contains(words[position]) else { throw usage() }; agent = words[position]
            default: throw usage()
            }
            position += 1
        }
        guard !(noSkill && skillTargets != nil) else { throw usage("--skill and --no-skill cannot be combined.") }
        return Invocation(command: command, json: json, helpFor: nil, identity: identity, resetPassword: reset, noSkill: noSkill, skillTargets: skillTargets, agent: agent, force: force)
    }
}

public struct ErrorBody: Codable { public let code: String; public let message: String }
public struct Envelope: Codable {
    public let ok: Bool
    public let command: String
    public let state: String?
    public let message: String?
    public let error: ErrorBody?
    public init(command: String, state: String? = nil, message: String) {
        self.ok = true; self.command = command; self.state = state; self.message = message; self.error = nil
    }
    public init(command: String, code: String, message: String) {
        self.ok = false; self.command = command; self.state = nil; self.message = nil; self.error = ErrorBody(code: code, message: message)
    }
}
public struct Request: Codable { public let v: Int; public let command: String; public init(_ command: String) { v = 1; self.command = command } }
public struct Reply: Codable {
    public let v: Int
    public let ok: Bool
    public let state: String?
    public let message: String?
    public let error: ErrorBody?
    public let helperVersion: String
    public let accessibility: Bool?
    public let credentialReadable: Bool?
    public init(state: String? = nil, message: String, accessibility: Bool? = nil, credentialReadable: Bool? = nil) {
        v = 1; ok = true; self.state = state; self.message = message; error = nil; helperVersion = "0.1.1"; self.accessibility = accessibility; self.credentialReadable = credentialReadable
    }
    public init(code: String, message: String) {
        v = 1; ok = false; state = nil; self.message = nil; error = ErrorBody(code: code, message: message); helperVersion = "0.1.1"; accessibility = nil; credentialReadable = nil
    }
}

public struct SafetyState: Codable, Equatable {
    public var lastAttempt: TimeInterval?
    public var breakerTripped: Bool
    public var signerSHA1: String?
    public init(lastAttempt: TimeInterval? = nil, breakerTripped: Bool = false, signerSHA1: String? = nil) { self.lastAttempt = lastAttempt; self.breakerTripped = breakerTripped; self.signerSHA1 = signerSHA1 }
    public mutating func admit(now: TimeInterval) throws {
        if breakerTripped { throw SparekeyError("Unlocks are paused. Run 'sparekey setup' locally.", code: "breaker_tripped") }
        if let lastAttempt, lastAttempt > now { self.lastAttempt = nil }
        if let lastAttempt = self.lastAttempt, now - lastAttempt < 30 { throw SparekeyError("Wait 30 seconds before another unlock attempt.", code: "rate_limited") }
        lastAttempt = now
    }
    public mutating func trip() { breakerTripped = true }
    public mutating func resetBreaker() { breakerTripped = false }
}

public enum ManagedAgent {
    public static func matches(_ data: Data, executable: String) -> Bool {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return false }
        return plist["Label"] as? String == "io.github.yoonpooh.sparekey.helper"
            && plist["ProgramArguments"] as? [String] == [executable, "serve"]
    }
}
public enum LockState {
    public static func parseValidatedSessionFlag(_ value: Any?) throws -> Bool {
        guard let value else { return false }
        guard let locked = value as? Bool else { throw SparekeyError("Unrecognized screen lock state.", code: "no_console_session") }
        return locked
    }
}
public struct LoginNode {
    public let role: String, subrole: String, identifier: String
    public let parent: Int?
    public let enabled: Bool, writable: Bool, pressable: Bool
    public init(role: String, subrole: String = "", identifier: String = "", parent: Int? = nil,
                enabled: Bool = true, writable: Bool = false, pressable: Bool = false) {
        self.role = role; self.subrole = subrole; self.identifier = identifier; self.parent = parent
        self.enabled = enabled; self.writable = writable; self.pressable = pressable
    }
}
public enum LoginPolicy {
    public enum Preparation: Equatable { case ready, collapsed, waitingForAccount, waitingForField }
    private static func safe(_ nodes: [LoginNode]) -> Bool {
        nodes.first?.role == "AXWindow" && nodes.first?.identifier == "login" && !nodes.contains {
            ["AXSheet", "AXList", "AXTable", "AXOutline", "AXComboBox", "AXPopUpButton"].contains($0.role)
                || ["AXDialog", "AXSystemDialog"].contains($0.subrole)
                || ["ResetPasswordTitle", "ResetUsingRecoveryButton"].contains($0.identifier)
        }
    }
    public static func preparation(in nodes: [LoginNode], ownLabel: Bool) throws -> Preparation {
        guard safe(nodes) else { throw SparekeyError("Unsupported login screen. No input was sent.", code: "login_window_unsupported") }
        let fields = nodes.indices.filter { nodes[$0].role == "AXTextField" }
        if fields.isEmpty { return ownLabel ? .collapsed : .waitingForAccount }
        guard fields.count == 1, let index = fields.first, nodes[index].identifier == "UserPasswordTextField",
              nodes[index].subrole == "AXSecureTextField", let parent = nodes[index].parent,
              nodes.indices.contains(parent) else { throw SparekeyError("Ambiguous password field.", code: "login_window_unsupported") }
        if !ownLabel { return .waitingForAccount }
        return nodes[index].enabled && nodes[index].writable ? .ready : .waitingForField
    }
    public static func field(in nodes: [LoginNode]) throws -> Int {
        guard safe(nodes) else { throw SparekeyError("Unsupported login screen.", code: "login_window_unsupported") }
        let fields = nodes.indices.filter { nodes[$0].role == "AXTextField" }
        guard fields.count == 1, let index = fields.first, nodes[index].identifier == "UserPasswordTextField",
              nodes[index].subrole == "AXSecureTextField", nodes[index].enabled, nodes[index].writable,
              let parent = nodes[index].parent, nodes.indices.contains(parent) else {
            throw SparekeyError("The secure password field is not ready.", code: "field_not_ready")
        }
        return index
    }
    public static func submit(in nodes: [LoginNode]) throws -> Int {
        let fieldIndex = try field(in: nodes)
        let buttons = nodes.indices.filter { nodes[$0].identifier == "LUIBUTTON_GO" }
        guard buttons.count == 1, let index = buttons.first, nodes[index].role == "AXButton",
              nodes[index].parent == nodes[fieldIndex].parent, nodes[index].enabled, nodes[index].pressable else {
            throw SparekeyError("The verified login button is not ready.", code: "field_not_ready")
        }
        return index
    }
}

public enum SkillSelection {
    public static func parseFlag(_ value: String) -> [String]? {
        let values = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !values.isEmpty, values.allSatisfy({ ["claude", "codex"].contains($0) }) else { return nil }
        return Array(Set(values)).sorted()
    }
    public static func parsePrompt(_ value: String) -> [String]? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "none" { return [] }
        let values = trimmed.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !values.isEmpty, values.allSatisfy({ ["1", "2"].contains($0) }) else { return nil }
        return Array(Set(values.map { $0 == "1" ? "codex" : "claude" })).sorted()
    }
}
public enum SkillPlan {
    public enum Action: Equatable { case create, skip, replace }
    public static func action(existing: Data?, new: Data) -> Action {
        guard let existing else { return .create }
        return existing == new ? .skip : .replace
    }
}

public enum SignaturePolicy {
    public static func requirement(identifier: String, certificateSHA1: String) throws -> String {
        let hash = certificateSHA1.uppercased()
        guard hash.count == 40, hash.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
              !identifier.isEmpty, identifier.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 }) else {
            throw SparekeyError("Invalid signing identity or identifier.")
        }
        return "identifier \"\(identifier)\" and certificate leaf = H\"\(hash)\""
    }
}
public enum InstallInventory {
    public static func allows(_ names: [String], expected: Set<String>) -> Bool { Set(names).isSubset(of: expected) }
}
public struct LineFrame {
    public let limit: Int
    private var bytes = Data()
    public init(limit: Int) { self.limit = limit }
    public mutating func append(_ byte: UInt8) throws -> Data? {
        if byte == 10 { return bytes }
        guard bytes.count < limit else { throw SparekeyError("Helper message too large.") }
        bytes.append(byte)
        return nil
    }
}
public enum UnlockAttempt {
    public static func run(state: inout SafetyState, now: TimeInterval,
                           persist: (SafetyState) throws -> Void,
                           submit: () throws -> Void, wasSubmitted: () -> Bool) throws {
        try state.admit(now: now)
        try persist(state)
        do { try submit() }
        catch {
            if wasSubmitted() { state.trip(); try persist(state) }
            throw error
        }
    }
}
