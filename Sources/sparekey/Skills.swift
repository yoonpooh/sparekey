import Foundation
import Darwin
import SparekeyCore

enum Skills {
    static var home: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["SPAREKEY_TEST_HOME"], !override.isEmpty { return override }
        #endif
        return NSHomeDirectory()
    }
    static func root(_ target: String) -> String {
        home + (target == "codex" ? "/.agents/skills/sparekey" : "/.claude/skills/sparekey")
    }
    static func detected(_ target: String) -> Bool {
        let home = home
        if target == "codex" { return FileManager.default.fileExists(atPath: home + "/.agents") || FileManager.default.fileExists(atPath: home + "/.codex") }
        return FileManager.default.fileExists(atPath: home + "/.claude")
    }
    static func title(_ target: String) -> String { target == "codex" ? "Codex skill" : "Claude Code skill" }
    static func prompt() throws -> [String] {
        guard isatty(STDIN_FILENO) == 1 else { throw SparekeyError("Choose skill targets with --agent or --skill.", code: "usage") }
        let palette = Console.palette
        func state(_ target: String) -> String { palette.dim(detected(target) ? "detected" : "not detected") }
        Console.row(.info, "Agent skills", "let an agent run sparekey for you")
        Console.line("      1  Codex         " + state("codex"))
        Console.line("      2  Claude Code   " + state("claude"))
        while true {
            guard let line = Console.ask("    Choose 1, 2, or 1,2 (Enter for none): ") else { throw SparekeyError("Skill selection cancelled.", code: "usage") }
            if let targets = SkillSelection.parsePrompt(line) { return targets }
            Console.line("    " + palette.mark(.warn) + " Enter 1, 2, 1,2, none, or press Enter.")
        }
    }
    static func confirm(_ target: String) throws -> Bool {
        guard isatty(STDIN_FILENO) == 1 else { throw SparekeyError("Existing skill differs; run in a TTY to confirm replacement.", code: "usage") }
        return Console.ask("    Replace the existing \(title(target)) and keep SKILL.md.bak? [y/N] ") == "y"
    }
    static func validateFolder(_ target: String, create: Bool) throws {
        let components = target == "codex" ? [".agents", "skills", "sparekey"] : [".claude", "skills", "sparekey"]
        var path = home
        for component in components {
            path += "/" + component
            var info = stat()
            if lstat(path, &info) != 0 {
                guard errno == ENOENT else { throw SparekeyError("Cannot inspect skill directory.") }
                if !create { return }
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else {
                throw SparekeyError("Skill directory is not owned by you or is a symlink.")
            }
        }
    }
    enum Outcome { case installed, unchanged, updated, declined }
    static func install(_ target: String, force: Bool) throws -> Outcome {
        guard ["codex", "claude"].contains(target) else { throw SparekeyError("Unknown skill target.", code: "usage") }
        try validateFolder(target, create: false)
        let folder = root(target), file = folder + "/SKILL.md", backup = file + ".bak"
        let new = Data(EmbeddedSkill.content.utf8)
        let current = try Paths.checkedFile(file) ? Data(contentsOf: URL(fileURLWithPath: file)) : nil
        switch SkillPlan.action(existing: current, new: new) {
        case .skip: return .unchanged
        case .create:
            try validateFolder(target, create: true)
            try new.write(to: URL(fileURLWithPath: file), options: .atomic)
            return .installed
        case .replace:
            guard try force || confirm(target) else { return .declined }
            guard !(try Paths.checkedFile(backup)) else { throw SparekeyError("Backup already exists at \(backup); refusing overwrite.") }
            try FileManager.default.copyItem(atPath: file, toPath: backup)
            try new.write(to: URL(fileURLWithPath: file), options: .atomic)
            return .updated
        }
    }
    static func installAndReport(_ target: String, force: Bool) throws {
        let folder = Console.display(root(target))
        switch try install(target, force: force) {
        case .installed: Console.row(.ok, title(target), "installed in " + folder)
        case .unchanged: Console.row(.info, title(target), "already current")
        case .updated: Console.row(.ok, title(target), "updated; previous version saved as SKILL.md.bak")
        case .declined: Console.row(.info, title(target), "kept your existing file")
        }
    }
    static func removeWritten() throws {
        for target in ["codex", "claude"] {
            let folder = root(target), file = folder + "/SKILL.md"
            try validateFolder(target, create: false)
            if try Paths.checkedFile(file), try Data(contentsOf: URL(fileURLWithPath: file)) == Data(EmbeddedSkill.content.utf8) {
                try FileManager.default.removeItem(atPath: file)
                if (try? FileManager.default.contentsOfDirectory(atPath: folder).isEmpty) == true { try FileManager.default.removeItem(atPath: folder) }
            }
        }
    }
}
