import Foundation

/// Status markers shared by setup and doctor. Symbols stay meaningful without color.
public enum Mark {
    case ok, warn, fail, info, neutral
    public var symbol: String {
        switch self {
        case .ok: return "✓"
        case .warn: return "!"
        case .fail: return "✗"
        case .info: return "•"
        case .neutral: return "–"
        }
    }
    var color: String {
        switch self {
        case .ok: return "32"
        case .warn: return "33"
        case .fail: return "31"
        case .info: return "36"
        case .neutral: return "2"
        }
    }
}

public struct Palette {
    public let enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }
    public static let plain = Palette(enabled: false)
    /// Color only on a terminal, with NO_COLOR unset and TERM not "dumb".
    public static func detect(isTTY: Bool, environment: [String: String]) -> Palette {
        Palette(enabled: isTTY && environment["NO_COLOR"] == nil && environment["TERM"] != "dumb")
    }
    func paint(_ text: String, _ code: String) -> String { enabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text }
    public func bold(_ text: String) -> String { paint(text, "1") }
    public func dim(_ text: String) -> String { paint(text, "2") }
    public func mark(_ mark: Mark) -> String { paint(mark.symbol, mark.color) }
}

public enum Layout {
    public static let setupLabelWidth = 17
    /// `  ✓ Label<pad>  detail`
    public static func row(_ mark: Mark, _ label: String, _ detail: String, width: Int, palette: Palette) -> String {
        let padded = label.padding(toLength: max(width, label.count), withPad: " ", startingAt: 0)
        let line = "  \(palette.mark(mark)) \(padded)"
        return detail.isEmpty ? line : line + "  " + detail
    }
    /// Lines aligned under a row's detail column.
    public static func notes(_ lines: [String], width: Int, palette: Palette) -> [String] {
        let indent = String(repeating: " ", count: 4 + width + 2)
        return lines.map { $0.isEmpty ? "" : indent + palette.dim($0) }
    }
    /// Subprocess output shown under a failed step.
    public static func details(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.map { "      " + $0 }
    }
    public static func displayPath(_ path: String, home: String) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
    public static func count(_ value: Int, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }
}

public enum SetupReport {
    public static func summary(warnings: Int, stablePath: String?, palette: Palette) -> [String] {
        var lines = [""]
        lines.append(palette.bold(warnings == 0 ? "Setup complete." : "Setup complete with \(Layout.count(warnings, "warning")).")
                     + " The saved password has not been tested at the lock screen yet.")
        if let stablePath { lines.append("Helper: " + stablePath) }
        lines += ["", palette.bold("Next"),
                  "  sparekey doctor     check the installation",
                  "  Lock this Mac, then from an agent or SSH session:",
                  "  sparekey probe      verify the lock screen without a password",
                  "  sparekey unlock     unlock once and verify"]
        return lines
    }
}

public enum CheckStatus: String, Codable {
    case ok, warn, fail, skip
    public var mark: Mark {
        switch self {
        case .ok: return .ok
        case .warn: return .warn
        case .fail: return .fail
        case .skip: return .neutral
        }
    }
}

public struct DoctorCheck: Equatable {
    public let name: String, title: String, status: CheckStatus, detail: String
    public let hint: [String]
    public init(_ name: String, _ title: String, _ status: CheckStatus, _ detail: String, hint: [String] = []) {
        self.name = name; self.title = title; self.status = status; self.detail = detail; self.hint = hint
    }
}

public struct DoctorFacts {
    public enum Helper: Equatable { case running(String), notRunning, versionMismatch }
    public enum SkillFile: Equatable { case missing, current, modified, unsafe }
    public var installed = false, signed = false, agentLoaded = false
    public var helper = Helper.notRunning
    public var accessibility: Bool?, credentialReadable: Bool?, breakerTripped: Bool?
    public var codexSkill = SkillFile.missing, claudeSkill = SkillFile.missing
    public var stablePath = "", uid: UInt32 = 0
    public init() {}
}

public enum DoctorReport {
    public static let expectedVersion = "0.1.2"
    static let setupHint = "Run 'sparekey setup' in a local terminal."

