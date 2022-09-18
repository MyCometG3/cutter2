//
//  SampleBufferChannel.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/08.
//  Copyright © 2018-2022年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

protocol SampleBufferChannelDelegate: AnyObject {
    func didRead(from channel: SampleBufferChannel, buffer: CMSampleBuffer)
}

class SampleBufferChannel: NSObject {
    
    init(readerOutput: AVAssetReaderOutput, writerInput: AVAssetWriterInput, trackID: CMPersistentTrackID) {
        arOutput = readerOutput
        awInput = writerInput
        
        queue = DispatchQueue.init(label: String(format: "SBC-\(arOutput.mediaType.rawValue)"))
        
        super.init()
    }
    
    /* ============================================ */
    // MARK: - Public properties
    /* ============================================ */
    
    public private(set) var arOutput: AVAssetReaderOutput
    public private(set) var awInput: AVAssetWriterInput
    public private(set) var finished: Bool = false
    
    public var mediaType: String {
        return arOutput.mediaType.rawValue
    }
    
    /* ============================================ */
    // MARK: - Private properties
    /* ============================================ */
    
    private weak var delegate: SampleBufferChannelDelegate? = nil
    private var completionHandler: (() -> Void)? = nil
    private var queue: DispatchQueue? = nil
    
    /* ============================================ */
    // MARK: - Public functions
    /* ============================================ */
    
    public func start(with delegate: SampleBufferChannelDelegate,
                      completionHandler: @escaping ()->Void) {
        guard let queue = self.queue else { return }
        
        self.delegate = delegate
        self.completionHandler = completionHandler
        
        awInput.requestMediaDataWhenReady(on: queue) {[unowned self] in // @escaping
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
        guard let queue = self.queue else { return }
        queue.async { [unowned self] in
            self.callCompletionHandlerIfNecessary()
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
