import XCTest
@testable import SparekeyCore

final class PreparationDiagnosticsTests: XCTestCase {
    func testCountsInspectionsIncludingFailuresWithoutRecordingTheirContents() throws {
        var diagnostics = PreparationDiagnostics(started: 10)
        XCTAssertEqual(diagnostics.inspect { "sensitive screen value" }, "sensitive screen value")
        XCTAssertThrowsError(try diagnostics.inspect { throw SparekeyError("secret error payload") })
        XCTAssertEqual(diagnostics.report(now: 10.25), "Preparation: inspections=2; elapsed_ms=250.")
    }

    func testInstrumentationDoesNotAddAttemptsOrAlterRetryTiming() throws {
        var now = 0.0
        var calls = 0
        var diagnostics = PreparationDiagnostics(started: now)
        let result: Int? = try PreparationRetry.run(deadline: 1, now: { now }, sleep: { now += $0 }, onTransient: {}) {
            try diagnostics.inspect {
                calls += 1
                if calls == 1 { throw SparekeyError("transient", transient: true) }
                return calls == 3 ? 42 : nil
            }
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(now, 0.2)
        XCTAssertEqual(diagnostics.report(now: now), "Preparation: inspections=3; elapsed_ms=200.")
    }

    func testNoInspectionAndClockFloor() {
        let diagnostics = PreparationDiagnostics(started: 1)
        XCTAssertEqual(diagnostics.report(now: 0), "Preparation: inspections=0; elapsed_ms=0.")
    }
}
