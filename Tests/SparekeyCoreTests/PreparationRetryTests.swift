import XCTest
@testable import SparekeyCore

final class PreparationRetryTests: XCTestCase {
    func testTransientErrorsRetryThenSucceed() throws {
        var now = 0.0, attempts = 0, failures = 0
        var sleeps: [TimeInterval] = []
        let result = try PreparationRetry.run(deadline: 5, now: { now },
                                              sleep: { sleeps.append($0); now += $0 },
                                              onTransient: { failures += 1 }) { () throws -> Int? in
            attempts += 1
            if attempts < 3 { throw SparekeyError("rebuilding", transient: true) }
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(failures, 2)
        XCTAssertEqual(sleeps, [0.1, 0.1])
    }
    func testUnmarkedAndUnknownErrorsFailImmediately() {
        let errors: [Error] = [SparekeyError("rejected", code: "login_window_unsupported"),
                               NSError(domain: "test", code: 1)]
        for expected in errors {
            var now = 0.0, attempts = 0
            XCTAssertThrowsError(try PreparationRetry.run(deadline: 5, now: { now },
                                                          sleep: { now += $0; XCTFail("Must not sleep") },
                                                          onTransient: { XCTFail("Must not retry") }) { () throws -> Int? in
                attempts += 1
                throw expected
            }) { error in
                XCTAssertEqual(String(describing: error), String(describing: expected))
            }
            XCTAssertEqual(attempts, 1)
        }
    }
    func testDeadlineRethrowsLastTransientWithOriginalCode() {
        for code in ["internal", "login_window_unsupported"] {
            var now = 0.0, attempts = 0
            XCTAssertThrowsError(try PreparationRetry.run(deadline: 5, now: { now },
                                                          sleep: { now += $0 }, onTransient: {}) { () throws -> Int? in
                attempts += 1
                now += 2.5
                throw SparekeyError("failure \(attempts)", code: code, transient: true)
            }) { error in
                XCTAssertEqual((error as? SparekeyError)?.description, "failure 2")
                XCTAssertEqual((error as? SparekeyError)?.code, code)
                XCTAssertEqual((error as? SparekeyError)?.transient, true)
            }
            XCTAssertEqual(attempts, 2)
            XCTAssertEqual(now, 5.1, accuracy: 0.0001)
        }
    }
    func testGoodPendingSnapshotClearsLastTransient() throws {
        var now = 0.0, attempts = 0
        let result = try PreparationRetry.run(deadline: 5, now: { now },
                                              sleep: { now += $0 }, onTransient: {}) { () throws -> Int? in
            attempts += 1
            if attempts == 1 { throw SparekeyError("rebuilding", transient: true) }
            now = 5
            return nil
        }
        XCTAssertNil(result)
        XCTAssertEqual(attempts, 2)
    }
    func testSleepStopsAtDeadlineWithoutAnotherAttempt() {
        var now = 0.0, attempts = 0
        XCTAssertThrowsError(try PreparationRetry.run(deadline: 0.25, now: { now },
                                                      sleep: { now += $0 }, onTransient: {}) { () throws -> Int? in
            attempts += 1
            throw SparekeyError("still rebuilding", transient: true)
        }) { error in
            XCTAssertEqual((error as? SparekeyError)?.description, "still rebuilding")
        }
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(now, 0.25)
    }
    func testExpiredDeadlineStillAttemptsOnce() throws {
        var attempts = 0
        let result = try PreparationRetry.run(deadline: 0, now: { 1 }, sleep: { _ in XCTFail("Must not sleep") },
                                              onTransient: {}) { () throws -> Int? in
            attempts += 1
            return 7
        }
        XCTAssertEqual(result, 7)
        XCTAssertEqual(attempts, 1)
    }
}
