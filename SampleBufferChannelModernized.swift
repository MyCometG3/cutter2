//
//  SampleBufferChannelModernized.swift
//  cutter2
//
//  Modern Swift Concurrency Implementation
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/// Modern async/await delegate protocol
protocol ModernSampleBufferChannelDelegate: AnyObject, Sendable {
    func didRead(from channel: ModernSampleBufferChannel, buffer: CMSampleBuffer) async
}

/// Modernized SampleBufferChannel using actor pattern and structured concurrency
actor ModernSampleBufferChannel {
    
    // MARK: - Public Properties
    
    public let arOutput: AVAssetReaderOutput
    public let awInput: AVAssetWriterInput  
    public let trackID: CMPersistentTrackID
    public private(set) var isFinished: Bool = false
    public private(set) var isCancelled: Bool = false
    
    public var mediaType: String {
        arOutput.mediaType.rawValue
    }
    
    // MARK: - Private Properties
    
    private weak var delegate: ModernSampleBufferChannelDelegate?
    private var processingTask: Task<Void, Error>?
    
    // MARK: - Initialization
    
    init(
        readerOutput: AVAssetReaderOutput,
        writerInput: AVAssetWriterInput,
        trackID: CMPersistentTrackID
    ) {
        self.arOutput = readerOutput
        self.awInput = writerInput
        self.trackID = trackID
    }
    
    // MARK: - Public Methods
    
    /// Start processing samples with modern async/await pattern
    /// - Parameter delegate: Delegate to receive sample buffer notifications
    /// - Returns: Async stream of processing progress
    public func start(with delegate: ModernSampleBufferChannelDelegate) -> AsyncThrowingStream<Float, Error> {
        self.delegate = delegate
        
        return AsyncThrowingStream<Float, Error> { continuation in
            processingTask = Task {
                do {
                    try await processsamples(progressContinuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Cancel processing
    public func cancel() {
        isCancelled = true
        processingTask?.cancel()
    }
    
    // MARK: - Private Methods
    
    private func processsamples(progressContinuation: AsyncThrowingStream<Float, Error>.Continuation) async throws {
        guard !isCancelled else { 
            throw CancellationError()
        }
        
        // Wait for writer input to be ready
        while !awInput.isReadyForMoreMediaData {
            if isCancelled {
                throw CancellationError()
            }
            // Use async sleep instead of blocking
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        var processedSamples = 0
        let estimatedTotalSamples = 1000 // This should be calculated based on track duration
        
        // Process samples
        while let sampleBuffer = arOutput.copyNextSampleBuffer() {
            // Check for cancellation
            if isCancelled {
                throw CancellationError()
            }
            
            // Notify delegate asynchronously
            if let delegate = delegate {
                await delegate.didRead(from: self, buffer: sampleBuffer)
            }
            
            // Write sample buffer
            while !awInput.isReadyForMoreMediaData {
                if isCancelled {
                    throw CancellationError()
                }
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            awInput.append(sampleBuffer)
            processedSamples += 1
            
            // Report progress
            let progress = Float(processedSamples) / Float(estimatedTotalSamples)
            progressContinuation.yield(min(progress, 1.0))
            
            // Yield control to prevent blocking
            await Task.yield()
        }
        
        // Mark input as finished
        awInput.markAsFinished()
        isFinished = true
    }
}

// MARK: - Sendable Conformance

extension ModernSampleBufferChannel: Sendable {
    // Actor provides automatic Sendable conformance
}

// MARK: - Error Types

extension ModernSampleBufferChannel {
    enum ProcessingError: Error, LocalizedError {
        case invalidSampleBuffer
        case writerNotReady
        case readerFailure
        
        var errorDescription: String? {
            switch self {
            case .invalidSampleBuffer:
                return "Invalid sample buffer received"
            case .writerNotReady:
                return "Writer input not ready for more data"
            case .readerFailure:
                return "Asset reader encountered an error"
            }
        }
    }
}

// MARK: - Usage Example for Integration

/*
Usage example showing how to integrate with existing MovieWriter:

```swift
// In MovieWriter actor:
private func prepareModernChannels(_ movie: AVMutableMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) async throws {
    var channels: [ModernSampleBufferChannel] = []
    
    for track in movie.tracks(withMediaType: .video) {
        let arOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        ar.add(arOutput)
        
        let awInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        aw.add(awInput)
        
        let channel = ModernSampleBufferChannel(
            readerOutput: arOutput,
            writerInput: awInput,
            trackID: track.trackID
        )
        channels.append(channel)
    }
    
    // Process all channels concurrently using TaskGroup
    try await withThrowingTaskGroup(of: Void.self) { group in
        for channel in channels {
            group.addTask {
                let progressStream = await channel.start(with: self)
                for try await progress in progressStream {
                    await self.updateProgress?(progress)
                }
            }
        }
        
        // Wait for all channels to complete
        for try await _ in group { }
    }
}
```
*/