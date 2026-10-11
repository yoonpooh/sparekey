import XCTest
@testable import SparekeyCore

final class LoginAccountPolicyTests: XCTestCase {
    private let names = ["local-user", "Local User"]

    func testExactShortAndFullNamesAreAccepted() throws {
        for name in names {
            try LoginAccountPolicy.verify(count: 1, role: "AXStaticText", label: name, allowedNames: names)
        }
    }

    func testMissingOrEmptyLabelRetriesUntilVerifiedWithoutInput() throws {
        for initial in [nil, "", " \n\t"] as [String?] {
            var now = 0.0, attempts = 0, accepted = 0
            let result = try PreparationRetry.run(deadline: 1, now: { now }, sleep: { now += $0 },
                                                  onTransient: {}) { () throws -> Bool? in
                attempts += 1
                try LoginAccountPolicy.verify(count: 1, role: "AXStaticText",
                                              label: attempts == 1 ? initial : self.names[0], allowedNames: self.names)
                accepted += 1
                return true
            }
            XCTAssertEqual(result, true)
            XCTAssertEqual(attempts, 2)
            XCTAssertEqual(accepted, 1)
        }
    }

    func testUnreadableLabelTimesOutWithoutAcceptingAccount() {
        var now = 0.0, accepted = false
        XCTAssertThrowsError(try PreparationRetry.run(deadline: 0.25, now: { now }, sleep: { now += $0 },
                                                       onTransient: {}) { () throws -> Bool? in
            try LoginAccountPolicy.verify(count: 1, role: "AXStaticText", label: nil, allowedNames: self.names)
            accepted = true
            return true
        }) { error in
            XCTAssertEqual((error as? SparekeyError)?.code, "field_not_ready")
            XCTAssertEqual((error as? SparekeyError)?.transient, true)
            XCTAssertFalse(String(describing: error).contains("does not exactly match"))
        }
        XCTAssertFalse(accepted)
        XCTAssertEqual(now, 0.25)
    }

    func testMismatchAndNearMatchesStopWithoutRetryOrNamesInError() {
        for label in ["other-user", "LOCAL-USER", "local-user ", "prefix local-user"] {
            var attempts = 0
            XCTAssertThrowsError(try PreparationRetry.run(deadline: 1, now: { 0 },
                                                           sleep: { _ in XCTFail("Must not retry") },
                                                           onTransient: { XCTFail("Must not retry") }) { () throws -> Bool? in
                attempts += 1
                try LoginAccountPolicy.verify(count: 1, role: "AXStaticText", label: label, allowedNames: self.names)
                return true
            }) { error in
                XCTAssertEqual((error as? SparekeyError)?.code, "login_account_mismatch")
                XCTAssertEqual((error as? SparekeyError)?.transient, false)
                for name in self.names + [label] { XCTAssertFalse(String(describing: error).contains(name)) }
            }
            XCTAssertEqual(attempts, 1)
        }
    }

    func testUnreadableThenMismatchedLabelNeverAcceptsAccount() {
        var now = 0.0, attempts = 0, accepted = false
        XCTAssertThrowsError(try PreparationRetry.run(deadline: 1, now: { now }, sleep: { now += $0 },
                                                       onTransient: {}) { () throws -> Bool? in
            attempts += 1
            try LoginAccountPolicy.verify(count: 1, role: "AXStaticText",
                                          label: attempts == 1 ? nil : "other-user", allowedNames: self.names)
            accepted = true
            return true
        }) { error in
            XCTAssertEqual((error as? SparekeyError)?.code, "login_account_mismatch")
        }
        XCTAssertFalse(accepted)
        XCTAssertEqual(attempts, 2)
    }

    func testDuplicateAndUnexpectedRoleStopEvenWhenLabelIsMissing() {
        for (count, role) in [(2, "AXStaticText"), (1, "AXTextField")] {
            for label in [nil, names[0]] as [String?] {
                XCTAssertThrowsError(try LoginAccountPolicy.verify(count: count, role: role, label: label, allowedNames: names)) { error in
                    XCTAssertEqual((error as? SparekeyError)?.code, "login_window_unsupported")
                    XCTAssertEqual((error as? SparekeyError)?.transient, false)
                    XCTAssertFalse(String(describing: error).contains("does not exactly match"))
                }
            }
        }
    }

