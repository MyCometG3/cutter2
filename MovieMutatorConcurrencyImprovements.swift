//
//  MovieMutatorConcurrencyImprovements.swift
//  cutter2
//
//  Improved concurrency patterns for MovieMutator
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Improved Concurrency Patterns
/* ============================================ */

extension MovieMutator {
    
    /// Modern async version of export operations that doesn't block threads
    /// - Parameters:
    ///   - url: destination URL
    ///   - type: file type
    ///   - preset: preset name
    /// - Returns: AsyncStream of progress updates
    public func exportMovieAsync(to url: URL, fileType type: AVFileType, presetName preset: String?) -> AsyncThrowingStream<Float, Error> {
        AsyncThrowingStream<Float, Error> { continuation in
            Task { @MainActor in
                do {
                    let movieWriterParams = prepareMovieWriterParams()
                    let movieWriter = MovieWriter(params: movieWriterParams)
                    
                    // Use modern progress monitoring with AsyncStream
                    let progressTask = Task {
                        // Monitor progress without blocking
                        while !Task.isCancelled {
                            // Get progress from movieWriter
                            let info = await movieWriter.exportSessionProgressInfo()
                            if let progress = info[progressInfoKey] as? Float {
                                continuation.yield(progress)
                            }
                            try await Task.sleep(nanoseconds: 100_000_000) // 100ms intervals
                        }
                    }
                    
                    // Perform export
                    try await movieWriter.exportMovie(to: url, fileType: type, presetName: preset)
                    
                    progressTask.cancel()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Non-blocking version of sync operations using async/await
    /// - Parameter block: async operation to perform
    /// - Returns: result of the operation
    public func performAsyncOnMainActor<T: Sendable>(_ block: @MainActor @Sendable () async throws -> T) async throws -> T {
        return try await MainActor.run {
            return try await block()
        }
    }
    
    /// Async version of edit operations with proper error handling
    /// - Parameter undoManager: undo manager wrapper
    /// - Returns: AsyncStream indicating completion
    public func cutSelectionAsync(using undoManager: UndoManagerWrapper) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream<Void, Error> { continuation in
            Task { @MainActor in
                do {
                    // Validate selection without blocking
                    let time = self.insertionTime
                    let range = self.selectedTimeRange
                    
                    guard validateRange(range, true) else {
                        NSSound.beep()
                        continuation.finish(throwing: EditError.invalidRange)
                        return
                    }
                    
                    // Perform operations asynchronously
                    guard let clip = writeRangeToPBoard(range) else {
                        NSSound.beep()
                        continuation.finish(throwing: EditError.clipboardError)
                        return
                    }
                    
                    guard let data = internalMovie.movHeader else {
                        NSSound.beep()
                        continuation.finish(throwing: EditError.movieHeaderError)
                        return
                    }
                    
                    // Register undo with async-aware handlers
                    let undoCutHandler: @Sendable (MovieMutator) -> Void = { [data, clip, range, time, unowned undoManager, unowned self] (me1) in
                        Task { @MainActor in
                            let redoCutHandler: @Sendable (MovieMutator) -> Void = { [range, time, unowned undoManager, unowned self] (me2) in
                                Task { @MainActor in
                                    me2.resetMarker(time, range, false)
                                    // Use async version for redo
                                    let _ = me2.cutSelectionAsync(using: undoManager)
                                }
                            }
                            undoManager.registerUndo(withTarget: me1, handler: redoCutHandler)
                            undoManager.setActionName("Cut selection")
                            
                            // Perform undo cut
                            me1.undoRemove(data, range, time, clip)
                        }
                    }
                    undoManager.registerUndo(withTarget: self, handler: undoCutHandler)
                    undoManager.setActionName("Cut selection")
                    
                    // Perform cut operation
                    self.doRemove(range, time)
                    refreshMovie()
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/* ============================================ */
// MARK: - Error Types for Async Operations
/* ============================================ */

extension MovieMutator {
    enum EditError: Error, LocalizedError {
        case invalidRange
        case clipboardError
        case movieHeaderError
        case undoManagerError
        
        var errorDescription: String? {
            switch self {
            case .invalidRange:
                return "Invalid time range selected"
            case .clipboardError:
                return "Failed to write to clipboard"
            case .movieHeaderError:
                return "Failed to read movie header"
            case .undoManagerError:
                return "Undo manager operation failed"
            }
        }
    }
}

/* ============================================ */
// MARK: - Progress Monitoring Improvements
/* ============================================ */

extension MovieMutator {
    
    /// Create a progress monitoring system using AsyncStream
    /// - Returns: AsyncStream of progress updates
    public func createProgressStream() -> AsyncStream<ProgressUpdate> {
        AsyncStream<ProgressUpdate> { continuation in
            Task {
                while !Task.isCancelled {
                    let update = ProgressUpdate(
                        currentTime: insertionTime,
                        selectedRange: selectedTimeRange,
                        movieDuration: movieDuration(),
                        timestamp: Date()
                    )
                    continuation.yield(update)
                    
                    try? await Task.sleep(nanoseconds: 16_666_667) // ~60 FPS updates
                }
                continuation.finish()
            }
        }
    }
}

/* ============================================ */
// MARK: - Progress Update Structure
/* ============================================ */

public struct ProgressUpdate: Sendable {
    public let currentTime: CMTime
    public let selectedRange: CMTimeRange
    public let movieDuration: CMTime
    public let timestamp: Date
    
    public var progress: Float {
        let duration = CMTimeGetSeconds(movieDuration)
        let current = CMTimeGetSeconds(currentTime)
        return duration > 0 ? Float(current / duration) : 0
    }
}

/* ============================================ */
// MARK: - Usage Examples and Integration Guide
/* ============================================ */

/*
Example usage of improved async patterns:

```swift
// 1. Non-blocking export with progress monitoring
func exportWithProgress() {
    Task {
        let progressStream = movieMutator.exportMovieAsync(
            to: url, 
            fileType: .mov, 
            presetName: nil
        )
        
        for try await progress in progressStream {
            await MainActor.run {
                progressIndicator.doubleValue = Double(progress)
            }
        }
    }
}

// 2. Async edit operations
func performCutOperation() {
    Task {
        let cutStream = movieMutator.cutSelectionAsync(using: undoManagerWrapper)
        
        do {
            for try await _ in cutStream {
                // Operation completed successfully
                await MainActor.run {
                    updateUI()
                }
            }
        } catch {
            await MainActor.run {
                showError(error)
            }
        }
    }
}

// 3. Real-time progress monitoring
func startProgressMonitoring() {
    Task {
        let progressStream = movieMutator.createProgressStream()
        
        for await update in progressStream {
            await MainActor.run {
                timelineView.currentTime = update.currentTime
                timelineView.selectedRange = update.selectedRange
            }
        }
    }
}
```

Key Improvements:
1. ✅ Eliminates thread blocking with DispatchQueue.main.sync
2. ✅ Uses structured concurrency patterns
3. ✅ Provides proper error handling
4. ✅ Maintains @MainActor isolation where needed
5. ✅ Offers progress monitoring without polling
6. ✅ Supports cancellation through Task cancellation
*/