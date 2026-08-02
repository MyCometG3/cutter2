//
//  TimelineViewRenderingTests.swift
//  cutter2Tests
//

import XCTest
import Cocoa
import AVFoundation
@testable import cutter2

@MainActor
final class TimelineViewRenderingTests: XCTestCase {
    private var timelineView: TimelineView!
    
    override func setUp() async throws {
        try await super.setUp()
        timelineView = TimelineView(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
    }
    
    override func tearDown() async throws {
        timelineView = nil
        try await super.tearDown()
    }
    
    func testPointOfPosition_CalculatesCorrectX() {
        let point = timelineView.point(of: 0.5)
        let width = timelineView.bounds.width - timelineView.leftMargin - timelineView.rightMargin
        let expectedX = timelineView.leftMargin + width * 0.5
        
        XCTAssertEqual(point.x, expectedX, accuracy: 0.001)
        XCTAssertEqual(point.y, timelineView.bounds.height / 2.0, accuracy: 0.001)
    }
    
    func testPointOfPosition_AtZero_ReturnsLeftEdge() {
        let point = timelineView.point(of: 0.0)
        
        XCTAssertEqual(point.x, timelineView.leftMargin, accuracy: 0.001)
        XCTAssertEqual(point.y, timelineView.bounds.height / 2.0, accuracy: 0.001)
    }
    
    func testPointOfPosition_AtOne_ReturnsRightEdge() {
        let point = timelineView.point(of: 1.0)
        let expectedX = timelineView.bounds.width - timelineView.rightMargin
        
        XCTAssertEqual(point.x, expectedX, accuracy: 0.001)
    }
    
    func testPointOfPosition_OutOfRange_PreservesLinearMapping() {
        let underflow = timelineView.point(of: -0.1)
        let overflow = timelineView.point(of: 1.1)
        let width = timelineView.bounds.width - timelineView.leftMargin - timelineView.rightMargin
        
        XCTAssertEqual(underflow.x, timelineView.leftMargin - width * 0.1, accuracy: 0.001)
        XCTAssertEqual(overflow.x, timelineView.leftMargin + width * 1.1, accuracy: 0.001)
    }
    
    func testUpdateTimeline_SameValues_ReturnsFalse() {
        timelineView.currentPosition = 0.5
        timelineView.startPosition = 0.2
        timelineView.endPosition = 0.8
        timelineView.isValid = true
        
        let result = timelineView.updateTimeline(
            current: 0.5,
            from: 0.2,
            to: 0.8,
            isValid: true
        )
        
        XCTAssertFalse(result)
    }
    
    func testUpdateTimeline_NewValues_ReturnsTrue() {
        timelineView.currentPosition = 0.5
        timelineView.startPosition = 0.2
        timelineView.endPosition = 0.8
        timelineView.isValid = true
        
        let result = timelineView.updateTimeline(
            current: 0.6,
            from: 0.3,
            to: 0.9,
            isValid: true
        )
        
        XCTAssertTrue(result)
    }
    
    func testUpdateTimeline_NaN_ClearsState() {
        timelineView.currentPosition = 0.5
        timelineView.startPosition = 0.2
        timelineView.endPosition = 0.8
        timelineView.isValid = true
        
        let result = timelineView.updateTimeline(
            current: .nan,
            from: .nan,
            to: .nan,
            isValid: true
        )
        
        XCTAssertTrue(result)
        XCTAssertFalse(timelineView.isValid)
        XCTAssertEqual(timelineView.currentPosition, 0.0, accuracy: 0.001)
        XCTAssertEqual(timelineView.startPosition, 0.0, accuracy: 0.001)
        XCTAssertEqual(timelineView.endPosition, 0.0, accuracy: 0.001)
    }
    
    func testLayout_CurrentMarkerCentered() {
        timelineView.currentPosition = 0.5
        timelineView.layout()
        
        guard let currentMarker = timelineView.currentMarker else {
            return XCTFail("current marker layer should exist")
        }
        
        let expectedX = timelineView.point(of: 0.5).x - currentMarker.frame.width / 2.0
        XCTAssertEqual(currentMarker.frame.midX, timelineView.point(of: 0.5).x, accuracy: 0.001)
        XCTAssertEqual(currentMarker.frame.origin.x, expectedX, accuracy: 0.001)
    }
    
    func testLayout_SelectionWidthMatchesRange() {
        timelineView.currentPosition = 0.5
        timelineView.startPosition = 0.2
        timelineView.endPosition = 0.8
        timelineView.isValid = true
        _ = timelineView.updateTimeline(current: 0.5, from: 0.2, to: 0.8, isValid: true)
        timelineView.layout()
        
        guard let selection = timelineView.selection else {
            return XCTFail("selection layer should exist")
        }
        
        let expectedWidth = timelineView.point(of: 0.8).x - timelineView.point(of: 0.2).x
        XCTAssertEqual(selection.frame.width, expectedWidth, accuracy: 1.0)
    }
    
    func testJKLMode_ChangesFillColorActive() {
        timelineView.jklMode = false
        let normalColor = timelineView.fillColorActive
        
        timelineView.jklMode = true
        let jklColor = timelineView.fillColorActive
        
        XCTAssertNotEqual(normalColor, jklColor)
        XCTAssertEqual(jklColor, NSColor.blue.cgColor)
    }
    
    func testSelectNewMarker_UpdatesStrokeAndFill() {
        guard let currentMarker = timelineView.currentMarker else {
            return XCTFail("current marker layer should exist")
        }
        
        XCTAssertTrue(timelineView.selectNewMarker(currentMarker))
        XCTAssertEqual(timelineView.selectedMarker, currentMarker)
        XCTAssertEqual(currentMarker.strokeColor, timelineView.strokeColorActive)
        XCTAssertEqual(currentMarker.fillColor, timelineView.fillColorActive)
    }
    
    // MARK: - TimelineView mouse input (T-14)
    
    /// Mock delegate for TimelineView mouse input tests
    @MainActor
    private final class MockTimelineDelegate: TimelineUpdateDelegate {
        var cursorUpdates: [Float64] = []
        var startUpdates: [Float64] = []
        var endUpdates: [Float64] = []
        var selectionUpdates: [(Float64, Float64)] = []
        var currentRequests: [anchor] = []
        var startRequests: [anchor] = []
        var endRequests: [anchor] = []
        var presentationInfoValue: PresentationInfo? = nil
        
        func didUpdateCursor(to position: Float64) { cursorUpdates.append(position) }
        func didUpdateStart(to position: Float64) { startUpdates.append(position) }
        func didUpdateEnd(to position: Float64) { endUpdates.append(position) }
        func didUpdateSelection(from fromPos: Float64, to toPos: Float64) {
            selectionUpdates.append((fromPos, toPos))
        }
        func presentationInfo(at position: Float64) -> PresentationInfo? { return presentationInfoValue }
        func previousInfo(of range: CMTimeRange) -> PresentationInfo? { return nil }
        func nextInfo(of range: CMTimeRange) -> PresentationInfo? { return nil }
        func doSetCurrent(to goTo: anchor) { currentRequests.append(goTo) }
        func doSetStart(to goTo: anchor) { startRequests.append(goTo) }
        func doSetEnd(to goTo: anchor) { endRequests.append(goTo) }
    }
    
    /// Clicking the start marker triggers selectNewMarker(true) and resetCurrent, which calls doSetCurrent
    func testSelectNewMarkerOnStartRequestsCurrent() throws {
        timelineView.layout()
        let delegate = MockTimelineDelegate()
        timelineView.delegate = delegate
        
        let window = NSWindow(contentRect: timelineView.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = timelineView
        
        guard let startMarker = timelineView.startMarker else {
            return XCTFail("start marker should exist")
        }
        
        let hitPoint = CGPoint(
            x: startMarker.frame.midX,
            y: startMarker.frame.midY
        )
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: hitPoint,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )!
        timelineView.mouseDown(with: event)
        
        XCTAssertEqual(delegate.currentRequests, [.start], "doSetCurrent(.start) should be called when clicking start marker")
    }
    
    /// Dragging the selected start marker updates startPosition and notifies the delegate
    func testMouseDraggedUpdatesStartPosition() throws {
        timelineView.layout()
        timelineView.isValid = true
        timelineView.endPosition = 0.8 // Prevent selection update (start < end after drag)
        let delegate = MockTimelineDelegate()
        timelineView.delegate = delegate
        
        guard let startMarker = timelineView.startMarker else {
            return XCTFail("start marker should exist")
        }
        timelineView.selectedMarker = startMarker
        
        let window = NSWindow(contentRect: timelineView.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = timelineView
        
        let event = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: CGPoint(x: 131.5, y: timelineView.bounds.midY),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )!
        timelineView.mouseDragged(with: event)
        
        XCTAssertFalse(delegate.startUpdates.isEmpty, "didUpdateStart should be called when dragging start marker")
        XCTAssertEqual(timelineView.startPosition, 0.5, accuracy: 0.01)
    }
    
    /// Dragging the selected current marker updates currentPosition and notifies the delegate
    func testMouseDraggedUpdatesCurrentPosition() throws {
        timelineView.layout()
        timelineView.isValid = true
        let delegate = MockTimelineDelegate()
        timelineView.delegate = delegate
        
        guard let currentMarker = timelineView.currentMarker else {
            return XCTFail("current marker should exist")
        }
        timelineView.selectedMarker = currentMarker
        
        let window = NSWindow(contentRect: timelineView.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = timelineView
        
        let event = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: CGPoint(x: 131.5, y: timelineView.bounds.midY),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )!
        timelineView.mouseDragged(with: event)
        
        XCTAssertFalse(delegate.cursorUpdates.isEmpty, "didUpdateCursor should be called when dragging current marker")
        XCTAssertEqual(timelineView.currentPosition, 0.5, accuracy: 0.01)
    }
    
    /// mouseDragged does nothing when no marker is selected
    func testMouseDraggedDoesNothingWhenNoSelection() throws {
        timelineView.layout()
        timelineView.isValid = true
        timelineView.currentPosition = 0.0
        
        let delegate = MockTimelineDelegate()
        timelineView.delegate = delegate
        
        let event = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: CGPoint(x: 100, y: 25),
            modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )!
        timelineView.mouseDragged(with: event)
        
        XCTAssertTrue(delegate.cursorUpdates.isEmpty)
        XCTAssertTrue(delegate.startUpdates.isEmpty)
        XCTAssertTrue(delegate.endUpdates.isEmpty)
        XCTAssertEqual(timelineView.currentPosition, 0.0, accuracy: 0.001)
    }
}
