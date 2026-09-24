import Foundation
import Darwin
import Security
import OpenDirectory
import ApplicationServices
import SparekeyCore

enum Setup {
    // Use only for non-interactive system tools. Password-reading children use ForegroundChild.
    static func process(_ executable: String, _ arguments: [String]) throws -> (Int32, Data) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let output = Pipe()
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = output
        task.standardError = FileHandle.standardError
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, data)
    }
    static func launchctl(_ arguments: [String]) throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run(); task.waitUntilExit()
        return task.terminationStatus
    }
    static func restartAgent(plist: String) throws {
        let domain = "gui/\(getuid())"
        let service = domain + "/" + Paths.label
        if try launchctl(["print", service]) == 0 {
            guard try launchctl(["bootout", service]) == 0 else { throw SparekeyError("Cannot stop previous LaunchAgent.") }
        }
        for _ in 0..<20 {
            if try launchctl(["print", service]) != 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard try launchctl(["print", service]) != 0 else { throw SparekeyError("Previous LaunchAgent did not stop.") }
        for _ in 0..<5 {
            if try launchctl(["bootstrap", domain, plist]) == 0 { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw SparekeyError("LaunchAgent could not start after retries.")
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
        guard result.0 == 0, let listing = String(data: result.1, encoding: .utf8) else { throw SparekeyError("Cannot list signing identities.") }
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
    static func createIdentity() throws {
        let name = "sparekey local signing"
        if try identityHash(name, loginOnly: true) != nil { return }
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
        guard random.0 == 0, let secret = String(data: random.1, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty else { throw SparekeyError("Cannot generate identity password.") }
        let passFile = directory.appendingPathComponent("pass")
        try Data(secret.utf8).write(to: passFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passFile.path)
        func run(_ args: [String]) throws {
            guard try process("/usr/bin/openssl", args).0 == 0 else { throw SparekeyError("Identity creation failed.") }
        }
        try run(["genrsa", "-out", key, "2048"])
        try run(["req", "-new", "-x509", "-sha256", "-days", "3650", "-key", key, "-out", cert,
                 "-config", directory.appendingPathComponent("certificate.cnf").path, "-extensions", "code_signing"])
        try run(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12, "-passout", "file:\(passFile.path)"])
        try LocalIdentity.importPKCS12(Data(contentsOf: URL(fileURLWithPath: p12)), passphrase: secret,
                                       keychainPath: NSHomeDirectory() + "/Library/Keychains/login.keychain-db")
    }
    static func verifySignature(_ path: String, certificateSHA1: String) -> Bool {
        guard (try? process("/usr/bin/codesign", ["--verify", "--strict", path]).0) == 0,
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
        guard try process("/usr/bin/codesign", ["--force", "--options", "runtime", "--sign", hash, "--identifier", Paths.identifier, temp]).0 == 0,
              verifySignature(temp, certificateSHA1: hash), rename(temp, Paths.stable) == 0 else {
            throw SparekeyError("Signing or signature verification failed.")
        }
    }
    static func password() throws -> Data {
        guard let first = getpass("Mac login password: ") else { throw SparekeyError("Password input cancelled.") }
        var value = Data(bytes: first, count: strlen(first)); memset(first, 0, strlen(first))
        guard !value.isEmpty else { throw SparekeyError("Password cannot be empty.") }
        guard let second = getpass("Confirm password: ") else { throw SparekeyError("Password confirmation cancelled.") }
        var confirmation = Data(bytes: second, count: strlen(second)); memset(second, 0, strlen(second))
        defer { confirmation.resetBytes(in: confirmation.startIndex..<confirmation.endIndex) }
        guard value == confirmation else { value.resetBytes(in: value.startIndex..<value.endIndex); throw SparekeyError("Passwords do not match.") }
        do {
            let session = ODSession.default()
            let node = try ODNode(session: session, type: UInt32(kODNodeTypeLocalNodes))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            let text = String(decoding: value, as: UTF8.self)
            try record.verifyPassword(text)
        } catch let issue as NSError where issue.code == Int(kODErrorCredentialsMethodNotSupported.rawValue) {
            FileHandle.standardError.write(Data("Warning: OpenDirectory password verification is unsupported; continuing.\n".utf8))
        } catch { throw SparekeyError("Password verification failed: \(error.localizedDescription)", code: "credential_unavailable") }
        return value
    }
    static func stableContinuation() throws {
        var value = try password()
        defer { value.resetBytes(in: value.startIndex..<value.endIndex) }
        try Credentials.replace(password: value)
    }
    static func run(_ invocation: Invocation) throws {
        try localTTY()
        let identity = invocation.identity ?? "sparekey local signing"
        if invocation.identity == nil { try createIdentity() }
        guard let identityHash = try identityHash(identity, loginOnly: invocation.identity == nil) else { throw SparekeyError("Signing identity not found: \(identity)") }
        if try Paths.checkedFile(Paths.plist) {
            guard ManagedAgent.matches(try Data(contentsOf: URL(fileURLWithPath: Paths.plist)), executable: Paths.stable) else {
                throw SparekeyError("An unrelated LaunchAgent occupies the target path.")
            }
        }
        try sign(identityHash)
        let directory = NSHomeDirectory() + "/Library/LaunchAgents"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let plist: [String: Any] = ["Label": Paths.label, "ProgramArguments": [Paths.stable, "serve"],
                                    "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10,
                                    "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        _ = try Paths.checkedFile(Paths.plist)
        try data.write(to: URL(fileURLWithPath: Paths.plist), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.plist)
        try restartAgent(plist: Paths.plist)
        var checked = try waitForCheck()
        guard checked.ok else { throw SparekeyError(checked.error?.message ?? "Helper check failed.", code: checked.error?.code ?? "internal") }
        if invocation.resetPassword || checked.credentialReadable == false {
            // One private prompt in the stable signed copy, then a fresh ACL and read-back.
            guard try ForegroundChild.run(Paths.stable, ["setup-continue"]) == 0 else {
                throw SparekeyError("Credential could not be refreshed.", code: "credential_unavailable")
            }
            try restartAgent(plist: Paths.plist)
            checked = try waitForCheck()
            guard checked.ok else { throw SparekeyError(checked.error?.message ?? "Helper check failed.", code: checked.error?.code ?? "internal") }
            guard checked.credentialReadable == true else {
                throw SparekeyError("Helper cannot read the refreshed credential.", code: "credential_unavailable")
            }
        } else if checked.credentialReadable != true {
            throw SparekeyError("Helper check omitted credential status.", code: "internal")
        }
        var state = (try? StateFile.read()) ?? SafetyState()
        state.resetBreaker(); state.signerSHA1 = identityHash; try StateFile.write(state)
        do {
            let targets: [String]
            if invocation.noSkill { targets = [] }
            else if let chosen = invocation.skillTargets { targets = chosen }
            else { targets = try Skills.prompt() }
            try Skills.install(targets, force: false)
        } catch { FileHandle.standardError.write(Data(("Warning: skill installation failed: " + error.localizedDescription + "\n").utf8)) }
        if checked.accessibility != true { print("Enable Accessibility for \(Paths.stable) in System Settings > Privacy & Security > Accessibility.") }
        print("Sparekey setup complete. The saved password has not been tested at the lock screen.")
    }
}
