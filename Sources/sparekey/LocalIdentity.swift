import Foundation
import Security
import SparekeyCore

enum LocalIdentity {
    static func importPKCS12(_ data: Data, passphrase: String, keychainPath: String) throws {
        var keychain: SecKeychain?
        guard SecKeychainOpen(keychainPath, &keychain) == errSecSuccess, let keychain else {
            throw SparekeyError("Cannot open signing keychain.")
        }
        var access: SecAccess?
        // An empty trusted-app list requires approval for every private-key use.
        guard SecAccessCreate("sparekey local signing key" as CFString, [] as CFArray, &access) == errSecSuccess,
              let access else { throw SparekeyError("Cannot create signing-key access policy.") }
        let secret = passphrase as CFString
        let attributes = [kSecAttrIsPermanent, kSecAttrIsSensitive] as CFArray
        let usage = [kSecAttrCanSign] as CFArray
        var parameters = SecItemImportExportKeyParameters()
        parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        parameters.passphrase = Unmanaged.passUnretained(secret as CFTypeRef)
        parameters.accessRef = Unmanaged.passUnretained(access)
        parameters.keyUsage = Unmanaged.passUnretained(usage)
        parameters.keyAttributes = Unmanaged.passUnretained(attributes)
        var format: SecExternalFormat = .formatPKCS12
        var itemType: SecExternalItemType = .itemTypeAggregate
        var items: CFArray?
        let status = SecItemImport(data as CFData, nil, &format, &itemType, [], &parameters, keychain, &items)
        guard status == errSecSuccess else { throw SparekeyError("Signing identity import failed (OSStatus \(status)).") }
        guard let identity = (items as? [SecIdentity])?.first else {
            throw SparekeyError("Import did not return a signing identity.")
        }
        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess,
              let privateKey, let values = SecKeyCopyAttributes(privateKey) as? [String: Any],
              values[kSecAttrIsExtractable as String] as? Bool == false,
              values[kSecAttrIsSensitive as String] as? Bool == true else {
            throw SparekeyError("Imported signing key is not non-extractable and sensitive.")
        }
    }
}
