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
    
    /// Returns the marker currently selected in the timeline.
    ///
    /// - Returns: The selected marker, or `.none` when no known marker is selected.
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
    
    /// Updates the current, start, and end marker positions and validity state.
    ///
    /// If any position is NaN, all marker positions are reset to zero and the timeline
    /// is marked invalid. A valid timeline with no selected marker selects the current
    /// marker automatically.
    ///
    /// - Parameters:
    ///   - curPosition: The current marker position as a relative value from 0.0 to 1.0.
    ///   - startPosition: The selection start position as a relative value from 0.0 to 1.0.
    ///   - endPosition: The selection end position as a relative value from 0.0 to 1.0.
    ///   - valid: Whether the supplied timeline state is valid.
    /// - Returns: `true` when the timeline state changed; otherwise, `false`.
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
    
    /// Updates the timeline's time label when the label layer has been initialized.
    ///
    /// - Parameter newLabel: The string to display in the time label.
    public func updateTimeLabel(to newLabel: String) {
        if let timeLabel = timeLabel {
            timeLabel.string = newLabel
        }
    }
    
    /* ============================================ */
    // MARK: - Utilities
    /* ============================================ */
    
    /// Quantizes a relative position to the nearest sample time-range boundary.
    ///
    /// - Parameter input: The relative position to quantize.
    /// - Returns: The nearest sample boundary, or `input` when sample information is unavailable.
    func quantize(_ input :Float64) -> Float64 {
        guard let vc = delegate, let info = vc.presentationInfo(at: input) else { return input }
        guard (info.endPosition - info.startPosition) > 0 else { return input }
        
        let ratio: Float64 = (input - info.startPosition) / (info.endPosition - info.startPosition)
        return (ratio < 0.5) ? info.startPosition : info.endPosition
    }
    
    /// Converts a mouse click event to a relative timeline position.
    ///
    /// - Parameters:
    ///   - event: The mouse event whose location is converted.
    ///   - toGrid: Whether to quantize the position to a sample time-range boundary.
    /// - Returns: A clamped relative position from 0.0 to 1.0.
    func position(from event: NSEvent, snap toGrid: Bool) -> Float64 {
        let point = self.convert(event.locationInWindow, from: nil)
        let width: CGFloat = self.bounds.width - (leftMargin + rightMargin)
        var pos: Float64 = Float64((point.x - leftMargin) / width)
        pos = min(max(pos, 0.0), 1.0) // clamp(x, a, b)
        return (toGrid ? quantize(pos) : pos)
    }
    
    /// Converts a relative timeline position to a point in the timeline view.
    ///
    /// - Parameter position: The relative timeline position.
    /// - Returns: A point on the timeline corresponding to `position`.
    func point(of position: Float64) -> CGPoint {
        let width: CGFloat = self.bounds.width - (leftMargin + rightMargin)
        let x: CGFloat = leftMargin + width * CGFloat(position)
        let y: CGFloat = self.bounds.height / 2
        let point = CGPoint(x: x, y: y)
        return point
    }
}
