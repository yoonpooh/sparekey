import Foundation
import Darwin
import SparekeyCore

enum Doctor {
    static func checks() -> [(String, Bool, String)] {
        let installed = (try? Paths.checkedFile(Paths.stable)) == true
        let state = try? StateFile.read()
        let signed = installed && state?.signerSHA1.map { Setup.verifySignature(Paths.stable, certificateSHA1: $0) } == true
        let plist = (try? Paths.checkedFile(Paths.plist)) == true && (try? ManagedAgent.matches(Data(contentsOf: URL(fileURLWithPath: Paths.plist)), executable: Paths.stable)) == true
        let loaded = (try? Setup.launchctl(["print", "gui/\(getuid())/" + Paths.label])) == 0
        let reply = try? Transport.request("check")
        return [
            ("install_path", installed, Paths.stable),
            ("signature", signed, "Signed stable copy and identifier"),
            ("launch_agent", plist && loaded, "LaunchAgent loaded"),
            ("helper_version", reply?.helperVersion == "0.1.0", reply?.helperVersion ?? "unavailable"),
            ("accessibility", reply?.accessibility == true, "Accessibility trust"),
            ("credential", reply?.credentialReadable == true, "Credential readable without UI"),
            ("breaker", state?.breakerTripped == false, state?.breakerTripped == true ? "tripped" : "clear or unavailable"),
            ("codex_skill", (try? Data(contentsOf: URL(fileURLWithPath: Skills.root("codex") + "/SKILL.md"))) == Data(EmbeddedSkill.content.utf8), "Codex skill"),
            ("claude_skill", (try? Data(contentsOf: URL(fileURLWithPath: Skills.root("claude") + "/SKILL.md"))) == Data(EmbeddedSkill.content.utf8), "Claude Code skill")
        ]
    }
    static func installedCheck(_ results: [(String, Bool, String)], _ name: String) -> Bool {
        results.first(where: { $0.0 == name })?.1 == true
    }
    static func run(json: Bool) {
        let results = checks()
        let healthy = results.prefix(7).allSatisfy { $0.1 }
        if json {
            var body: [String: Any] = ["ok": healthy, "command": "doctor", "checks": Dictionary(uniqueKeysWithValues: results.map { ($0.0, $0.1) })]
            if healthy { body["message"] = "Sparekey is ready." }
            else {
                let code: String
                if !installedCheck(results, "install_path") { code = "not_set_up" }
                else if !installedCheck(results, "helper_version") { code = "helper_not_running" }
                else if !installedCheck(results, "accessibility") { code = "accessibility_missing" }
                else if !installedCheck(results, "credential") { code = "credential_unavailable" }
                else if !installedCheck(results, "breaker") { code = "breaker_tripped" }
                else { code = "internal" }
                body["error"] = ["code": code, "message": "Sparekey needs attention. See checks."]
            }
            if let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) { print(string) }
        } else {
            for (name, passed, detail) in results { print("\(passed ? "OK" : "FAIL") \(name): \(detail)") }
            if !healthy { FileHandle.standardError.write(Data("Run 'sparekey setup' locally to repair setup, credential, or permissions.\n".utf8)) }
        }
        if !healthy { exit(1) }
    }
}
