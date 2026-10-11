import Foundation

/// Classifies only the verified loginwindow's FocusedUser element. Never logs account names.
public enum LoginAccountPolicy {
    /// Scan the complete snapshot before reading any label, so a later duplicate cannot be hidden by an unreadable first label.
    public static func verify(in nodes: [LoginNode], allowedNames: [String], readLabel: (Int) throws -> String?) throws -> Bool {
        let labels = nodes.indices.filter { nodes[$0].identifier == "FocusedUser" }
        guard let index = labels.first else { return false }
        try verify(count: labels.count, role: nodes[index].role,
                   label: try readLabel(index), allowedNames: allowedNames)
        return true
    }

    public static func verify(count: Int, role: String, label: @autoclosure () throws -> String?, allowedNames: [String]) throws {
        guard count == 1 else {
            throw SparekeyError("The login account label is ambiguous (multiple FocusedUser elements). No password was submitted.",
                                code: "login_window_unsupported")
        }
        guard role == "AXStaticText" else {
            throw SparekeyError("The login account label has an unsupported element role. No password was submitted.",
                                code: "login_window_unsupported")
        }
        let value: String?
        do { value = try label() }
        catch let issue as SparekeyError where issue.transient {
            throw SparekeyError("The login account label could not be read while the Accessibility screen was being inspected. The current account could not be verified. No password was submitted.",
                                code: "field_not_ready", transient: true)
        }
        guard let label = value, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SparekeyError("The login account label is not readable yet. The current account could not be verified. No password was submitted.",
                                code: "field_not_ready", transient: true)
        }
        // Do not trim, case-fold, or partially match a populated account name.
        guard allowedNames.contains(label) else {
            throw SparekeyError("The populated login account label does not exactly match this user's account names. No password was submitted.",
                                code: "login_account_mismatch")
        }
    }
}
