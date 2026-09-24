import ApplicationServices
import Foundation
import Security

let service = "io.github.yoonpooh.sparekey.spike"
let account = "uid:\(getuid())"
#if V2
let variant = "v2"
#else
let variant = "v1"
#endif

func report(_ message: String) {
    print(message)
    if let path = ProcessInfo.processInfo.environment["SPIKE_LOG"] {
        let line = Data((message + "\n").utf8)
        if FileManager.default.fileExists(atPath: path),
           let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            FileManager.default.createFile(atPath: path, contents: line)
        }
    }
}

func fail(_ operation: String, _ status: OSStatus) -> Never {
    report("\(operation): OSStatus \(status)")
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    report("usage: probe ax|kc-save|kc-read|kc-delete|whoami")
    exit(2)
}

let mode = CommandLine.arguments[1]
let path = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
if mode == "whoami" {
    report("variant=\(variant) path=\(path)")
    exit(0)
}
if mode == "ax" {
    report("variant=\(variant) AXIsProcessTrusted=\(AXIsProcessTrusted())")
    exit(0)
}

guard ["kc-save", "kc-read", "kc-delete"].contains(mode) else {
    report("unknown mode: \(mode)")
    exit(2)
}

var login: SecKeychain?
let loginPath = NSHomeDirectory() + "/Library/Keychains/login.keychain-db"
let openStatus = SecKeychainOpen(loginPath, &login)
guard openStatus == errSecSuccess, let login else { fail("open login keychain", openStatus) }

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecMatchSearchList as String: [login]
]

switch mode {
case "kc-save":
    var trusted: SecTrustedApplication?
    let trustedStatus = SecTrustedApplicationCreateFromPath(path, &trusted)
    guard trustedStatus == errSecSuccess, let trusted else { fail("create trusted application", trustedStatus) }
    var access: SecAccess?
    let accessStatus = SecAccessCreate("sparekey signing spike" as CFString, [trusted] as CFArray, &access)
    guard accessStatus == errSecSuccess, let access else { fail("create access", accessStatus) }
    let attributes: [String: Any] = [
        kSecValueData as String: Data("sparekey-spike-dummy".utf8),
        kSecAttrAccess as String: access
    ]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
        var add = query
        add.removeValue(forKey: kSecMatchSearchList as String)
        add[kSecUseKeychain as String] = login
        for (key, value) in attributes { add[key] = value }
        status = SecItemAdd(add as CFDictionary, nil)
    }
    guard status == errSecSuccess else { fail("kc-save", status) }
    report("kc-save: success (OSStatus \(status))")
case "kc-read":
    SecKeychainSetUserInteractionAllowed(false)
    defer { SecKeychainSetUserInteractionAllowed(true) }
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &result)
    guard status == errSecSuccess, result as? Data != nil else { fail("kc-read", status) }
    report("kc-read: success (OSStatus \(status))")
case "kc-delete":
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { fail("kc-delete", status) }
    report(status == errSecItemNotFound ? "kc-delete: no item to delete" : "kc-delete: success (OSStatus 0)")
default:
    fatalError("validated above")
}
