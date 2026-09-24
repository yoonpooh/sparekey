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
    static func prompt() throws -> [String] {
        guard isatty(STDIN_FILENO) == 1 else { throw SparekeyError("Choose skill targets with --agent or --skill.", code: "usage") }
        while true {
            print("Install Sparekey skill for [1] Codex (\(detected("codex") ? "detected" : "not detected")) [2] Claude Code (\(detected("claude") ? "detected" : "not detected"))?")
            print("Enter numbers separated by commas, 'none', or Enter for none: ", terminator: "")
            guard let line = readLine() else { throw SparekeyError("Skill selection cancelled.", code: "usage") }
            if let targets = SkillSelection.parsePrompt(line) { return targets }
            FileHandle.standardError.write(Data("Invalid selection. Enter 1, 2, 1,2, none, or Enter.\n".utf8))
        }
    }
    static func confirm(_ target: String) throws -> Bool {
        guard isatty(STDIN_FILENO) == 1 else { throw SparekeyError("Existing skill differs; run in a TTY to confirm replacement.", code: "usage") }
        print("Replace existing \(target) skill and save SKILL.md.bak? [y/N] ", terminator: "")
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "y"
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
    static func install(_ targets: [String], force: Bool) throws {
        for target in targets {
            guard ["codex", "claude"].contains(target) else { throw SparekeyError("Unknown skill target.", code: "usage") }
            try validateFolder(target, create: false)
            let folder = root(target), file = folder + "/SKILL.md", backup = file + ".bak"
            let new = Data(EmbeddedSkill.content.utf8)
            let current = try Paths.checkedFile(file) ? Data(contentsOf: URL(fileURLWithPath: file)) : nil
            switch SkillPlan.action(existing: current, new: new) {
            case .skip: print("\(target) skill already current.")
            case .create:
                try validateFolder(target, create: true)
                try new.write(to: URL(fileURLWithPath: file), options: .atomic)
                print("Installed \(target) skill.")
            case .replace:
                guard try force || confirm(target) else { print("Skipped \(target) skill."); continue }
                guard !(try Paths.checkedFile(backup)) else { throw SparekeyError("Backup already exists at \(backup); refusing overwrite.") }
                try FileManager.default.copyItem(atPath: file, toPath: backup)
                try new.write(to: URL(fileURLWithPath: file), options: .atomic)
                print("Updated \(target) skill; previous version saved as SKILL.md.bak.")
            }
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
