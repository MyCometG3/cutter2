//
//  ActorIsolationUtils.swift
//  cutter2
//
//  Created by Copilot Code Review on 2025/08/06.
//  Copyright © 2025 MyCometG3. All rights reserved.
//

import Foundation

/// Utility class providing common actor isolation patterns used throughout the application.
/// This centralized implementation reduces code duplication and ensures consistency.
public final class ActorIsolationUtils {
    
    /// Executes an asynchronous, throwing operation synchronously on a detached task.
    /// - Parameter block: A closure that performs asynchronous work and may throw.
    /// - Returns: The result produced by the closure.
    /// - Throws: An error thrown by the closure.
    /// - Warning: This blocks the current thread. Do not call from the main thread.
    public static func performAsync<T: Sendable>(_ block: @Sendable @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = DispatchQueue(label: "com.mycometg3.cutter2.ActorIsolationUtils.ResultLock")
        var result: Result<T, Error>?
        
        Task.detached(priority: .userInitiated) {
            let taskResult: Result<T, Error>
            do {
                taskResult = .success(try await block())
            } catch {
                taskResult = .failure(error)
            }
            lock.sync {
                result = taskResult
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return try lock.sync { try result!.get() }
    }
    
    /// Executes an asynchronous, non-throwing operation synchronously on a detached task.
    /// - Parameter block: A closure that performs asynchronous work.
    /// - Returns: The result produced by the closure.
    /// - Warning: This blocks the current thread. Do not call from the main thread.
    public static func performAsync<T: Sendable>(_ block: @Sendable @escaping () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = DispatchQueue(label: "com.mycometg3.cutter2.ActorIsolationUtils.ResultLock")
        var result: T?
        
        Task.detached(priority: .userInitiated) {
            let taskResult = await block()
            lock.sync {
                result = taskResult
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return lock.sync { result! }
    }
    
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