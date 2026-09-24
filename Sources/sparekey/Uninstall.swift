import Foundation
import Darwin
import SparekeyCore

enum Uninstall {
    static func present(_ path: String) throws -> Bool {
        var info = stat()
        if lstat(path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw SparekeyError("Cannot inspect uninstall path.")
    }
    static func run() throws {
        try Setup.localTTY()
        if try present(Paths.base) {
            try Paths.checkedDirectory(Paths.base, create: false)
            for directory in [Paths.base + "/bin", Paths.run] {
                if try present(directory) { try Paths.checkedDirectory(directory, create: false) }
            }
        }
        let installed = try Paths.checkedFile(Paths.stable)
        if installed {
            guard let hash = try StateFile.read().signerSHA1, Setup.verifySignature(Paths.stable, certificateSHA1: hash) else { throw SparekeyError("Stable copy signature is unexpected. No files removed.") }
            let current = Bundle.main.executableURL?.resolvingSymlinksInPath().path
            if current != Paths.stable {
                guard try ForegroundChild.run(Paths.stable, ["uninstall"]) == 0 else { throw SparekeyError("Stable copy could not complete uninstall.") }
                return
            }
        }
        let agent = try Paths.checkedFile(Paths.plist)
        if agent {
            guard ManagedAgent.matches(try Data(contentsOf: URL(fileURLWithPath: Paths.plist)), executable: Paths.stable) else {
                throw SparekeyError("LaunchAgent does not match Sparekey. No files removed.")
            }
        }
        let baseExists = try present(Paths.base)
        if baseExists {
            try Paths.checkedDirectory(Paths.base, create: false)
            for (directory, allowed) in [(Paths.base, Set(["bin", "run", "state.json"])),
                                         (Paths.base + "/bin", Set(["sparekey"])),
                                         (Paths.run, Set(["control.sock", "service.lock"]))] {
                if try present(directory) {
                    try Paths.checkedDirectory(directory, create: false)
                    let names = try FileManager.default.contentsOfDirectory(atPath: directory)
                    guard InstallInventory.allows(names, expected: allowed) else { throw SparekeyError("Unexpected files in Sparekey directory. No files removed.") }
                }
            }
            _ = try Paths.checkedFile(Paths.state)
        }
        let runtime = try present(Paths.run)
        if runtime { try Paths.checkedDirectory(Paths.run, create: false) }
        for (path, type) in [(Paths.socket, S_IFSOCK), (Paths.run + "/service.lock", S_IFREG)] {
            var info = stat()
            if lstat(path, &info) == 0 {
                guard info.st_uid == getuid(), info.st_mode & S_IFMT == type else { throw SparekeyError("Unexpected runtime path. No files removed.") }
            }
        }
        let service = "gui/\(getuid())/" + Paths.label
        if try Setup.launchctl(["print", service]) == 0 {
            guard agent, try Setup.launchctl(["bootout", service]) == 0 else { throw SparekeyError("Cannot stop helper.") }
        }
        var lock: Int32 = -1
        if runtime { lock = open(Paths.run + "/service.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600) }
        defer { if lock >= 0 { close(lock) } }
        if runtime {
            guard lock >= 0 else { throw SparekeyError("Cannot open helper lock.") }
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while flock(lock, LOCK_EX | LOCK_NB) != 0 {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw SparekeyError("Helper still running.") }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        try Skills.removeWritten()
        try Credentials.delete()
        if agent { try FileManager.default.removeItem(atPath: Paths.plist) }
        if installed { try FileManager.default.removeItem(atPath: Paths.stable) }
        for path in [Paths.socket, Paths.run + "/service.lock", Paths.state] {
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        }
        for directory in [Paths.run, Paths.base + "/bin", Paths.base] {
            if (try? FileManager.default.contentsOfDirectory(atPath: directory).isEmpty) == true { try FileManager.default.removeItem(atPath: directory) }
        }
        print("Sparekey uninstalled. The signing identity was kept; remove 'sparekey local signing' in Keychain Access if desired.")
        print("Remove the old Accessibility entry in System Settings if it remains.")
    }
}
