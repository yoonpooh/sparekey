import XCTest
@testable import SparekeyCore

final class DisplayContinuityTests: XCTestCase {
    func testGracePeriodLockFlagRetriesWakeAfterCooldownWithoutEndingHold() {
        XCTAssertEqual(DisplayContinuityPolicy.watcher(locked: true, displayAsleep: true,
                                                       canWake: true), .wake)
        XCTAssertEqual(DisplayContinuityPolicy.watcher(locked: true, displayAsleep: true,
                                                       canWake: false), .keep)
        XCTAssertEqual(DisplayContinuityPolicy.watcher(locked: true, displayAsleep: true,
                                                       canWake: true), .wake)
        XCTAssertEqual(DisplayContinuityPolicy.watcher(locked: false, displayAsleep: false,
                                                       canWake: true), .keep)
    }

    func testAwakePasswordLockEndsHold() {
        XCTAssertEqual(DisplayContinuityPolicy.watcher(locked: true, displayAsleep: false,
                                                       canWake: false), .end)
        XCTAssertEqual(DisplayContinuityPolicy.watcher(locked: true, displayAsleep: false,
                                                       canWake: true), .end)
    }

    func testPostUnlockWakeAndReadyDecisions() {
        for (locked, asleep) in [(true, false), (false, true), (true, true)] {
            XCTAssertTrue(DisplayContinuityPolicy.needsPostUnlockWake(locked: locked, displayAsleep: asleep))
            XCTAssertFalse(DisplayContinuityPolicy.isReady(locked: locked, displayAsleep: asleep))
        }
        XCTAssertFalse(DisplayContinuityPolicy.needsPostUnlockWake(locked: false, displayAsleep: false))
        XCTAssertTrue(DisplayContinuityPolicy.isReady(locked: false, displayAsleep: false))
    }

    func testCoverAndHoldPrecedeSubmissionAndVerification() throws {
        var events: [String] = []
        let token = try UnlockDisplayTransaction.run(cover: { events.append("cover") },
                                                     acquire: { events.append("hold"); return 7 },
                                                     submit: { events.append("submit") },
                                                     verify: { events.append("verify") },
                                                     release: { events.append("release") })
        XCTAssertEqual(token, 7)
        XCTAssertEqual(events, ["cover", "hold", "submit", "verify"])
    }

    func testFailedSubmissionOrVerificationReleasesHold() {
        for failingStep in ["submit", "verify"] {
            var events: [String] = []
            XCTAssertThrowsError(try UnlockDisplayTransaction.run(cover: { events.append("cover") },
                                                              acquire: { events.append("hold"); return 7 },
                                                              submit: {
                                                                  events.append("submit")
                                                                  if failingStep == "submit" { throw SparekeyError("failed") }
                                                              }, verify: {
                                                                  events.append("verify")
                                                                  if failingStep == "verify" { throw SparekeyError("failed") }
                                                              }, release: { events.append("release") }))
            XCTAssertEqual(events.last, "release")
            XCTAssertEqual(events.filter { $0 == "release" }.count, 1)
        }
    }

    func testFailedCoverDoesNotAcquireOrSubmit() {
        var events: [String] = []
        XCTAssertThrowsError(try UnlockDisplayTransaction.run(cover: {
            events.append("cover")
            throw SparekeyError("failed")
        }, acquire: { events.append("hold"); return 7 }, submit: { events.append("submit") },
           verify: { events.append("verify") }, release: { events.append("release") }))
        XCTAssertEqual(events, ["cover"])
    }

    func testProbeCoversBeforeWakeAndKeepsHoldOnGraceUnlock() throws {
        var events: [String] = []
        let token = try ProbeDisplayTransaction.run(cover: { events.append("cover") },
                                                    acquire: { events.append("hold"); return 9 },
                                                    probe: { events.append("wake-and-inspect"); return true },
                                                    verifyUnlocked: { events.append("verify") },
                                                    release: { events.append("release") })
        XCTAssertEqual(token, 9)
        XCTAssertEqual(events, ["cover", "hold", "wake-and-inspect", "verify"])
    }

    func testProbeGraceUnlockThenUnlockReusesCoveredHold() throws {
        var ownership = CoverOwnership()
        XCTAssertTrue(ownership.begin(attempt: 1))
        let token = try ProbeDisplayTransaction.run(cover: {}, acquire: { 9 },
                                                    probe: { true }, verifyUnlocked: {}, release: {})
        XCTAssertEqual(ownership.bind(attempt: 1, token: token!), .bound)
        XCTAssertTrue(UnlockedRequestPolicy.canReuseHold(held: true,
                                                         covered: ownership.owns(token: token!), noCover: false))
        XCTAssertFalse(UnlockedRequestPolicy.canReuseHold(held: false, covered: true, noCover: false))
        XCTAssertFalse(UnlockedRequestPolicy.canReuseHold(held: true, covered: false, noCover: false))
    }

    func testProbeReleasesHoldWhenStillLockedOrInspectionFails() {
        for fail in [false, true] {
            var events: [String] = []
            let run = {
                try ProbeDisplayTransaction.run(cover: { events.append("cover") },
                                                acquire: { events.append("hold"); return 9 },
                                                probe: {
                                                    events.append("inspect")
                                                    if fail { throw SparekeyError("failed") }
                                                    return false
                                                }, verifyUnlocked: { events.append("verify") },
                                                release: { events.append("release") })
            }
            if fail { XCTAssertThrowsError(try run()) }
            else { XCTAssertNil(try? run()) }
            XCTAssertEqual(events, ["cover", "hold", "inspect", "release"])
        }
    }

    func testProbeCoverFailureNeverWakes() {
        var woke = false
        XCTAssertThrowsError(try ProbeDisplayTransaction.run(cover: {
            throw SparekeyError("cover unavailable", code: "cover_unavailable")
        }, acquire: { XCTFail("Hold must not start"); return 9 },
           probe: { woke = true; return true }, verifyUnlocked: {}, release: {}))
        XCTAssertFalse(woke)
    }

    func testLockCommandAlwaysActsOnPreexistingGraceFlag() throws {
        var events: [String] = []
        try LockCommandPolicy.run(initiallyLocked: true, sendShortcut: { events.append("shortcut") },
                                  confirm: { events.append("confirm"); return true },
                                  immediate: { events.append("immediate") })
        XCTAssertEqual(events, ["shortcut", "immediate", "confirm"])

        events = []
        try LockCommandPolicy.run(initiallyLocked: false, sendShortcut: { events.append("shortcut") },
                                  confirm: { events.append("confirm"); return true },
                                  immediate: { events.append("immediate") })
        XCTAssertEqual(events, ["shortcut", "confirm"])

        events = []
        var confirmations = 0
        try LockCommandPolicy.run(initiallyLocked: false, sendShortcut: { events.append("shortcut") },
                                  confirm: { events.append("confirm"); confirmations += 1; return confirmations == 2 },
                                  immediate: { events.append("immediate") })
        XCTAssertEqual(events, ["shortcut", "confirm", "immediate", "confirm"])
    }
}
