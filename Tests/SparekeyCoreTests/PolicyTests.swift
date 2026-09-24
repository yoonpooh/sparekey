import XCTest
@testable import SparekeyCore

final class PolicyTests: XCTestCase {
    private func localBuildFolder(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build")
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
    }
    func testCommandRoutingAndSkillFlags() throws {
        XCTAssertEqual(try Invocation.parse([]).command, .help)
        XCTAssertEqual(try Invocation.parse(["--version"]).command, .version)
        XCTAssertTrue(try Invocation.parse(["unlock", "--json"]).json)
        XCTAssertTrue(try Invocation.parse(["unlock", "--no-cover"]).noCover)
        XCTAssertThrowsError(try Invocation.parse(["lock", "--no-cover"]))
        XCTAssertThrowsError(try Invocation.parse(["unlock", "--no-cover", "--no-cover"]))
        XCTAssertEqual(try Invocation.parse(["setup", "--skill", "codex"]).skillTargets, ["codex"])
        XCTAssertEqual(try Invocation.parse(["setup", "--skill", "claude,codex"]).skillTargets, ["claude", "codex"])
        XCTAssertEqual(try Invocation.parse(["setup", "--skill", "codex", "--skill", "claude"]).skillTargets, ["claude", "codex"])
        XCTAssertThrowsError(try Invocation.parse(["setup", "--skill", "codex", "--no-skill"]))
        XCTAssertThrowsError(try Invocation.parse(["setup", "--skill", "other"]))
        XCTAssertThrowsError(try Invocation.parse(["status", "--skill", "codex"]))
        XCTAssertThrowsError(try Invocation.parse(["serve", "--json"]))
        XCTAssertEqual(try Invocation.parse(["skill", "install", "--agent", "codex"]).agent, "codex")
    }
    func testSelectionPromptParsing() {
        XCTAssertEqual(SkillSelection.parsePrompt(""), [])
        XCTAssertEqual(SkillSelection.parsePrompt("none"), [])
        XCTAssertEqual(SkillSelection.parsePrompt("1"), ["codex"])
        XCTAssertEqual(SkillSelection.parsePrompt("2, 1"), ["claude", "codex"])
        XCTAssertNil(SkillSelection.parsePrompt("3"))
        XCTAssertNil(SkillSelection.parsePrompt("1,"))
        XCTAssertNil(SkillSelection.parsePrompt("codex"))
    }
    func testPersistentLimiterAndBreaker() throws {
        var state = SafetyState()
        try state.admit(now: 100)
        XCTAssertThrowsError(try state.admit(now: 129.9))
        let encoded = try JSONEncoder().encode(state)
        var restored = try JSONDecoder().decode(SafetyState.self, from: encoded)
        try restored.admit(now: 90)
        try restored.admit(now: 130)
        restored.trip()
        XCTAssertThrowsError(try restored.admit(now: 200))
        restored.resetBreaker()
        try restored.admit(now: 200)
        var future = SafetyState(lastAttempt: 9_999)
        try future.admit(now: 100)
        XCTAssertEqual(future.lastAttempt, 100)
    }
    func testEnvelopeAndProtocol() throws {
        let envelope = Envelope(command: "unlock", code: "rate_limited", message: "wait")
        let data = try JSONEncoder().encode(envelope)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String: Any] != nil, true)
        XCTAssertEqual(try JSONDecoder().decode(Envelope.self, from: data).error?.code, "rate_limited")
        XCTAssertEqual(try JSONDecoder().decode(Request.self, from: JSONEncoder().encode(Request("status"))).v, 1)
        XCTAssertEqual(Request("unlock").v, 2)
        XCTAssertTrue(Request("unlock").isSupportedByCoverHelper)
        XCTAssertTrue(Request("unlock", noCover: true).isSupportedByCoverHelper)
        XCTAssertTrue(try JSONDecoder().decode(Request.self, from: JSONEncoder().encode(Request("unlock", noCover: true))).noCover)
        let oldCLI = try JSONDecoder().decode(Request.self, from: Data(#"{"v":1,"command":"unlock"}"#.utf8))
        XCTAssertFalse(oldCLI.noCover)
        XCTAssertTrue(oldCLI.isSupportedByCoverHelper)
        XCTAssertFalse(try JSONDecoder().decode(Request.self, from: Data(#"{"v":2,"command":"status"}"#.utf8)).isSupportedByCoverHelper)
    }
    func testNewPendingCoverIgnoresOldWatcherEnd() {
        var ownership = CoverOwnership()
        XCTAssertTrue(ownership.begin(attempt: 1))
        XCTAssertEqual(ownership.bind(attempt: 1, token: 1), .bound)
        // External relock, then a new unlock before the old watcher notices.
        XCTAssertTrue(ownership.begin(attempt: 2))
        XCTAssertFalse(ownership.end(token: 1))
        XCTAssertEqual(ownership.bind(attempt: 2, token: 2), .bound)
        XCTAssertTrue(ownership.end(token: 2))
        XCTAssertTrue(ownership.begin(attempt: 3))
        XCTAssertTrue(ownership.cancel(attempt: 3))
        XCTAssertFalse(ownership.begin(attempt: 3))
    }
    func testDisplayRevealRecoveryDecision() {
        XCTAssertFalse(DisplayRevealPolicy.shouldRecover(elapsed: 1.49, state: .waitingForAccount,
                                                        sawOwnLabel: false, attempted: false))
        XCTAssertTrue(DisplayRevealPolicy.shouldRecover(elapsed: 1.5, state: .waitingForAccount,
                                                       sawOwnLabel: false, attempted: false))
        XCTAssertFalse(DisplayRevealPolicy.shouldRecover(elapsed: 2, state: .waitingForAccount,
                                                        sawOwnLabel: true, attempted: false))
        XCTAssertFalse(DisplayRevealPolicy.shouldRecover(elapsed: 2, state: .waitingForField,
                                                        sawOwnLabel: false, attempted: false))
        XCTAssertFalse(DisplayRevealPolicy.shouldRecover(elapsed: 2, state: .waitingForAccount,
                                                        sawOwnLabel: false, attempted: true))
    }
    func testCoverUnavailableConsumesLimiterWithoutTrippingBreaker() {
        var state = SafetyState()
        XCTAssertThrowsError(try UnlockAttempt.run(state: &state, now: 100, persist: { _ in },
                                                  submit: { throw SparekeyError("cover unavailable", code: "cover_unavailable") },
                                                  wasSubmitted: { false }))
        XCTAssertEqual(state.lastAttempt, 100)
        XCTAssertFalse(state.breakerTripped)
    }
    func testLoginPolicyRequiresOwnAccountAndSingleSubmission() throws {
        let nodes = [LoginNode(role: "AXWindow", identifier: "login"),
                     LoginNode(role: "AXGroup", parent: 0),
                     LoginNode(role: "AXTextField", subrole: "AXSecureTextField", identifier: "UserPasswordTextField", parent: 1, writable: true),
                     LoginNode(role: "AXButton", identifier: "LUIBUTTON_GO", parent: 1, pressable: true)]
        XCTAssertEqual(try LoginPolicy.preparation(in: nodes, ownLabel: false), .waitingForAccount)
        XCTAssertEqual(try LoginPolicy.preparation(in: nodes, ownLabel: true), .ready)
        XCTAssertEqual(try LoginPolicy.submit(in: nodes), 3)
        XCTAssertThrowsError(try LoginPolicy.submit(in: nodes + [nodes[3]]))
        XCTAssertThrowsError(try LoginPolicy.submit(in: nodes + [LoginNode(role: "AXSheet")]))
    }
    func testManagedAgentOwnership() throws {
        let path = "/private/test/bin/sparekey"
        let expected = try PropertyListSerialization.data(fromPropertyList: ["Label": "io.github.yoonpooh.sparekey.helper", "ProgramArguments": [path, "serve"]], format: .xml, options: 0)
        XCTAssertTrue(ManagedAgent.matches(expected, executable: path))
        XCTAssertFalse(ManagedAgent.matches(expected, executable: "/other"))
    }
    func testTemporarySkillSelectionPlan() throws {
        let folder = localBuildFolder("sparekey-skill-plan")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("SKILL.md")
        let embedded = Data("Sparekey skill\n".utf8)
        XCTAssertEqual(SkillPlan.action(existing: nil, new: embedded), .create)
        try embedded.write(to: file)
        XCTAssertEqual(SkillPlan.action(existing: try Data(contentsOf: file), new: embedded), .skip)
        try Data("user edited\n".utf8).write(to: file)
        XCTAssertEqual(SkillPlan.action(existing: try Data(contentsOf: file), new: embedded), .replace)
    }
    func testStateStoreRoundTripPermissionsAndCorruption() throws {
        let folder = localBuildFolder("sparekey-state")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        var state = SafetyState(signerSHA1: String(repeating: "A", count: 40))
        try state.admit(now: 100)
        try StateStore.write(state, directory: folder.path)
        XCTAssertEqual(try StateStore.read(directory: folder.path), state)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data("broken".utf8).write(to: file)
        XCTAssertThrowsError(try StateStore.read(directory: folder.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try StateStore.read(directory: folder.path))
    }
    func testProtocolFramingLimits() throws {
        var frame = LineFrame(limit: 3)
        XCTAssertNil(try frame.append(65))
        XCTAssertNil(try frame.append(66))
        XCTAssertNil(try frame.append(67))
        XCTAssertEqual(try frame.append(10), Data("ABC".utf8))
        var overflow = LineFrame(limit: 2)
        _ = try overflow.append(65); _ = try overflow.append(66)
        XCTAssertThrowsError(try overflow.append(67))
    }
    func testUnconfirmedSubmissionTripsPersistedBreaker() throws {
        var state = SafetyState()
        var persisted: [SafetyState] = []
        var submitted = false
        XCTAssertThrowsError(try UnlockAttempt.run(state: &state, now: 100,
                                                   persist: { persisted.append($0) },
                                                   submit: { submitted = true; throw SparekeyError("not confirmed", code: "unlock_not_confirmed") },
                                                   wasSubmitted: { submitted }))
        XCTAssertEqual(persisted.count, 2)
        XCTAssertTrue(persisted.last!.breakerTripped)
        XCTAssertThrowsError(try state.admit(now: 200))
    }
    func testUninstallAllowlistAndSignatureRequirement() throws {
        XCTAssertTrue(InstallInventory.allows(["state.json", "run"], expected: ["state.json", "run", "bin"]))
        XCTAssertFalse(InstallInventory.allows(["state.json", "other"], expected: ["state.json", "run", "bin"]))
        let hash = String(repeating: "AB", count: 20)
        XCTAssertEqual(try SignaturePolicy.requirement(identifier: "io.github.yoonpooh.sparekey", certificateSHA1: hash),
                       "identifier \"io.github.yoonpooh.sparekey\" and certificate leaf = H\"\(hash)\"")
        XCTAssertThrowsError(try SignaturePolicy.requirement(identifier: "io.github.yoonpooh.sparekey", certificateSHA1: "bad"))
        XCTAssertThrowsError(try SignaturePolicy.requirement(identifier: "bad\"name", certificateSHA1: hash))
    }
    func testSkillPlan() {
        let value = Data("skill".utf8)
        XCTAssertEqual(SkillPlan.action(existing: nil, new: value), .create)
        XCTAssertEqual(SkillPlan.action(existing: value, new: value), .skip)
        XCTAssertEqual(SkillPlan.action(existing: Data(), new: value), .replace)
    }
}
