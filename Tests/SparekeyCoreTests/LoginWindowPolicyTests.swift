import XCTest
@testable import SparekeyCore

final class LoginWindowPolicyTests: XCTestCase {
    // Synthetic AX metadata. The incident's second window was not observable through CUA.
    private let login = LoginWindow(root: LoginNode(role: "AXWindow", identifier: "login"),
                                    modal: false, childCount: 2, actionCount: 1)
    private let empty = LoginWindow(root: LoginNode(role: "AXWindow", subrole: "AXStandardWindow"),
                                    modal: false, childCount: 0, actionCount: 0)

    func testSelectsLoginAlongsideAnEmptyNonmodalWindowInEitherOrder() throws {
        XCTAssertEqual(try LoginWindowPolicy.select(in: [empty, login]), 1)
        XCTAssertEqual(try LoginWindowPolicy.select(in: [login, empty]), 0)
        let noSubrole = LoginWindow(root: LoginNode(role: "AXWindow"), modal: false, childCount: 0, actionCount: 0)
        XCTAssertEqual(try LoginWindowPolicy.select(in: [noSubrole, login]), 1)
    }

    private func assertUnsupported(_ windows: [LoginWindow], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try LoginWindowPolicy.select(in: windows), file: file, line: line) { error in
            XCTAssertEqual((error as? SparekeyError)?.code, "login_window_unsupported", file: file, line: line)
        }
    }

    func testRejectsMissingAmbiguousOrDisguisedLoginWindows() {
        for windows in [[], [empty], [login, login]] {
            assertUnsupported(windows)
        }
        for root in [LoginNode(role: "AXGroup", identifier: "login"),
                     LoginNode(role: "AXWindow", subrole: "AXDialog", identifier: "login"),
                     LoginNode(role: "AXWindow", subrole: "AXSystemDialog", identifier: "login")] {
            assertUnsupported([LoginWindow(root: root, modal: false, childCount: 0, actionCount: 0)])
        }
        assertUnsupported([LoginWindow(root: login.root, modal: true, childCount: 2, actionCount: 1)])
    }

    func testRejectsDialogsUnknownAndInteractiveAuxiliaryWindows() {
        for root in [LoginNode(role: "AXSheet"), LoginNode(role: "AXUnknown"),
                     LoginNode(role: "AXWindow", subrole: "AXDialog"),
                     LoginNode(role: "AXWindow", subrole: "AXSystemDialog"),
                     LoginNode(role: "AXWindow", subrole: "unrecognized"),
                     LoginNode(role: "AXWindow", identifier: "authentication")] {
            assertUnsupported([login, LoginWindow(root: root, modal: false, childCount: 0, actionCount: 0)])
        }
        for modal in [true, nil] as [Bool?] {
            assertUnsupported([login, LoginWindow(root: empty.root, modal: modal, childCount: 0, actionCount: 0)])
        }
        for count in [1, nil] as [Int?] {
            assertUnsupported([login, LoginWindow(root: empty.root, modal: false, childCount: count, actionCount: 0)])
            assertUnsupported([login, LoginWindow(root: empty.root, modal: false, childCount: 0, actionCount: count)])
        }
    }

    func testBoundsWindowInspectionAndRechecksAuxiliaryWindows() throws {
        XCTAssertEqual(try LoginWindowPolicy.select(in: [login] + Array(repeating: empty, count: 7)), 0)
        assertUnsupported([login] + Array(repeating: empty, count: 8))
        XCTAssertEqual(try LoginWindowPolicy.select(in: [empty, login]), 1)
        assertUnsupported([LoginWindow(root: empty.root, modal: true, childCount: 0, actionCount: 0), login])
    }

    func testDiagnosticsDescribeMetadataWithoutGuessingDialogIdentity() {
        let unknown = LoginWindow(root: LoginNode(role: "AXWindow", identifier: "private-identifier"),
                                  modal: nil, childCount: nil, actionCount: nil)
        XCTAssertThrowsError(try LoginWindowPolicy.select(in: [login, unknown])) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("found 2"))
            XCTAssertTrue(message.contains("role=AXWindow"))
            XCTAssertTrue(message.contains("modal=unknown"))
            XCTAssertTrue(message.contains("children=unknown"))
            XCTAssertTrue(message.contains("actions=unknown"))
            XCTAssertFalse(message.contains("private-identifier"))
            XCTAssertFalse(message.contains("Force Quit"))
        }
    }

    func testSingleLoginStillRequiresAccountAndSecureFieldVerification() throws {
        XCTAssertEqual(try LoginWindowPolicy.select(in: [login]), 0)
        let nodes = [login.root,
                     LoginNode(role: "AXStaticText", identifier: "FocusedUser", parent: 0),
                     LoginNode(role: "AXGroup", parent: 0),
                     LoginNode(role: "AXTextField", subrole: "AXSecureTextField", identifier: "UserPasswordTextField",
                               parent: 2, writable: true),
                     LoginNode(role: "AXButton", identifier: "LUIBUTTON_GO", parent: 2, pressable: true)]
        let ownLabel = try LoginAccountPolicy.verify(in: nodes, allowedNames: ["local-user"]) { _ in "local-user" }
        XCTAssertEqual(try LoginPolicy.preparation(in: nodes, ownLabel: ownLabel), .ready)
        XCTAssertEqual(try LoginPolicy.submit(in: nodes), 4)
        XCTAssertThrowsError(try LoginAccountPolicy.verify(in: nodes, allowedNames: ["local-user"]) { _ in "another-user" })
        XCTAssertThrowsError(try LoginPolicy.field(in: nodes + [nodes[3]]))
    }
}
