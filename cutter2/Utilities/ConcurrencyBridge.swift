//
//  ConcurrencyBridge.swift
//  cutter2
//
//  Async-to-sync bridge and MainActor-isolated sync call utilities.
//  Merged from AsyncBridge.swift and ActorUtilities.swift.
//
//  Created by Takashi Mochizuki on 2026/06/13.
//  Copyright © 2026 MyCometG3. All rights reserved.
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

private final class ThrowingAsyncResultBox<T: Sendable>: @unchecked Sendable {
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

/* ============================================ */
// MARK: - Actor isolation utilities
/* ============================================ */

/// Shared actor isolation utilities for running MainActor-isolated closures synchronously
public struct ActorUtilities {

    /// Runs a throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A closure isolated to the main actor that may throw an error.
    /// - Returns: The result of the closure's operation.
    /// - Throws: Any error thrown by the closure.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    public static func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try block()
            }
        } else {
            return try DispatchQueue.main.sync {
                return try MainActor.assumeIsolated {
                    try block()
                }
            }
        }
    }

    /// Runs a non-throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A non-throwing closure isolated to the main actor.
    /// - Returns: The result of the closure's operation.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    public static func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                block()
            }
        } else {
            return DispatchQueue.main.sync {
                return MainActor.assumeIsolated {
                    block()
                }
            }
        }
    }
}
