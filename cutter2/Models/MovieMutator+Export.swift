//
//  MovieMutator+Export.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - export/write support
/* ============================================ */

extension MovieMutator {
    internal func prepareMovieWriterParams() -> MovieWriterParams {
        return MovieWriterParams(movie: self.internalMovie,
                                 unblockUserInteraction: self.unblockUserInteraction,
                                 progressContinuation: self.progressContinuation)
    }
    
    /// Run a MovieWriter operation with consistent lifetime management.
    ///
    /// This helper centralizes the creation of `MovieWriter`, assignment to
    /// `currentMovieWriter`, and cleanup in a single place. It eliminates the
    /// copy-pasted `Task { @MainActor in ... defer { ... } }` pattern from
    /// `exportMovie`, `exportCustomMovie`, and `writeMovie`.
    ///
    /// `withMovieWriter` itself runs on the main actor because `MovieMutator` is
    /// `@MainActor`, so the writer is created and the `currentMovieWriter` property
    /// is mutated directly without an additional unstructured `Task` hop.
    ///
    /// - Parameter operation: An async closure that receives the prepared
    ///   `MovieWriter` and performs the actual export/write work.
    /// - Returns: The value produced by `operation`.
    /// - Throws: Any error thrown by `operation`.
    private func withMovieWriter<T: Sendable>(
        _ operation: (MovieWriter) async throws -> T
    ) async throws -> T {
        let movieWriterParams = prepareMovieWriterParams()
        let movieWriter = MovieWriter(params: movieWriterParams)
        self.currentMovieWriter = movieWriter
        defer { self.currentMovieWriter = nil }
        return try await operation(movieWriter)
    }
    
    public func exportMovie(to url: URL, fileType type: AVFileType, presetName preset: String?) async throws {
        try await withMovieWriter { movieWriter in
            try await movieWriter.exportMovie(to: url, fileType: type, presetName: preset)
        }
    }
    
    public func exportCustomMovie(to url: URL, fileType type: AVFileType, settings param: [String: any Sendable]) async throws {
        try await withMovieWriter { movieWriter in
            try await movieWriter.exportCustomMovie(to: url, fileType: type, settings: param)
        }
    }
    
    public func writeMovie(to url: URL, fileType type: AVFileType, copySampleData selfContained: Bool) async throws {
        try await withMovieWriter { movieWriter in
            try await movieWriter.writeMovie(to: url, fileType: type, copySampleData: selfContained)
        }
    }
    
    /// Cancel ongoing export or write operation
    ///
    /// This method cancels any ongoing export or write operation by calling the appropriate
    /// cancel method on the current MovieWriter instance.
    ///
    /// The method is safe to call at any time:
    /// - If no operation is in progress, it has no effect
    /// - If an operation is in progress, it attempts to cancel it gracefully
    /// - For custom exports, both cancelExport() and cancelCustomMovie() are called
    ///
    /// **Design Notes:**
    /// - This method is async due to the actor hop to MovieWriter
    /// - The writer reference is captured to avoid race conditions
    /// - On the MovieWriter actor, cancellation is synchronous: it sets the writeCancelled
    ///   flag and cancels the export session
    /// - The ongoing export/write operation checks writeCancelled flag and throws OperationCancelled
    public func cancel() async {
        guard let writer = self.currentMovieWriter else { return }
        // Capture the writer reference to avoid race condition between check and use
        await writer.cancelExport()
        await writer.cancelCustomMovie()
    }
}
