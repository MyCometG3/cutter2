//
//  Document+Utilities.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/16.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - Misc utilities
/* ============================================ */

extension Document {
    public func inspectorDictionary() -> [String:Any] {
        
        var dict: [String:Any] = [:]
        guard let mutator = self.movieMutator else { return dict }
        
        dict[titleInspectKey] = self.displayName
        dict[pathInspectKey] = mutator.mediaDataPaths()?.joined(separator: "\n")
        dict[videoFormatInspectKey] = mutator.videoFormats()?.joined(separator: "\n")
        dict[videoFPSInspectKey] = mutator.videoFPSs()?.joined(separator: "\n")
        dict[audioFormatInspectKey] = mutator.audioFormats()?.joined(separator: "\n")
        dict[videoDataSizeInspectKey] = mutator.videoDataSizes()?.joined(separator: "\n")
        dict[audioDataSizeInspectKey] = mutator.audioDataSizes()?.joined(separator: "\n")
        dict[currentTimeInspectKey] = mutator.shortTimeString(mutator.insertionTime, withDecimals: true)
        dict[movieDurationInspectKey] = mutator.shortTimeString(mutator.movieDuration(), withDecimals: true)
        
        let range: CMTimeRange = mutator.selectedTimeRange
        dict[selectionStartInspectKey] = mutator.shortTimeString(range.start, withDecimals: true)
        dict[selectionEndInspectKey] = mutator.shortTimeString(range.end, withDecimals: true)
        dict[selectionDurationInspectKey] = mutator.shortTimeString(range.duration, withDecimals: true)
        
        return dict
    }
    
    /// used in debugInfo()
    public func modifier(_ mask: NSEvent.ModifierFlags) -> Bool {
        
        guard let current = NSApp.currentEvent?.modifierFlags else { return false }
        
        return current.contains(mask)
    }
    
    /// Cleanup for close document
    public func cleanup() {
        
        //
        self.removeMutationObserver()
        self.removeAllUndoRecords()
        self.useUpdateTimer(false)
        self.removePlayerObserver()
        
        //
        self.viewController?.cleanup()
        
        // dealloc AVPlayer
        self.player?.pause()
        self.playerView?.player = nil
        
        // dealloc mutator
        self.movieMutator = nil
    }
    
    /// Update Timeline view, seek, and refresh AVPlayerItem if required
    public func updateGUI(_ time: CMTime, _ timeRange: CMTimeRange, _ reload: Bool) {
        
        // update GUI
        self.updateTimeline(time, range: timeRange)
        if reload {
            self.updatePlayer()
        } else {
            guard let player = self.player else { return }
            self.resumeAfterSeek(to: time, with: player.rate)
        }
    }
    
    /// Seek and Play
    public func resumeAfterSeek(to time: CMTime, with rate: Float) {
        
        guard let mutator = self.movieMutator else { return }
        #if DEBUG
        LoggingSystem.video.debug("resumeAfterSeek: time=\(mutator.shortTimeString(time, withDecimals: true)) raw=\(mutator.rawTimeString(time))")
        #endif
        
        guard let player = self.player else { return }
        
        updateRate(player, 0.0)
        let handler: @Sendable (Bool) -> Void = {[weak self, weak player, weak mutator] (finished) in // @escaping
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            guard let player = player else { preconditionFailure("Unexpected nil player detected.") }
            guard let mutator = mutator else { preconditionFailure("Unexpected nil mutator detected.") }
            performSyncOnMainActor {
                updateRate(player, rate)
                updateTimeline(time, range: mutator.selectedTimeRange)
            }
        }
        player.seek(to: time, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero, completionHandler: handler)
    }
    
    /// Update marker position in Timeline view
    public func updateTimeline(_ time: CMTime, range: CMTimeRange) {
        
        guard let mutator = self.movieMutator else { return }
        
        // Update marker position
        mutator.insertionTime = time
        mutator.selectedTimeRange = range
        
        // Prepare userInfo
        var userInfo: [AnyHashable:Any] = [:]
        userInfo[timeInfoKey] = NSValue(time: time)
        userInfo[rangeInfoKey] = NSValue(timeRange: range)
        userInfo[curPositionInfoKey] = NSNumber(value: positionOfTime(time))
        userInfo[startPositionInfoKey] = NSNumber(value: positionOfTime(range.start))
        userInfo[endPositionInfoKey] = NSNumber(value: positionOfTime(range.end))
        userInfo[stringInfoKey] = mutator.shortTimeString(time, withDecimals: true)
        userInfo[durationInfoKey] = NSNumber(value: CMTimeGetSeconds(mutator.movieDuration()))
        
        // Post notification (.timelineUpdateReq)
        let notification = Notification(name: .timelineUpdateReq,
                                        object: self,
                                        userInfo: userInfo)
        let center = NotificationCenter.default
        center.post(notification)
    }
    
    /// Refresh AVPlayerItem and seek as is
    private func updatePlayer() {
        
        guard let mutator = movieMutator, let pv = playerView else { return }
        
        if let player = pv.player {
            // Apply modified source movie
            let playerItem = mutator.makePlayerItem()
            player.replaceCurrentItem(with: playerItem)
            
            // seek
            let handler: @Sendable (Bool) -> Void = {[weak self, weak pv] (finished) in // @escaping
                
                guard let self else { preconditionFailure("Unexpected nil self detected.") }
                guard let pv = pv else { preconditionFailure("Unexpected nil pv detected.") }
                performSyncOnMainActor {
                    pv.needsDisplay = true
                }
            }
            playerItem.seek(to: mutator.insertionTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero,
                            completionHandler: handler)
        } else {
            // Initial setup
            let playerItem = mutator.makePlayerItem()
            let player: AVPlayer = AVPlayer(playerItem: playerItem)
            pv.player = player
            
            // AddObserver to AVPlayer
            self.addPlayerObserver()
            
            // Start polling timer
            self.useUpdateTimer(true)
        }
    }
    
    /// Setup polling timer - queryPosition()
    private func useUpdateTimer(_ enable: Bool) {
        
        if enable {
            if self.timer == nil {
                self.timer = Timer.scheduledTimer(timeInterval: self.pollingInterval,
                                                  target: self,
                                                  selector: #selector(queryPosition),
                                                  userInfo: nil,
                                                  repeats: true)
            }
        } else {
            if let timer = self.timer {
                timer.invalidate()
                self.timer = nil
            }
        }
    }
    
    /// Poll AVPlayer/AVPlayerItem status and refresh Timeline
    @objc func queryPosition() {
        
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        guard let playerItem = self.playerItem else { return }
        
        let notReady: Bool = (player.status != .readyToPlay)
        let empty: Bool = playerItem.isPlaybackBufferEmpty
        if notReady || empty { return }
        
        let current = player.currentTime()
        if mutator.insertionTime != current {
            let range = mutator.selectedTimeRange
            
            if checkTailOfMovie() {
                // ignore
            } else {
                updateTimeline(current, range: range)
            }
        }
    }
    
    /// Update AVPlayer.rate if required
    /// - Parameters:
    ///   - player: AVPlayer to be updated
    ///   - newRate: new requested rate
    func updateRate(_ player: AVPlayer, _ newRate: Float) {
        guard player.rate != newRate else { return }
        player.rate = newRate
    }
}