    public static func evaluate(_ facts: DoctorFacts) -> [DoctorCheck] {
        let restart = "launchctl kickstart -k gui/\(facts.uid)/io.github.yoonpooh.sparekey.helper"
        var checks: [DoctorCheck] = []
        checks.append(facts.installed
            ? DoctorCheck("install_path", "Stable copy", .ok, facts.stablePath)
            : DoctorCheck("install_path", "Stable copy", .fail, "not installed", hint: [setupHint]))
        if !facts.installed { checks.append(DoctorCheck("signature", "Signature", .skip, "not checked")) }
        else if facts.signed { checks.append(DoctorCheck("signature", "Signature", .ok, "pinned certificate, hardened runtime")) }
        else { checks.append(DoctorCheck("signature", "Signature", .fail, "missing or unexpected", hint: ["Rerun 'sparekey setup' to re-sign the stable copy."])) }
        checks.append(facts.agentLoaded
            ? DoctorCheck("launch_agent", "LaunchAgent", .ok, "loaded")
            : DoctorCheck("launch_agent", "LaunchAgent", .fail, "not loaded", hint: [setupHint]))
        let running: Bool
        switch facts.helper {
        case .running(let version) where version == expectedVersion:
            running = true; checks.append(DoctorCheck("helper_version", "Helper", .ok, "running, version \(version)"))
        case .running(let version):
            running = false; checks.append(DoctorCheck("helper_version", "Helper", .fail, "version \(version) differs", hint: ["Rerun 'sparekey setup' to refresh the helper."]))
        case .versionMismatch:
            running = false; checks.append(DoctorCheck("helper_version", "Helper", .fail, "version differs", hint: ["Rerun 'sparekey setup' to refresh the helper."]))
        case .notRunning:
            running = false; checks.append(DoctorCheck("helper_version", "Helper", .fail, "not responding", hint: [facts.installed ? "Restart it: \(restart)" : setupHint]))
        }
        switch (running, facts.accessibility) {
        case (true, true?): checks.append(DoctorCheck("accessibility", "Accessibility", .ok, "enabled"))
        case (true, _):
            checks.append(DoctorCheck("accessibility", "Accessibility", .fail, "not enabled", hint: [
                "Add the stable copy above in System Settings >",
                "Privacy & Security > Accessibility.",
                "If it is already listed, remove it and add it again.",
                "Then restart the helper: \(restart)"]))
        default: checks.append(DoctorCheck("accessibility", "Accessibility", .skip, "unknown while the helper is down"))
        }
        switch (running, facts.credentialReadable) {
        case (true, true?): checks.append(DoctorCheck("credential", "Credential", .ok, "readable without prompts"))
        case (true, _): checks.append(DoctorCheck("credential", "Credential", .fail, "not readable by the helper", hint: ["Rerun 'sparekey setup' locally; it asks for your password once."]))
        default: checks.append(DoctorCheck("credential", "Credential", .skip, "unknown while the helper is down"))
        }
        switch facts.breakerTripped {
        case false?: checks.append(DoctorCheck("breaker", "Circuit breaker", .ok, "clear"))
        case true?: checks.append(DoctorCheck("breaker", "Circuit breaker", .fail, "tripped; unlocks are paused", hint: ["Rerun 'sparekey setup' locally to clear it."]))
        case nil: checks.append(DoctorCheck("breaker", "Circuit breaker", .skip, "no state yet"))
        }
        for (name, title, agent, file) in [("codex_skill", "Codex skill", "codex", facts.codexSkill),
                                           ("claude_skill", "Claude Code skill", "claude", facts.claudeSkill)] {
            switch file {
            case .current: checks.append(DoctorCheck(name, title, .ok, "installed"))
            case .missing: checks.append(DoctorCheck(name, title, .skip, "not installed"))
            case .modified: checks.append(DoctorCheck(name, title, .fail, "differs from this version",
                                                      hint: ["Run 'sparekey skill install --agent \(agent)' (keeps SKILL.md.bak)."]))
            case .unsafe: checks.append(DoctorCheck(name, title, .fail, "cannot be verified safely",
                                                    hint: ["The skill folder or SKILL.md is a symlink, not yours, or unreadable.",
                                                           "Fix or remove it, then run 'sparekey skill install --agent \(agent)'."]))
            }
        }
        return checks
    }
    public static func healthy(_ checks: [DoctorCheck]) -> Bool { !checks.contains { $0.status == .fail } }
    public static func errorCode(_ checks: [DoctorCheck], facts: DoctorFacts) -> String? {
        func failed(_ name: String) -> Bool { checks.contains { $0.name == name && $0.status == .fail } }
        guard !healthy(checks) else { return nil }
        if failed("install_path") { return "not_set_up" }
        if failed("helper_version") { return facts.helper == .versionMismatch ? "helper_version_mismatch" : "helper_not_running" }
        if failed("accessibility") { return "accessibility_missing" }
        if failed("credential") { return "credential_unavailable" }
        if failed("breaker") { return "breaker_tripped" }
        if failed("codex_skill") || failed("claude_skill") { return "skill_outdated" }
        return "internal"
    }
    public static func summary(_ checks: [DoctorCheck]) -> String {
        let problems = checks.filter { $0.status == .fail }.count
        let warnings = checks.filter { $0.status == .warn }.count
        if problems == 0 && warnings == 0 { return "All checks passed." }
        var parts: [String] = []
        if problems > 0 { parts.append(Layout.count(problems, "problem")) }
        if warnings > 0 { parts.append(Layout.count(warnings, "warning")) }
        return parts.joined(separator: ", ") + " found."
    }
    public static func render(_ checks: [DoctorCheck], palette: Palette) -> String {
        let width = checks.map(\.title.count).max() ?? 0
        var lines = [palette.bold("Sparekey doctor"), ""]
        for check in checks {
            lines.append(Layout.row(check.status.mark, check.title, check.detail, width: width, palette: palette))
            lines += Layout.notes(check.hint, width: width, palette: palette)
        }
        let summary = summary(checks)
        lines += ["", healthy(checks) ? summary : palette.bold(summary)]
        if !healthy(checks) { lines.append(palette.dim("Fix the items marked \(Mark.fail.symbol), then run 'sparekey doctor' again.")) }
        return lines.joined(separator: "\n")
    }
    /// `checks` keeps its v0.1 name→passed shape; `statuses` adds ok|warn|fail|skip.
    public static func json(_ checks: [DoctorCheck], facts: DoctorFacts) -> [String: Any] {
        var body: [String: Any] = ["ok": healthy(checks), "command": "doctor",
                                   "checks": Dictionary(uniqueKeysWithValues: checks.map { ($0.name, $0.status == .ok) }),
                                   "statuses": Dictionary(uniqueKeysWithValues: checks.map { ($0.name, $0.status.rawValue) })]
        if let code = errorCode(checks, facts: facts) { body["error"] = ["code": code, "message": "Sparekey needs attention. See checks."] }
        else { body["message"] = "Sparekey is ready." }
        return body
    }
}
