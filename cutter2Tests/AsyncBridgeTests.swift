import XCTest
import Foundation
@testable import cutter2

final class AsyncBridgeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private enum TestError: Error { case expected }

    func testPerformCompletesWithValue() async {
        let task = Task.detached {
            try AsyncBridge.perform(timeout: 1.0, allowMainThread: false) { @Sendable in
                42
            }
        }
        do {
            let result = try await task.value
            XCTAssertEqual(result, 42)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPerformPropagatesThrow() async {
        var caught = false
        let task = Task.detached {
            try AsyncBridge.perform(timeout: 1.0, allowMainThread: false) { @Sendable in
                throw TestError.expected
            }
        }
        do {
            _ = try await task.value
        } catch TestError.expected {
            caught = true
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(caught)
    }

    func testPerformTimeout() async {
        var caughtTimeout = false
        let task = Task.detached {
            try AsyncBridge.perform(timeout: 0.01, allowMainThread: false) { @Sendable in
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return 0
            }
        }
        do {
            _ = try await task.value
        } catch PerformAsyncError.timeout(_) {
            caughtTimeout = true
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(caughtTimeout)
    }

    @MainActor
    func testPerformAllowMainThread() {
        XCTAssertTrue(Thread.isMainThread, "testPerformAllowMainThread must run on main thread")
        do {
            let value = try AsyncBridge.perform(timeout: nil, allowMainThread: true) { @Sendable in
                "ok"
            }
            XCTAssertEqual(value, "ok")
        } catch {
            XCTFail("unexpected throw: \(error)")
        }
    }
}
