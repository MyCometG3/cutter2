//
//  Document+ActorIsolation.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - Actor isolation
/* ============================================ */

/// A simple thread-safe container for holding mutable results captured by @Sendable closures.
///
/// This class uses `@unchecked Sendable` because:
/// - Access is synchronized via a DispatchQueue in `performAsync`
/// - The value is only written once and read once
/// - No concurrent access occurs during normal operation
/// - The DispatchQueue provides the necessary memory barrier
private final class SendableBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

extension SendableBox: @unchecked Sendable {}

extension Document {
    
    /// Executes an asynchronous, throwing operation synchronously on a detached task.
    ///
    /// This method bridges async/await operations to synchronous AppKit document APIs.
    /// It is designed to be called from `nonisolated` contexts (specifically `Document.write(...)`).
    ///
    /// **Design Rationale:**
    /// - `Task.detached` is used because:
    ///   - Must be called from a `nonisolated` context (no parent task to inherit from)
    ///   - AppKit's `canAsynchronouslyWrite` already executes `write()` on a background queue
    ///   - No task priority inheritance is needed (AppKit manages thread priority)
    /// - Semaphore waiting is used because:
    ///   - Must block until async operation completes (AppKit document save requires synchronous return)
    ///   - DispatchQueue provides thread-safe result passing
    /// - Works in conjunction with `canAsynchronouslyWrite() -> Bool { true }`
    ///
    /// - Parameter block: A closure that performs asynchronous work and may throw.
    /// - Returns: The result produced by the closure.
    /// - Throws: An error thrown by the closure.
    /// - Warning: This blocks the current thread. Do not call from the main thread.
    nonisolated func performAsync<T: Sendable>(_ block: @Sendable @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = DispatchQueue(label: "ResultLock")
        let resultBox = SendableBox<Result<T, Error>?>(nil)
        Task.detached(priority: .userInitiated) { @Sendable in
            let taskResult: Result<T, Error>
            do {
                taskResult = .success(try await block())
            } catch {
                taskResult = .failure(error)
            }
            lock.sync {
                resultBox.value = taskResult
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try lock.sync { try resultBox.value!.get() }
    }
    
    /// Executes an asynchronous, non-throwing operation synchronously on a detached task.
    ///
    /// This is the non-throwing variant of `performAsync`. See the throwing version for detailed rationale.
    ///
    /// - Parameter block: A closure that performs asynchronous work.
    /// - Returns: The result produced by the closure.
    /// - Warning: This blocks the current thread. Do not call from the main thread.
    nonisolated func performAsync<T: Sendable>(_ block: @Sendable @escaping () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = DispatchQueue(label: "ResultLock")
        let resultBox = SendableBox<T?>(nil)
        Task.detached(priority: .userInitiated) { @Sendable in
            let taskResult = await block()
            lock.sync {
                resultBox.value = taskResult
            }
            semaphore.signal()
        }
        semaphore.wait()
        return lock.sync { resultBox.value! }
    }
    
    /// Runs a throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A closure isolated to the main actor that may throw an error.
    /// - Returns: The result of the closure's operation.
    /// - Throws: Any error thrown by the closure.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () throws -> T) throws -> T {
        return try ActorUtilities.performSyncOnMainActor(block)
    }
    
    /// Runs a non-throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A non-throwing closure isolated to the main actor.
    /// - Returns: The result of the closure's operation.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () -> T) -> T {
        return ActorUtilities.performSyncOnMainActor(block)
    }
}
