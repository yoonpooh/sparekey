import XCTest
import SparekeyCore
@testable import sparekey

final class SetupCheckTests: XCTestCase {
    func testOnlyMissingHelperIsRetriedDuringSetup() throws {
        var calls = 0, sleeps = 0
        let reply = try Setup.waitForCheck(request: {
            calls += 1
            if calls < 3 { throw SparekeyError("missing", code: "helper_not_running") }
            return Reply(state: "unlocked", message: "ready")
        }, sleep: { XCTAssertEqual($0, 0.25); sleeps += 1 })
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(sleeps, 2)
    }

    func testResponseAndConnectionFailuresArePreservedWithoutRetries() {
        for code in ["helper_timeout", "helper_disconnected", "helper_connection_failed", "helper_version_mismatch"] {
            var calls = 0
            XCTAssertThrowsError(try Setup.waitForCheck(request: {
                calls += 1
                throw SparekeyError("failed", code: code)
            }, sleep: { _ in XCTFail("Must not retry") })) {
                XCTAssertEqual(($0 as? SparekeyError)?.code, code)
            }
            XCTAssertEqual(calls, 1)
        }
    }
}