    func testInvalidStructureIsRejectedBeforeReadingLabel() {
        func unreadable() throws -> String? {
            XCTFail("Must not read a label from an ambiguous or unsupported element")
            throw SparekeyError("AX inspection failed", transient: true)
        }
        for (count, role) in [(2, "AXStaticText"), (1, "AXTextField")] {
            XCTAssertThrowsError(try LoginAccountPolicy.verify(count: count, role: role,
                                                              label: try unreadable(), allowedNames: names)) { error in
                XCTAssertEqual((error as? SparekeyError)?.code, "login_window_unsupported")
                XCTAssertEqual((error as? SparekeyError)?.transient, false)
            }
        }
    }

    func testCompleteSnapshotRejectsLaterDuplicateBeforeReadingEitherValue() {
        let nodes = [LoginNode(role: "AXWindow", identifier: "login"),
                     LoginNode(role: "AXStaticText", identifier: "FocusedUser", parent: 0),
                     LoginNode(role: "AXTextField", subrole: "AXSecureTextField", identifier: "UserPasswordTextField", parent: 0),
                     LoginNode(role: "AXStaticText", identifier: "FocusedUser", parent: 0)]
        for firstLabel in [nil, "other-user", names[0]] as [String?] {
            var reads = 0
            XCTAssertThrowsError(try LoginAccountPolicy.verify(in: nodes, allowedNames: names) { _ in
                reads += 1
                return firstLabel
            }) { error in
                XCTAssertEqual((error as? SparekeyError)?.code, "login_window_unsupported")
                XCTAssertEqual((error as? SparekeyError)?.transient, false)
            }
            XCTAssertEqual(reads, 0)
        }
    }

    func testCompleteSnapshotWithoutLabelRemainsUnverifiedWithoutReadingValues() throws {
        let nodes = [LoginNode(role: "AXWindow", identifier: "login")]
        let ownLabel = try LoginAccountPolicy.verify(in: nodes, allowedNames: names) { _ in
            XCTFail("Must not read a nonexistent label")
            return self.names[0]
        }
        XCTAssertFalse(ownLabel)
        XCTAssertEqual(try LoginPolicy.preparation(in: nodes, ownLabel: ownLabel), .waitingForAccount)
    }

    func testCompleteSnapshotAcceptsOnlyTheSingleFocusedUserValue() throws {
        let nodes = [LoginNode(role: "AXWindow", identifier: "login"),
                     LoginNode(role: "AXStaticText", identifier: "unrelated", parent: 0),
                     LoginNode(role: "AXStaticText", identifier: "FocusedUser", parent: 0)]
        var reads: [Int] = []
        let ownLabel = try LoginAccountPolicy.verify(in: nodes, allowedNames: names) { index in
            reads.append(index)
            return self.names[1]
        }
        XCTAssertTrue(ownLabel)
        XCTAssertEqual(reads, [2])
        XCTAssertEqual(try LoginPolicy.preparation(in: nodes, ownLabel: ownLabel), .collapsed)
    }

    func testCompleteSnapshotRejectsUnsupportedRoleBeforeValueRead() {
        let nodes = [LoginNode(role: "AXWindow", identifier: "login"),
                     LoginNode(role: "AXTextField", identifier: "FocusedUser", parent: 0)]
        XCTAssertThrowsError(try LoginAccountPolicy.verify(in: nodes, allowedNames: names) { _ in
            XCTFail("Must not read an unsupported label")
            return self.names[0]
        }) { error in
            XCTAssertEqual((error as? SparekeyError)?.code, "login_window_unsupported")
            XCTAssertEqual((error as? SparekeyError)?.transient, false)
        }
    }

    func testAccountReadInspectionFailureKeepsAccountUnverifiedAndUsesFieldError() {
        let nodes = [LoginNode(role: "AXStaticText", identifier: "FocusedUser")]
        XCTAssertThrowsError(try LoginAccountPolicy.verify(in: nodes, allowedNames: names) { _ in
            throw SparekeyError("AX failure", transient: true)
        }) { error in
            XCTAssertEqual((error as? SparekeyError)?.code, "field_not_ready")
            XCTAssertEqual((error as? SparekeyError)?.transient, true)
        }
    }
}
