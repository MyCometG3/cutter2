//
//  Document+TimelineUpdateDelegate.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - TimelineUpdateDelegate Protocol
/* ============================================ */

extension Document: TimelineUpdateDelegate {
    
    /// Updates the insertion marker from a relative timeline position.
    ///
    /// - Parameter position: The relative movie position from 0.0 to 1.0.
    public func didUpdateCursor(to position: Float64) {
        
        guard let mutator = self.movieMutator else { return }
        let time: CMTime = quantize(position)
        updateGUI(time, mutator.selectedTimeRange, false)
    }
    
    /// Updates the selection start marker from a relative timeline position.
    ///
    /// - Parameter position: The relative movie position from 0.0 to 1.0.
    public func didUpdateStart(to position: Float64) {
        
        guard let mutator = self.movieMutator else { return }
        let fromTime: CMTime = quantize(position)
        let toTime: CMTime = mutator.selectedTimeRange.end
        let newRange = CMTimeRangeFromTimeToTime(start: fromTime, end: toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// Updates the selection end marker from a relative timeline position.
    ///
    /// - Parameter position: The relative movie position from 0.0 to 1.0.
    public func didUpdateEnd(to position: Float64) {
        
        guard let mutator = self.movieMutator else { return }
        let fromTime: CMTime = mutator.selectedTimeRange.start
        let toTime: CMTime = quantize(position)
        let newRange = CMTimeRangeFromTimeToTime(start: fromTime, end: toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// Updates the selection range from two relative timeline positions.
    ///
    /// - Parameters:
    ///   - fromPos: The relative selection start position from 0.0 to 1.0.
    ///   - toPos: The relative selection end position from 0.0 to 1.0.
    public func didUpdateSelection(from fromPos: Float64, to toPos: Float64) {
        
        guard let mutator = self.movieMutator else { return }
        let fromTime: CMTime = quantize(fromPos)
        let toTime: CMTime = quantize(toPos)
        let newRange = CMTimeRangeFromTimeToTime(start: fromTime, end: toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// Returns presentation information at a relative movie position.
    ///
    /// - Parameter position: The relative movie position from 0.0 to 1.0.
    /// - Returns: Presentation information, or `nil` when no movie mutator is available.
    public func presentationInfo(at position: Float64) -> PresentationInfo? {
        
        guard let mutator = self.movieMutator else { return nil }
        return mutator.presentationInfoAtPosition(position)
    }
    
    /// Returns presentation information for the sample immediately before a range.
    ///
    /// - Parameter range: The range whose preceding sample is requested.
    /// - Returns: Presentation information, or `nil` when no preceding sample is available.
    public func previousInfo(of range: CMTimeRange) -> PresentationInfo? {
        
        guard let mutator = self.movieMutator else { return nil }
        return mutator.previousInfo(of: range)
    }
    
    /// Returns presentation information for the sample immediately after a range.
    ///
    /// - Parameter range: The range whose following sample is requested.
    /// - Returns: Presentation information, or `nil` when no following sample is available.
    public func nextInfo(of range: CMTimeRange) -> PresentationInfo? {
        
        guard let mutator = self.movieMutator else { return nil }
        return mutator.nextInfo(of: range)
    }
    
    /// Moves the current marker to the specified anchor and updates the timeline.
    ///
    /// - Parameter anchor: The anchor describing the destination.
    public func doSetCurrent(to anchor: anchor) {
        
        guard let mutator = self.movieMutator else { return }
        let current: CMTime = mutator.insertionTime
        let start: CMTime = mutator.selectedTimeRange.start
        let end: CMTime = mutator.selectedTimeRange.end
        let duration: CMTime = mutator.movieDuration()
        
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
        
        let newCurrent: CMTime = mutator.insertionTime
        let newRange: CMTimeRange = mutator.selectedTimeRange
        self.updateGUI(newCurrent, newRange, false)
    }
    
    /// Moves the selection start marker to the specified anchor and updates the timeline.
    ///
    /// - Parameter anchor: The anchor describing the destination.
    public func doSetStart(to anchor: anchor) {
        
        guard let mutator = self.movieMutator else { return }
        let current: CMTime = mutator.insertionTime
        let start: CMTime = mutator.selectedTimeRange.start
        let end: CMTime = mutator.selectedTimeRange.end
        let duration: CMTime = mutator.movieDuration()
        var newRange: CMTimeRange = mutator.selectedTimeRange
        
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
    
    /// Moves the selection end marker to the specified anchor and updates the timeline.
    ///
    /// - Parameter anchor: The anchor describing the destination.
    public func doSetEnd(to anchor: anchor) {
        
        guard let mutator = self.movieMutator else { return }
        let current: CMTime = mutator.insertionTime
        let start: CMTime = mutator.selectedTimeRange.start
        let end: CMTime = mutator.selectedTimeRange.end
        let duration: CMTime = mutator.movieDuration()
        var newRange: CMTimeRange = mutator.selectedTimeRange
        
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
