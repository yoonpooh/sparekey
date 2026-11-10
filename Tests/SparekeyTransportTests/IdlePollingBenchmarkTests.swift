import XCTest
import Darwin
import SparekeyCore
@testable import sparekey

final class IdlePollingBenchmarkTests: XCTestCase {
    func testReadOnlyIdlePollingCost() throws {
        guard let value = ProcessInfo.processInfo.environment["SPAREKEY_IDLE_BENCHMARK_SECONDS"] else {
            throw XCTSkip("Opt-in read-only benchmark; see docs/idle-polling.md")
        }
        let seconds = try XCTUnwrap(Int(value))
        XCTAssertTrue((5...300).contains(seconds))
        guard (5...300).contains(seconds) else { return }
        for repetition in 1...3 {
            for queries in [false, true] {
                let queue = DispatchQueue(label: "sparekey.idle-benchmark")
                let timer = DispatchSource.makeTimerSource(queue: queue)
                let done = DispatchSemaphore(value: 0)
                var ticks = 0, reads = 0, failures = 0
                var keep = 0, end = 0, wake = 0
                var before = rusage()
                XCTAssertEqual(getrusage(RUSAGE_SELF, &before), 0)
                let started = ProcessInfo.processInfo.systemUptime
                timer.schedule(deadline: .now() + 1, repeating: 1)
                timer.setEventHandler {
                    ticks += 1
                    if queries {
                        reads += 1
                        do {
                            let locked = try Screen.locked()
                            let asleep = Screen.displayAsleep()
                            switch DisplayContinuityPolicy.watcher(locked: locked, displayAsleep: asleep, canWake: true) {
                            case .keep: keep += 1
                            case .end: end += 1
                            case .wake: wake += 1
                            }
                        } catch { failures += 1 }
                    }
                    if ticks >= seconds { timer.cancel(); done.signal() }
                }
                timer.resume()
                XCTAssertEqual(done.wait(timeout: .now() + Double(seconds) + 10), .success)
                timer.cancel()
                queue.sync {}
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                var after = rusage()
                XCTAssertEqual(getrusage(RUSAGE_SELF, &after), 0)
                func cpu(_ usage: rusage) -> Double {
                    Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
                    Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
                }
                let cpuSeconds = cpu(after) - cpu(before)
                let record: [String: Any] = [
                    "mode": queries ? "read-only-watcher" : "timer-control", "repetition": repetition,
                    "elapsed_seconds": elapsed, "ticks": ticks, "queries": reads,
                    "queries_per_second": Double(reads) / elapsed, "read_failures": failures,
                    "keep": keep, "end": end, "wake": wake,
                    "representative_hold_idle": queries && keep == seconds && failures == 0,
                    "cpu_seconds": cpuSeconds, "cpu_percent_one_core": cpuSeconds / elapsed * 100,
                    "process_peak_rss_bytes": after.ru_maxrss,
                    "voluntary_context_switches": after.ru_nvcsw - before.ru_nvcsw,
                    "involuntary_context_switches": after.ru_nivcsw - before.ru_nivcsw
                ]
                let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                print("IDLE_BENCHMARK " + String(decoding: data, as: UTF8.self))
                XCTAssertEqual(ticks, seconds)
                XCTAssertEqual(reads, queries ? seconds : 0)
                XCTAssertEqual(failures, 0, "A failed console read is not a representative idle sample.")
            }
        }
    }
}
