import Foundation
import Darwin
import SparekeyCore

/// Codex owns plugin installation/configuration; Sparekey supplies the local package.
enum CodexPlugin {
    static var root: String { Skills.home + "/plugins/sparekey" }
    static var marketplace: String { Skills.home + "/.agents/plugins/marketplace.json" }
    static let relativeRoot = "plugins/sparekey"
    static var files: [String: Data] {
        [".codex-plugin/plugin.json": Data(EmbeddedCodexPlugin.manifest.utf8),
         "skills/sparekey/SKILL.md": Data(EmbeddedSkill.content.utf8),
         "assets/logo.png": EmbeddedCodexPlugin.logo]
    }

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
                  source["path"] as? String == "./plugins/sparekey" else {
                throw SparekeyError("The existing Sparekey marketplace entry points elsewhere; no changes made.")
            }
        }
        return Catalog(body: body, name: name, registered: !matches.isEmpty, previous: previous)
    }

    static func register(_ catalog: Catalog) throws {
        if catalog.registered { return }
        try Skills.validateDirectory(".agents/plugins", create: true)
        let current = try Paths.checkedFile(marketplace) ? Data(contentsOf: URL(fileURLWithPath: marketplace)) : nil
        guard current == catalog.previous else { throw SparekeyError("Codex marketplace changed during installation; retry.") }
        var body = catalog.body
        var entries = body["plugins"] as! [[String: Any]]
        entries.append(["name": "sparekey", "source": ["source": "local", "path": "./plugins/sparekey"],
                        "policy": ["installation": "AVAILABLE", "authentication": "ON_INSTALL"], "category": "Productivity"])
        body["plugins"] = entries
        try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: marketplace), options: .atomic)
    }

    static func installed(_ name: String) throws -> [String: Any]? {
        let result = try run(["list", "--marketplace", name])
        guard let entries = result["installed"] as? [[String: Any]] else { throw SparekeyError("Codex did not return an installed plugin list.") }
        let entry = entries.first { $0["pluginId"] as? String == "sparekey@" + name }
        if let entry {
            guard let source = entry["source"] as? [String: Any], source["source"] as? String == "local",
                  source["path"] as? String == root else {
                throw SparekeyError("Installed Sparekey plugin comes from a different source; no migration performed.")
            }
        }
        return entry
    }

    static func matches(_ entry: [String: Any]?) -> Bool {
        guard let entry else { return false }
        return entry["installed"] as? Bool == true && entry["enabled"] as? Bool == true && entry["version"] as? String == EmbeddedCodexPlugin.version
    }

    static func packageCurrent() throws -> Bool {
        try Skills.validateDirectory(relativeRoot, create: false)
        var current = true
        for (relative, expected) in files {
            let parent = (relative as NSString).deletingLastPathComponent
            try Skills.validateDirectory(relativeRoot + "/" + parent, create: false)
            let path = root + "/" + relative
            if try !Paths.checkedFile(path) { current = false }
            else if try Data(contentsOf: URL(fileURLWithPath: path)) != expected { current = false }
        }
        return current
    }

    static func confirmReplacement(_ label: String, force: Bool) throws {
        if force { return }
        guard isatty(STDIN_FILENO) == 1 else {
            throw SparekeyError("Existing \(label) differs. Use --force to back it up and replace it, or run in a TTY.", code: "usage")
        }
        guard Console.ask("    Back up and replace the existing \(label)? [y/N] ") == "y" else {
            throw SparekeyError("Kept the existing \(label); plugin installation cancelled.")
        }
    }

    static func backup(_ path: String, label: String) throws {
        try Skills.validateDirectory(".sparekey-backups", create: true)
        let destination = Skills.home + "/.sparekey-backups/" + label + "-" + UUID().uuidString
        try FileManager.default.copyItem(atPath: path, toPath: destination)
        Console.row(.info, "Backup", Console.display(destination))
    }

    static func install(force: Bool) throws {
        _ = try executable()
        let catalog = try catalog()
        let before = try installed(catalog.name) // Also preflight CLI plugin support before writing.
        let current = try packageCurrent()
        try Skills.validateFolder("codex", create: false)
        let legacy = Skills.root("codex") + "/SKILL.md"
        let previous = try Paths.checkedFile(legacy) ? Data(contentsOf: URL(fileURLWithPath: legacy)) : nil
        if let previous, previous != Data(EmbeddedSkill.content.utf8) {
            try confirmReplacement("Codex standalone skill", force: force)
        }
        if !current && FileManager.default.fileExists(atPath: root) {
            try confirmReplacement("Codex plugin package", force: force)
            try backup(root, label: "codex-plugin")
        }
        for (relative, content) in files {
            let parent = (relative as NSString).deletingLastPathComponent
            try Skills.validateDirectory(relativeRoot + "/" + parent, create: true)
            _ = try Paths.checkedFile(root + "/" + relative)
            try content.write(to: URL(fileURLWithPath: root + "/" + relative), options: .atomic)
        }
        try register(catalog)
        if !current || !matches(before) {
            let result = try run(["add", "sparekey@" + catalog.name])
            guard result["pluginId"] as? String == "sparekey@" + catalog.name,
                  result["version"] as? String == EmbeddedCodexPlugin.version else {
                throw SparekeyError("Codex did not confirm the expected Sparekey plugin version; standalone skill kept.")
            }
        }
        guard matches(try installed(catalog.name)) else {
            throw SparekeyError("Codex plugin is not installed and enabled at the expected version; standalone skill kept.")
        }
        if let previous {
            try Skills.validateFolder("codex", create: false)
            guard try Paths.checkedFile(legacy), try Data(contentsOf: URL(fileURLWithPath: legacy)) == previous else {
                throw SparekeyError("Standalone skill changed during installation; it was kept.")
            }
            try backup(Skills.root("codex"), label: "codex-skill")
            try FileManager.default.removeItem(atPath: legacy)
            if try FileManager.default.contentsOfDirectory(atPath: Skills.root("codex")).isEmpty {
                try FileManager.default.removeItem(atPath: Skills.root("codex"))
            }
        }
        Console.row(.ok, "Codex plugin", "installed: sparekey@" + catalog.name,
                    notes: ["Start a new Codex thread to load the plugin."])
    }

    static func state() -> DoctorFacts.CodexPlugin {
        do {
            let catalog = try catalog()
            try Skills.validateFolder("codex", create: false)
            let legacy = try Paths.checkedFile(Skills.root("codex") + "/SKILL.md")
            if !catalog.registered { return legacy ? .legacy : .missing }
            guard let entry = try installed(catalog.name) else { return legacy ? .legacy : .missing }
            if legacy { return .duplicate }
            if entry["enabled"] as? Bool != true { return .disabled }
            guard matches(entry) else { return .outdated }
            return try packageCurrent() ? .current : .outdated
        } catch { return .unavailable }
    }

    static func removeInstalled() throws {
        let catalog = try catalog()
        guard catalog.registered, let entry = try installed(catalog.name), entry["installed"] as? Bool == true else { return }
        _ = try run(["remove", "sparekey@" + catalog.name])
        guard try installed(catalog.name) == nil else { throw SparekeyError("Codex still reports Sparekey installed.") }
    }
}
