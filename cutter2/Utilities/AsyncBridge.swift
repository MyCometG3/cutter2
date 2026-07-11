//
//  AsyncBridge.swift
//  cutter2
//
//  Unified async-to-sync bridge adopted from performAsync_comparison.md §10.2.
//

/* This software is released under the MIT License, see LICENSE.txt. */

import Foundation
import os.lock

enum PerformAsyncError: Error {
    case timeout(TimeInterval)
    case operationFailed(String)
}

private final class UnfairLockBox: @unchecked Sendable {
    private var rawLock = os_unfair_lock_s()
    
    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(&rawLock)
        defer { os_unfair_lock_unlock(&rawLock) }
        return try body()
    }
}

private final class AsyncResultBox<T>: @unchecked Sendable {
    private let lock = UnfairLockBox()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: T?
    
    func store(_ value: T) {
        lock.withLock { self.value = value }
        semaphore.signal()
    }
    
    func waitAndGet(timeout: TimeInterval?) throws -> T {
        let waitResult: DispatchTimeoutResult
        if let timeout = timeout {
            waitResult = semaphore.wait(timeout: .now() + timeout)
            guard case .success = waitResult else {
                throw PerformAsyncError.timeout(timeout)
            }
        } else {
            semaphore.wait()
        }
        
        return try lock.withLock {
            guard let value = value else {
                throw PerformAsyncError.operationFailed(
                    "Async operation failed to complete"
                )
            }
            return value
        }
    }
}

internal final class ThrowingAsyncResultBox<T>: @unchecked Sendable {
    private let lock = UnfairLockBox()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<T, Error>?
    
    func store(_ result: Result<T, Error>) {
        lock.withLock { self.result = result }
        semaphore.signal()
    }
    
    func waitAndGet(timeout: TimeInterval?) throws -> T {
        let waitResult: DispatchTimeoutResult
        if let timeout = timeout {
            waitResult = semaphore.wait(timeout: .now() + timeout)
            guard case .success = waitResult else {
                throw PerformAsyncError.timeout(timeout)
            }
        } else {
            semaphore.wait()
        }
        
        return try lock.withLock {
            guard let result = result else {
                throw PerformAsyncError.operationFailed(
                    "Async operation failed to complete"
                )
            }
            return try result.get()
        }
    }
}

enum AsyncBridge {
    
    static func perform<T: Sendable>(
        timeout: TimeInterval? = nil,
        allowMainThread: Bool = false,
        _ block: @Sendable @escaping () async throws -> T
    ) throws -> T {
        precondition(
            allowMainThread || !Thread.isMainThread,
            "AsyncBridge.perform must not be called from the main thread. Use allowMainThread: true if you understand the deadlock risk."
        )
        
        let box = ThrowingAsyncResultBox<T>()
        let task = Task.detached(priority: .userInitiated) { [box, block] in
            do {
                let value = try await block()
                box.store(.success(value))
            } catch {
                box.store(.failure(error))
            }
        }
        do {
            return try box.waitAndGet(timeout: timeout)
        } catch {
            task.cancel()
            throw error
        }
    }
}
