import Foundation

public struct LoginWindow {
    public let root: LoginNode
    public let modal: Bool?
    public let childCount: Int?
    public let actionCount: Int?

    public init(root: LoginNode, modal: Bool?, childCount: Int?, actionCount: Int?) {
        self.root = root; self.modal = modal
        self.childCount = childCount; self.actionCount = actionCount
    }
}

public enum LoginWindowPolicy {
    public static func select(in windows: [LoginWindow]) throws -> Int {
        func unsupported(_ reason: String) -> SparekeyError {
            let metadata = windows.prefix(8).enumerated().map { index, window in
                let root = window.root
                let role = ["AXWindow", "AXSheet", "AXUnknown"].contains(root.role) ? root.role : "other"
                let subrole = ["AXStandardWindow", "AXDialog", "AXSystemDialog"].contains(root.subrole)
                    ? root.subrole : (root.subrole.isEmpty ? "none" : "other")
                let identifier = root.identifier == "login" ? "login" : (root.identifier.isEmpty ? "none" : "other")
                return "[\(index) role=\(role) subrole=\(subrole) id=\(identifier) modal=\(window.modal.map { String($0) } ?? "unknown") children=\(window.childCount.map { String($0) } ?? "unknown") actions=\(window.actionCount.map { String($0) } ?? "unknown")]"
            }.joined(separator: " ")
            return SparekeyError("Unsupported login window layout (\(reason); found \(windows.count)). \(metadata) No password was submitted. No windows were closed.",
                                code: "login_window_unsupported", transient: true)
        }
        guard !windows.isEmpty, windows.count <= 8 else { throw unsupported("inspection requires 1...8 windows") }
        let candidates = windows.indices.filter { windows[$0].root.role == "AXWindow" && windows[$0].root.identifier == "login" }
        guard candidates.count == 1, let selected = candidates.first else { throw unsupported("expected one login window") }
        for (index, window) in windows.enumerated() {
            guard ["", "AXStandardWindow"].contains(window.root.subrole), window.modal != true else {
                throw unsupported("dialog or unsupported window \(index)")
            }
            if index != selected {
                // Only an explicitly empty, nonmodal, inert AX window may be ignored.
                guard window.root.role == "AXWindow", window.root.identifier.isEmpty,
                      window.modal == false, window.childCount == 0, window.actionCount == 0 else {
                    throw unsupported("unverified auxiliary window \(index)")
                }
            }
        }
        return selected
    }
}
