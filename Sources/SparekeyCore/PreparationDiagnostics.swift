import Foundation

public struct PreparationDiagnostics {
    private let started: TimeInterval
    public private(set) var inspections = 0

    public init(started: TimeInterval) { self.started = started }
    public mutating func inspect<T>(_ body: () throws -> T) rethrows -> T {
        inspections += 1
        return try body()
    }
    public func report(now: TimeInterval) -> String {
        "Preparation: inspections=\(inspections); elapsed_ms=\(Int(max(0, now - started) * 1000))."
    }
}
