//
//  SampleBufferChannel.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/08.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

protocol SampleBufferChannelDelegate: AnyObject {
    func didRead(from channel: SampleBufferChannel, buffer: CMSampleBuffer)
}

/// `@unchecked Sendable` rationale:
/// Thread safety is achieved by confining all mutation of `finished` and
/// `completionHandler` to the serial `queue`. `start()` sets `delegate` and
/// `completionHandler` before the `requestMediaDataWhenReady` callback fires on
/// `queue`, so there is no race between `start()` and the callback. `cancel()`
/// also dispatches to `queue` before touching `finished`. `delegate` is held
/// as a `weak` reference. `@unchecked` is intentional; the serial queue
/// guarantees sequential access.
class SampleBufferChannel: @unchecked Sendable {
    
    init(readerOutput: AVAssetReaderOutput, writerInput: AVAssetWriterInput, trackID: CMPersistentTrackID) {
        self.arOutput = readerOutput
        self.awInput = writerInput
        self.trackID = trackID
        self.queue = DispatchQueue.init(label: String(format: "SBC-\(arOutput.mediaType.rawValue)"))
    }
    
    /* ============================================ */
    // MARK: - Public properties
    /* ============================================ */
    
    /// The reader output supplying sample buffers.
    public let arOutput: AVAssetReaderOutput
    /// The writer input receiving sample buffers.
    public let awInput: AVAssetWriterInput
    /// The media track ID associated with this channel.
    public let trackID: CMPersistentTrackID
    /// Whether the channel has finished and its writer input has been marked finished.
    public private(set) var finished: Bool = false
    
    /// The media type of the reader output.
    public var mediaType: String {
        return arOutput.mediaType.rawValue
    }
    
    /* ============================================ */
    // MARK: - Private properties
    /* ============================================ */
    
    private weak var delegate: SampleBufferChannelDelegate? = nil
    private var completionHandler: (() -> Void)? = nil
    private let queue: DispatchQueue
    
    /* ============================================ */
    // MARK: - Public functions
    /* ============================================ */
    
    /// Starts reading sample buffers and forwarding them to the delegate on the channel queue.
    ///
    /// The completion handler is called when input is exhausted, appending fails, the
    /// delegate is unavailable, or the channel is cancelled.
    ///
    /// - Parameters:
    ///   - delegate: The object that receives each sample buffer.
    ///   - completionHandler: The closure called once when the channel finishes.
    public func start(with delegate: SampleBufferChannelDelegate,
                      completionHandler: @escaping ()->Void) {
        self.delegate = delegate
        self.completionHandler = completionHandler
        
        awInput.requestMediaDataWhenReady(on: queue) {[weak self] in // @escaping
            guard let self else { return }
            if self.finished { return }
            
            guard let delegate: SampleBufferChannelDelegate = self.delegate else {
                // Delegate (typically MovieWriter actor) was deallocated mid-export.
                // Terminate the channel by invoking the completion handler so the
                // caller's withCheckedContinuation resumes and the task group does
                // not deadlock. Matches the H-02(b) teardown-safety pattern
                // applied to [weak delegate] references.
                self.callCompletionHandlerIfNecessary()
                return
            }
            let arOutput: AVAssetReaderOutput = self.arOutput
            let awInput: AVAssetWriterInput = self.awInput
            
            var needsCompletion: Bool = false
            while awInput.isReadyForMoreMediaData && needsCompletion == false {
                let sb: CMSampleBuffer? = arOutput.copyNextSampleBuffer()
                if let sb = sb {
                    delegate.didRead(from: self, buffer: sb)
                    
                    let success: Bool = awInput.append(sb)
                    needsCompletion = !success
                } else {
                    needsCompletion = true
                }
            }
            
            if needsCompletion {
                self.callCompletionHandlerIfNecessary()
            }
        }
    }
    
    /// Cancels the channel on its serial queue and completes its writer input.
    public func cancel() {
        queue.async { [weak self] in
            do {
                guard let self else { return }
                self.callCompletionHandlerIfNecessary()
            }
        }
    }
    
    private func callCompletionHandlerIfNecessary() {
        if self.finished == false {
            self.finished = true
            
            self.awInput.markAsFinished()
            
            if let handler = self.completionHandler {
                handler()
                self.completionHandler = nil
            }
        }
    }
}
