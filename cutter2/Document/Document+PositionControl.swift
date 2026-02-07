//
//  Document+PositionControl.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: -  Position control
/* ============================================ */

extension Document {
    
    /// Move either start/end marker at current marker (nearest marker do sync)
    public func syncSelection(_ current: CMTime) {
        
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
        
        guard let player = self.player else { return false }
        
        // NOTE: Return false if player is not paused.
        if player.rate != 0.0 { return false }
        
        let current = player.currentTime()
        if current == CMTime.zero {
            return true
        }
        return false
    }
    
    private func debugTrackRange(_ range: CMTimeRange, _ current: CMTime, _ endOfRange: Bool) {
        #if DEBUG
        guard let mutator = self.movieMutator else { return }
        let rangeStart = String(format: "%4.3f", range.start.seconds)
        let rangeEnd = String(format: "%4.3f", range.end.seconds)
        let currentStr = String(format: "%4.3f", current.seconds)
        let insertionStr = String(format: "%4.3f", mutator.insertionTime.seconds)
        let timeDiff = current == mutator.insertionTime ? "" : " (diff)"
        let contains = (range.start <= current && current <= range.end)
        let endNote = endOfRange ? " - End of Movie" : ""
        
        LoggingSystem.video.debug("Track range: [\(rangeStart), \(rangeEnd)], current: \(currentStr), insertion: \(insertionStr)\(timeDiff), containsTime: \(contains)\(endNote)")
        #endif
    }
    
    /// Check if it is tail of movie
    public func checkTailOfMovie() -> Bool {
        
        guard let mutator = self.movieMutator else { return false }
        guard let player = self.player else { return false }
        
        // NOTE: Return false if player is not paused.
        if player.rate != 0.0 { return false }
        
        let current = player.currentTime()
        let duration: CMTime = mutator.movieDuration()
        
        // validate cached range value
        if let range = cachedLastSampleRange, range.start <= current, current <= range.end {
            // use cached result
            // debugTrackRange(range, current, true)
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
                // debugTrackRange(info.timeRange, current, endOfRange)
            }
            return cachedWithinLastSampleRange
        }
    }
    
    /// Snap to grid - Adjust Timeline resolution
    public func quantize(_ position: Float64) -> CMTime {
        
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
