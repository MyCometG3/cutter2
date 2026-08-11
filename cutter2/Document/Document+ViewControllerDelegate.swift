//
//  Document+ViewControllerDelegate.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - ViewControllerDelegate Protocol
/* ============================================ */

extension Document: ViewControllerDelegate {
    
    /// Indicates whether the document has a positive-duration selection.
    ///
    /// - Returns: `true` when a movie mutator has a positive-duration selection.
    public func hasSelection() -> Bool {
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.selectedTimeRange.duration > CMTime.zero) ? true : false
    }
    
    /// Indicates whether the document's movie has a positive duration.
    ///
    /// - Returns: `true` when a movie mutator has a positive-duration movie.
    public func hasDuration() -> Bool {
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.movieDuration() > CMTime.zero) ? true : false
    }
    
    /// Indicates whether the pasteboard contains a valid movie clip.
    ///
    /// - Returns: `true` when the current pasteboard clip can be inserted.
    public func hasClipOnPBoard() -> Bool {
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.validateClipFromPBoard()) ? true : false
    }
    
    /// Logs diagnostic movie, playback, and sample information in DEBUG builds.
    ///
    /// Additional previous and next sample information is logged when the Option key is held.
    public func debugInfo() {
        #if DEBUG
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        
        LoggingSystem.document.debug("===== Document State: \(mutator.ts()) =====")
        
        do {
            let t = mutator.movieDuration()
            LoggingSystem.document.debug("Movie duration: \(mutator.shortTimeString(t, withDecimals: true)) [\(mutator.rawTimeString(t))]")
        }
        do {
            let t = mutator.insertionTime
            LoggingSystem.document.debug("Movie insertion: \(mutator.shortTimeString(t, withDecimals: true)) [\(mutator.rawTimeString(t))]")
        }
        do {
            let t = mutator.selectedTimeRange.start
            LoggingSystem.document.debug("Selection start: \(mutator.shortTimeString(t, withDecimals: true)) [\(mutator.rawTimeString(t))]")
        }
        do {
            let t = mutator.selectedTimeRange.end
            LoggingSystem.document.debug("Selection end: \(mutator.shortTimeString(t, withDecimals: true)) [\(mutator.rawTimeString(t))]")
        }
        do {
            let t = player.currentTime()
            LoggingSystem.document.debug("Movie current: \(mutator.shortTimeString(t, withDecimals: true)) [\(mutator.rawTimeString(t))]")
        }
        do {
            guard let info = mutator.presentationInfoAtTime(mutator.insertionTime) else {
                LoggingSystem.document.debug("Presentation info: not available")
                return
            }
            let s = info.timeRange.start
            let e = info.timeRange.end
            LoggingSystem.document.debug("Sample start: \(mutator.shortTimeString(s, withDecimals: true)) [\(mutator.rawTimeString(s))]")
            LoggingSystem.document.debug("Sample end: \(mutator.shortTimeString(e, withDecimals: true)) [\(mutator.rawTimeString(e))]")
        }
        
        // Additional info when Option key is pressed
        guard modifier(.option) else { return }
        do {
            if let info = mutator.presentationInfoAtTime(mutator.insertionTime) {
                if let prev = mutator.previousInfo(of: info.timeRange) {
                    let s = prev.timeRange.start
                    let e = prev.timeRange.end
                    LoggingSystem.document.debug("Previous sample start: \(mutator.shortTimeString(s, withDecimals: true)) [\(mutator.rawTimeString(s))]")
                    LoggingSystem.document.debug("Previous sample end: \(mutator.shortTimeString(e, withDecimals: true)) [\(mutator.rawTimeString(e))]")
                } else {
                    LoggingSystem.document.debug("Previous presentation info: not available")
                }
            } else {
                LoggingSystem.document.debug("Presentation info: not available")
            }
        }
        do {
            if let info = mutator.presentationInfoAtTime(mutator.insertionTime) {
                if let next = mutator.nextInfo(of: info.timeRange) {
                    let s = next.timeRange.start
                    let e = next.timeRange.end
                    LoggingSystem.document.debug("Next sample start: \(mutator.shortTimeString(s, withDecimals: true)) [\(mutator.rawTimeString(s))]")
                    LoggingSystem.document.debug("Next sample end: \(mutator.shortTimeString(e, withDecimals: true)) [\(mutator.rawTimeString(e))]")
                } else {
                    LoggingSystem.document.debug("Next presentation info: not available")
                }
            } else {
                LoggingSystem.document.debug("Presentation info: not available")
            }
        }
        #endif
    }
    
    /// Converts a relative movie position into movie time.
    ///
    /// - Parameter position: A relative position from 0.0 to 1.0.
    /// - Returns: The corresponding movie time, or zero when no mutator is available.
    public func timeOfPosition(_ position: Float64) -> CMTime {
        
        guard let mutator = self.movieMutator else { return CMTime.zero }
        return mutator.timeOfPosition(position)
    }
    
    /// Converts movie time into a relative movie position.
    ///
    /// - Parameter time: The movie time to convert.
    /// - Returns: A relative position from 0.0 to 1.0, or zero when no mutator is available.
    public func positionOfTime(_ time: CMTime) -> Float64 {
        
        guard let mutator = self.movieMutator else { return 0.0 }
        return mutator.positionOfTime(time)
    }
    
    /// Cuts the current selection and registers the operation with the document undo manager.
    public func doCut() {
        
        guard let mutator = self.movieMutator else { return }
        mutator.cutSelection(using: self.undoManagerWrapper)
    }
    
    /// Copies the current selection to the pasteboard.
    public func doCopy() {
        
        guard let mutator = self.movieMutator else { return }
        mutator.copySelection()
    }
    
    /// Pastes the pasteboard clip at the current insertion marker and registers an undo action.
    public func doPaste() {
        
        guard let mutator = self.movieMutator else { return }
        mutator.pasteAtInsertionTime(using: self.undoManagerWrapper)
    }
    
    /// Deletes the current selection and registers the operation with the document undo manager.
    public func doDelete() {
        
        guard let mutator = self.movieMutator else { return }
        mutator.deleteSelection(using: self.undoManagerWrapper)
    }
    
    /// Selects the complete internal movie range while preserving the current insertion time.
    public func selectAll() {
        
        guard let mutator = self.movieMutator else { return }
        let time = mutator.insertionTime
        let range: CMTimeRange = mutator.movieRange()
        self.updateGUI(time, range, false)
    }
    
    /// Moves the current marker by a number of sample steps.
    ///
    /// - Parameters:
    ///   - count: The signed number of sample steps; positive moves forward and negative moves backward.
    ///   - resetStart: Whether to reset the selection start marker while stepping.
    ///   - resetEnd: Whether to reset the selection end marker while stepping.
    public func doStepByCount(_ count: Int64, _ resetStart: Bool, _ resetEnd: Bool) {
        
        var target: CMTime? = nil
        doStepByCount(count, resetStart, resetEnd, &target)
    }
    
    /// offset current marker by specified step (private)
    private func doStepByCount(_ count: Int64, _ resetStart: Bool, _ resetEnd: Bool, _ target: inout CMTime?) {
        
        guard let mutator = self.movieMutator else { return }
        guard let player = player, let item = playerItem else { return }
        
        // pause first
        let rate = player.rate
        updateRate(player, 0.0)
        
        //
        let nowTime = mutator.insertionTime
        if checkTailOfMovie(), let lastRange = cachedLastSampleRange {
            // Player is at final sample. Special handling required.
            if count > 0 && mutator.insertionTime < lastRange.end {
                resetSelection(lastRange.end, resetStart, resetEnd)
                updateTimeline(lastRange.end, range: mutator.selectedTimeRange)
                cachedTime = lastRange.start
                target = lastRange.start
                return
            }
            if count < 0 && mutator.insertionTime > lastRange.start {
                resetSelection(lastRange.start, resetStart, resetEnd)
                updateTimeline(lastRange.start, range: mutator.selectedTimeRange)
                cachedTime = lastRange.start
                target = lastRange.start
                return
            }
        }
        
        // step and resume
        let duration = mutator.movieDuration()
        let okForward = (count > 0 && item.canStepForward && nowTime < duration)
        let okBackward = (count < 0 && item.canStepBackward && CMTime.zero < nowTime)
        if okForward {
            guard let info = mutator.presentationInfoAtTime(nowTime) else { return }
            let newTime = CMTimeClampToRange(info.timeRange.end, range: mutator.movieRange())
            resetSelection(newTime, resetStart, resetEnd)
            resumeAfterSeek(to: newTime, with: rate)
            target = newTime
        } else if okBackward {
            guard let info = mutator.presentationInfoAtTime(nowTime) else { return }
            guard let prev = mutator.previousInfo(of: info.timeRange) else { return }
            let newTime = CMTimeClampToRange(prev.timeRange.start, range: mutator.movieRange())
            resetSelection(newTime, resetStart, resetEnd)
            resumeAfterSeek(to: newTime, with: rate)
            target = newTime
        } else {
            self.updateGUI(nowTime, mutator.selectedTimeRange, false)
            target = nowTime
        }
    }
    
    /// Moves the current marker by a number of seconds and snaps to the nearest sample boundary.
    ///
    /// - Parameters:
    ///   - offset: The signed offset in seconds.
    ///   - resetStart: Whether to reset the selection start marker while stepping.
    ///   - resetEnd: Whether to reset the selection end marker while stepping.
    public func doStepBySecond(_ offset: Float64, _ resetStart: Bool, _ resetEnd: Bool) {
        
        var target: CMTime? = nil
        doStepBySecond(offset, resetStart, resetEnd, &target)
    }
    
    /// offset current marker by specified seconds (private)
    private func doStepBySecond(_ offset: Float64, _ resetStart: Bool, _ resetEnd: Bool, _ target: inout CMTime?) {
        
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        let movieRange: CMTimeRange = mutator.movieRange()
        
        // pause first
        var rate = player.rate
        updateRate(player, 0.0)
        
        // calc target time
        var adjust: Bool = true
        let nowTime = mutator.insertionTime
        let offsetTime = CMTimeMakeWithSeconds(offset, preferredTimescale: nowTime.timescale)
        var newTime = nowTime + offsetTime
        if newTime < movieRange.start {
            newTime = movieRange.start; adjust = false
        } else if newTime > movieRange.end {
            newTime = movieRange.end; adjust = false
        }
        
        // adjust time (snap to grid)
        if adjust, let info = mutator.presentationInfoAtTime(newTime) {
            let beforeCenter: Bool = (info.timeRange.end - newTime) > (newTime - info.timeRange.start)
            newTime = beforeCenter ? info.timeRange.start : info.timeRange.end
        }
        
        // implicit pause
        if newTime == movieRange.end {
            rate = 0.0
        }
        
        // seek and resume
        resetSelection(newTime, resetStart, resetEnd)
        resumeAfterSeek(to: newTime, with: rate)
        target = newTime
    }
    
    /// Adjusts the player volume by a signed percentage offset.
    ///
    /// Values from -100 through 100 adjust the volume and clamp it to 0.0 through 1.0.
    /// Values below -100 mute the player.
    ///
    /// - Parameter percent: The signed volume percentage offset.
    public func doVolumeOffset(_ percent: Int) {
        
        guard let player = self.player else { return }
        
        // Mute/Unmute handling
        player.isMuted = (percent < -100) ? true : false
        
        // Update AVPlayer.volume
        if percent >= -100 && percent <= +100 {
            var volume: Float = player.volume
            volume += Float(percent) / 100.0
            volume = min(max(volume, 0.0), 1.0)
            player.volume = volume
        }
    }
    
    /// Moves the current marker left by one sample or to the previous selection boundary.
    ///
    /// - Parameters:
    ///   - optionKey: Whether to move between selection boundaries instead of stepping one sample.
    ///   - shiftKey: Whether to extend or synchronize the selection at the resulting position.
    ///   - resetStart: Whether to reset the selection start marker while stepping.
    ///   - resetEnd: Whether to reset the selection end marker while stepping.
    public func doMoveLeft(_ optionKey: Bool, _ shiftKey: Bool, _ resetStart: Bool, _ resetEnd: Bool) {
        
        guard let mutator = self.movieMutator else { return }
        var target: CMTime? = nil
        if optionKey {
            var current: CMTime = mutator.insertionTime
            let selection: CMTimeRange = mutator.selectedTimeRange
            let start: CMTime = selection.start
            let end: CMTime = selection.end
            let limit: CMTime = CMTime.zero
            current = (
                (end < current) ? end :
                    (start < current) ? start : limit
            )
            updateGUI(current, selection, false)
            target = current
        } else {
            doStepByCount(-1, resetStart, resetEnd, &target)
        }
        if shiftKey, let target = target {
            syncSelection(target)
            updateGUI(target, mutator.selectedTimeRange, false)
        }
    }
    
    /// Moves the current marker right by one sample or to the next selection boundary.
    ///
    /// - Parameters:
    ///   - optionKey: Whether to move between selection boundaries instead of stepping one sample.
    ///   - shiftKey: Whether to extend or synchronize the selection at the resulting position.
    ///   - resetStart: Whether to reset the selection start marker while stepping.
    ///   - resetEnd: Whether to reset the selection end marker while stepping.
    public func doMoveRight(_ optionKey: Bool, _ shiftKey: Bool, _ resetStart: Bool, _ resetEnd: Bool) {
        
        guard let mutator = self.movieMutator else { return }
        var target: CMTime? = nil
        if optionKey {
            var current: CMTime = mutator.insertionTime
            let selection: CMTimeRange = mutator.selectedTimeRange
            let start: CMTime = selection.start
            let end: CMTime = selection.end
            let limit: CMTime = mutator.movieDuration()
            current = (
                (current < start) ? start :
                    (current < end) ? end : limit
            )
            updateGUI(current, selection, false)
            target = current
        } else {
            doStepByCount(+1, resetStart, resetEnd, &target)
        }
        if shiftKey, let target = target {
            syncSelection(target)
            updateGUI(target, mutator.selectedTimeRange, false)
        }
    }
    
    /// Sets a clamped slow-motion playback rate.
    ///
    /// - Parameter ratio: The requested playback rate, clamped to -1.0 through 1.0.
    public func doSetSlow(_ ratio: Float) {
        
        guard let player = self.player else { return }
        guard let item = self.playerItem else { return }
        
        let okForward: Bool = (item.status == .readyToPlay)
        let okReverse: Bool = item.canPlayReverse
        let okSlowForward: Bool = item.canPlaySlowForward
        let okSlowReverse: Bool = item.canPlaySlowReverse
        
        let newRate: Float = min(max(ratio, -1.0), 1.0)
        
        if newRate == 0.0 {
            updateRate(player, newRate)
            return
        }
        if newRate > 0.0 && okForward && okSlowForward {
            if checkTailOfMovie() { // Restart from head of movie
                self.resumeAfterSeek(to: CMTime.zero, with: newRate)
            } else { // Start play
                updateRate(player, newRate)
            }
            return
        }
        if newRate < 0.0 && okReverse && okSlowReverse {
            if checkHeadOfMovie() { // Restart from tail of the movie
                self.resumeAfterSeek(to: item.duration, with: newRate)
            } else { // Start play
                updateRate(player, newRate)
            }
            return
        }
        //
        NSSound.beep()
    }
    
    /// Adjusts the playback rate by the requested rate step when the player supports it.
    ///
    /// - Parameter offset: The signed playback-rate step; zero pauses playback.
    public func doSetRate(_ offset: Int) {
        
        guard let player = self.player else { return }
        guard let item = self.playerItem else { return }
        var currentRate: Float = player.rate
        let okForward: Bool = (item.status == .readyToPlay)
        let okReverse: Bool = item.canPlayReverse
        let okFastForward: Bool = item.canPlayFastForward
        let okFastReverse: Bool = item.canPlayFastReverse
        
        // Fine acceleration control on fastforward/fastreverse
        let resolution: Float = 3.0 // 1.0, 1.33, 1.66, 2.00, 2.33, ...
        if -1.0 < currentRate && currentRate < 1.0 {
            currentRate = 0.0
        }
        if currentRate > 0.0 {
            currentRate = (currentRate - 1.0) * resolution + 1.0
        } else if currentRate < 0.0 {
            currentRate = (currentRate + 1.0) * resolution - 1.0
        }
        var newRate: Float = (offset == 0) ? 0.0 : (currentRate + Float(offset))
        if newRate > 0.0 {
            newRate = (newRate - 1.0) / resolution + 1.0
        } else if newRate < 0.0 {
            newRate = (newRate + 1.0) / resolution - 1.0
        }
        
        //
        if newRate == 0.0 {
            updateRate(player, newRate)
            return
        }
        if newRate > 0.0 && okForward {
            if newRate == 1.0 || (newRate > 1.0 && okFastForward) {
                if checkTailOfMovie() { // Restart from head of the movie
                    self.resumeAfterSeek(to: CMTime.zero, with: newRate)
                } else { // Start play
                    updateRate(player, newRate)
                }
                return
            }
        }
        if newRate < 0.0 && okReverse {
            if newRate == -1.0 || (newRate < -1.0 && okFastReverse) {
                if checkHeadOfMovie() { // Restart from tail of the movie
                    self.resumeAfterSeek(to: item.duration, with: newRate)
                } else { // Start play
                    updateRate(player, newRate)
                }
                return
            }
        }
        //
        NSSound.beep()
    }
    
    /// Toggles playback between playing and paused states.
    public func doTogglePlay() {
        
        guard let player = self.player else { return }
        let currentRate: Float = player.rate
        if currentRate != 0.0 { // play => pause
            doSetRate(0)
        } else { // pause => play
            if checkTailOfMovie() { // Restart play from head of the movie
                self.resumeAfterSeek(to: CMTime.zero, with: 1.0)
            } else { // Start play
                doSetRate(+1)
            }
        }
    }
}
