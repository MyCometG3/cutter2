//
//  TimelineView.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/21.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

public extension NSBezierPath {
    /// Translate NSBezierPath to CGPath
    public var cgPath: CGPath {
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
}
        }
        return path
    }
}

/// View to ViewController - Mouse Event related protocol (No CMTime)
protocol TimelineUpdateDelegate : class {
    // called on mouse down/drag event
    func didUpdateCursor(to position : Float64)
    func didUpdateStart(to position : Float64)
    func didUpdateEnd(to position : Float64)
    func didUpdateSelection(from fromPos : Float64, to toPos : Float64)
    //
    func presentationInfo(at position : Float64) -> PresentationInfo?
    func previousInfo(of range: CMTimeRange) -> PresentationInfo?
    func nextInfo(of range: CMTimeRange) -> PresentationInfo?
    //
    func doSetCurrent(to goTo : anchor)
    func doSetStart(to goTo : anchor)
    func doSetEnd(to goTo : anchor)
}

/// Anchor Position definition
///
/// - current: insertion marker
/// - head: head of movie
/// - start: start of selection
/// - end: end of selection
/// - tail: tail of movie
/// - startOrHead: toggle anchor for CurrentMarker
/// - endOrTail: toggle anchor for CurrentMakrer
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
    case endOrTail // for current makrer
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

class TimelineView: NSView, CALayerDelegate {
    /// Delegate object which conforms TimelineUpdateDelegate protocol
    public weak var delegate : TimelineUpdateDelegate? = nil
    
    /// Recalculate Mouse Tracking Area on Window resize event
    public var needsUpdateTrackingArea : Bool = false
    
