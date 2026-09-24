import XCTest
@testable import SparekeyCore

final class OutputTests: XCTestCase {
    private func ready() -> DoctorFacts {
        var facts = DoctorFacts()
        facts.installed = true; facts.signed = true; facts.agentLoaded = true
        facts.helper = .running("0.1.1"); facts.accessibility = true; facts.credentialReadable = true
        facts.breakerTripped = false; facts.codexSkill = .current
        facts.stablePath = "/Users/me/Library/Application Support/sparekey/bin/sparekey"; facts.uid = 501
        return facts
    }
    private func status(_ checks: [DoctorCheck], _ name: String) -> CheckStatus? { checks.first { $0.name == name }?.status }

    func testColorDetection() {
        XCTAssertTrue(Palette.detect(isTTY: true, environment: ["TERM": "xterm-256color"]).enabled)
        XCTAssertFalse(Palette.detect(isTTY: false, environment: ["TERM": "xterm-256color"]).enabled)
        XCTAssertFalse(Palette.detect(isTTY: true, environment: ["TERM": "xterm", "NO_COLOR": ""]).enabled)
        XCTAssertFalse(Palette.detect(isTTY: true, environment: ["TERM": "dumb"]).enabled)
        XCTAssertEqual(Palette(enabled: true).mark(.ok), "\u{1B}[32m✓\u{1B}[0m")
        XCTAssertEqual(Palette.plain.mark(.fail), "✗")
    }
    func testRowsAlignAndReadWithoutColor() {
        XCTAssertEqual(Layout.row(.ok, "Helper", "running", width: 10, palette: .plain), "  ✓ Helper      running")
        XCTAssertEqual(Layout.row(.info, "Password", "", width: 4, palette: .plain), "  • Password")
        XCTAssertEqual(Layout.notes(["fix it", ""], width: 6, palette: .plain), ["            fix it", ""])
        XCTAssertEqual(Layout.details("  noise\n\nmore \n"), ["      noise", "      more"])
        XCTAssertEqual(Layout.displayPath("/Users/me/.agents/skills", home: "/Users/me"), "~/.agents/skills")
        XCTAssertEqual(Layout.displayPath("/Users/meta/x", home: "/Users/me"), "/Users/meta/x")
        XCTAssertEqual(Layout.count(1, "problem"), "1 problem")
        XCTAssertEqual(Layout.count(2, "warning"), "2 warnings")
    }
    func testSetupSummaryMentionsPathOnlyWhenGiven() {
        let without = SetupReport.summary(warnings: 1, stablePath: nil, palette: .plain)
        XCTAssertTrue(without.contains { $0.hasPrefix("Setup complete with 1 warning.") })
        XCTAssertFalse(without.contains { $0.hasPrefix("Helper:") })
        XCTAssertTrue(without.contains("Next"))
        XCTAssertTrue(without.contains { $0.contains("sparekey probe") })
        let with = SetupReport.summary(warnings: 0, stablePath: "/p/sparekey", palette: .plain)
        XCTAssertTrue(with.contains("Helper: /p/sparekey"))
        XCTAssertTrue(with.contains { $0.hasPrefix("Setup complete. ") })
    }
    func testDoctorOptionalSkillsAreNotFailures() {
        let checks = DoctorReport.evaluate(ready())
        XCTAssertEqual(status(checks, "claude_skill"), .skip)
        XCTAssertEqual(status(checks, "codex_skill"), .ok)
        XCTAssertTrue(DoctorReport.healthy(checks))
        XCTAssertEqual(DoctorReport.summary(checks), "All checks passed.")
        let json = DoctorReport.json(checks, facts: ready())
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual((json["checks"] as? [String: Bool])?["claude_skill"], false)
        XCTAssertEqual((json["statuses"] as? [String: String])?["claude_skill"], "skip")
        XCTAssertEqual(json["message"] as? String, "Sparekey is ready.")
        XCTAssertNil(json["error"])
    }
    func testDoctorFailuresCarryHintsAndCodes() {
        var facts = ready()
        facts.accessibility = false; facts.claudeSkill = .modified
        let checks = DoctorReport.evaluate(facts)
        XCTAssertEqual(status(checks, "accessibility"), .fail)
        XCTAssertTrue(checks.first { $0.name == "accessibility" }!.hint.contains { $0.contains("gui/501/io.github.yoonpooh.sparekey.helper") })
        XCTAssertEqual(status(checks, "claude_skill"), .fail)
        XCTAssertEqual(DoctorReport.errorCode(checks, facts: facts), "accessibility_missing")
        XCTAssertEqual(DoctorReport.summary(checks), "2 problems found.")
        facts.accessibility = true
        XCTAssertEqual(DoctorReport.errorCode(DoctorReport.evaluate(facts), facts: facts), "skill_outdated")
        facts.claudeSkill = .unsafe
        let unsafe = DoctorReport.evaluate(facts)
        XCTAssertEqual(status(unsafe, "claude_skill"), .fail)
        XCTAssertFalse(unsafe.first { $0.name == "claude_skill" }!.hint.isEmpty)
        XCTAssertFalse(DoctorReport.healthy(unsafe))
        XCTAssertEqual(DoctorReport.errorCode(unsafe, facts: facts), "skill_outdated")
        facts.breakerTripped = true
        XCTAssertEqual(DoctorReport.errorCode(DoctorReport.evaluate(facts), facts: facts), "breaker_tripped")
    }
    func testDoctorDependentChecksSkipWhenHelperOrInstallMissing() {
        var facts = ready()
        facts.helper = .notRunning; facts.accessibility = nil; facts.credentialReadable = nil
        var checks = DoctorReport.evaluate(facts)
        XCTAssertEqual(status(checks, "helper_version"), .fail)
        XCTAssertEqual(status(checks, "accessibility"), .skip)
        XCTAssertEqual(status(checks, "credential"), .skip)
        XCTAssertEqual(DoctorReport.errorCode(checks, facts: facts), "helper_not_running")
        facts.helper = .versionMismatch
        XCTAssertEqual(DoctorReport.errorCode(DoctorReport.evaluate(facts), facts: facts), "helper_version_mismatch")
        var fresh = DoctorFacts()
        fresh.stablePath = "/p"
        checks = DoctorReport.evaluate(fresh)
        XCTAssertEqual(status(checks, "signature"), .skip)
        XCTAssertEqual(status(checks, "breaker"), .skip)
        XCTAssertEqual(DoctorReport.errorCode(checks, facts: fresh), "not_set_up")
        XCTAssertEqual(Set(checks.map(\.name)), ["install_path", "signature", "launch_agent", "helper_version", "accessibility",
                                                 "credential", "breaker", "codex_skill", "claude_skill"])
    }
    func testDoctorRenderPlacesHintUnderFailingRow() {
        var facts = ready()
        facts.accessibility = false
        let lines = DoctorReport.render(DoctorReport.evaluate(facts), palette: .plain).components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "Sparekey doctor")
        let row = lines.firstIndex { $0.hasPrefix("  ✗ Accessibility") }!
        XCTAssertTrue(lines[row + 1].hasPrefix(String(repeating: " ", count: 4 + 17 + 2) + "Add the stable copy"))
        XCTAssertTrue(lines.contains("  – Claude Code skill  not installed"))
        XCTAssertTrue(lines.contains("1 problem found."))
        XCTAssertFalse(lines.joined().contains("\u{1B}"))
    }
}
