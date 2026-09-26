//
//  TimelineView.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/21.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

public extension NSBezierPath {
    /// Translate NSBezierPath to CGPath
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0 ..< self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                NSSound.beep()
                break
            }
        }
        return path
    }
}

/// Provides relative-position timeline events and sample navigation to a view controller.
///
/// All positions are relative values from 0.0 to 1.0. Implementations may update
/// document state or return `nil` when sample information is unavailable.
@MainActor
protocol TimelineUpdateDelegate: AnyObject {
    /// Reports a change to the current marker position.
    func didUpdateCursor(to position: Float64)
    /// Reports a change to the selection start position.
    func didUpdateStart(to position: Float64)
    /// Reports a change to the selection end position.
    func didUpdateEnd(to position: Float64)
    /// Reports a change to the selection range.
    func didUpdateSelection(from fromPos: Float64, to toPos: Float64)
    /// Returns sample presentation information at a relative position, if available.
    func presentationInfo(at position: Float64) -> PresentationInfo?
    /// Returns the presentation information immediately before a range, if available.
    func previousInfo(of range: CMTimeRange) -> PresentationInfo?
    /// Returns the presentation information immediately after a range, if available.
    func nextInfo(of range: CMTimeRange) -> PresentationInfo?
    /// Moves the current marker to the specified anchor.
    func doSetCurrent(to goTo: anchor)
    /// Moves the selection start marker to the specified anchor.
    func doSetStart(to goTo: anchor)
    /// Moves the selection end marker to the specified anchor.
    func doSetEnd(to goTo: anchor)
}

/// Anchor Position definition
///
/// - current: insertion marker
/// - head: head of movie
/// - start: start of selection
/// - end: end of selection
/// - tail: tail of movie
/// - startOrHead: toggle anchor for CurrentMarker
/// - endOrTail: toggle anchor for CurrentMarker
/// - headOrCurrent: toggle anchor for StartMarker
/// - tailOrCurrent: toggle anchor for EndMarker
/// - forward: seek forward anchor
/// - backward: seek backward anchor
enum anchor {
    case current
    case head
    case start
    case end
    case tail
    case startOrHead // for current marker
    case endOrTail // for current marker
    case headOrCurrent // for start marker
    case tailOrCurrent // for end marker
    case forward
    case backward
}

/// Selected marker
///
/// - current: insertion marker
/// - start: start of selection
/// - end: end of selection
/// - none: none
enum marker {
    case current
    case start
    case end
    case none
}

@MainActor
class TimelineView: NSView, CALayerDelegate {
    
    /* ============================================ */
    // MARK: - Properties
    /* ============================================ */
    
    /// Delegate object which conforms TimelineUpdateDelegate protocol
    public weak var delegate: TimelineUpdateDelegate? = nil
    
    /// Recalculate Mouse Tracking Area on Window resize event
    public var needsUpdateTrackingArea: Bool = false
    
    /// Choose visual appearance
    public var jklMode: Bool = false {
        didSet {
            selectedMarker?.fillColor = fillColorActive
            selection?.fillColor = fillColorActive
        }
    }
    
    /* ============================================ */
    // MARK: - State for ViewController
    /* ============================================ */
    
    // data model
    var currentPosition: Float64 = 0.0
    var startPosition: Float64 = 0.0
    var endPosition: Float64 = 0.0
    
    // CATextLayer
    var timeLabel: CATextLayer? = nil
    
    // CAShapeLayer
    var isValid: Bool = false
    var currentMarker: CAShapeLayer? = nil
    var startMarker: CAShapeLayer? = nil
    var endMarker: CAShapeLayer? = nil
    var selection: CAShapeLayer? = nil
    var timeline: CAShapeLayer? = nil
    weak var selectedMarker: CAShapeLayer? = nil
    
    // visual constants
    let leftMargin: CGFloat = 75.0
    let rightMargin: CGFloat = 12.0
    let labelWidth: CGFloat = 72.0
    let labelHeight: CGFloat = 14.0
    let wUnit: CGFloat = 8.0
    let hUnit: CGFloat = 8.0
    let strokeColorActive: CGColor = NSColor.black.cgColor
    var fillColorActive: CGColor {
        if jklMode {
            return NSColor.blue.cgColor
        } else {
            return NSColor.red.cgColor
        }
    }
    let strokeColorInactive: CGColor = NSColor.gray.cgColor
    let fillColorInactive: CGColor = NSColor.lightGray.cgColor
    var labelColor: CGColor = NSColor.unemphasizedSelectedTextColor.cgColor
    
    /* ============================================ */
    // MARK: - NSView methods
    /* ============================================ */
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initializeLayers()
    }
    
    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        initializeLayers()
    }
    
    private func initializeLayers() {
        self.wantsLayer = true
        
        setupLabel()
        setupSublayer()
        needsUpdateTrackingArea = true
    }
}
