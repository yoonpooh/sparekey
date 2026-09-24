import Foundation
import Darwin
import SparekeyCore

enum Doctor {
    static func skillFile(_ target: String) -> DoctorFacts.SkillFile {
        let file = Skills.root(target) + "/SKILL.md"
        do {
            try Skills.validateFolder(target, create: false)
            guard try Paths.checkedFile(file) else { return .missing }
            return try Data(contentsOf: URL(fileURLWithPath: file)) == Data(EmbeddedSkill.content.utf8) ? .current : .modified
        } catch { return .unsafe }
    }
    static func facts() -> DoctorFacts {
        var facts = DoctorFacts()
        facts.stablePath = Paths.stable
        facts.uid = getuid()
        facts.installed = (try? Paths.checkedFile(Paths.stable)) == true
        let state = try? StateFile.read()
        facts.signed = facts.installed && state?.signerSHA1.map { Setup.verifySignature(Paths.stable, certificateSHA1: $0) } == true
        let plist = (try? Paths.checkedFile(Paths.plist)) == true && (try? ManagedAgent.matches(Data(contentsOf: URL(fileURLWithPath: Paths.plist)), executable: Paths.stable)) == true
        facts.agentLoaded = plist && (try? Setup.launchctl(["print", Setup.service])) == 0
        do {
            let reply = try Transport.request("check")
            facts.helper = .running(reply.helperVersion)
            facts.accessibility = reply.accessibility
            facts.credentialReadable = reply.credentialReadable
        } catch let issue as SparekeyError where issue.code == "helper_version_mismatch" {
            facts.helper = .versionMismatch
        } catch {
            facts.helper = .notRunning
        }
        facts.breakerTripped = state?.breakerTripped
        facts.codexSkill = skillFile("codex")
        facts.claudeSkill = skillFile("claude")
        return facts
    }
    static func run(json: Bool) {
        let facts = facts()
        let checks = DoctorReport.evaluate(facts)
        if json {
            let body = DoctorReport.json(checks, facts: facts)
            if let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) { print(string) }
        } else {
            print(DoctorReport.render(checks, palette: Console.palette))
        }
        if !DoctorReport.healthy(checks) { exit(1) }
    }
}
