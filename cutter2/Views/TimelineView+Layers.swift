//
//  TimelineView+Layers.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

@MainActor
extension TimelineView: NSViewLayerContentScaleDelegate {
    
    /* ============================================ */
    // MARK: - NSView methods
    /* ============================================ */
    
    override func layout() {
        super.layout()
        
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
        let currentPoint: CGPoint = point(of: currentPosition)
        let startPoint: CGPoint = point(of: startPosition)
        let endPoint: CGPoint = point(of: endPosition)
        let leftPoint: CGPoint = point(of: 0.0)
        let rightPoint: CGPoint = point(of: 1.0)
        
        // Arrange each Markers
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let cMark = currentMarker {
            let curRect: CGRect = cMark.frame
            let newRect: CGRect  = CGRect(x: currentPoint.x - (curRect.width / 2.0),
                                          y: currentPoint.y - (hUnit * 0.5),
                                          width: curRect.width,
                                          height: curRect.height)
            cMark.frame = newRect
        }
        if let sMark = startMarker {
            let curRect: CGRect  = sMark.frame
            let newRect: CGRect  = CGRect(x: startPoint.x - curRect.width,
                                          y: startPoint.y - (hUnit * 0.5 + curRect.height),
                                          width: curRect.width,
                                          height: curRect.height)
            sMark.frame = newRect
        }
        if let eMark = endMarker {
            let curRect: CGRect  = eMark.frame
            let newRect: CGRect  = CGRect(x: endPoint.x,
                                          y: endPoint.y - (hUnit * 0.5 + curRect.height),
                                          width: curRect.width,
                                          height: curRect.height)
            eMark.frame = newRect
        }
        if let sLine = selection {
            let curRect: CGRect = sLine.frame
            let newRect: CGRect  = CGRect(x: startPoint.x,
                                          y: startPoint.y - (hUnit * 0.5),
                                          width: endPoint.x - startPoint.x,
                                          height: curRect.height)
            sLine.path = NSBezierPath(rect: newRect).cgPath
            sLine.bounds = sLine.path!.boundingBox
            sLine.frame = newRect
        }
        if let tLine = timeline {
            let curRect: CGRect = tLine.frame
            let newRect: CGRect = CGRect(x: leftPoint.x,
                                         y: leftPoint.y - (hUnit * 0.5),
                                         width: rightPoint.x - leftPoint.x,
                                         height: curRect.height)
            tLine.path = NSBezierPath(rect: newRect).cgPath
            tLine.bounds = tLine.path!.boundingBox
            tLine.frame = newRect
        }
        if let label = timeLabel {
            let curRect: CGRect = label.frame
            let width = curRect.width
            let height = curRect.height
            label.bounds = label.contentsRect
            let newRect = CGRect(x: (leftMargin-width)/2.0,
                                 y: (self.bounds.height - height)/2,
                                 width: width,
                                 height: height)
            label.frame = newRect
            
            // dark mode support
            label.foregroundColor = labelColor
            
            // HiDPI support for text rendering
            if let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor {
                if label.contentsScale != scale {
                    label.contentsScale = scale
                }
            }
        }
        CATransaction.commit()
    }
    
    /* ============================================ */
    // MARK: - NSViewLayerContentScaleDelegate
    /* ============================================ */
    
    func layer(_ layer: CALayer, shouldInheritContentsScale newScale: CGFloat, from window: NSWindow) -> Bool {
        return true
    }
    
    /* ============================================ */
    // MARK: - Sublayer setup Private
    /* ============================================ */
    
    /// Prepare CATextLayer
    func setupLabel() {
        do {
            let label = CATextLayer()
            let fontName: CFString = "Helvetica" as CFString
            label.font = fontName
            label.fontSize = 11.5
            label.alignmentMode = CATextLayerAlignmentMode.center
            label.string = "00:00:00.000"
            label.delegate = self // CATextLayer requires NSLayerDelegateContentsScaleUpdating
            label.bounds = CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight)
            timeLabel = label
        }
        
        if let layer = self.layer, let timeLabel = timeLabel {
            layer.addSublayer(timeLabel)
        }
    }
    
    /// Prepare CAShapeLayer
    func setupSublayer() {
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
            shape.bounds = path.cgPath.boundingBox
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
            shape.bounds = path.cgPath.boundingBox
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
            shape.bounds = path.cgPath.boundingBox
            endMarker = shape
        }
        
        // Create timeline
        do {
            let width: CGFloat = self.bounds.width - (leftMargin + rightMargin)
            let height: CGFloat = hUnit
            let xOrigin: CGFloat = leftMargin
            let yOrigin: CGFloat = (self.bounds.height/2.0) - (height/2.0)
            let rect = NSRect(x: xOrigin, y: yOrigin,
                              width: width, height: height)
            let path = NSBezierPath(rect: rect)
            let shape = CAShapeLayer()
            shape.strokeColor = strokeColorInactive
            shape.fillColor = fillColorInactive
            shape.lineWidth = 1.0
            shape.path = path.cgPath
            shape.bounds = path.cgPath.boundingBox
            timeline = shape
        }
        
        // Create selection marker (rectangle)
        do {
            let leftMargin: CGFloat = 60.0
            let width: CGFloat = 0.0
            let height: CGFloat = hUnit
            let xOrigin: CGFloat = leftMargin
            let yOrigin: CGFloat = (self.bounds.height/2.0) - (height/2.0)
            let rect = NSRect(x: xOrigin, y: yOrigin,
                              width: width, height: height)
            let path = NSBezierPath(rect: rect)
            let shape = CAShapeLayer()
            shape.strokeColor = strokeColorInactive
            shape.fillColor = fillColorActive
            shape.lineWidth = 1.0
            shape.path = path.cgPath
            shape.bounds = path.cgPath.boundingBox
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
}
