//  MovieMutatorEditTests.swift (T-09)
//  cutter2Tests

import XCTest
import AVFoundation
import CoreMedia
@testable import cutter2

/// nonisolated helper: write a sample .mov off the main thread
private func writeSampleMovie(
    to url: URL,
    duration: TimeInterval,
    timescale: CMTimeScale,
    frameDuration: CMTime,
    frameCount: Int
) -> Bool {
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }

    let width = 320
    let height = 180
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
    )
    guard writer.canAdd(input) else { return false }
    writer.add(input)

    guard writer.startWriting() else { return false }
    writer.startSession(atSourceTime: .zero)

    let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
    ]
    var pixelBuffer: CVPixelBuffer?
    let pstatus = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                      kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
    guard pstatus == kCVReturnSuccess, let pb = pixelBuffer else { return false }
    CVPixelBufferLockBaseAddress(pb, [])
    if let base = CVPixelBufferGetBaseAddress(pb) {
        memset(base, 0, CVPixelBufferGetDataSize(pb))
    }
    CVPixelBufferUnlockBaseAddress(pb, [])

    var presentation = CMTime.zero
    for _ in 0..<frameCount {
        while !input.isReadyForMoreMediaData { usleep(1000) }
        let ok = adaptor.append(pb, withPresentationTime: presentation)
        if !ok { return false }
        presentation = CMTimeAdd(presentation, frameDuration)
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: presentation)
    let group = DispatchGroup()
    group.enter()
    writer.finishWriting { group.leave() }
    group.wait()
    return writer.status == .completed
}

@MainActor
final class MovieMutatorEditTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func makeMutator(
        duration: TimeInterval = 10.0,
        insertionTime: TimeInterval = 0.0,
        selectionDuration: TimeInterval = 1.0
    ) -> MovieMutator? {
        let timescale: CMTimeScale = 600
        let frameRate: Int = 30
        let frameDuration = CMTime(value: CMTimeValue(timescale) / CMTimeValue(frameRate), timescale: timescale)
        let frameCount = Int((duration * Double(frameRate)).rounded())

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutter2_edit_test_\(UUID().uuidString).mov")

        // Write fixture off main thread to avoid AVAssetWriter thread warnings
        let writeOK = DispatchQueue.global().sync {
            writeSampleMovie(to: tempURL, duration: duration, timescale: timescale,
                             frameDuration: frameDuration, frameCount: frameCount)
        }
        guard writeOK else {
            XCTFail("failed to write sample movie")
            return nil
        }

        let movie = AVMutableMovie(url: tempURL, options: nil)
        guard movie.range.duration > CMTime.zero else {
            XCTFail("AVMutableMovie(url:) produced empty movie")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        try? FileManager.default.removeItem(at: tempURL)
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
        XCTAssertNotNil(NSPasteboard.general.data(forType: .movieMutator),
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
