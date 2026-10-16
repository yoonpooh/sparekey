import Foundation
import Darwin
import SparekeyCore

/// Compatibility cleanup for plugins installed by Sparekey 0.3.0–0.3.3.
enum CodexPlugin {
    static var root: String { Skills.home + "/.codex/plugins/sparekey" }
    static var legacyRoot: String { Skills.home + "/plugins/sparekey" }
    static var marketplace: String { Skills.home + "/.agents/plugins/marketplace.json" }
    static let relativeRoot = ".codex/plugins/sparekey"
    static let legacyRelativeRoot = "plugins/sparekey"
    static func executable() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
        if environment["SPAREKEY_TEST_HOME"] != nil {
            guard let path = environment["SPAREKEY_TEST_CODEX"], path.hasPrefix("/"),
                  FileManager.default.isExecutableFile(atPath: path) else {
                throw SparekeyError("Codex CLI is unavailable in the isolated test environment.")
            }
            return path
        }
        #endif
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let path = String(directory) + "/codex"
            if path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw SparekeyError("Codex CLI was not found on PATH. Install or update Codex CLI, then run 'sparekey skill install --agent codex'.")
    }

    /// File-backed output avoids pipe deadlocks; every child has a bounded lifetime.
    static func run(_ arguments: [String]) throws -> [String: Any] {
        let binary = try executable()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sparekey-codex-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let stdout = temporary.appendingPathComponent("stdout"), stderr = temporary.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdout.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: stderr.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: stdout), errors = try FileHandle(forWritingTo: stderr)
        defer { try? output.close(); try? errors.close() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["plugin"] + arguments + ["--json"]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = output; task.standardError = errors
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPAREKEY_TEST_HOME"] != nil {
            var environment = ProcessInfo.processInfo.environment
            environment["HOME"] = Skills.home
            environment["CODEX_HOME"] = Skills.home + "/.codex"
            task.environment = environment
        }
        #endif
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        try task.run()
        var timeout: Double = 30
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPAREKEY_TEST_HOME"] != nil,
           let value = ProcessInfo.processInfo.environment["SPAREKEY_TEST_CODEX_TIMEOUT"].flatMap(Double.init) { timeout = value }
        #endif
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut { kill(task.processIdentifier, SIGKILL); task.waitUntilExit() }
            throw SparekeyError("Codex plugin command timed out. The existing standalone skill was kept; retry 'sparekey skill install --agent codex'.")
        }
        guard task.terminationStatus == 0 else {
            let detail = String(decoding: try Data(contentsOf: stderr), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw SparekeyError("Codex plugin command failed. Install or update Codex CLI and retry. " + String(detail.prefix(1200)))
        }
        guard let body = try JSONSerialization.jsonObject(with: Data(contentsOf: stdout)) as? [String: Any] else {
            throw SparekeyError("Codex returned an invalid plugin response.")
        }
        return body
    }

    struct Catalog {
        var body: [String: Any]
        let name: String
        let registered: Bool
        let previous: Data?
    }
    static func catalog() throws -> Catalog {
        try Skills.validateDirectory(".agents/plugins", create: false)
        let previous = try Paths.checkedFile(marketplace) ? Data(contentsOf: URL(fileURLWithPath: marketplace)) : nil
        let body: [String: Any]
        if let previous {
            guard let parsed = try JSONSerialization.jsonObject(with: previous) as? [String: Any] else {
                throw SparekeyError("Codex personal marketplace is not a JSON object.")
            }
            body = parsed
        } else {
            body = ["name": "personal", "interface": ["displayName": "Personal"], "plugins": [[String: Any]]()]
        }
        guard let name = body["name"] as? String,
              name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              let entries = body["plugins"] as? [[String: Any]] else {
            throw SparekeyError("Codex personal marketplace has an invalid name or plugin list; no changes made.")
        }
        let matches = entries.filter { $0["name"] as? String == "sparekey" }
        guard matches.count <= 1 else { throw SparekeyError("Duplicate Sparekey marketplace entries; no changes made.") }
        if let entry = matches.first {
            guard let source = entry["source"] as? [String: Any], source["source"] as? String == "local",
                  ["./" + relativeRoot, "./" + legacyRelativeRoot].contains(source["path"] as? String ?? "") else {
                throw SparekeyError("The existing Sparekey marketplace entry points elsewhere; no changes made.")
            }
        }
        return Catalog(body: body, name: name, registered: !matches.isEmpty,
                       previous: previous)
    }

    static func installed(_ name: String) throws -> [String: Any]? {
        let result = try run(["list", "--marketplace", name])
        guard let entries = result["installed"] as? [[String: Any]] else { throw SparekeyError("Codex did not return an installed plugin list.") }
        let entry = entries.first { $0["pluginId"] as? String == "sparekey@" + name }
        if let entry {
            guard let source = entry["source"] as? [String: Any], source["source"] as? String == "local",
                  [root, legacyRoot].contains(source["path"] as? String ?? "") else {
                throw SparekeyError("Installed Sparekey plugin comes from a different source; no migration performed.")
            }
        }
        return entry
    }

    static func removeInstalled() throws {
        let catalog = try catalog()
        guard catalog.registered else { return }
        if let entry = try installed(catalog.name), entry["installed"] as? Bool == true {
            _ = try run(["remove", "sparekey@" + catalog.name])
            guard try installed(catalog.name) == nil else { throw SparekeyError("Codex still reports Sparekey installed; standalone skill was not changed.") }
        }
        try Skills.validateDirectory(".agents/plugins", create: false)
        guard try Paths.checkedFile(marketplace), try Data(contentsOf: URL(fileURLWithPath: marketplace)) == catalog.previous else {
            throw SparekeyError("Codex marketplace changed during removal; kept the current catalog. Retry skill installation.")
        }
        var body = catalog.body
        body["plugins"] = (body["plugins"] as! [[String: Any]]).filter { $0["name"] as? String != "sparekey" }
        try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: marketplace), options: .atomic)
        Console.row(.ok, "Legacy plugin", "removed; source files and backups kept for recovery")
    }
}
