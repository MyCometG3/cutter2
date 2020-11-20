//
//  Document+Utilities.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/16.
//  Copyright © 2018-2020年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Sheet control
/* ============================================ */

extension Document {
    
    /// Update progress
    public func updateProgress(_ progress: Float) {
        // Swift.print(#function, #line, #file)
        
        // Thread safety
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        
        // Use Low frequency update
        let unit = NSEC_PER_MSEC * 100 // 100ms
        let t: UInt64 = CVGetCurrentHostTime()
        if lastUpdateAt == 0 {
            lastUpdateAt = t
        } else {
            if (t - lastUpdateAt) > unit {
                lastUpdateAt = lastUpdateAt + unit
            } else {
                return
            }
        }
        
        // Update UI in main queue
        DispatchQueue.main.async { [progress, unowned self] in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard let alert = self.alert else { return }
            guard progress.isNormal else { return }
            
            alert.informativeText = String("Please hold on minute(s)...: \(Int(progress * 100)) %")
        }
    }
    
    /// Show busy modalSheet
    public func showBusySheet(_ message: String?, _ info: String?) {
        // Swift.print(#function, #line, #file)
        
        DispatchQueue.main.async { [message, info, unowned self] in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard let window = self.window else { return }
            
            let alert: NSAlert = NSAlert()
            alert.messageText = message ?? "Processing...(message)"
            alert.informativeText = info ?? "Hold on seconds...(informative)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "") // No button on sheet
            let handler: (NSApplication.ModalResponse) -> Void = {(response) in // @escaping
                //if response == .stop {/* hideBusySheet() called */}
            }
            alert.beginSheetModal(for: window, completionHandler: handler)
            
            // Keep NSAlert object for later update
            self.alert = alert
        }
    }
    
    /// Hide busy modalSheet
    public func hideBusySheet() {
        // Swift.print(#function, #line, #file)
        
        DispatchQueue.main.async { [unowned self] in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard let window = self.window else { return }
            guard let alert = self.alert else { return }
            
            window.endSheet(alert.window)
            
            // Release NSAlert object
            self.alert = nil
        }
    }
    
    /// Present ErrorSheet asynchronously
    public func showErrorSheet(_ error: Error) {
        // Swift.print(#function, #line, #file)
        
        // Don't use NSDocument default error handling
        DispatchQueue.main.async { [error, unowned self] in // @escaping
            // Swift.print(#function, #line, #file)
            
            let alert = NSAlert(error: error)
            let err :NSError = error as NSError
            var text :String? = nil
            let userInfo: [String:Any] = err.userInfo // Can be empty dictionary
            if userInfo.count > 0 {
                let keys = userInfo.keys
                if keys.contains(NSUnderlyingErrorKey) || keys.contains(NSDebugDescriptionErrorKey) {
                    text = err.description
                } else if keys.contains(NSLocalizedFailureErrorKey) {
                    text = userInfo[NSLocalizedFailureErrorKey] as? String
                } else if keys.contains(NSLocalizedDescriptionKey) {
                    text = userInfo[NSLocalizedDescriptionKey] as? String
                } else if keys.contains(NSLocalizedFailureReasonErrorKey) {
                    text = userInfo[NSLocalizedFailureReasonErrorKey] as? String
                }
            }
            if let text = text {
                alert.informativeText = text
            }
            alert.beginSheetModal(for: self.window!, completionHandler: nil)
        }
    }
}

/* ============================================ */
// MARK: - Misc utilities
/* ============================================ */

extension Document {
    public func inspecterDictionary() -> [String:Any] {
        // Swift.print(#function, #line, #file)
        
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
        // Swift.print(#function, #line, #file)
        
        guard let current = NSApp.currentEvent?.modifierFlags else { return false }
        
        return current.contains(mask)
    }
    
    /// Cleanup for close document
    public func cleanup() {
        // Swift.print(#function, #line, #file)
        
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
        // Swift.print(#function, #line, #file)
        
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
        // Swift.print(#function, #line, #file)
        
        #if false
        guard let mutator = self.movieMutator else { return }
        Swift.print("#####", "resumeAfterSeek",
                    mutator.shortTimeString(time, withDecimals: true),
                    mutator.rawTimeString(time))
        #endif
        
        guard let player = self.player else { return }
        
        player.pause()
        let handler: (Bool) -> Void = {[player, unowned self] (finished) in // @escaping
            guard let mutator = self.movieMutator else { return }
            player.rate = rate
            self.updateTimeline(time, range: mutator.selectedTimeRange)
        }
        player.seek(to: time, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero, completionHandler: handler)
    }
    
