import Foundation
import Darwin
import SparekeyCore
import AppKit

let help = """
sparekey 0.1.2 — unlock and relock this user's logged-in Mac

Usage:
  sparekey                  Show help
  sparekey unlock [--json] [--no-cover]  Unlock once and verify; cover displays by default
  sparekey lock [--json]    Lock and verify
  sparekey status [--json]  Read lock state
  sparekey probe [--json]   Verify login field without a password
  sparekey setup [--identity NAME] [--reset-password] [--skill claude|codex|claude,codex] [--no-skill]
  sparekey doctor [--json]  Check installation and permissions
  sparekey skill install [--agent claude|codex] [--force]
  sparekey uninstall        Remove Sparekey installation
  sparekey help [command]   Show help
  sparekey version          Print version

Exit 0 success, 1 operational failure, 2 usage error. The internal serve command is for launchd.
"""
func printJSON(_ body: Envelope) {
    if let data = try? JSONEncoder().encode(body), let value = String(data: data, encoding: .utf8) { print(value) }
}
func fail(_ issue: SparekeyError, command: String, json: Bool, exitCode: Int32 = 1) -> Never {
    if json { printJSON(Envelope(command: command, code: issue.code, message: issue.description)) }
    else { FileHandle.standardError.write(Data(("Error: " + issue.description + "\n").utf8)) }
    exit(exitCode)
}
let args = Array(CommandLine.arguments.dropFirst())
let invocation: Invocation
do { invocation = try Invocation.parse(args) }
catch {
    let issue = error as? SparekeyError ?? SparekeyError("Invalid arguments.", code: "usage")
    fail(issue, command: args.first.flatMap { Command(rawValue: $0) }?.rawValue ?? "help", json: args.contains("--json"), exitCode: 2)
}
let command = invocation.command
if command == .help {
    if let target = invocation.helpFor, target != .help { print("Usage: sparekey \(target.rawValue)\n\n" + help) }
    else { print(help) }
    exit(0)
}
if command == .version { print("sparekey 0.1.2"); exit(0) }
do {
    guard getuid() != 0, getuid() == geteuid() else { throw SparekeyError("Run as your regular user, without sudo.") }
    switch command {
    case .testImport:
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let p12 = environment["SPAREKEY_TEST_P12_PATH"], let pass = environment["SPAREKEY_TEST_PASS_PATH"],
              let keychain = environment["SPAREKEY_TEST_KEYCHAIN_PATH"], keychain.contains("/sparekey-import-test-"),
              keychain != NSHomeDirectory() + "/Library/Keychains/login.keychain-db" else {
            throw SparekeyError("Test import requires isolated paths.", code: "usage")
        }
        try LocalIdentity.importPKCS12(Data(contentsOf: URL(fileURLWithPath: p12)),
                                       passphrase: String(decoding: Data(contentsOf: URL(fileURLWithPath: pass)), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                                       keychainPath: keychain)
        print("test-import-ok")
        #else
        throw SparekeyError("Internal test command unavailable.", code: "usage")
        #endif
    case .ttyProbe:
        #if DEBUG
        guard try ForegroundChild.run(Bundle.main.executableURL!.path, ["tty-probe-child"]) == 0 else { throw SparekeyError("PTY child failed.") }
        #else
        throw SparekeyError("Internal test command unavailable.", code: "usage")
        #endif
    case .ttyProbeChild:
        #if DEBUG
        guard let input = getpass("Probe input: "), String(cString: input) == "probe" else { throw SparekeyError("PTY input failed.") }
        print("tty-ready")
        #else
        throw SparekeyError("Internal test command unavailable.", code: "usage")
        #endif
    case .serve:
        _ = try Screen.locked()
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        DispatchQueue.global(qos: .userInitiated).async {
            do { try Transport.serve() }
            catch {
                FileHandle.standardError.write(Data(("Helper stopped: \(error)\n").utf8))
                DispatchQueue.main.async { app.terminate(nil) }
            }
        }
        app.run()
    case .continueSetup:
        try Setup.localTTY()
        guard Bundle.main.executableURL?.resolvingSymlinksInPath().path == Paths.stable else { throw SparekeyError("Setup continuation requires stable copy.") }
        exit(Setup.stableContinuation())
    case .credentialHandoff: try Handoff.receive()
    case .setup: try Setup.run(invocation)
    case .uninstall: try Uninstall.run()
    case .skill:
        let targets = try invocation.agent.map { [$0] } ?? Skills.prompt()
        for target in targets { try Skills.installAndReport(target, force: invocation.force) }
        if targets.isEmpty { Console.row(.info, "Agent skills", "none selected") }
    case .doctor: Doctor.run(json: invocation.json)
    case .unlock, .lock, .status, .probe:
        let reply = try Transport.request(command.rawValue, noCover: invocation.noCover)
        guard reply.ok else { throw SparekeyError(reply.error?.message ?? "Helper operation failed.", code: reply.error?.code ?? "internal") }
        if invocation.json { printJSON(Envelope(command: command.rawValue, state: reply.state, message: reply.message ?? "Completed.")) }
        else { print(reply.state ?? reply.message ?? "Completed.") }
    default: break
    }
} catch let reported as ReportedFailure {
    fail(reported.issue, command: command.rawValue, json: invocation.json, exitCode: reported.issue.code == "usage" ? 2 : 1)
} catch {
    let issue = error as? SparekeyError ?? SparekeyError("Operation failed.")
    fail(issue, command: command.rawValue, json: invocation.json, exitCode: issue.code == "usage" ? 2 : 1)
}
