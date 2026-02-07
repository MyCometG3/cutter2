//
//  TimelineView+Utilities.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

extension TimelineView {
    
    /* ============================================ */
    // MARK: - Utilities public
    /* ============================================ */
    
    public func marker() -> marker {
        guard let selectedMarker = selectedMarker else { return .none }
        guard let cMark = currentMarker else { return .none }
        guard let sMark = startMarker else { return .none }
        guard let eMark = endMarker else { return .none }
        
        switch selectedMarker {
        case cMark:
            return .current
        case sMark:
            return .start
        case eMark:
            return .end
        default:
            return .none
        }
    }
    
    /// Update 3 marker positions
    public func updateTimeline(current curPosition: Float64,
                               from startPosition: Float64,
                               to endPosition: Float64,
                               isValid valid: Bool) -> Bool {
        // Check if update is not required
        if (self.currentPosition == curPosition &&
            self.startPosition == startPosition &&
            self.endPosition == endPosition &&
            self.isValid == valid) {
            return false
        }
        
        //
        if !valid && marker() != .none {
            _ = unselectMarker()
        }
        
        // Check if either value is NaN
        if curPosition.isNaN || startPosition.isNaN || endPosition.isNaN {
            self.isValid = false
            self.currentPosition = 0.0
            self.startPosition = 0.0
            self.endPosition = 0.0
            return true
        }
        
        // select current marker if none is selected
        if valid && marker() == .none {
            if let cur = self.currentMarker {
                _ = selectNewMarker(cur)
            }
        }
        
        // update as is
        self.isValid = valid
        self.currentPosition = curPosition
        self.startPosition = startPosition
        self.endPosition = endPosition
        return true
    }
    
    /// Update Time label string
    public func updateTimeLabel(to newLabel: String) {
        if let timeLabel = timeLabel {
            timeLabel.string = newLabel
        }
    }
    
    /* ============================================ */
    // MARK: - Utilities
    /* ============================================ */
    
    /// Quantize position to the sample timerange boundary
    ///
    /// - Parameter input: position in Float64
    /// - Returns: quantized position in Float64
    func quantize(_ input :Float64) -> Float64 {
        guard let vc = delegate, let info = vc.presentationInfo(at: input) else { return input }
        
        let ratio: Float64 = (input - info.startPosition) / (info.endPosition - info.startPosition)
        return (ratio < 0.5) ? info.startPosition : info.endPosition
    }
    
    /// Convert mouse click event to position value in timeLine
    ///
    /// - Parameters:
    ///   - event: mouse event
    ///   - toGrid: set true to quantize
    /// - Returns: position in Float64
    func position(from event: NSEvent, snap toGrid: Bool) -> Float64 {
        let point = self.convert(event.locationInWindow, from: nil)
        let width: CGFloat = self.bounds.width - (leftMargin + rightMargin)
        var pos: Float64 = Float64((point.x - leftMargin) / width)
        pos = min(max(pos, 0.0), 1.0) // clamp(x, a, b)
        return (toGrid ? quantize(pos) : pos)
    }
    
    /// Convert position value in timeLine to point
    ///
    /// - Parameter position: position in timeLine
    /// - Returns: CGPoint on timeLine relative to position value
    func point(of position: Float64) -> CGPoint {
        let width: CGFloat = self.bounds.width - (leftMargin + rightMargin)
        let x: CGFloat = leftMargin + width * CGFloat(position)
        let y: CGFloat = self.bounds.height / 2
        let point = CGPoint(x: x, y: y)
        return point
    }
}
