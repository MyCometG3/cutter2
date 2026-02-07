//
//  TimelineView+Input.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

extension TimelineView {
    
    /* ============================================ */
    // MARK: - Mouse Event
    /* ============================================ */
    
    // NSView Instance Property
    override var mouseDownCanMoveWindow: Bool { return false }
    
    /// Activate(Select) specified marker on mouse click
    ///
    /// - Parameter marker: marker to be selected
    /// - Returns: true if marker selection is updated. false if already selected.
    func selectNewMarker(_ marker: CAShapeLayer) -> Bool {
        // called on mouse down event
        guard let cMark = currentMarker else { return false }
        guard let sMark = startMarker, let eMark = endMarker else { return false }
        guard let sLine = selection, let tLine = timeline else { return false }
        
        var marker = marker // mutable copy
        if marker == sLine || marker == tLine {
            marker = cMark
        }
        if selectedMarker == marker {
            // Same marker - no selection change
            return false
        } else {
            // Different marker - change marker selection
            switch marker {
            case sMark:
                fallthrough
            case eMark:
                fallthrough
            case cMark:
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                cMark.strokeColor = strokeColorInactive
                cMark.fillColor = fillColorInactive
                sMark.strokeColor = strokeColorInactive
                sMark.fillColor = fillColorInactive
                eMark.strokeColor = strokeColorInactive
                eMark.fillColor = fillColorInactive
                marker.strokeColor = strokeColorActive
                marker.fillColor = fillColorActive
                CATransaction.commit()
                
                selectedMarker = marker
                self.needsLayout = true
            default:
                break // keep selectedMarker here
            }
            return true
        }
    }
    
    /// Inactivate(unselect) selected marker
    ///
    /// - Returns: true if marker selection is updated.
    func unselectMarker() -> Bool {
        guard let cMark = currentMarker else { return false }
        guard let sMark = startMarker, let eMark = endMarker else { return false }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cMark.strokeColor = strokeColorInactive
        cMark.fillColor = fillColorInactive
        sMark.strokeColor = strokeColorInactive
        sMark.fillColor = fillColorInactive
        eMark.strokeColor = strokeColorInactive
        eMark.fillColor = fillColorInactive
        CATransaction.commit()
        
        selectedMarker = nil
        self.needsLayout = true
        
        return true
    }
    
    /// Update marker position according to mouse event
    ///
    /// - Parameters:
    ///   - marker: target marker to move
    ///   - event: NSEvent of mouse click/drag
    private func updateMarkerPosition(_ marker: CAShapeLayer, with event: NSEvent) {
        // called on mouse down/drag event
        guard let vc = delegate else { NSSound.beep(); return }
        guard let cMark = currentMarker else { return }
        guard let sMark = startMarker, let eMark = endMarker else { return }
        guard let sLine = selection, let tLine = timeline else { return }
        
        let position = self.position(from: event, snap: true)
        switch marker {
        case sLine:
            fallthrough
        case tLine:
            fallthrough
        case cMark:
            currentPosition = position
            vc.didUpdateCursor(to: currentPosition)
            self.needsLayout = true
        case sMark:
            startPosition = position
            if startPosition > endPosition {
                endPosition = startPosition
                vc.didUpdateSelection(from: startPosition,
                                      to: endPosition)
            } else {
                vc.didUpdateStart(to: startPosition)
            }
            self.needsLayout = true
        case eMark:
            endPosition = position
            if startPosition > endPosition {
                startPosition = endPosition
                vc.didUpdateSelection(from: startPosition,
                                      to: endPosition)
            } else {
                vc.didUpdateEnd(to: endPosition)
            }
            self.needsLayout = true
        default:
            break
        }
    }
    
    /// Sync insertion marker to selection marker start/end
    ///
    /// - Parameter anchor: target marker
    private func resetCurrent(to anchor: anchor) {
        guard let vc = delegate else { NSSound.beep(); return }
        vc.doSetCurrent(to: anchor)
    }
    
    /* ============================================ */
    // MARK: - Mouse Event handling
    /* ============================================ */
    
    // NSResponder
    override func mouseMoved(with event: NSEvent) {
        //let point = self.convert(event.locationInWindow, from: nil)
    }
    
    // NSResponder
    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        
        if let layer = self.layer, let target = layer.hitTest(point) {
            if let shapeLayer = target as? CAShapeLayer {
                // Update selected marker
                if selectNewMarker(shapeLayer) == false {
                    updateMarkerPosition(shapeLayer, with: event)
                } else {
                    switch marker() {
                    case .start:
                        resetCurrent(to: .start)
                    case .end:
                        resetCurrent(to: .end)
                    default:
                        break
                    }
                    
                }
            }
        }
    }
    
    // NSResponder
    override func mouseDragged(with event: NSEvent) {
        // let point = self.convert(event.locationInWindow, to: self)
        
        if let marker = selectedMarker {
            updateMarkerPosition(marker, with: event)
        }
    }
    
    /* ============================================ */
    // MARK: - Keyboard Event handling
    /* ============================================ */
    
    // NSResponder
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    // NSResponder
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    // NSResponder
    override func resignFirstResponder() -> Bool {
        return false
    }
    
    // NSView(NSKeyboardUI)
    override var canBecomeKeyView: Bool {
        return true
    }
    
    // NOTE: Most key event handler(s) are defined in ViewController.
}
