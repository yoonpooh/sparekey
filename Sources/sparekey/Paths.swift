import Foundation
import Darwin
import SparekeyCore

enum Paths {
    static let identifier = "io.github.yoonpooh.sparekey"
    static let label = identifier + ".helper"
    static var base: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["SPAREKEY_TEST_RUNTIME_DIR"], !override.isEmpty { return override }
        #endif
        return NSHomeDirectory() + "/Library/Application Support/sparekey"
    }
    static var run: String { base + "/run" }
    static var socket: String { run + "/control.sock" }
    static var state: String { base + "/state.json" }
    static var stable: String { base + "/bin/sparekey" }
    static var plist: String { NSHomeDirectory() + "/Library/LaunchAgents/" + label + ".plist" }
    static func checkedDirectory(_ path: String, create: Bool) throws {
        var info = stat()
        if lstat(path, &info) != 0 {
            guard errno == ENOENT, create else { throw SparekeyError("Sparekey is not set up. Run 'sparekey setup'.", code: "not_set_up") }
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard lstat(path, &info) == 0 else { throw SparekeyError("Cannot inspect directory.") }
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            throw SparekeyError("Unexpected directory ownership or permissions.")
        }
    }
    static func checkedFile(_ path: String) throws -> Bool {
        var info = stat()
        if lstat(path, &info) != 0 { if errno == ENOENT { return false }; throw SparekeyError("Cannot inspect file.") }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else { throw SparekeyError("Refusing an unexpected file or symlink.") }
        return true
    }
}

enum StateFile {
    static func read() throws -> SafetyState { try StateStore.read(directory: Paths.base) }
    static func write(_ value: SafetyState) throws { try StateStore.write(value, directory: Paths.base) }
}
