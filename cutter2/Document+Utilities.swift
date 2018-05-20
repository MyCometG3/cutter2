//
//  Document+Utilities.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/16.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Sheet control
/* ============================================ */

extension Document {
    
    /// Update progress
    internal func updateProgress(_ progress : Float) {
        guard let alert = self.alert else { return }
        guard progress.isNormal else { return }
        
        let t : UInt64 = CVGetCurrentHostTime()
        guard (t - lastUpdateAt) > 100000000 else { return }
        lastUpdateAt = t
        
        DispatchQueue.main.async {
            alert.informativeText = String("Please hold on minute(s)... : \(Int(progress * 100)) %")
        }
    }
    
    /// Show busy modalSheet
    internal func showBusySheet(_ message : String?, _ info : String?) {
        DispatchQueue.main.async {
            guard let window = self.window else { return }
            
            let alert : NSAlert = NSAlert()
            alert.messageText = message ?? "Processing...(message)"
            alert.informativeText = info ?? "Hold on seconds...(informative)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "") // No button on sheet
            let handler : (NSApplication.ModalResponse) -> Void = {(response) in
                //if response == .stop {/* hideBusySheet() called */}
            }
            
            alert.beginSheetModal(for: window, completionHandler: handler)
            self.alert = alert
        }
    }
    
    /// Hide busy modalSheet
    internal func hideBusySheet() {
        DispatchQueue.main.async {
            guard let window = self.window else { return }
            guard let alert = self.alert else { return }
            
            window.endSheet(alert.window)
            self.alert = nil
        }
    }
    
    /// Present ErrorSheet asynchronously
    internal func showErrorSheet(_ error: Error) {
        // Don't use NSDocument default error handling
        DispatchQueue.main.async {
            let alert = NSAlert(error: error)
            do {
                let err = error as NSError
                let userInfo : [String:Any]? = err.userInfo
                if let info = userInfo {
                    var showDebugInfo: Bool = false
                    let keys = info.keys
                    if keys.contains(NSUnderlyingErrorKey) || keys.contains(NSDebugDescriptionErrorKey) {
                        showDebugInfo = true
                    }
                    if #available(OSX 10.13, *), keys.contains(NSLocalizedFailureErrorKey) {
                        showDebugInfo = true
                    }
                    if showDebugInfo {
                        alert.informativeText = err.description
                    } else if keys.contains(NSLocalizedFailureReasonErrorKey) {
                        alert.informativeText =  info[NSLocalizedFailureReasonErrorKey] as! String
                    }
                }
            }
            alert.beginSheetModal(for: self.window!, completionHandler: nil)
        }
    }
}

/* ============================================ */
// MARK: - Misc utilities
/* ============================================ */

let titleInspectKey : String = "title" // String
let pathInspectKey : String = "path" // String (numTracks)
let videoFormatInspectKey : String = "videoFormat" // String (numTracks)
let videoFPSInspectKey : String = "videoFPS" // String (numTracks)
let audioFormatInspectKey : String = "audioFormat" // String (numTracks)
let videoDataSizeInspectKey : String = "videoDataSize" // String (numTracks)
let audioDataSizeInspectKey : String = "audioDataSize" // String (numTracks)
let currentTimeInspectKey : String = "currentTime" // String
let movieDurationInspectKey : String = "movieDuration" // String
let selectionStartInspectKey : String = "selectionStart" // String
let selectionEndInspectKey : String = "selectionEnd" // String
let selectionDurationInspectKey : String = "selectionDuration" // String
extension Document {
    internal func inspecterDictionary() -> [String:Any] {
        var dict : [String:Any] = [:]
        guard let mutator = self.movieMutator else { return dict }

        dict[titleInspectKey] = self.displayName
        
        dict[pathInspectKey] = {
            var urlString = ""
            if let urlArray = mutator.mediaDataURLs() {
                let urlStringArray : [String] = urlArray.map{(url) in url.path}
                urlString = urlStringArray.joined(separator: ", ")
            }
            return urlString
        }()
        
        dict[videoFormatInspectKey] = mutator.videoFormats()?.joined(separator: "\n")
        dict[videoFPSInspectKey] = mutator.videoFPS()?.joined(separator: "\n")
        dict[audioFormatInspectKey] = mutator.audioFormat()?.joined(separator: "\n")
        dict[videoDataSizeInspectKey] = mutator.videoDataSize()?.joined(separator: "\n")
        dict[audioDataSizeInspectKey] = mutator.audioDataSize()?.joined(separator: "\n")
        dict[currentTimeInspectKey] = mutator.shortTimeString(mutator.insertionTime, withDecimals: true)
        dict[movieDurationInspectKey] = mutator.shortTimeString(mutator.movieDuration(), withDecimals: true)
        
        let range : CMTimeRange = mutator.selectedTimeRange
        dict[selectionStartInspectKey] = mutator.shortTimeString(range.start, withDecimals: true)
        dict[selectionEndInspectKey] = mutator.shortTimeString(range.end, withDecimals: true)
        dict[selectionDurationInspectKey] = mutator.shortTimeString(range.duration, withDecimals: true)
        
        return dict
    }
    
