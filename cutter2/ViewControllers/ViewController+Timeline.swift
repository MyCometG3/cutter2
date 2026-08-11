//
//  ViewController+Timeline.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - TimelineUpdateDelegate
/* ============================================ */

extension ViewController {
    
    /// Forwards a current-marker update to the document delegate.
    ///
    /// - Parameter position: The relative position from 0.0 to 1.0.
    public func didUpdateCursor(to position: Float64) {
        guard let document = delegate else { return }
        document.didUpdateCursor(to: position)
    }
    
    /// Forwards a selection-start update and optionally moves the current marker with it.
    ///
    /// - Parameter position: The relative position from 0.0 to 1.0.
    public func didUpdateStart(to position: Float64) {
        guard let document = delegate else { return }
        if followSelectionMove {
            document.didUpdateCursor(to: position)
            document.didUpdateStart(to: position)
        } else {
            document.didUpdateStart(to: position)
        }
    }
    
    /// Forwards a selection-end update and optionally moves the current marker with it.
    ///
    /// - Parameter position: The relative position from 0.0 to 1.0.
    public func didUpdateEnd(to position: Float64) {
        guard let document = delegate else { return }
        if followSelectionMove {
            document.didUpdateCursor(to: position)
            document.didUpdateEnd(to: position)
        } else {
            document.didUpdateEnd(to: position)
        }
    }
    
    /// Forwards a selection-range update and synchronizes the current marker when configured.
    ///
    /// - Parameters:
    ///   - fromPos: The selection start position from 0.0 to 1.0.
    ///   - toPos: The selection end position from 0.0 to 1.0.
    public func didUpdateSelection(from fromPos: Float64, to toPos: Float64) {
        guard let document = delegate else { return }
        if fromPos == toPos && followSelectionMove {
            document.didUpdateCursor(to: fromPos)
            document.didUpdateSelection(from: fromPos, to: toPos)
        } else {
            document.didUpdateSelection(from: fromPos, to: toPos)
        }
    }
    
    /// Returns presentation information from the document delegate at a relative position.
    ///
    /// - Parameter position: The relative movie position from 0.0 to 1.0.
    /// - Returns: Presentation information, or `nil` when the document delegate is unavailable.
    public func presentationInfo(at position: Float64) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.presentationInfo(at: position)
    }
    
    /// Returns the presentation information immediately before a time range.
    ///
    /// - Parameter range: The range whose preceding sample is requested.
    /// - Returns: Presentation information, or `nil` when no preceding sample is available.
    public func previousInfo(of range: CMTimeRange) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.previousInfo(of: range)
    }
    
    /// Returns the presentation information immediately after a time range.
    ///
    /// - Parameter range: The range whose following sample is requested.
    /// - Returns: Presentation information, or `nil` when no following sample is available.
    public func nextInfo(of range: CMTimeRange) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.nextInfo(of: range)
    }
    
    /// Moves the current marker to an anchor through the document delegate.
    ///
    /// - Parameter goTo: The anchor describing the destination.
    public func doSetCurrent(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetCurrent(to: goTo)
    }
    
    /// Moves the selection start marker to an anchor through the document delegate.
    ///
    /// - Parameter goTo: The anchor describing the destination.
    public func doSetStart(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetStart(to: goTo)
    }
    
    /// Moves the selection end marker to an anchor through the document delegate.
    ///
    /// - Parameter goTo: The anchor describing the destination.
    public func doSetEnd(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetEnd(to: goTo)
    }
}
