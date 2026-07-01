//
//  Document+UI.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/13.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - UI Operations
/* ============================================ */

extension Document {
    
    /* ============================================ */
    // MARK: - Resize window
    /* ============================================ */
    
    public func displayRatio(_ baseSize: CGSize?) -> CGFloat {
        
        guard let mutator = self.movieMutator else { return 1.0 }
        // S-10: guard let for playerView (Optional AVPlayerView?)
        guard let playerView = self.playerView else { return 1.0 }
        
        let size = baseSize ?? mutator.dimensions(of: self.dimensionsType)
        if size == NSZeroSize { return 1.0 }
        
        let viewSize = playerView.frame.size
        let hRatio = viewSize.width / size.width
        let vRatio = viewSize.height / size.height
        let ratio = (hRatio < vRatio) ? hRatio: vRatio
        
        return ratio
    }
    
    @IBAction func resizeWindow(_ sender: Any?) {
        
        guard let mutator = self.movieMutator else { return }
        // S-10: guard let for window and playerView
        guard let window = self.window, let playerView = self.playerView else { return }
        // S-10 follow-up: NSWindow.screen is also Optional (nil when offscreen / teardown)
        guard let screen = window.screen else { return }
        
        let screenRect = screen.visibleFrame
        let viewSize = playerView.frame.size
        let windowSize = window.frame.size
        let extraSize = NSSize(width: windowSize.width - viewSize.width,
                               height: windowSize.height - viewSize.height)
        
        // Calc new video size
        var size = mutator.dimensions(of: self.dimensionsType)
        var keepTopLeft = false
        if let menuItem = sender as? NSMenuItem {
            var ratio = displayRatio(size)
            let tag = menuItem.tag
            switch tag {
            case 0: // 50%
                size = NSSize(width: size.width/2, height: size.height/2)
            case 1: // 100%
                break
            case 2: // 200%
                size = NSSize(width: size.width*2, height: size.height*2)
            case 10: // -10%
                ratio = ceil(ratio * 10 - 1.0) / 10.0
                ratio = min(max(ratio, 0.2), 5.0)
                size = NSSize(width: size.width*ratio, height: size.height*ratio)
            case 11: // +10%
                ratio = floor(ratio * 10 + 1.0) / 10.0
                ratio = min(max(ratio, 0.2), 5.0)
                size = NSSize(width: size.width*ratio, height: size.height*ratio)
            case 99: // fit to screen
                size = NSSize(width: size.width*10, height: size.height*10)
            default: // 100% resize from top-left
                keepTopLeft = true
            }
        }
        
        // Calc new window size
        var newWindowSize = NSSize(width: extraSize.width + size.width,
                                   height: extraSize.height + size.height)
        if newWindowSize.width > screenRect.size.width || newWindowSize.height > screenRect.size.height {
            // shrink; Limit window size to fit in
            size = mutator.dimensions(of: self.dimensionsType)
            let hRatio = (screenRect.size.width - extraSize.width) / size.width
            let vRatio = (screenRect.size.height - extraSize.height) / size.height
            let ratio = (hRatio < vRatio) ? hRatio : vRatio
            size = NSSize(width: size.width * ratio, height: size.height * ratio)
            newWindowSize = NSSize(width: extraSize.width + size.width,
                                   height: extraSize.height + size.height)
        }
        
        // Transpose to anchor point
        var origin = window.frame.origin
        do {
            if keepTopLeft { // preserve top left corner
                let newOrigin = NSPoint(x: origin.x,
                                        y: origin.y - (newWindowSize.height - windowSize.height))
                origin = newOrigin
            } else { // preserve top center point
                let newOrigin = NSPoint(x: origin.x + (windowSize.width/2) - (newWindowSize.width/2) ,
                                        y: origin.y - (newWindowSize.height - windowSize.height))
                origin = newOrigin
            }
        }
        
        // Transpose into screenRect
        do {
            let scrXmax: CGFloat = screenRect.origin.x + screenRect.size.width
            let scrYmax: CGFloat = screenRect.origin.y + screenRect.size.height
            let errXmin: Bool = (origin.x < screenRect.origin.x)
            let errXmax: Bool = (origin.x + newWindowSize.width > scrXmax)
            let errYmin: Bool = (origin.y < screenRect.origin.y)
            let errYmax: Bool = (origin.y + newWindowSize.height > scrYmax)
            if errXmin || errXmax || errYmin || errYmax {
                let hOffset: CGFloat = (errXmax
                                        ? (scrXmax - (origin.x + newWindowSize.width))
                                        : (errXmin ? (screenRect.origin.x - origin.x) : 0.0))
                let vOffset: CGFloat = (errYmax
                                        ? (scrYmax - (origin.y + newWindowSize.height))
                                        : (errYmin ? (screenRect.origin.y - origin.y) : 0.0))
                let newOrigin = NSPoint(x: origin.x + hOffset, y: origin.y + vOffset)
                origin = newOrigin
            }
        }
        
        // Apply new Rect to window
        let newWindowRect = NSRect(origin: origin, size: newWindowSize)
        window.setFrame(newWindowRect, display: true, animate: false)
    }
    
    /* ============================================ */
    // MARK: - modify clap/pasp
    /* ============================================ */
    
    @IBAction func modifyClapPasp(_ sender: Any?) {
        
        guard let mutator = self.movieMutator else { NSSound.beep(); return }
        guard let dict: [AnyHashable:Any] = mutator.clappaspDictionary() else { NSSound.beep(); return }
        // S-10: guard let for window (early-bail before storyboard instantiation)
        guard let window = self.window else { NSSound.beep(); return }
        
        // Prepare CAPAR SheetController
        let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
        let sid: NSStoryboard.SceneIdentifier = "CAPARSheet Controller"
        guard let caparWC = storyboard.instantiateController(withIdentifier: sid) as? NSWindowController else {
            preconditionFailure("Failed to instantiate CAPARSheet Controller")
        }
        // caparWC.loadWindow()
        
        // Prepare CAPAR ViewController
        guard let contVC = caparWC.contentViewController else { preconditionFailure("Unexpected nil contentViewController detected.") }
        guard let caparVC = contVC as? CAPARViewController else { preconditionFailure("Unexpected nil CAPARViewController detected.") }
        guard caparVC.applySource(dict) else { return }
        
        // Show CAPAR Sheet
        caparVC.beginSheetModal(for: window) {[caparVC, mutator, weak self] (response) in // @escaping
            self?.afterSheetContinue(response) { document in
                // Update Clap/Pasp settings
                let result: [AnyHashable:Any] = caparVC.resultContent
                let done: Bool = mutator.applyClapPasp(result, using: document.undoManagerWrapper)
                if !done {
                    var info: [String:Any] = [:]
                    info[NSLocalizedDescriptionKey] = "Failed to modify CAPAR extensions."
                    info[NSLocalizedFailureReasonErrorKey] = "Check if video track has same dimensions."
                    let err = NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: info)
                    
                    document.showErrorSheet(err)
                }
            }
        }
    }
}

/* ============================================ */
// MARK: - Playback updates
/* ============================================ */

extension Document {
    
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
        let handler: @Sendable (Bool) -> Void = {[weak self, weak player, weak mutator] (_) in // @escaping
            guard let self else { return }
            guard let player = player else { return }
            guard let mutator = mutator else { return }
            ActorUtilities.performSyncOnMainActor {
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
            let handler: @Sendable (Bool) -> Void = {[weak pv] (_) in // @escaping
                
                guard let pv = pv else { return }
                ActorUtilities.performSyncOnMainActor {
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
    func useUpdateTimer(_ enable: Bool) {
        
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
