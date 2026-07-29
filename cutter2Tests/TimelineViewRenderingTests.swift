//
//  TimelineViewRenderingTests.swift
//  cutter2Tests
//

import XCTest
import Cocoa
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
}
