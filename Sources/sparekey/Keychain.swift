import Foundation
import Security
import Darwin
import SparekeyCore

enum Credentials {
    static let service = Paths.identifier
    static var account: String { "uid:\(getuid())" }
    static func replace(password: Data) throws {
        var trusted: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(Paths.stable, &trusted) == errSecSuccess, let trusted else {
            throw SparekeyError("Cannot bind credential to stable helper.")
        }
        var access: SecAccess?
        guard SecAccessCreate("sparekey login password" as CFString, [trusted] as CFArray, &access) == errSecSuccess, let access else {
            throw SparekeyError("Cannot create credential ACL.")
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        let old = SecItemDelete(query as CFDictionary)
        guard old == errSecSuccess || old == errSecItemNotFound else {
            throw SparekeyError("Cannot remove old credential (OSStatus \(old)).", code: "credential_unavailable")
        }
        let attributes: [String: Any] = [kSecValueData as String: password, kSecAttrAccess as String: access]
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard status == errSecSuccess else { throw SparekeyError("Keychain save failed (OSStatus \(status)).", code: "credential_unavailable") }
    }
    static func read() throws -> Data {
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, !data.isEmpty else {
            throw SparekeyError("Saved password unavailable (OSStatus \(status)). Run 'sparekey setup' locally.", code: "credential_unavailable")
        }
        return data
    }
    static func delete() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SparekeyError("Cannot delete credential (OSStatus \(status)).", code: "credential_unavailable")
        }
    }
}
