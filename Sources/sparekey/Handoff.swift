import Foundation
import CryptoKit
import Security
import SparekeyCore

// Upgrades re-sign the helper, and the login Keychain partitions the credential by the creating
// binary's cdhash, so the new copy cannot read it. During setup the still-running helper hands the
// password to the new stable copy, which re-saves it under its own partition. Both ends run over
// XPC with a code-signing requirement pinned to the local certificate, so macOS checks each peer;
// this trusts no more than the credential ACL already does: code signed by the pinned key.
@objc protocol HandoffService {
    func credential(_ reply: @escaping (Data?) -> Void)
}

enum Handoff {
    static let service = Paths.identifier + ".handoff"

    /// Identifier plus the running code's leaf certificate. Computed only after the running code
    /// is verified against its file, so the helper must call it at startup, before setup can
    /// replace the stable file.
    static func pinnedRequirement() -> String? {
        var own: SecCode?, ownStatic: SecStaticCode?, information: CFDictionary?
        guard SecCodeCopySelf([], &own) == errSecSuccess, let own,
              SecCodeCheckValidity(own, [], nil) == errSecSuccess,
              SecCodeCopyStaticCode(own, [], &ownStatic) == errSecSuccess, let ownStatic,
              SecCodeCopySigningInformation(ownStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let leaf = ((information as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first else { return nil }
        let hash = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02X", $0) }.joined()
        return try? SignaturePolicy.requirement(identifier: Paths.identifier, certificateSHA1: hash)
    }

    final class Exporter: NSObject, HandoffService {
        func credential(_ reply: @escaping (Data?) -> Void) {
            guard (try? Screen.locked()) == false, var password = try? Credentials.read() else { reply(nil); return }
            defer { password.resetBytes(in: password.startIndex..<password.endIndex) }
            // The read can wait on the Keychain; recheck so a lock during the wait withholds it.
            reply((try? Screen.locked()) == false ? password : nil)
        }
    }

    final class Listener: NSObject, NSXPCListenerDelegate {
        let requirement: String
        init(requirement: String) { self.requirement = requirement }
        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            connection.setCodeSigningRequirement(requirement)
            connection.exportedInterface = NSXPCInterface(with: HandoffService.self)
            connection.exportedObject = Exporter()
            connection.resume()
            return true
        }
    }

    private static var listener: NSXPCListener?
    private static var delegate: Listener?

    /// Helper side. Without a pinned requirement (for example an unsigned debug build) there is no handoff.
    static func listen() {
        guard let requirement = pinnedRequirement() else { return }
        let listener = NSXPCListener(machServiceName: service)
        let delegate = Listener(requirement: requirement)
        listener.delegate = delegate
        listener.resume()
        self.listener = listener
        self.delegate = delegate
    }

    /// New stable copy side. Returns without changes when the credential is already readable.
    static func receive() throws {
        guard Bundle.main.executableURL?.resolvingSymlinksInPath().path == Paths.stable else {
            throw SparekeyError("Credential handoff requires the stable copy.", code: "usage")
        }
        if var existing = try? Credentials.read() { existing.resetBytes(in: existing.startIndex..<existing.endIndex); return }
        guard let requirement = pinnedRequirement() else { throw SparekeyError("The stable copy is not signed with a pinned certificate.") }
        let connection = NSXPCConnection(machServiceName: service, options: [])
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: HandoffService.self)
        connection.resume()
        defer { connection.invalidate() }
        var received: Data?
        let done = DispatchSemaphore(value: 0)
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in done.signal() } as? HandoffService
        proxy?.credential { value in received = value; done.signal() }
        guard proxy != nil, done.wait(timeout: .now() + 15) == .success, var password = received, !password.isEmpty else {
            throw SparekeyError("The running helper did not hand over the credential.", code: "credential_unavailable")
        }
        received = nil
        defer { password.resetBytes(in: password.startIndex..<password.endIndex) }
        guard try Setup.verify(password) else {
            throw SparekeyError("macOS cannot verify passwords here, so the handed-over credential was not saved.", code: "credential_unavailable")
        }
        try Credentials.replace(password: password)
        var check = try Credentials.read()
        check.resetBytes(in: check.startIndex..<check.endIndex)
    }
}
