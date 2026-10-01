import XCTest
@testable import SparekeyCore

final class RelockAuthorityTests: XCTestCase {
    func testTaskCompletionLocksOnce() throws {
        let authority = RelockAuthority()
        let token = try XCTUnwrap(authority.grant(hold: 1, checkpoint: authority.checkpoint()))
        var locks = 0
        try authority.lock(token: token) { locks += 1 }
        XCTAssertThrowsError(try authority.lock(token: token) { locks += 1 })
        XCTAssertEqual(locks, 1)
    }
    func testUserLockAndManualUnlockCannotRestoreOldAuthority() throws {
        let authority = RelockAuthority()
        let token = try XCTUnwrap(authority.grant(hold: 1, checkpoint: authority.checkpoint()))
        authority.revoke()
        XCTAssertThrowsError(try authority.lock(token: token) { XCTFail("Must leave user session alone") })
        XCTAssertThrowsError(try authority.lock(token: nil) { XCTFail("Old tokenless threads must not lock") })
        let next = try XCTUnwrap(authority.grant(hold: 2, checkpoint: authority.checkpoint()))
        XCTAssertNotEqual(next, token)
        XCTAssertThrowsError(try authority.lock(token: token) { XCTFail("Old task must not lock new task") })
        try authority.lock(token: next) {}
    }
    func testLockDuringUnlockTransactionPreventsGrant() {
        let authority = RelockAuthority()
        let checkpoint = authority.checkpoint()
        authority.revoke()
        XCTAssertNil(authority.grant(hold: 1, checkpoint: checkpoint))
    }
    func testEndedHoldAndRestartRejectOldTokens() throws {
        let authority = RelockAuthority()
        let token = try XCTUnwrap(authority.grant(hold: 1, checkpoint: authority.checkpoint()))
        authority.end(hold: 2)
        XCTAssertEqual(authority.grant(hold: 1, checkpoint: authority.checkpoint()), token)
        authority.end(hold: 1)
        XCTAssertThrowsError(try authority.lock(token: token) { XCTFail() })
        XCTAssertThrowsError(try RelockAuthority().lock(token: token) { XCTFail() })
    }
    func testAlreadyUnlockedCannotCreateOrResurrectAuthority() throws {
        let authority = RelockAuthority()
        XCTAssertNil(authority.existing(hold: 1))
        let token = try XCTUnwrap(authority.grant(hold: 1, checkpoint: authority.checkpoint()))
        XCTAssertEqual(authority.existing(hold: 1), token)
        authority.revoke()
        XCTAssertNil(authority.existing(hold: 1))
        XCTAssertThrowsError(try authority.lock(token: nil) { XCTFail() })
    }
    func testTokenWireAndCLI() throws {
        let token = UUID().uuidString
        let invocation = try Invocation.parse(["lock", "--lock-token", token, "--json"])
        XCTAssertEqual(invocation.lockToken, token)
        XCTAssertThrowsError(try Invocation.parse(["unlock", "--lock-token", token]))
        XCTAssertThrowsError(try Invocation.parse(["lock", "--lock-token", "invalid"]))
        XCTAssertTrue(try Invocation.parse(["lock", "--force"]).force)
        XCTAssertThrowsError(try Invocation.parse(["lock", "--force", "--lock-token", token]))
        XCTAssertTrue(Request("lock", forceLock: true).isSupportedByCoverHelper)
        XCTAssertFalse(Request("lock", lockToken: token, forceLock: true).isSupportedByCoverHelper)
        XCTAssertEqual(Request("probe").v, 3)
        XCTAssertTrue(Request("probe").isSupportedByCoverHelper)
        let request = Request("lock", lockToken: token)
        XCTAssertEqual(request.v, 3) // Old helpers reject instead of unconditionally locking.
        XCTAssertTrue(request.isSupportedByCoverHelper)
        XCTAssertEqual(try JSONDecoder().decode(Request.self, from: JSONEncoder().encode(request)).lockToken, token)
        let reply = Reply(state: "unlocked", message: "done", lockToken: token)
        XCTAssertEqual(try JSONDecoder().decode(Reply.self, from: JSONEncoder().encode(reply)).lockToken, token)
        let envelope = Envelope(command: "unlock", state: "unlocked", message: "done", lockToken: token)
        XCTAssertEqual(try JSONDecoder().decode(Envelope.self, from: JSONEncoder().encode(envelope)).lockToken, token)
    }
}
