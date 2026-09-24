import Foundation
import Darwin
import SparekeyCore

enum ForegroundChild {
    // No POSIX_SPAWN_SETPGROUP: password prompts must retain the caller's foreground pgroup.
    static func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let arguments = [executable] + arguments
        var cArguments = arguments.map { strdup($0) }
        cArguments.append(nil)
        defer { for pointer in cArguments { if let pointer { free(pointer) } } }
        guard cArguments.dropLast().allSatisfy({ $0 != nil }) else { throw SparekeyError("Cannot allocate continuation arguments.") }
        var child: pid_t = 0
        let result = cArguments.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(&child, executable, nil, nil, buffer.baseAddress!, environ)
        }
        guard result == 0 else { throw SparekeyError("Cannot start foreground continuation (errno \(result)).") }
        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 {
            if errno == EINTR { continue }
            throw SparekeyError("Cannot wait for foreground continuation.")
        }
        if status & 0x7f == 0 { return (status >> 8) & 0xff }
        return 128 + (status & 0x7f)
    }
}
