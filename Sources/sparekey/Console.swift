import Foundation
import Darwin
import SparekeyCore

/// A step failure that carries captured subprocess output for display under the ✗ line.
struct StepFailure: Error {
    let issue: SparekeyError
    let details: String
    init(_ message: String, code: String = "internal", details: String = "") {
        issue = SparekeyError(message, code: code); self.details = details
    }
}

/// A setup step already printed its ✗ row; main still prints the stderr diagnostic and exit status.
struct ReportedFailure: Error { let issue: SparekeyError }

enum Console {
    static let environment = ProcessInfo.processInfo.environment
    static let stdoutTTY = isatty(STDOUT_FILENO) == 1
    static let interactive = stdoutTTY && isatty(STDIN_FILENO) == 1
    static let palette = Palette.detect(isTTY: stdoutTTY, environment: environment)
    static let errorPalette = Palette.detect(isTTY: isatty(STDERR_FILENO) == 1, environment: environment)
    /// Pending lines are rewritten in place only where cursor control works.
    static let rewrites = stdoutTTY && environment["TERM"] != "dumb"
    static let width = Layout.setupLabelWidth
    private static var pending = false

    static func write(_ text: String) {
        fputs(text, stdout); fflush(stdout)
    }
    static func line(_ text: String = "") {
        clearPending(); write(text + "\n")
    }
    /// Failures and their details go to stderr; progress stays on stdout.
    static func errorLine(_ text: String) {
        clearPending(); fputs(text + "\n", stderr)
    }
    static func display(_ path: String) -> String { Layout.displayPath(path, home: NSHomeDirectory()) }

    /// Shows `  • Label  detail` while a step runs; the next row replaces it.
    static func begin(_ label: String, _ detail: String) {
        guard rewrites else { return }
        clearPending()
        write(Layout.row(.info, label, palette.dim(detail), width: width, palette: palette))
        pending = true
    }
    static func row(_ mark: Mark, _ label: String, _ detail: String, notes: [String] = []) {
        let failed = mark == .fail, style = failed ? errorPalette : palette
        let emit: (String) -> Void = failed ? errorLine : { line($0) }
        emit(Layout.row(mark, label, detail, width: width, palette: style))
        for note in Layout.notes(notes, width: width, palette: style) { emit(note) }
    }
    static func details(_ text: String) {
        for detail in Layout.details(text) { errorLine(errorPalette.dim(detail)) }
    }
    private static func clearPending() {
        if pending { write("\r\u{1B}[2K"); pending = false }
    }
    /// Reads one trimmed, lowercased line; nil on EOF.
    static func ask(_ prompt: String) -> String? {
        clearPending(); write(prompt)
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
