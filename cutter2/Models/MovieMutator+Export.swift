//
//  MovieMutator+Export.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
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
                                 updateProgress: self.updateProgress,
                                 progressContinuation: self.progressContinuation)
    }
    
    public func exportMovie(to url: URL, fileType type: AVFileType, presetName preset: String?) async throws {
        let movieWriterParams = prepareMovieWriterParams()
        try await Task { @MainActor in
            let movieWriter = MovieWriter(params: movieWriterParams)
            self.currentMovieWriter = movieWriter
            defer { self.currentMovieWriter = nil }
            try await movieWriter.exportMovie(to: url, fileType: type, presetName: preset)
        }.value
    }
    
    public func exportCustomMovie(to url: URL, fileType type: AVFileType, settings param: [String:Sendable]) async throws {
        let movieWriterParams = prepareMovieWriterParams()
        try await Task { @MainActor in
            let movieWriter = MovieWriter(params: movieWriterParams)
            self.currentMovieWriter = movieWriter
            defer { self.currentMovieWriter = nil }
            try await movieWriter.exportCustomMovie(to: url, fileType: type, settings: param)
        }.value
    }
    
    public func writeMovie(to url: URL, fileType type: AVFileType, copySampleData selfContained: Bool) async throws {
        let movieWriterParams = prepareMovieWriterParams()
        try await Task { @MainActor in
            let movieWriter = MovieWriter(params: movieWriterParams)
            self.currentMovieWriter = movieWriter
            defer { self.currentMovieWriter = nil }
            try await movieWriter.writeMovie(to: url, fileType: type, copySampleData: selfContained)
        }.value
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
    /// - This method is asynchronous and should be awaited to ensure proper cancellation
    /// - The writer reference is captured to avoid race conditions
    /// - Uses structured concurrency to ensure the cancellation does not outlive the parent instance
    ///   - Actual cancellation happens asynchronously in MovieWriter
    ///   - Cancellation state is tracked via writeCancelled flag
    ///   - The ongoing operation will detect cancellation and throw appropriately
    public func cancel() async {
        guard let writer = self.currentMovieWriter else { return }
        // Capture the writer reference to avoid race condition between check and use
        await writer.cancelExport()
        await writer.cancelCustomMovie(())
    }
}
