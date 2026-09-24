import Foundation
import Darwin

public enum StateStore {
    private static func directory(_ path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            throw SparekeyError("State directory is unsafe.")
        }
    }
    private static func file(_ path: String) throws -> Bool {
        var info = stat()
        if lstat(path, &info) != 0 {
            if errno == ENOENT { return false }
            throw SparekeyError("Cannot inspect state file.")
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else {
            throw SparekeyError("State file is not an owned regular file.")
        }
        return true
    }
    public static func read(directory path: String) throws -> SafetyState {
        try directory(path)
        let state = path + "/state.json"
        guard try file(state) else { return SafetyState() }
        var info = stat()
        guard lstat(state, &info) == 0, info.st_mode & 0o777 == 0o600 else {
            throw SparekeyError("State file permissions are unsafe.")
        }
        return try JSONDecoder().decode(SafetyState.self, from: Data(contentsOf: URL(fileURLWithPath: state)))
    }
    public static func write(_ value: SafetyState, directory path: String) throws {
        try directory(path)
        let state = path + "/state.json"
        _ = try file(state)
        let data = try JSONEncoder().encode(value)
        let temp = path + "/.state-\(UUID().uuidString)"
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SparekeyError("Cannot create state file.") }
        var openFD = true
        defer {
            if openFD { close(fd) }
            unlink(temp)
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SparekeyError("Cannot write state file.") }
                offset += count
            }
        }
        let synced = fsync(fd) == 0
        let closed = close(fd) == 0
        openFD = false
        guard synced, closed, rename(temp, state) == 0 else { throw SparekeyError("Cannot replace state file.") }
    }
}
