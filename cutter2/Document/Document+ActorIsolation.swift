//
//  Document+ActorIsolation.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - Actor isolation
/* ============================================ */

extension Document {
    
    /// Executes an asynchronous, throwing operation synchronously on a detached task.
    ///
    /// This method bridges async/await operations to synchronous AppKit document APIs.
    /// It is designed to be called from `nonisolated` contexts (specifically `Document.write(...)`).
    ///
    /// Implementation is delegated to `AsyncBridge.perform` (adopted from
    /// `performAsync_comparison.md` §10.2). AppKit's `canAsynchronouslyWrite` executes
    /// `write()` on a background queue, so the default `allowMainThread: false`
    /// precondition is satisfied.
    ///
    /// - Parameter block: A closure that performs asynchronous work and may throw.
    /// - Returns: The result produced by the closure.
    /// - Throws: An error thrown by the closure.
    /// - Warning: This blocks the current thread. Do not call from the main thread.
    nonisolated func performAsync<T: Sendable>(_ block: @Sendable @escaping () async throws -> T) throws -> T {
        return try AsyncBridge.perform(block)
    }
    
    /// Executes an asynchronous, non-throwing operation synchronously on a detached task.
    ///
    /// A `() async -> T` block satisfies `() async throws -> T`, so the throwing
    /// variant of `AsyncBridge.perform` is reused. See the throwing version for design rationale.
    ///
    /// - Parameter block: A closure that performs asynchronous work.
    /// - Returns: The result produced by the closure.
    /// - Warning: This blocks the current thread. Do not call from the main thread.
    nonisolated func performAsync<T: Sendable>(_ block: @Sendable @escaping () async -> T) -> T {
        do {
            return try AsyncBridge.perform(block)
        } catch {
            fatalError("Non-throwing performAsync unexpectedly threw: \(error)")
        }
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
