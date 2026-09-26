import Foundation
import Darwin
import Security
import OpenDirectory
import ApplicationServices
import SparekeyCore

enum Setup {
    static let defaultIdentity = "sparekey local signing"
    static var service: String { "gui/\(getuid())/" + Paths.label }
    // Use only for non-interactive system tools. Password-reading children use ForegroundChild.
    // Both streams are captured so tool noise appears only under a failed step.
    static func process(_ executable: String, _ arguments: [String], input: Data? = nil) throws -> (status: Int32, output: Data, errors: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let output = Pipe(), errors = Pipe(), feed = Pipe()
        task.standardInput = input == nil ? FileHandle.nullDevice : feed
        task.standardOutput = output
        task.standardError = errors
        try task.run()
        if let input { feed.fileHandleForWriting.write(input); try? feed.fileHandleForWriting.close() }
        var errorData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errorData = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        task.waitUntilExit()
        return (task.terminationStatus, data, String(decoding: errorData, as: UTF8.self))
    }
    static func launchctl(_ arguments: [String]) throws -> Int32 {
        try process("/bin/launchctl", arguments).status
    }
    static func restartAgent(plist: String) throws {
        let domain = "gui/\(getuid())"
        if try launchctl(["print", service]) == 0 {
            let stop = try process("/bin/launchctl", ["bootout", service])
            guard stop.status == 0 else { throw StepFailure("Cannot stop the previous helper.", details: stop.errors) }
        }
        for _ in 0..<20 {
            if try launchctl(["print", service]) != 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard try launchctl(["print", service]) != 0 else { throw StepFailure("The previous helper did not stop.") }
        var last = ""
        for _ in 0..<5 {
            let start = try process("/bin/launchctl", ["bootstrap", domain, plist])
            if start.status == 0 { return }
            last = start.errors
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw StepFailure("The LaunchAgent could not start after retries.", details: last)
    }
    static func waitForCheck() throws -> Reply {
        for _ in 0..<40 {
            do { return try Transport.request("check") }
            catch let issue as SparekeyError where issue.code == "helper_version_mismatch" { throw issue }
            catch { Thread.sleep(forTimeInterval: 0.25) }
        }
        throw SparekeyError("Helper did not start.", code: "helper_not_running")
    }
    static func localTTY() throws {
        guard getuid() != 0, getuid() == geteuid(), isatty(STDIN_FILENO) == 1,
              ProcessInfo.processInfo.environment["SSH_CONNECTION"] == nil,
              ProcessInfo.processInfo.environment["SSH_TTY"] == nil else {
            throw SparekeyError("Run setup in a local interactive terminal as your regular user.")
        }
        guard try !Screen.locked() else { throw SparekeyError("Unlock this Mac before setup.") }
    }
    static func identityHash(_ name: String, loginOnly: Bool = false) throws -> String? {
        let arguments = ["find-identity", "-p", "codesigning"] + (loginOnly ? [NSHomeDirectory() + "/Library/Keychains/login.keychain-db"] : [])
        let result = try process("/usr/bin/security", arguments)
        guard result.status == 0, let listing = String(data: result.output, encoding: .utf8) else {
            throw StepFailure("Cannot list signing identities.", details: result.errors)
        }
        let pattern = try NSRegularExpression(pattern: #"^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)""#, options: [.anchorsMatchLines])
        // find-identity lists trusted identities twice (policy and valid sections); dedupe by hash.
        let matches = Set(pattern.matches(in: listing, range: NSRange(listing.startIndex..., in: listing)).compactMap { match -> String? in
            guard let labelRange = Range(match.range(at: 2), in: listing), String(listing[labelRange]) == name,
                  let hashRange = Range(match.range(at: 1), in: listing) else { return nil }
            return String(listing[hashRange]).uppercased()
        })
        guard matches.count <= 1 else { throw SparekeyError("Signing identity name is ambiguous: \(name)") }
        return matches.first
    }
    /// Returns true when a new identity was created.
    static func createIdentity() throws -> Bool {
        if try identityHash(defaultIdentity, loginOnly: true) != nil { return false }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sparekey-sign-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = """
        [ req ]
        distinguished_name = dn
        prompt = no
        x509_extensions = code_signing
        [ dn ]
        CN = sparekey local signing
        [ code_signing ]
        basicConstraints = critical,CA:FALSE
        keyUsage = critical,digitalSignature
        extendedKeyUsage = codeSigning
        """
        try config.write(to: directory.appendingPathComponent("certificate.cnf"), atomically: true, encoding: .utf8)
        let key = directory.appendingPathComponent("private.key").path
        let cert = directory.appendingPathComponent("certificate.pem").path
        let p12 = directory.appendingPathComponent("identity.p12").path
        let random = try process("/usr/bin/openssl", ["rand", "-hex", "32"])
        guard random.status == 0, let secret = String(data: random.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty else { throw SparekeyError("Cannot generate identity password.") }
        let passFile = directory.appendingPathComponent("pass")
        try Data(secret.utf8).write(to: passFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passFile.path)
        func run(_ args: [String]) throws {
            let result = try process("/usr/bin/openssl", args)
            guard result.status == 0 else { throw StepFailure("Identity creation failed.", details: result.errors) }
        }
        try run(["genrsa", "-out", key, "2048"])
        try run(["req", "-new", "-x509", "-sha256", "-days", "3650", "-key", key, "-out", cert,
                 "-config", directory.appendingPathComponent("certificate.cnf").path, "-extensions", "code_signing"])
        try run(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12, "-passout", "file:\(passFile.path)"])
        try LocalIdentity.importPKCS12(Data(contentsOf: URL(fileURLWithPath: p12)), passphrase: secret,
                                       keychainPath: NSHomeDirectory() + "/Library/Keychains/login.keychain-db")
        return true
    }
    static func verifySignature(_ path: String, certificateSHA1: String) -> Bool {
        guard (try? process("/usr/bin/codesign", ["--verify", "--strict", path]).status) == 0,
              let requirementText = try? SignaturePolicy.requirement(identifier: Paths.identifier, certificateSHA1: certificateSHA1) else { return false }
        var code: SecStaticCode?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let details = information as? [String: Any],
              let flags = details[kSecCodeInfoFlags as String] as? NSNumber else { return false }
        return flags.uint32Value & 0x10000 != 0 // kSecCodeSignatureRuntime
    }
    static func sign(_ hash: String) throws {
        let source = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
        try Paths.checkedDirectory(Paths.base, create: true)
        try Paths.checkedDirectory(Paths.base + "/bin", create: true)
        _ = try Paths.checkedFile(Paths.stable)
        let temp = Paths.base + "/bin/.sparekey-\(UUID().uuidString)"
        defer { unlink(temp) }
        try FileManager.default.copyItem(atPath: source, toPath: temp)
        let signed = try process("/usr/bin/codesign", ["--force", "--options", "runtime", "--sign", hash, "--identifier", Paths.identifier, temp])
        guard signed.status == 0 else { throw StepFailure("Signing failed.", details: signed.errors) }
        guard verifySignature(temp, certificateSHA1: hash), rename(temp, Paths.stable) == 0 else {
            throw StepFailure("Signature verification failed.")
        }
    }
    static func password() throws -> Data {
        guard let first = getpass("    Mac login password: ") else { throw SparekeyError("Password input cancelled.") }
        var value = Data(bytes: first, count: strlen(first)); memset(first, 0, strlen(first))
        guard !value.isEmpty else { throw SparekeyError("Password cannot be empty.") }
        guard let second = getpass("    Confirm password:   ") else {
            value.resetBytes(in: value.startIndex..<value.endIndex)
            throw SparekeyError("Password confirmation cancelled.")
        }
        var confirmation = Data(bytes: second, count: strlen(second)); memset(second, 0, strlen(second))
        defer { confirmation.resetBytes(in: confirmation.startIndex..<confirmation.endIndex) }
        guard value == confirmation else { value.resetBytes(in: value.startIndex..<value.endIndex); throw SparekeyError("Passwords do not match.") }
        return value
    }
    /// Returns false when OpenDirectory cannot verify passwords on this Mac.
    static func verify(_ value: Data) throws -> Bool {
        do {
            let session = ODSession.default()
            let node = try ODNode(session: session, type: UInt32(kODNodeTypeLocalNodes))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            let text = String(decoding: value, as: UTF8.self)
            try record.verifyPassword(text)
            return true
        } catch let issue as NSError where issue.code == Int(kODErrorCredentialsMethodNotSupported.rawValue) {
            return false
        } catch let issue as NSError where issue.code == Int(kODErrorCredentialsInvalid.rawValue) {
            throw SparekeyError(rejected, code: "credential_unavailable")
        } catch { throw SparekeyError("Password verification failed: \(error.localizedDescription)", code: "credential_unavailable") }
    }
    static let rejected = "macOS did not accept that password."
    static let retryable: Set = ["Passwords do not match.", "Password cannot be empty.", rejected]
    static let unverifiedExit: Int32 = 3
    /// Runs in the stable copy. Exit 0 saved and verified, 3 saved without verification, 1 not saved.
    static func stableContinuation() -> Int32 {
        for attempt in 1...3 {
            do {
                var value = try password()
                defer { value.resetBytes(in: value.startIndex..<value.endIndex) }
                let verified = try verify(value)
                try Credentials.replace(password: value)
                return verified ? 0 : unverifiedExit
            } catch {
                let issue = error as? SparekeyError ?? SparekeyError("Password could not be saved.")
                let retry = attempt < 3 && retryable.contains(issue.description)
                if retry { Console.line("    " + Console.palette.mark(.warn) + " " + issue.description + " Try again.") }
                else { Console.errorLine("    " + Console.errorPalette.mark(.fail) + " " + issue.description) }
                if !retry { return 1 }
            }
        }
        return 1
    }
    static func step<T>(_ label: String, _ pending: String, _ body: () throws -> T) throws -> T {
        Console.begin(label, pending)
        do { return try body() }
        catch let failure as ReportedFailure { throw failure }
        catch let failure as StepFailure {
            Console.row(.fail, label, failure.issue.description)
            Console.details(failure.details)
            throw ReportedFailure(issue: failure.issue)
        } catch {
            let issue = error as? SparekeyError ?? SparekeyError(error.localizedDescription)
            Console.row(.fail, label, issue.description)
            throw ReportedFailure(issue: issue)
        }
    }
    static func checkedReply(_ reply: Reply) throws -> Reply {
        guard reply.ok else { throw SparekeyError(reply.error?.message ?? "Helper check failed.", code: reply.error?.code ?? "internal") }
        return reply
    }
    static func run(_ invocation: Invocation) throws {
        try localTTY()
        Console.line(Console.palette.bold("Sparekey 0.2.1 setup"))
        Console.line()
        try steps(invocation)
    }
    static func steps(_ invocation: Invocation) throws {
        var warnings = 0
        let identity = invocation.identity ?? defaultIdentity
        let (identityHash, created) = try step("Signing identity", "checking the login Keychain") { () throws -> (String, Bool) in
            let created = invocation.identity == nil ? try createIdentity() : false
            guard let hash = try identityHash(identity, loginOnly: invocation.identity == nil) else { throw SparekeyError("Signing identity not found: \(identity)") }
            return (hash, created)
        }
        Console.row(.ok, "Signing identity", (created ? "created " : "reused ") + "\"\(identity)\"")
        try step("Helper copy", "signing; choose Allow (not Always Allow) if Keychain asks") {
            if try Paths.checkedFile(Paths.plist) {
                guard ManagedAgent.matches(try Data(contentsOf: URL(fileURLWithPath: Paths.plist)), executable: Paths.stable) else {
                    throw SparekeyError("An unrelated LaunchAgent occupies the target path.")
                }
            }
            try sign(identityHash)
        }
        Console.row(.ok, "Helper copy", "signed and verified")
        // Before the restart stops it, let the running helper hand the saved password to the new copy.
        if !invocation.resetPassword { handoff() }
        var checked = try step("Background helper", "starting") { () throws -> Reply in
            let directory = NSHomeDirectory() + "/Library/LaunchAgents"
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let plist: [String: Any] = ["Label": Paths.label, "ProgramArguments": [Paths.stable, "serve"],
                                        "MachServices": [Handoff.service: true],
                                        "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10,
                                        "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive"]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            _ = try Paths.checkedFile(Paths.plist)
            try data.write(to: URL(fileURLWithPath: Paths.plist), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.plist)
            try restartAgent(plist: Paths.plist)
            return try checkedReply(waitForCheck())
        }
        Console.row(.ok, "Background helper", "running")
        if invocation.resetPassword || checked.credentialReadable == false {
            Console.row(.info, "Password", invocation.resetPassword ? "replacing the saved password" : "the helper needs your password",
                        notes: ["Typed privately; saved only in your login Keychain."])
            // One private prompt in the stable signed copy, then a fresh ACL and read-back.
            let status = try ForegroundChild.run(Paths.stable, ["setup-continue"])
            guard status == 0 || status == unverifiedExit else {
                throw ReportedFailure(issue: SparekeyError("Credential could not be refreshed.", code: "credential_unavailable"))
            }
            checked = try step("Password", "checking helper access") { () throws -> Reply in
                try restartAgent(plist: Paths.plist)
                let reply = try checkedReply(waitForCheck())
                guard reply.credentialReadable == true else {
                    throw SparekeyError("The helper cannot read the refreshed credential.", code: "credential_unavailable")
                }
                return reply
            }
            if status == 0 { Console.row(.ok, "Password", "saved (verified with macOS)") }
            else { warnings += 1; Console.row(.warn, "Password", "saved; macOS could not verify it on this Mac") }
        } else {
            guard checked.credentialReadable == true else {
                throw ReportedFailure(issue: SparekeyError("Helper check omitted credential status.", code: "internal"))
            }
            Console.row(.info, "Password", "kept existing (the helper can read it)")
        }
        try step("Safety state", "saving") {
            var state = (try? StateFile.read()) ?? SafetyState()
            state.resetBreaker(); state.signerSHA1 = identityHash; try StateFile.write(state)
        }
        warnings += installSkills(invocation)
        let enabled = try accessibility(checked)
        if !enabled { warnings += 1 }
        for line in SetupReport.summary(warnings: warnings, stablePath: enabled ? Paths.stable : nil, palette: Console.palette) { Console.line(line) }
    }
    /// Best effort and bounded: on any failure the restarted helper reports the credential unreadable
    /// and setup asks for the password instead.
    static func handoff() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: Paths.stable)
        task.arguments = ["credential-handoff"]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        guard (try? task.run()) != nil else { return }
        if done.wait(timeout: .now() + 30) == .timedOut {
            // Never let a stalled child overlap the interactive fallback that also replaces the item.
            task.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut { kill(task.processIdentifier, SIGKILL); task.waitUntilExit() }
        }
    }
    /// Returns the number of warnings.
    static func installSkills(_ invocation: Invocation) -> Int {
        let targets: [String]
        do {
            if invocation.noSkill { targets = [] }
            else if let chosen = invocation.skillTargets { targets = chosen }
            else { targets = try Skills.prompt() }
        } catch {
            Console.row(.warn, "Agent skills", "not chosen: " + ((error as? SparekeyError)?.description ?? error.localizedDescription))
            return 1
        }
        if targets.isEmpty {
            Console.row(.info, "Agent skills", "none selected", notes: ["Add one later: sparekey skill install"])
            return 0
        }
        var warnings = 0
        for target in targets {
            do { try Skills.installAndReport(target, force: false) }
            catch {
                warnings += 1
                Console.row(.warn, Skills.title(target), "not installed: " + ((error as? SparekeyError)?.description ?? error.localizedDescription))
            }
        }
        return warnings
    }
    static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    /// Returns true when the helper reports Accessibility trust. A missing permission or a skip
    /// is a warning; a helper that cannot restart or answer fails the step.
    static func accessibility(_ checked: Reply) throws -> Bool {
        let label = "Accessibility"
        if checked.accessibility == true { Console.row(.ok, label, "enabled"); return true }
        let path = Paths.stable
        let pane = "System Settings > Privacy & Security > Accessibility"
        guard Console.interactive else {
            Console.row(.warn, label, "not enabled", notes: ["Add this helper in", pane + ":", path])
            return false
        }
        Console.row(.warn, label, "not enabled yet", notes: [
            "Needed to use the lock screen. Add this helper in", pane + ":", path])
        guard let answer = Console.ask("    Press Enter to open System Settings and show the helper in Finder, or type s to skip: "), answer != "s" else {
            Console.row(.warn, label, "skipped", notes: ["Enable it later, then run 'sparekey doctor'."])
            return false
        }
        _ = try? process("/usr/bin/pbcopy", [], input: Data(path.utf8))
        _ = try? process("/usr/bin/open", [settingsURL])
        _ = try? process("/usr/bin/open", ["-R", path])
        Console.line(Console.palette.dim("    Path copied to the clipboard. Drag sparekey from Finder into the list, or click +,"))
        Console.line(Console.palette.dim("    press Cmd-Shift-G, paste, and choose Open. Then turn it on."))
        Console.line(Console.palette.dim("    If sparekey is already listed, remove it with - and add it again."))
        while true {
            guard let answer = Console.ask("    Press Enter after enabling it, or type s to skip: "), answer != "s" else {
                Console.row(.warn, label, "skipped", notes: ["Enable it later, then run 'sparekey doctor'."])
                return false
            }
            let reply = try step(label, "restarting the helper") { () throws -> Reply in
                let restart = try process("/bin/launchctl", ["kickstart", "-k", service])
                guard restart.status == 0 else { throw StepFailure("Cannot restart the helper.", details: restart.errors) }
                return try checkedReply(waitForCheck())
            }
            if reply.accessibility == true { Console.row(.ok, label, "enabled"); return true }
            Console.row(.warn, label, "still not enabled", notes: ["Make sure the sparekey switch is on. Remove and re-add it if it already was."])
        }
    }
}
