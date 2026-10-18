import XCTest
import Darwin
import SparekeyCore
@testable import sparekey

final class TransportTests: XCTestCase {
    private func withSocket(_ body: (Int32, Int32) throws -> Void) throws {
        var sockets: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw SparekeyError("Cannot create test sockets.")
        }
        defer { sockets.forEach { close($0) } }
        sockets.forEach { Transport.configure($0, seconds: 20) }
        try body(sockets[0], sockets[1])
    }

    private func write(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { bytes in
            XCTAssertEqual(Darwin.write(fd, bytes.baseAddress, bytes.count), bytes.count)
        }
    }

    func testCompleteFrameAndTrailingData() throws {
        try withSocket { reader, writer in
            write(Data("hello\nignored".utf8), to: writer)
            XCTAssertEqual(try Transport.receive(reader), Data("hello".utf8))
        }
    }

    func testEmptyAndExactLimitFrames() throws {
        for text in ["", "abc"] {
            try withSocket { reader, writer in
                write(Data((text + "\n").utf8), to: writer)
                XCTAssertEqual(try Transport.receive(reader, limit: 3), Data(text.utf8))
            }
        }
    }

    func testOversizedFrameIsRejected() throws {
        try withSocket { reader, writer in
            write(Data("abcd\n".utf8), to: writer)
            XCTAssertThrowsError(try Transport.receive(reader, limit: 3)) { error in
                XCTAssertEqual((error as? SparekeyError)?.description, "Helper message too large.")
            }
        }
    }

    func testDefaultLimitAcrossReceiveBuffers() throws {
        try withSocket { reader, writer in
            let payload = Data(repeating: 97, count: 4096)
            write(payload + Data([10]), to: writer)
            XCTAssertEqual(try Transport.receive(reader), payload)
        }
    }

    func testOversizedFrameWithoutNewlineIsRejected() throws {
        try withSocket { reader, writer in
            write(Data(repeating: 97, count: 4097), to: writer)
            XCTAssertThrowsError(try Transport.receive(reader)) { error in
                XCTAssertEqual((error as? SparekeyError)?.description, "Helper message too large.")
            }
        }
    }

    func testFragmentedFrame() throws {
        try withSocket { reader, writer in
            write(Data("hel".utf8), to: writer)
            let finished = expectation(description: "writer finished")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                self.write(Data("lo\n".utf8), to: writer)
                finished.fulfill()
            }
            XCTAssertEqual(try Transport.receive(reader), Data("hello".utf8))
            wait(for: [finished], timeout: 1)
        }
    }

    func testDisconnectBeforeNewlineIsRejected() throws {
        try withSocket { reader, writer in
            write(Data("partial".utf8), to: writer)
            shutdown(writer, SHUT_WR)
            XCTAssertThrowsError(try Transport.receive(reader)) { error in
                XCTAssertEqual((error as? SparekeyError)?.code, "helper_not_running")
            }
        }
    }

    func testCompleteFrameFollowedByDisconnectIsAccepted() throws {
        try withSocket { reader, writer in
            write(Data("done\n".utf8), to: writer)
            shutdown(writer, SHUT_WR)
            XCTAssertEqual(try Transport.receive(reader), Data("done".utf8))
        }
    }

    func testRequestAndReplyRoundTrip() throws {
        try withSocket { reader, writer in
            try Transport.send(Request("status"), to: writer)
            let request = try JSONDecoder().decode(Request.self, from: Transport.receive(reader, limit: 256))
            XCTAssertEqual(request.command, "status")
            XCTAssertTrue(request.isSupportedByCoverHelper)
            try Transport.send(Reply(state: "unlocked", message: "unlocked"), to: reader)
            let reply = try JSONDecoder().decode(Reply.self, from: Transport.receive(writer))
            XCTAssertTrue(reply.ok)
            XCTAssertEqual(reply.state, "unlocked")
        }
    }

    func testSlowPartialFrameCannotExtendTotalDeadline() throws {
        try withSocket { reader, writer in
            let sent = expectation(description: "delayed byte sent")
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                self.write(Data("x".utf8), to: writer)
                sent.fulfill()
            }
            let start = ProcessInfo.processInfo.systemUptime
            XCTAssertThrowsError(try Transport.receive(reader)) { error in
                XCTAssertEqual((error as? SparekeyError)?.code, "helper_not_running")
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            XCTAssertLessThan(elapsed, 21, "Partial input extended the 20-second frame deadline.")
            wait(for: [sent], timeout: 1)
        }
    }

    func testIdleRequestConnectionHasShorterDeadline() throws {
        try withSocket { reader, writer in
            let disconnected = expectation(description: "stalled client disconnected")
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                shutdown(writer, SHUT_WR)
                disconnected.fulfill()
            }
            let start = ProcessInfo.processInfo.systemUptime
            XCTAssertThrowsError(try Transport.receive(reader, limit: 256, timeout: 2)) { error in
                XCTAssertEqual((error as? SparekeyError)?.code, "helper_not_running")
            }
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2.5)
            wait(for: [disconnected], timeout: 2)
        }
    }
}