    /// used in debugInfo()
    internal func modifier(_ mask : NSEvent.ModifierFlags) -> Bool {
        guard let current = NSApp.currentEvent?.modifierFlags else { return false }
        
        return current.contains(mask)
    }
    
    /// Cleanup for close document
    internal func cleanup() {
        //
        self.removeMutationObserver()
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
    internal func updateGUI(_ time : CMTime, _ timeRange : CMTimeRange, _ reload : Bool) {
        // Swift.print(#function, #line)
        
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
    internal func resumeAfterSeek(to time : CMTime, with rate : Float) {
        guard let player = self.player else { return }
        guard let mutator = self.movieMutator else { return }
        
        do {
            let t = time
            Swift.print("resumeAfterSeek",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        
        player.pause()
        let handler : (Bool) -> Void = {[unowned player] (finished) in
            guard let mutator = self.movieMutator else { return }
            player.rate = rate
            self.updateTimeline(time, range: mutator.selectedTimeRange)
        }
        player.seek(to: time, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero, completionHandler: handler)
    }
    
    /// Update marker position in Timeline view
    internal func updateTimeline(_ time : CMTime, range : CMTimeRange) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        
        // Update marker position
        mutator.insertionTime = time
        mutator.selectedTimeRange = range
        
        // Prepare userInfo
        var userInfo : [AnyHashable:Any] = [:]
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
        //Swift.print(#function, #line)
        guard let mutator = movieMutator, let pv = playerView else { return }
        
        if let player = pv.player {
            // Apply modified source movie
            let playerItem = mutator.makePlayerItem()
            player.replaceCurrentItem(with: playerItem)
            
            // seek
            let handler : (Bool) -> Void = {[unowned pv] (finished) in
                pv.needsDisplay = true
            }
            playerItem.seek(to: mutator.insertionTime, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero,
                            completionHandler: handler)
        } else {
            // Initial setup
            let playerItem = mutator.makePlayerItem()
            let player : AVPlayer = AVPlayer(playerItem: playerItem)
            pv.player = player
            
            // AddObserver to AVPlayer
            self.addPlayerObserver()
            
            // Start polling timer
            self.useUpdateTimer(true)
        }
    }
    
    /// Setup polling timer - queryPosition()
    private func useUpdateTimer(_ enable : Bool) {
        //Swift.print(#function, #line, (enable ? "on" : "off"))
        
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
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        guard let playerItem = self.playerItem else { return }
        
        let notReady : Bool = (player.status != .readyToPlay)
        let empty : Bool = playerItem.isPlaybackBufferEmpty
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
        //Swift.print(#function, #line)
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
        //Swift.print(#function, #line)
        guard let player = self.player else { return }
        
        player.removeObserver(self,
                              forKeyPath: #keyPath(AVPlayer.status),
                              context: &(self.kvoContext))
        player.removeObserver(self,
                              forKeyPath: #keyPath(AVPlayer.rate),
                              context: &(self.kvoContext))
    }
    
    // NSKeyValueObserving protocol - observeValue(forKeyPath:of:change:context:)
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        //Swift.print(#function, #line)
        guard context == &(self.kvoContext) else { return }
        guard let object = object as? AVPlayer else { return }
        guard let keyPath = keyPath, let change = change else { return }
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        
        if object == player && keyPath == #keyPath(AVPlayer.status) {
            // Swift.print(#function, #line, "#keyPath(AVPlayer.status)")
            
            // Force redraw when AVPlayer.status is updated
            let newStatus = change[.newKey] as! NSNumber
            if newStatus.intValue == AVPlayerStatus.readyToPlay.rawValue {
                // Seek and refresh View
                let time = mutator.insertionTime
                let range = mutator.selectedTimeRange
                self.updateGUI(time, range, false)
            } else if newStatus.intValue == AVPlayerStatus.failed.rawValue {
                //
                Swift.print("ERROR: AVPlayerStatus.failed detected.")
            }
            return
        } else if object == player && keyPath == #keyPath(AVPlayer.rate) {
            //Swift.print(#function, #line, "#keyPath(AVPlayer.rate)")
            
            // Check special case : movie play reached at end of movie
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
    internal func addMutationObserver() {
        //Swift.print(#function, #line)
        let handler : (Notification) -> Void = {[unowned self] (notification) in
            Swift.print("========================== Received : .movieWasMutated ==========================")
            
            // extract CMTime/CMTimeRange from userInfo
            guard let userInfo = notification.userInfo else { return }
            guard let timeValue = userInfo[timeValueInfoKey] as? NSValue else { return }
            guard let timeRangeValue = userInfo[timeRangeValueInfoKey] as? NSValue else { return }
            
            let time : CMTime = timeValue.timeValue
            let timeRange : CMTimeRange = timeRangeValue.timeRangeValue
            self.updateGUI(time, timeRange, true)
        }
        let center = NotificationCenter.default
        center.addObserver(forName: .movieWasMutated,
                           object: movieMutator,
                           queue: OperationQueue.main,
                           using: handler)
    }
    
    /// Unregister observer for movie mutation
    internal func removeMutationObserver() {
        //Swift.print(#function, #line)
        let center = NotificationCenter.default
        center.removeObserver(self,
                              name: .movieWasMutated,
                              object: movieMutator)
    }
}

/* ============================================ */
// MARK: -  Position control
/* ============================================ */

extension Document {

    /// Move either start/end marker at current marker (nearest marker do sync)
    internal func syncSelection(_ current: CMTime) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let selection : CMTimeRange = mutator.selectedTimeRange
        let start : CMTime = selection.start
        let end : CMTime = selection.end
        
        let halfDuration : CMTime = CMTimeMultiplyByRatio(selection.duration, 1, 2)
        let centerOfRange : CMTime = start + halfDuration
        let t1 : CMTime = (current < centerOfRange) ? current : start
        let t2 : CMTime = (current > centerOfRange) ? current : end
        let newSelection : CMTimeRange = CMTimeRangeFromTimeToTime(t1, t2)
        mutator.selectedTimeRange = newSelection
    }
    
    /// Move either Or both start/end marker to current marker
    internal func resetSelection(_ newTime : CMTime, _ resetStart : Bool, _ resetEnd : Bool) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let selection : CMTimeRange = mutator.selectedTimeRange
        let start : CMTime = selection.start
        let end : CMTime = selection.end
        
        let sFlag : Bool = (resetEnd && newTime < start) ? true : resetStart
        let eFlag : Bool = (resetStart && newTime > end) ? true : resetEnd
        if sFlag || eFlag {
            let t1 : CMTime = sFlag ? newTime : start
            let t2 : CMTime = eFlag ? newTime : end
            let newSelection : CMTimeRange = CMTimeRangeFromTimeToTime(t1, t2)
            mutator.selectedTimeRange = newSelection
        }
    }
    