    /// Update 3 marker positions
    public func updateTimeline(current curPosition : Float64,
                               from startPosition : Float64,
                               to endPosition : Float64,
                               isValid valid : Bool) -> Bool {
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
    public func updateTimeLabel(to newLabel : String) {
        if let timeLabel = timeLabel {
            timeLabel.string = newLabel
        }
    }
    
    /* ============================================ */
    // MARK: - private var for ViewController
    /* ============================================ */
    
    // data model
    private var currentPosition : Float64 = 0.0
    private var startPosition : Float64 = 0.0
    private var endPosition : Float64 = 0.0
    
    // CATextLayer
    private var timeLabel : CATextLayer? = nil
    
    // CAShapeLayer
    private var isValid : Bool = false
    private var currentMarker : CAShapeLayer? = nil
    private var startMarker : CAShapeLayer? = nil
    private var endMarker : CAShapeLayer? = nil
    private var selection : CAShapeLayer? = nil
    private var timeline : CAShapeLayer? = nil
    private weak var selectedMarker : CAShapeLayer? = nil
    
    // visual constants
    private let leftMargin : CGFloat = 75.0
    private let rightMargin : CGFloat = 12.0
    private let labelWidth : CGFloat = 72.0
    private let labelHeight : CGFloat = 14.0
    private let wUnit : CGFloat = 8.0
    private let hUnit : CGFloat = 8.0
    private let strokeColorActive : CGColor = NSColor.black.cgColor
    private let fillColorActive : CGColor = NSColor.red.cgColor
    private let strokeColorInactive : CGColor = NSColor.gray.cgColor
    private let fillColorInactive : CGColor = NSColor.lightGray.cgColor
    private var backGroundColor : CGColor {
        if #available(OSX 10.14, *) {
            return NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
        } else {
            return NSColor.controlColor.cgColor
        }
    }
    private var labelColor : CGColor {
        if #available(OSX 10.14, *) {
            return NSColor.unemphasizedSelectedTextColor.cgColor
        } else {
            return NSColor.darkGray.cgColor
        }
    }

    // NSView Instance Property
    override var mouseDownCanMoveWindow: Bool { return false }
    
    /* ============================================ */
    // MARK: - NSView methods
    /* ============================================ */
    
    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        self.wantsLayer = true
        
        setupLabel()
        setupSublayer()
        needsUpdateTrackingArea = true // setupTrackingArea()
    }
    
    override func layout() {
        // Swift.print(#function, #line, #file)
        
        // dark mode support
        if let layer = self.layer {
            layer.backgroundColor = backGroundColor
        }
        
        // On initial/resized state, update tracking area
        if needsUpdateTrackingArea {
            needsUpdateTrackingArea = false
            
            if !(self.trackingAreas.isEmpty) {
                for area in self.trackingAreas {
                    self.removeTrackingArea(area)
                }
            }
            let area = NSTrackingArea(rect: self.bounds,
                                      options: [.mouseMoved, .activeInKeyWindow],
                                      owner: self,
                                      userInfo: nil)
            self.addTrackingArea(area)
        }
        
        // layout markers/timeline as is
        let currentPoint : CGPoint = point(of: currentPosition)
        let startPoint : CGPoint = point(of: startPosition)
        let endPoint : CGPoint = point(of: endPosition)
        let leftPoint : CGPoint = point(of: 0.0)
        let rightPoint : CGPoint = point(of: 1.0)
        
        // Arrange each Markers
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let cMark = currentMarker {
            let curRect : CGRect = cMark.frame
            let newRect : CGRect  = CGRect(x: currentPoint.x - (curRect.width / 2.0),
                                           y: currentPoint.y - (hUnit * 0.5),
                                           width: curRect.width,
                                           height: curRect.height)
            cMark.frame = newRect
        }
        if let sMark = startMarker {
            let curRect : CGRect  = sMark.frame
            let newRect : CGRect  = CGRect(x: startPoint.x - curRect.width,
                                           y: startPoint.y - (hUnit * 0.5 + curRect.height),
                                           width: curRect.width,
                                           height: curRect.height)
            sMark.frame = newRect
        }
        if let eMark = endMarker {
            let curRect : CGRect  = eMark.frame
            let newRect : CGRect  = CGRect(x: endPoint.x,
                                           y: endPoint.y - (hUnit * 0.5 + curRect.height),
                                           width: curRect.width,
                                           height: curRect.height)
            eMark.frame = newRect
        }
        if let sLine = selection {
            let curRect : CGRect = sLine.frame
            let newRect : CGRect  = CGRect(x: startPoint.x,
                                           y: startPoint.y - (hUnit * 0.5),
                                           width: endPoint.x - startPoint.x,
                                           height: curRect.height)
            sLine.path = NSBezierPath(rect: newRect).cgPath
            sLine.bounds = sLine.path!.boundingBox
            sLine.frame = newRect
        }
        if let tLine = timeline {
            let curRect : CGRect = tLine.frame
            let newRect : CGRect = CGRect(x: leftPoint.x,
                                          y: leftPoint.y - (hUnit * 0.5),
                                          width: rightPoint.x - leftPoint.x,
                                          height: curRect.height)
            tLine.path = NSBezierPath(rect: newRect).cgPath
            tLine.bounds = tLine.path!.boundingBox
            tLine.frame = newRect
        }
        if let label = timeLabel {
            let curRect : CGRect = label.frame
            let width = curRect.width
            let height = curRect.height
            label.bounds = label.contentsRect
            let newRect = CGRect(x: (leftMargin-width)/2.0,
                                 y: (self.bounds.height - height)/2,
                                 width: width,
                                 height: height)
            label.frame = newRect
            
            // dark mode support
            label.backgroundColor = backGroundColor
            label.foregroundColor = labelColor
        }
        CATransaction.commit()
        
        super.layout()
    }
    
    /* ============================================ */
    // MARK: - NSLayerDelegateContentsScaleUpdating
    /* ============================================ */
    
    func layer(_ layer: CALayer, shouldInheritContentsScale newScale: CGFloat, from window: NSWindow) -> Bool {
        return true
    }
    
    /* ============================================ */
    // MARK: - Sublayer setup
    /* ============================================ */
    
    /// Prepare CATextLayer
    private func setupLabel() {
        do {
            let label = CATextLayer()
            let fontName : CFString = "Helvetica" as CFString
            label.font = fontName
            label.fontSize = 11.5
            label.alignmentMode = CATextLayerAlignmentMode.center
            label.string = "00:00:00.000"
            label.delegate = self // CATextLayer requires NSLayerDelegateContentsScaleUpdating
            label.bounds = CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight)
            timeLabel = label
        }
        
        if let layer = self.layer {
            layer.addSublayer(timeLabel!)
        }
    }
    
    /// Prepare CAShapeLayer
    private func setupSublayer() {
        // Create current marker (downward triangle)
        do {
            let path = NSBezierPath()
            path.move(to: NSPoint.zero)
            path.relativeLine(to: NSPoint(x: wUnit, y: hUnit))
            path.relativeLine(to: NSPoint(x: -2*wUnit, y: 0.0))
            path.relativeLine(to: NSPoint(x: wUnit, y: -hUnit))
            path.close()
            path.relativeLine(to: NSPoint(x: 0.0, y: -hUnit))
            let shape = CAShapeLayer()
            shape.strokeColor = strokeColorInactive
            shape.fillColor = fillColorInactive
            shape.lineWidth = 1.0
            shape.path = path.cgPath
            shape.bounds = shape.path!.boundingBox
            currentMarker = shape
        }
        
        // Create start marker (right-downward triangle)
        do {
            let path = NSBezierPath()
            path.move(to: NSPoint.zero)
            path.relativeLine(to: NSPoint(x: -wUnit * 1.4, y: 0.0))
            path.relativeLine(to: NSPoint(x: 0.0, y: hUnit * 0.4))
            path.relativeLine(to: NSPoint(x: wUnit * 0.4, y: 0.0))
            path.relativeLine(to: NSPoint(x: wUnit, y: hUnit))
            path.relativeLine(to: NSPoint(x: 0.0, y: -hUnit))
            path.close()
            let shape = CAShapeLayer()
            shape.strokeColor = strokeColorInactive
            shape.fillColor = fillColorInactive
            shape.lineWidth = 1.0
            shape.path = path.cgPath
            shape.bounds = shape.path!.boundingBox
            startMarker = shape
        }
        
        // Create end marker (left-downward triangle)
        do {
            let path = NSBezierPath()
            path.move(to: NSPoint.zero)
            path.relativeLine(to: NSPoint(x: wUnit * 1.4, y: 0.0))
            path.relativeLine(to: NSPoint(x: 0.0, y: hUnit * 0.4))
            path.relativeLine(to: NSPoint(x: -wUnit * 0.4, y:0.0))
            path.relativeLine(to: NSPoint(x: -wUnit, y: hUnit))
            path.relativeLine(to: NSPoint(x: 0.0, y: -hUnit))
            path.close()
            let shape = CAShapeLayer()
            shape.strokeColor = strokeColorInactive
            shape.fillColor = fillColorInactive
            shape.lineWidth = 1.0
            shape.path = path.cgPath
            shape.bounds = shape.path!.boundingBox
            endMarker = shape
        }
        
        // Create timeline
        do {
            let width : CGFloat = self.bounds.width - (leftMargin + rightMargin)
            let height : CGFloat = hUnit
            let xOrigin : CGFloat = leftMargin
            let yOrigin : CGFloat = (self.bounds.height/2.0) - (height/2.0)
            let rect = NSRect(x: xOrigin, y: yOrigin,
                              width: width, height: height)
            let path = NSBezierPath(rect: rect)
            let shape = CAShapeLayer()
            shape.strokeColor = strokeColorInactive
            shape.fillColor = fillColorInactive
            shape.lineWidth = 1.0
            shape.path = path.cgPath
            shape.bounds = shape.path!.boundingBox
            timeline = shape
        }
        
        // Create selection marker (rectangle)
        do {
            let leftMargin : CGFloat = 60.0
            let width : CGFloat = 0.0
            let height : CGFloat = hUnit
            let xOrigin : CGFloat = leftMargin
            let yOrigin : CGFloat = (self.bounds.height/2.0) - (height/2.0)
            let rect = NSRect(x: xOrigin, y: yOrigin,
                              width: width, height: height)
            let path = NSBezierPath(rect: rect)
            let shape = CAShapeLayer()
            shape.strokeColor = NSColor.red.cgColor//strokeColorInactive
            shape.fillColor = fillColorActive
            shape.lineWidth = 1.0
            shape.path = path.cgPath
            shape.bounds = shape.path!.boundingBox
            selection = shape
        }
        
        // markers' position will be udpated in layout()
        if let layer = self.layer {
            layer.addSublayer(timeline!)
            layer.addSublayer(selection!)
            layer.addSublayer(currentMarker!)
            layer.addSublayer(startMarker!)
            layer.addSublayer(endMarker!)
        }
    }
    
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
    
    /* ============================================ */
    // MARK: - Utilities
    /* ============================================ */
    
    /// Quantize position to the sample timerange boundary
    ///
    /// - Parameter input: position in Float64
    /// - Returns: quantized position in Float64
    private func quantize(_ input :Float64) -> Float64 {
        guard let vc = delegate, let info = vc.presentationInfo(at: input) else { return input }
        
        let ratio : Float64 = (input - info.startPosition) / (info.endPosition - info.startPosition)
        return (ratio < 0.5) ? info.startPosition : info.endPosition
    }
    
    /// Convert mouse click event to position value in timeLine
    ///
    /// - Parameters:
    ///   - event: mouse event
    ///   - toGrid: set true to quantize
    /// - Returns: position in Float64
    private func position(from event : NSEvent, snap toGrid : Bool) -> Float64 {
        let point = self.convert(event.locationInWindow, from: nil)
        let width : CGFloat = self.bounds.width - (leftMargin + rightMargin)
        var pos : Float64 = Float64((point.x - leftMargin) / width)
        pos = min(max(pos, 0.0), 1.0) // clamp(x, a, b)
        return (toGrid ? quantize(pos) : pos)
    }
    
    /// Convert position value in timeLine to point
    ///
    /// - Parameter position: position in timeLine
    /// - Returns: CGPoint on timeLine relative to position value
    private func point(of position : Float64) -> CGPoint {
        let width : CGFloat = self.bounds.width - (leftMargin + rightMargin)
        let x : CGFloat = leftMargin + width * CGFloat(position)
        let y : CGFloat = self.bounds.height / 2
        let point = CGPoint(x: x, y: y)
        return point
    }
    
    /* ============================================ */
    // MARK: - Mouse Event support
    /* ============================================ */
    
    /// Activate(Select) specified marker on mouse click
    ///
    /// - Parameter marker: marker to be selected
    /// - Returns: true if marker selection is updated. false if already selected.
    private func selectNewMarker(_ marker : CAShapeLayer) -> Bool {
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
    private func unselectMarker() -> Bool {
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
    private func updateMarkerPosition(_ marker : CAShapeLayer, with event : NSEvent) {
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
    private func resetCurrent(to anchor : anchor) {
        guard let vc = delegate else { NSSound.beep(); return }
        vc.doSetCurrent(to: anchor)
    }
    
    /* ============================================ */
    // MARK: - Mouse Event handling
    /* ============================================ */
    
    override func mouseMoved(with event: NSEvent) {
        //let point = self.convert(event.locationInWindow, from: nil)
        // Swift.print("#####", point, position(from: event))
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        // Swift.print("#####", point, position(from: event))
        
        if let layer = self.layer, let target = layer.hitTest(point) {
            //print (target)
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
    
    override func mouseDragged(with event: NSEvent) {
        // let point = self.convert(event.locationInWindow, to: self)
        // Swift.print("#####", point, position(from: event))
        
        if let marker = selectedMarker {
            updateMarkerPosition(marker, with: event)
        }
    }
    
    /* ============================================ */
    // MARK: - Keyboard Event handling
    /* ============================================ */
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override var canBecomeKeyView: Bool {
        return true
    }
    
    // NOTE: Most key event handler(s) are defined in ViewController.
}
