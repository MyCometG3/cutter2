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
    
    public func hasSelection() -> Bool {
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.selectedTimeRange.duration > CMTime.zero) ? true : false
    }
    
    public func hasDuration() -> Bool {
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.movieDuration() > CMTime.zero) ? true : false
    }
    
    public func hasClipOnPBoard() -> Bool {
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.validateClipFromPBoard()) ? true : false
    }
    
    public func debugInfo() {
        
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        
        #if DEBUG
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
    
    public func timeOfPosition(_ position: Float64) -> CMTime {
        
        guard let mutator = self.movieMutator else { return CMTime.zero }
        return mutator.timeOfPosition(position)
    }
    
    public func positionOfTime(_ time: CMTime) -> Float64 {
        
        guard let mutator = self.movieMutator else { return 0.0 }
        return mutator.positionOfTime(time)
    }
    
    public func doCut() {
        
        guard let mutator = self.movieMutator else { return }
        mutator.cutSelection(using: self.undoManagerWrapper)
    }
    
    public func doCopy() {
        
        guard let mutator = self.movieMutator else { return }
        mutator.copySelection()
    }
    
    public func doPaste() {
        
        guard let mutator = self.movieMutator else { return }
        mutator.pasteAtInsertionTime(using: self.undoManagerWrapper)
    }
    
    /// Delete selection range
    public func doDelete() {
        
        guard let mutator = self.movieMutator else { return }
        mutator.deleteSelection(using: self.undoManagerWrapper)
    }
    
    /// Select all range of movie
    public func selectAll() {
        
        guard let mutator = self.movieMutator else { return }
        let time = mutator.insertionTime
        let range: CMTimeRange = mutator.movieRange()
        self.updateGUI(time, range, false)
    }
    
    /// offset current marker by specified step
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
    
    /// offset current marker by specified seconds
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
    
    /// offset current volume by specified percent
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
    
    /// move left current marker by key combination
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
    
    /// move right current marker by key combination
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
    
    /// Perform slowmotion
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
    
    /// Set playback rate
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
    
    /// Toggle play
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