    /// Check if it is head of movie
    internal func checkHeadOfMovie() -> Bool {
        //Swift.print(#function, #line)
        guard let player = self.player else { return false }
        
        // NOTE: Return false if player is not paused.
        if player.rate != 0.0 { return false }
        
        let current = player.currentTime()
        if current == kCMTimeZero {
            return true
        }
        return false
    }
    
    /// Check if it is tail of movie
    internal func checkTailOfMovie() -> Bool {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return false }
        guard let player = self.player else { return false }
        
        // NOTE: Return false if player is not paused.
        if player.rate != 0.0 { return false }
        
        let current = player.currentTime()
        let duration : CMTime = mutator.movieDuration()
        
        // validate cached range value
        if cachedTime == current {
            // use cached result
            return cachedWithinLastSampleRange
        } else {
            // reset cache
            cachedTime = current
            cachedWithinLastSampleRange = false
            cachedLastSampleRange = kCMTimeRangeInvalid
            
            if let info = mutator.presentationInfoAtTime(current) {
                let endOfRange : Bool = info.timeRange.end == duration
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
    internal func quantize(_ position : Float64) -> CMTime {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return kCMTimeZero }
        let position : Float64 = min(max(position, 0.0), 1.0)
        if let info = mutator.presentationInfoAtPosition(position) {
            let ratio : Float64 = (position - info.startPosition) / (info.endPosition - info.startPosition)
            return (ratio < 0.5) ? info.timeRange.start : info.timeRange.end
        } else {
            return CMTimeMultiplyByFloat64(mutator.movieDuration(), position)
        }
    }
    
}
