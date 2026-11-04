import Foundation
import XCTest
@testable import Thorbis
#if os(macOS)
import Darwin
#endif

final class BoundTapProcessLeaseTests: XCTestCase {
    func testSecondLeaseIsExcludedUntilFirstCloses() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path
        let first = try BoundTapProcessLease.acquire(path: path)
        XCTAssertThrowsError(try BoundTapProcessLease.acquire(path: path))
        first.close()
        let second = try BoundTapProcessLease.acquire(path: path)
        second.close()
    }

    func testSymlinkCannotRedirectLease() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("lock").path
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: dir.path)
        XCTAssertThrowsError(try BoundTapProcessLease.acquire(path: path))
    }

    #if os(macOS)
    func testAnotherProcessAndCrashRelease() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", "import os,fcntl,sys,time; f=os.open(sys.argv[1],os.O_RDONLY); fcntl.flock(f,fcntl.LOCK_EX); os.write(1,b'R'); time.sleep(60)", path]
        process.standardOutput = pipe
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        var watched = pollfd(fd: pipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&watched, 1, 5_000) > 0 else {
            XCTFail("Child did not acquire the directory lease")
            return
        }
        XCTAssertEqual(try pipe.fileHandleForReading.read(upToCount: 1), Data("R".utf8))
        XCTAssertThrowsError(try BoundTapProcessLease.acquire(path: path))
        XCTAssertEqual(Darwin.kill(process.processIdentifier, SIGKILL), 0)
        process.waitUntilExit()
        let recovered = try BoundTapProcessLease.acquire(path: path)
        recovered.close()
    }
    #endif
}
