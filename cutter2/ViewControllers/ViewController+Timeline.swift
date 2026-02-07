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
    
    public func didUpdateCursor(to position: Float64) {
        guard let document = delegate else { return }
        document.didUpdateCursor(to: position)
    }
    
    public func didUpdateStart(to position: Float64) {
        guard let document = delegate else { return }
        if followSelectionMove {
            document.didUpdateCursor(to: position)
            document.didUpdateStart(to: position)
        } else {
            document.didUpdateStart(to: position)
        }
    }
    
    public func didUpdateEnd(to position: Float64) {
        guard let document = delegate else { return }
        if followSelectionMove {
            document.didUpdateCursor(to: position)
            document.didUpdateEnd(to: position)
        } else {
            document.didUpdateEnd(to: position)
        }
    }
    
    public func didUpdateSelection(from fromPos: Float64, to toPos: Float64) {
        guard let document = delegate else { return }
        if fromPos == toPos && followSelectionMove {
            document.didUpdateCursor(to: fromPos)
            document.didUpdateSelection(from: fromPos, to: toPos)
        } else {
            document.didUpdateSelection(from: fromPos, to: toPos)
        }
    }
    
    public func presentationInfo(at position: Float64) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.presentationInfo(at: position)
    }
    
    public func previousInfo(of range: CMTimeRange) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.previousInfo(of: range)
    }
    
    public func nextInfo(of range: CMTimeRange) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.nextInfo(of: range)
    }
    
    public func doSetCurrent(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetCurrent(to: goTo)
    }
    
    public func doSetStart(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetStart(to: goTo)
    }
    
    public func doSetEnd(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetEnd(to: goTo)
    }
}