    /// Update marker position in Timeline view
    public func updateTimeline(_ time: CMTime, range: CMTimeRange) {
        // Swift.print(#function, #line, #file)
        
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
        // Swift.print(#function, #line, #file)
        
        guard let mutator = movieMutator, let pv = playerView else { return }
        
        if let player = pv.player {
            // Apply modified source movie
            let playerItem = mutator.makePlayerItem()
            player.replaceCurrentItem(with: playerItem)
            
            // seek
            let handler: (Bool) -> Void = {[pv] (finished) in // @escaping
                pv.needsDisplay = true
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
        // Swift.print(#function, #line, #file)
        
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
        // Swift.print(#function, #line, #file)
        
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
    
}

/* ============================================ */
// MARK: - Observer
/* ============================================ */

extension Document {
    
    /// Add AVPlayer properties observer
    private func addPlayerObserver() {
        // Swift.print(#function, #line, #file)
        
        guard let player = self.player else { return }
        
        player.addObserver(self,
                           forKeyPath: #keyPath(AVPlayer.status),
                           options: [.old, .new],
                           context: &(self.kvoContext))
        player.addObserver(self,
                           forKeyPath: #keyPath(AVPlayer.rate),
                           options: [.old, .new],
                           context: &(self.kvoContext))
    }
    
    /// Remove AVPlayer properties observer
    private func removePlayerObserver() {
        // Swift.print(#function, #line, #file)
        
        guard let player = self.player else { return }
        
        player.removeObserver(self,
                              forKeyPath: #keyPath(AVPlayer.status),
                              context: &(self.kvoContext))
        player.removeObserver(self,
                              forKeyPath: #keyPath(AVPlayer.rate),
                              context: &(self.kvoContext))
    }
    
    // NSKeyValueObserving protocol - observeValue(forKeyPath:of:change:context:)
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey:Any]?,
                               context: UnsafeMutableRawPointer?) {
        // Swift.print(#function, #line, #file)
        
        guard context == &(self.kvoContext) else { return }
        guard let object = object as? AVPlayer else { return }
        guard let keyPath = keyPath, let change = change else { return }
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        
        if object == player && keyPath == #keyPath(AVPlayer.status) {
            // Swift.print("#####", "#keyPath(AVPlayer.status)")
            
            // Force redraw when AVPlayer.status is updated
            let newStatus = change[.newKey] as! NSNumber
            if newStatus.intValue == AVPlayer.Status.readyToPlay.rawValue {
                // Seek and refresh View
                let time = mutator.insertionTime
                let range = mutator.selectedTimeRange
                self.updateGUI(time, range, false)
            } else if newStatus.intValue == AVPlayer.Status.failed.rawValue {
                //
                Swift.print("ERROR: AVPlayerStatus.failed detected.")
            }
            return
        } else if object == player && keyPath == #keyPath(AVPlayer.rate) {
            // Swift.print("#####", "#keyPath(AVPlayer.rate)")
            
            // Check special case: movie play reached at end of movie
            let oldRate = change[.oldKey] as! NSNumber
            let newRate = change[.newKey] as! NSNumber
            if oldRate.floatValue > 0.0 && newRate.floatValue == 0.0 {
                // TODO: refine here
                let current = player.currentTime()
                let duration = mutator.movieDuration()
                let selection = mutator.selectedTimeRange
                if current == duration {
                    // now Stopped at end of movie - force update GUI to end of movie
                    updateTimeline(current, range: selection)
                }
            } else {
                // ignore
            }
            return
        } else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
        }
    }
    
    /// Register observer for movie mutation
    public func addMutationObserver() {
        // Swift.print(#function, #line, #file)
        
        let handler: (Notification) -> Void = {[unowned self] (notification) in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard let mutator = self.movieMutator else { return }
            guard let object = notification.object as? MovieMutator else { return }
            guard mutator == object else { return }
            
            #if false
            Swift.print("#####", "========================",
                        "Received: .movieWasMutated :", self.displayName!)
            #endif
            
            // extract CMTime/CMTimeRange from userInfo
            guard let userInfo = notification.userInfo else { return }
            guard let timeValue = userInfo[timeValueInfoKey] as? NSValue else { return }
            guard let timeRangeValue = userInfo[timeRangeValueInfoKey] as? NSValue else { return }
            
            let time: CMTime = timeValue.timeValue
            let timeRange: CMTimeRange = timeRangeValue.timeRangeValue
            self.updateGUI(time, timeRange, true)
        }
        let addBlock: () -> Void = {
            guard let mutator = self.movieMutator else { return }
            let center = NotificationCenter.default
            var observer: NSObjectProtocol? = nil
            observer = center.addObserver(forName: .movieWasMutated,
                                          object: mutator,
                                          queue: OperationQueue.main,
                                          using: handler)
            self.mutationObserver = observer
        }
        if (Thread.isMainThread) {
            addBlock()
        } else {
            DispatchQueue.main.sync(execute: addBlock)
        }
    }
    
    /// Unregister observer for movie mutation
    public func removeMutationObserver() {
        // Swift.print(#function, #line, #file)
        
        let removeBlock = {
            guard let mutator = self.movieMutator else { return }
            guard let observer = self.mutationObserver else { return }
            let center = NotificationCenter.default
            center.removeObserver(observer,
                                  name: .movieWasMutated,
                                  object: mutator)
            self.mutationObserver = nil
        }
        if (Thread.isMainThread) {
            removeBlock()
        } else {
            DispatchQueue.main.sync(execute: removeBlock)
        }
    }
    
    /// Unregister all undo record for current MovieMutator object
    public func removeAllUndoRecords() {
        // Swift.print(#function, #line, #file)
        
        if let mutator = self.movieMutator, let undoManager = self.undoManager {
            undoManager.removeAllActions(withTarget: mutator)
        }
    }
}

