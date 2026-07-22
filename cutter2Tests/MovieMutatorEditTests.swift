//  MovieMutatorEditTests.swift (T-09)
//  cutter2Tests

import XCTest
import AVFoundation
import CoreMedia
import AppKit
@testable import cutter2

@MainActor
final class MovieMutatorEditTests: XCTestCase {

    /// Fixture files kept until tearDown so AVMutableMovie can lazy-read sample data.
    private let fixtureStore = TestFixtureURLStore()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        for url in fixtureStore.takeAll() {
            try? FileManager.default.removeItem(at: url)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeMutator(
        duration: TimeInterval = 10.0,
        insertionTime: TimeInterval = 0.0,
        selectionDuration: TimeInterval = 1.0
    ) -> MovieMutator? {
        let timescale: CMTimeScale = 600
        let frameRate: Int = 30

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutter2_edit_test_\(UUID().uuidString).mov")

        // Write fixture off main thread to avoid AVAssetWriter thread warnings
        let writeOK = DispatchQueue.global().sync {
            writeSampleMovie(to: tempURL, duration: duration, timescale: timescale, frameRate: frameRate)
        }
        guard writeOK else {
            XCTFail("failed to write sample movie")
            return nil
        }
        fixtureStore.append(tempURL)

        let movie = AVMutableMovie(url: tempURL, options: nil)
        guard movie.range.duration > CMTime.zero else {
            XCTFail("AVMutableMovie(url:) produced empty movie")
            return nil
        }
        movie.timescale = timescale

        let mutator = MovieMutator(with: movie)
        mutator.insertionTime = CMTime(seconds: insertionTime, preferredTimescale: timescale)
        mutator.selectedTimeRange = CMTimeRange(
            start: CMTime(seconds: insertionTime, preferredTimescale: timescale),
            duration: CMTime(seconds: selectionDuration, preferredTimescale: timescale)
        )
        return mutator
    }

    // MARK: - Cut / Paste / Delete round-trip (T-09)

    func testCutSelectionRegistersUndoAndCachesClip() {
        guard let mutator = makeMutator(duration: 10.0, insertionTime: 0.0, selectionDuration: 1.0) else { return }
        let realUM = UndoManager()
        realUM.groupsByEvent = false

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertNil(pasteboard.data(forType: .movieMutator),
                     "precondition: pasteboard must not already hold .movieMutator")

        let durationBefore = mutator.movieRange().duration.seconds
        let selectionBefore = mutator.selectedTimeRange.duration.seconds

        realUM.beginUndoGrouping()
        let wrapper = UndoManagerWrapper(realUM)
        mutator.cutSelection(using: wrapper)
        realUM.endUndoGrouping()

        XCTAssertTrue(realUM.canUndo, "undo must be registered after cut")
        XCTAssertEqual(realUM.undoActionName, "Cut selection")
        XCTAssertEqual(mutator.movieRange().duration.seconds,
                       durationBefore - selectionBefore, accuracy: 0.01,
                       "movie duration must shrink by selection")
        XCTAssertNotNil(pasteboard.data(forType: .movieMutator),
                        "clip must be cached on PBoard")
    }

    func testCutUndoRestoresDurationAndMarker() {
        guard let mutator = makeMutator(duration: 10.0, insertionTime: 0.0, selectionDuration: 1.0) else { return }
        let realUM = UndoManager()
        realUM.groupsByEvent = false

        let durationBefore = mutator.movieRange().duration.seconds
        let insertionBefore = mutator.insertionTime.seconds
        let selectionStartBefore = mutator.selectedTimeRange.start.seconds
        let selectionDurationBefore = mutator.selectedTimeRange.duration.seconds

        realUM.beginUndoGrouping()
        let wrapper = UndoManagerWrapper(realUM)
        mutator.cutSelection(using: wrapper)
        realUM.endUndoGrouping()

        realUM.undo()

        XCTAssertEqual(mutator.movieRange().duration.seconds, durationBefore, accuracy: 0.01,
                       "duration restored")
        XCTAssertEqual(mutator.insertionTime.seconds, insertionBefore, accuracy: 0.01,
                       "insertionTime restored")
        XCTAssertEqual(mutator.selectedTimeRange.start.seconds, selectionStartBefore, accuracy: 0.01,
                       "selection start restored")
        XCTAssertEqual(mutator.selectedTimeRange.duration.seconds, selectionDurationBefore, accuracy: 0.01,
                       "selection duration restored")
        XCTAssertTrue(realUM.canRedo, "redo available after undo")
    }

    func testCutRedoReappliesCut() {
        guard let mutator = makeMutator(duration: 10.0, insertionTime: 0.0, selectionDuration: 1.0) else { return }
        let realUM = UndoManager()
        realUM.groupsByEvent = false

        let durationBefore = mutator.movieRange().duration.seconds
        let selectionBefore = mutator.selectedTimeRange.duration.seconds

        realUM.beginUndoGrouping()
        let wrapper = UndoManagerWrapper(realUM)
        mutator.cutSelection(using: wrapper)
        realUM.endUndoGrouping()

        realUM.undo()
        realUM.redo()

        XCTAssertEqual(mutator.movieRange().duration.seconds,
                       durationBefore - selectionBefore, accuracy: 0.01,
                       "redo re-applies cut")
        XCTAssertTrue(realUM.canUndo, "undo available after redo")
    }

    func testPasteAtInsertionTimeRoundTrip() {
        guard let mutator = makeMutator(duration: 10.0, insertionTime: 0.0, selectionDuration: 1.0) else { return }
        let realUM = UndoManager()
        realUM.groupsByEvent = false

        let durationBefore = mutator.movieRange().duration.seconds
        let selectionBefore = mutator.selectedTimeRange.duration.seconds

        // Cut
        realUM.beginUndoGrouping()
        let cutWrapper = UndoManagerWrapper(realUM)
        mutator.cutSelection(using: cutWrapper)
        realUM.endUndoGrouping()
        XCTAssertEqual(mutator.movieRange().duration.seconds,
                       durationBefore - selectionBefore, accuracy: 0.01)

        // Paste (cut's doRemove made selection zero-duration; paste allows needsDuration=false)
        realUM.beginUndoGrouping()
        let pasteWrapper = UndoManagerWrapper(realUM)
        mutator.pasteAtInsertionTime(using: pasteWrapper)
        realUM.endUndoGrouping()
        XCTAssertEqual(mutator.movieRange().duration.seconds, durationBefore, accuracy: 0.01,
                       "paste restores duration")

        // Undo paste -> back to cut state
        realUM.undo()
        XCTAssertEqual(mutator.movieRange().duration.seconds,
                       durationBefore - selectionBefore, accuracy: 0.01,
                       "undo paste returns to cut state")

        // Redo paste -> duration restored
        realUM.redo()
        XCTAssertEqual(mutator.movieRange().duration.seconds, durationBefore, accuracy: 0.01,
                       "redo paste re-inserts clip")
    }

    func testDeleteSelectionRoundTrip() {
        guard let mutator = makeMutator(duration: 10.0, insertionTime: 0.0, selectionDuration: 1.0) else { return }
        let realUM = UndoManager()
        realUM.groupsByEvent = false

        let durationBefore = mutator.movieRange().duration.seconds
        let selectionBefore = mutator.selectedTimeRange.duration.seconds

        realUM.beginUndoGrouping()
        let delWrapper = UndoManagerWrapper(realUM)
        mutator.deleteSelection(using: delWrapper)
        realUM.endUndoGrouping()
        XCTAssertEqual(realUM.undoActionName, "Delete selection")
        XCTAssertEqual(mutator.movieRange().duration.seconds,
                       durationBefore - selectionBefore, accuracy: 0.01,
                       "delete shrinks movie")

        realUM.undo()
        XCTAssertEqual(mutator.movieRange().duration.seconds, durationBefore, accuracy: 0.01,
                       "undo restores duration")

        realUM.redo()
        XCTAssertEqual(mutator.movieRange().duration.seconds,
                       durationBefore - selectionBefore, accuracy: 0.01,
                       "redo re-deletes")
    }
}
