//
//  Document+Delegate.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/16.
//  Copyright © 2018-2019年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

extension Document : ViewControllerDelegate {
    
    /* ============================================ */
    // MARK: - ViewControllerDelegate Protocol
    /* ============================================ */
    
    public func hasSelection() -> Bool {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.selectedTimeRange.duration > CMTime.zero) ? true : false
    }
    
    public func hasDuration() -> Bool {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.movieDuration() > CMTime.zero) ? true : false
    }
    
    public func hasClipOnPBoard() -> Bool {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return false }
        return (mutator.validateClipFromPBoard()) ? true : false
    }
    
    public func debugInfo() {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let player = self.player!
        Swift.print("##### ", mutator.ts(), " #####")
        #if true
        do {
            let t = mutator.movieDuration()
            Swift.print(" movie duration",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            let t = mutator.insertionTime
            Swift.print("movie insertion",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            let t = mutator.selectedTimeRange.start
            Swift.print("      sel start",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            let t = mutator.selectedTimeRange.end
            Swift.print("        sel end",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            let t = player.currentTime()
            Swift.print("  movie current",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            guard let info = mutator.presentationInfoAtTime(mutator.insertionTime) else {
                Swift.print("presentationInfo", "not available!!!")
                return
            }
            let s = info.timeRange.start
            let e = info.timeRange.end
            Swift.print("   sample start",
                        mutator.shortTimeString(s, withDecimals: true),
                        mutator.rawTimeString(s))
            Swift.print("     sample end",
                        mutator.shortTimeString(e, withDecimals: true),
                        mutator.rawTimeString(e))
        }
        
        //
        guard modifier(.option) else { return }
        do {
            if let info = mutator.presentationInfoAtTime(mutator.insertionTime) {
                if let prev = mutator.previousInfo(of: info.timeRange) {
                    let s = prev.timeRange.start
                    let e = prev.timeRange.end
                    Swift.print(" p sample start",
                                mutator.shortTimeString(s, withDecimals: true),
                                mutator.rawTimeString(s))
                    Swift.print(" prv sample end",
                                mutator.shortTimeString(e, withDecimals: true),
                                mutator.rawTimeString(e))
                } else {
                    Swift.print("prev presentationInfo", "not available!!!")
                }
            } else {
                Swift.print("presentationInfo", "not available!!!")
            }
        }
        do {
            if let info = mutator.presentationInfoAtTime(mutator.insertionTime) {
                if let next = mutator.nextInfo(of: info.timeRange) {
                    let s = next.timeRange.start
                    let e = next.timeRange.end
                    Swift.print(" n sample start",
                                mutator.shortTimeString(s, withDecimals: true),
                                mutator.rawTimeString(s))
                    Swift.print(" nxt sample end",
                                mutator.shortTimeString(e, withDecimals: true),
                                mutator.rawTimeString(e))
                } else {
                    Swift.print("next presentationInfo", "not available!!!")
                }
            } else {
                Swift.print("presentationInfo", "not available!!!")
            }
        }
        #endif
        #if false
        Swift.print(mutator.clappaspDictionary() as Any)
        #endif
    }
    
    public func timeOfPosition(_ position : Float64) -> CMTime {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return CMTime.zero }
        return mutator.timeOfPosition(position)
    }
    
    public func positionOfTime(_ time : CMTime) -> Float64 {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return 0.0 }
        return mutator.positionOfTime(time)
    }
    
    public func doCut() throws {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        mutator.cutSelection(using: self.undoManager!)
    }
    
    public func doCopy() throws {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        mutator.copySelection()
    }
    
    public func doPaste() throws {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        mutator.pasteAtInsertionTime(using: self.undoManager!)
    }
    
    /// Delete selection range
    public func doDelete() throws {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        mutator.deleteSelection(using: self.undoManager!)
    }
    
    /// Select all range of movie
    public func selectAll() {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let time = mutator.insertionTime
        let range : CMTimeRange = mutator.movieRange()
        self.updateGUI(time, range, false)
    }
    
    /// offset current marker by specified step
    public func doStepByCount(_ count : Int64, _ resetStart : Bool, _ resetEnd : Bool) {
        // Swift.print(#function, #line, #file)
        
        var target : CMTime? = nil
        doStepByCount(count, resetStart, resetEnd, &target)
    }
    
    /// offset current marker by specified step (private)
    private func doStepByCount(_ count : Int64, _ resetStart : Bool, _ resetEnd : Bool, _ target : inout CMTime?) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        guard let player = player, let item = playerItem else { return }
        
        // pause first
        let rate = player.rate
        player.rate = 0.0
        
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
    public func doStepBySecond(_ offset : Float64, _ resetStart : Bool, _ resetEnd : Bool) {
        // Swift.print(#function, #line, #file)
        
        var target : CMTime? = nil
        doStepBySecond(offset, resetStart, resetEnd, &target)
    }
    
    /// offset current marker by specified seconds (private)
    private func doStepBySecond(_ offset: Float64, _ resetStart : Bool, _ resetEnd : Bool, _ target : inout CMTime?) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        let movieRange : CMTimeRange = mutator.movieRange()
        
        // pause first
        var rate = player.rate
        player.rate = 0.0
        
        // calc target time
        var adjust : Bool = true
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
            let beforeCenter : Bool = (info.timeRange.end - newTime) > (newTime - info.timeRange.start)
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
        // Swift.print(#function, #line, #file)
        
        guard let player = self.player else { return }
        
        // Mute/Unmute handling
        player.isMuted = (percent < -100) ? true : false
        
        // Update AVPlayer.volume
        if percent >= -100 && percent <= +100 {
            var volume : Float = player.volume
            volume += Float(percent) / 100.0
            volume = min(max(volume, 0.0), 1.0)
            player.volume = volume
        }
    }
    
    /// move left current marker by key combination
    public func doMoveLeft(_ optionKey : Bool, _ shiftKey : Bool, _ resetStart : Bool, _ resetEnd : Bool) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        var target : CMTime? = nil
        if optionKey {
            var current : CMTime = mutator.insertionTime
            let selection : CMTimeRange = mutator.selectedTimeRange
            let start : CMTime = selection.start
            let end : CMTime = selection.end
            let limit : CMTime = CMTime.zero
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
    public func doMoveRight(_ optionKey : Bool, _ shiftKey : Bool, _ resetStart : Bool, _ resetEnd : Bool) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        var target : CMTime? = nil
        if optionKey {
            var current : CMTime = mutator.insertionTime
            let selection : CMTimeRange = mutator.selectedTimeRange
            let start : CMTime = selection.start
            let end : CMTime = selection.end
            let limit : CMTime = mutator.movieDuration()
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
    public func doSetSlow(_ ratio : Float) {
        // Swift.print(#function, #line, #file)
        
        guard let player = self.player else { return }
        guard let item = self.playerItem else { return }
        
        let okForward : Bool = (item.status == .readyToPlay)
        let okReverse : Bool = item.canPlayReverse
        let okSlowForward : Bool = item.canPlaySlowForward
        let okSlowReverse : Bool = item.canPlaySlowReverse
        
        let newRate : Float = min(max(ratio, -1.0), 1.0)
        
        if newRate == 0.0 {
            player.pause()
            return
        }
        if newRate > 0.0 && okForward && okSlowForward {
            if checkTailOfMovie() { // Restart from head of movie
                self.resumeAfterSeek(to: CMTime.zero, with: newRate)
            } else { // Start play
                player.rate = newRate
            }
            return
        }
        if newRate < 0.0 && okReverse && okSlowReverse {
            if checkHeadOfMovie() { // Restart from tail of the movie
                self.resumeAfterSeek(to: item.duration, with: newRate)
            } else { // Start play
                player.rate = newRate
            }
            return
        }
        //
        NSSound.beep()
    }
    
    /// Set playback rate
    public func doSetRate(_ offset : Int) {
        // Swift.print(#function, #line, #file)
        
        guard let player = self.player else { return }
        guard let item = self.playerItem else { return }
        var currentRate : Float = player.rate
        let okForward : Bool = (item.status == .readyToPlay)
        let okReverse : Bool = item.canPlayReverse
        let okFastForward : Bool = item.canPlayFastForward
        let okFastReverse : Bool = item.canPlayFastReverse
        
        // Fine acceleration control on fastforward/fastreverse
        let resolution : Float = 3.0 // 1.0, 1.33, 1.66, 2.00, 2.33, ...
        if -1.0 < currentRate && currentRate < 1.0 {
            currentRate = 0.0
        }
        if currentRate > 0.0 {
            currentRate = (currentRate - 1.0) * resolution + 1.0
        } else if currentRate < 0.0 {
            currentRate = (currentRate + 1.0) * resolution - 1.0
        }
        var newRate : Float = (offset == 0) ? 0.0 : (currentRate + Float(offset))
        if newRate > 0.0 {
            newRate = (newRate - 1.0) / resolution + 1.0
        } else if newRate < 0.0 {
            newRate = (newRate + 1.0) / resolution - 1.0
        }
        
        //
        if newRate == 0.0 {
            player.pause()
            return
        }
        if newRate > 0.0 && okForward {
            if newRate == 1.0 || (newRate > 1.0 && okFastForward) {
                if checkTailOfMovie() { // Restart from head of movie
                    self.resumeAfterSeek(to: CMTime.zero, with: newRate)
                } else { // Start play
                    player.rate = newRate
                }
                return
            }
        }
        if newRate < 0.0 && okReverse {
            if newRate == -1.0 || (newRate < -1.0 && okFastReverse) {
                if checkHeadOfMovie() { // Restart from tail of the movie
                    self.resumeAfterSeek(to: item.duration, with: newRate)
                } else { // Start play
                    player.rate = newRate
                }
                return
            }
        }
        //
        NSSound.beep()
    }
    
    /// Toggle play
    public func doTogglePlay() {
        // Swift.print(#function, #line, #file)
        
        guard let player = self.player else { return }
        let currentRate : Float = player.rate
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
    
    /* ============================================ */
    // MARK: - TimelineUpdateDelegate Protocol
    /* ============================================ */
    
    /// called on mouse down/drag event
    public func didUpdateCursor(to position : Float64) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let time : CMTime = quantize(position)
        updateGUI(time, mutator.selectedTimeRange, false)
    }
    
    /// called on mouse down/drag event
    public func didUpdateStart(to position : Float64) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let fromTime : CMTime = quantize(position)
        let toTime : CMTime = mutator.selectedTimeRange.end
        let newRange = CMTimeRangeFromTimeToTime(start: fromTime, end: toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// called on mouse down/drag event
    public func didUpdateEnd(to position : Float64) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let fromTime : CMTime = mutator.selectedTimeRange.start
        let toTime : CMTime = quantize(position)
        let newRange = CMTimeRangeFromTimeToTime(start: fromTime, end: toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// called on mouse down/drag event
    public func didUpdateSelection(from fromPos : Float64, to toPos : Float64) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let fromTime : CMTime = quantize(fromPos)
        let toTime : CMTime = quantize(toPos)
        let newRange = CMTimeRangeFromTimeToTime(start: fromTime, end: toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// get PresentationInfo at specified position
    public func presentationInfo(at position: Float64) -> PresentationInfo? {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return nil }
        return mutator.presentationInfoAtPosition(position)
    }
    
    /// get PresentationInfo at prior to specified range
    public func previousInfo(of range: CMTimeRange) -> PresentationInfo? {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return nil }
        return mutator.previousInfo(of: range)
    }
    
    /// get PresentationInfo at next to specified range
    public func nextInfo(of range: CMTimeRange) -> PresentationInfo? {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return nil }
        return mutator.nextInfo(of: range)
    }
    
    /// Move current marker to specified anchor point
    public func doSetCurrent(to anchor : anchor) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let current : CMTime = mutator.insertionTime
        let start : CMTime = mutator.selectedTimeRange.start
        let end : CMTime = mutator.selectedTimeRange.end
        let duration : CMTime = mutator.movieDuration()
        
        switch anchor {
        case .head :
            mutator.insertionTime = CMTime.zero
        case .start :
            mutator.insertionTime = start
        case .end :
            mutator.insertionTime = end
        case .tail :
            mutator.insertionTime = duration
        case .startOrHead :
            if mutator.insertionTime != start {
                mutator.insertionTime = start
            } else {
                mutator.insertionTime = CMTime.zero
            }
        case .endOrTail :
            if mutator.insertionTime != end {
                mutator.insertionTime = end
            } else {
                mutator.insertionTime = duration
            }
        case .forward :
            if current < start {
                mutator.insertionTime = start
            } else if current < end {
                mutator.insertionTime = end
            } else {
                mutator.insertionTime = duration
            }
        case .backward :
            if end < current {
                mutator.insertionTime = end
            } else if start < current {
                mutator.insertionTime = start
            } else {
                mutator.insertionTime = CMTime.zero
            }
        default:
            NSSound.beep()
            return
        }
        
        let newCurrent : CMTime = mutator.insertionTime
        let newRange : CMTimeRange = mutator.selectedTimeRange
        self.updateGUI(newCurrent, newRange, false)
    }
    
    /// Move selection start marker to specified anchor point
    public func doSetStart(to anchor : anchor) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let current : CMTime = mutator.insertionTime
        let start : CMTime = mutator.selectedTimeRange.start
        let end : CMTime = mutator.selectedTimeRange.end
        let duration : CMTime = mutator.movieDuration()
        var newRange : CMTimeRange = mutator.selectedTimeRange
        
        switch anchor {
        case .headOrCurrent :
            if start != CMTime.zero {
                newRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: end)
            } else {
                fallthrough
            }
        case .current :
            if current < end {
                newRange = CMTimeRangeFromTimeToTime(start: current, end: end)
            } else {
                newRange = CMTimeRangeFromTimeToTime(start: current, end: current)
            }
        case .head :
            newRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: end)
        case .end :
            newRange = CMTimeRangeFromTimeToTime(start: end, end: end)
        case .tail :
            newRange = CMTimeRangeFromTimeToTime(start: duration, end: duration)
        default:
            NSSound.beep()
            return
        }
        
        updateTimeline(current, range: newRange)
    }
    
    /// Move selection end marker to specified anchor point
    public func doSetEnd(to anchor : anchor) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        let current : CMTime = mutator.insertionTime
        let start : CMTime = mutator.selectedTimeRange.start
        let end : CMTime = mutator.selectedTimeRange.end
        let duration : CMTime = mutator.movieDuration()
        var newRange : CMTimeRange = mutator.selectedTimeRange
        
        switch anchor {
        case .tailOrCurrent :
            if end != duration {
                newRange = CMTimeRangeFromTimeToTime(start: start, end: duration)
            } else {
                fallthrough
            }
        case .current :
            if start < current {
                newRange = CMTimeRangeFromTimeToTime(start: start, end: current)
            } else {
                newRange = CMTimeRangeFromTimeToTime(start: current, end: current)
            }
        case .head :
            newRange = CMTimeRangeFromTimeToTime(start: CMTime.zero, end: CMTime.zero)
        case .start :
            newRange = CMTimeRangeFromTimeToTime(start: start, end: start)
        case .tail:
            newRange = CMTimeRangeFromTimeToTime(start: start, end: duration)
        default:
            NSSound.beep()
            return
        }
        
        updateTimeline(current, range: newRange)
    }
}
