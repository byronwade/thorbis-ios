import Foundation
import XCTest
@testable import Thorbis

final class TerminalOneShotTests: XCTestCase {
    func testConcurrentCallbacksClaimContinuationOnlyOnce() {
        let oneShot = TerminalOneShot(42)
        let lock = NSLock()
        nonisolated(unsafe) var count = 0
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            if oneShot.take() != nil {
                lock.lock()
                count += 1
                lock.unlock()
            }
        }
        XCTAssertEqual(count, 1)
    }
}
