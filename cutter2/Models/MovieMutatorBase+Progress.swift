//
//  MovieMutatorBase+Progress.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/04.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation
import AVFoundation

@MainActor
extension MovieMutatorBase {
    /// Creates an async stream for progress updates
    ///
    /// This stream emits progress values (0.0 to 1.0) during long-running operations
    /// like export or write. The stream completes when the operation finishes.
    ///
    /// - Returns: An AsyncStream that yields Float progress values
    ///
    /// ## Important: Timing Requirement
    /// The stream **MUST** be created **BEFORE** starting the export/write operation.
    /// This ensures the progress continuation is set synchronously before the operation
    /// begins yielding progress values.
    ///
    /// ## Usage Example
    /// ```swift
    /// // Create stream BEFORE starting the operation
    /// let stream = mutator.progressStream()
    ///
    /// // Then start consuming progress updates
    /// let progressTask = Task { @MainActor in
    ///     for await progress in stream {
    ///         updateProgressUI(progress)
    ///     }
    /// }
    /// defer { progressTask.cancel() }
    ///
    /// // Now start the operation (continuation is already set)
    /// try await mutator.exportMovie(to: url, fileType: .mov, presetName: nil)
    /// ```
    ///
    /// ## Incorrect Usage (will lose progress updates)
    /// ```swift
    /// // ❌ DON'T: Creating stream inside Task delays initialization
    /// let task = Task {
    ///     for await progress in mutator.progressStream() {  // Too late!
    ///         updateProgressUI(progress)
    ///     }
    /// }
    /// try await mutator.exportMovie(...)  // Starts before continuation is set
    /// ```
    public func progressStream() -> AsyncStream<Float> {
        AsyncStream { [weak self] continuation in
            // Assign continuation on MainActor using ActorUtilities to ensure
            // proper isolation tracking and avoid strict concurrency warnings.
            ActorUtilities.performSyncOnMainActor {
                self?.progressContinuation = continuation
            }
            
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.progressContinuation = nil
                }
            }
        }
    }
}
