//
//  SampleBufferChannel.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/08.
//  Copyright © 2018-2023年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

protocol SampleBufferChannelDelegate: AnyObject {
    func didRead(from channel: SampleBufferChannel, buffer: CMSampleBuffer)
}

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
    
    public let arOutput: AVAssetReaderOutput
    public let awInput: AVAssetWriterInput
    public let trackID: CMPersistentTrackID
    public private(set) var finished: Bool = false
    
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
    
    public func start(with delegate: SampleBufferChannelDelegate,
                      completionHandler: @escaping ()->Void) {
        self.delegate = delegate
        self.completionHandler = completionHandler
        
        awInput.requestMediaDataWhenReady(on: queue) {[weak self] in // @escaping
            guard let self else { fatalError("Unexpected nil self detected.") }
            if self.finished { return }
            
            let delegate: SampleBufferChannelDelegate = self.delegate!
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
    
    public func cancel() {
        queue.async { [weak self] in
            do {
                guard let self else { fatalError("Unexpected nil self detected.") }
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
