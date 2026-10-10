import XCTest
@testable import SparekeyCore

final class AuthenticatedTakeoverTests: XCTestCase {
    func testSuccessfulAuthenticationRevokesAgentRelockBeforeRevealingScreen() throws {
        let authority = RelockAuthority()
        let token = authority.grant(hold: 7, checkpoint: authority.checkpoint())
        var released = false
        XCTAssertTrue(AuthenticatedTakeoverTransaction.run(authenticated: true, expectedHold: 7,
                                                           currentHold: { 7 }, isUnlocked: { true },
                                                           revoke: { authority.revoke(hold: 7) }, release: {
            do {
                try authority.lock(token: token) { XCTFail("Agent must not lock user session") }
                XCTFail("Old relock authority must be rejected")
            } catch {
                XCTAssertEqual((error as? SparekeyError)?.code, "relock_revoked")
            }
            released = true
        }))
        XCTAssertTrue(released)
    }

    func testCancelFailureAndStaleSuccessPreserveCurrentTask() throws {
        for (authenticated, hold, unlocked) in [(false, UInt64(7), true), (true, 8, true), (true, 7, false)] {
            let authority = RelockAuthority()
            let token = authority.grant(hold: hold, checkpoint: authority.checkpoint())
            XCTAssertFalse(AuthenticatedTakeoverTransaction.run(authenticated: authenticated, expectedHold: 7,
                                                                currentHold: { hold }, isUnlocked: { unlocked },
                                                                revoke: { XCTFail("Must preserve current authority") },
                                                                release: { XCTFail("Must keep current cover") }))
            try authority.lock(token: token) {}
        }
    }

    func testEndedHoldCannotBeTakenOverByLateAuthentication() {
        XCTAssertFalse(AuthenticatedTakeoverTransaction.run(authenticated: true, expectedHold: 7,
                                                            currentHold: { nil }, isUnlocked: { true },
                                                            revoke: { XCTFail() }, release: { XCTFail() }))
    }

    func testTakeoverRevokesQueuedCleanupButCannotRevokeAnotherHold() throws {
        let authority = RelockAuthority()
        let token = authority.grant(hold: 7, checkpoint: authority.checkpoint())
        XCTAssertTrue(authority.revoke(hold: 7))
        XCTAssertThrowsError(try authority.lock(token: token) { XCTFail("Queued cleanup must be rejected") })
        let next = authority.grant(hold: 8, checkpoint: authority.checkpoint())
        XCTAssertFalse(authority.revoke(hold: 7))
        try authority.lock(token: next) {}
    }
}