/* ============================================ */
// MARK: -  Position control
/* ============================================ */

extension Document {
    
    /// Move either start/end marker at current marker (nearest marker do sync)
    public func syncSelection(_ current: CMTime) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let selection: CMTimeRange = mutator.selectedTimeRange
        let start: CMTime = selection.start
        let end: CMTime = selection.end
        
        let halfDuration: CMTime = CMTimeMultiplyByRatio(selection.duration, multiplier: 1, divisor: 2)
        let centerOfRange: CMTime = start + halfDuration
        let t1: CMTime = (current < centerOfRange) ? current : start
        let t2: CMTime = (current > centerOfRange) ? current : end
        let newSelection: CMTimeRange = CMTimeRangeFromTimeToTime(start: t1, end: t2)
        mutator.selectedTimeRange = newSelection
    }
    
    /// Move either Or both start/end marker to current marker
    public func resetSelection(_ newTime: CMTime, _ resetStart: Bool, _ resetEnd: Bool) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let selection: CMTimeRange = mutator.selectedTimeRange
        let start: CMTime = selection.start
        let end: CMTime = selection.end
        
        let sFlag: Bool = (resetEnd && newTime < start) ? true : resetStart
        let eFlag: Bool = (resetStart && newTime > end) ? true : resetEnd
        if sFlag || eFlag {
            let t1: CMTime = sFlag ? newTime : start
            let t2: CMTime = eFlag ? newTime : end
            let newSelection: CMTimeRange = CMTimeRangeFromTimeToTime(start: t1, end: t2)
            mutator.selectedTimeRange = newSelection
        }
    }
    
    /// Check if it is head of movie
    public func checkHeadOfMovie() -> Bool {
        // Swift.print(#function, #line, #file)
        
        guard let player = self.player else { return false }
        
        // NOTE: Return false if player is not paused.
        if player.rate != 0.0 { return false }
        
        let current = player.currentTime()
        if current == CMTime.zero {
            return true
        }
        return false
    }
    
    /// Check if it is tail of movie
    public func checkTailOfMovie() -> Bool {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return false }
        guard let player = self.player else { return false }
        
        // NOTE: Return false if player is not paused.
        if player.rate != 0.0 { return false }
        
        let current = player.currentTime()
        let duration: CMTime = mutator.movieDuration()
        
        // validate cached range value
        if cachedTime == current {
            // use cached result
            return cachedWithinLastSampleRange
        } else {
            // reset cache
            cachedTime = current
            cachedWithinLastSampleRange = false
            cachedLastSampleRange = CMTimeRange.invalid
            
            if let info = mutator.presentationInfoAtTime(current) {
                let endOfRange: Bool = info.timeRange.end == duration
                if endOfRange {
                    cachedTime = current
                    cachedWithinLastSampleRange = true
                    cachedLastSampleRange = info.timeRange
                }
            }
            return cachedWithinLastSampleRange
        }
    }
    
    /// Snap to grid - Adjust Timeline resolution
    public func quantize(_ position: Float64) -> CMTime {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return CMTime.zero }
        let position: Float64 = min(max(position, 0.0), 1.0)
        if let info = mutator.presentationInfoAtPosition(position) {
            let ratio: Float64 = (position - info.startPosition) / (info.endPosition - info.startPosition)
            return (ratio < 0.5) ? info.timeRange.start : info.timeRange.end
        } else {
            return CMTimeMultiplyByFloat64(mutator.movieDuration(), multiplier: position)
        }
    }
}

/* ============================================ */
// MARK: -  Movie Reference utility
/* ============================================ */

extension Document {
    
    public func validateIfSelfContained(for url: URL) -> Bool {
        // Swift.print(#function, #line, #file)
        
        /*
         If a movie refers to one file path only and it is same as the movie's filePath,
         - the URL is the only one source of the movie
         - movie file is self-containd - no referencing track is included
         
         In case of in-memory movie (no-file-backed) it should be a reference movie.
         In case of multiple url found it should be a reference movie.
         */
        let refURLs: [URL] = self.movieMutator?.queryMediaDataURLs() ?? []
        if refURLs.count == 1 && refURLs[0] == url {
            return true
        }
        //
        if refURLs.count < 1 {
            Swift.print("ERROR: Unable to get track reference URLs")
        }
        if refURLs.count == 1 {
            Swift.print("NOTE: Different track reference URL found")
        }
        if refURLs.count > 1 {
            Swift.print("NOTE: Multiple track reference URLs found")
        }
        return false
    }
}
