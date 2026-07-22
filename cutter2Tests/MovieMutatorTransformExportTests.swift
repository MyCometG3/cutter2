//  MovieMutatorTransformExportTests.swift (T-02)
//  cutter2Tests

import XCTest
import AVFoundation
import CoreMedia
import AppKit
@testable import cutter2

@MainActor
final class MovieMutatorTransformExportTests: XCTestCase {

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

    private func makeMutator(duration: TimeInterval = 1.0) async -> MovieMutator? {
        let timescale: CMTimeScale = 600
        let frameRate: Int = 30

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutter2_transform_test_\(UUID().uuidString).mov")

        let writeOK = await Task.detached {
            writeSampleMovie(to: tempURL, duration: duration, timescale: timescale, frameRate: frameRate)
        }.value
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
        mutator.insertionTime = .zero
        mutator.selectedTimeRange = CMTimeRange(start: .zero, duration: .zero)
        return mutator
    }

    // MARK: - clappaspDictionary

    func testClappaspDictionaryReturnsDefaultsForH264Fixture() async {
        guard let mutator = await makeMutator() else { return }
        guard let dict = mutator.clappaspDictionary() else {
            return XCTFail("expected non-nil clap/pasp dict for video fixture")
        }
        let dimensions = dict[dimensionsKey] as? NSSize
        let clapSize = dict[clapSizeKey] as? NSSize
        let clapOffset = dict[clapOffsetKey] as? NSPoint
        let pasp = dict[paspRatioKey] as? NSSize

        XCTAssertEqual(dimensions, NSSize(width: 320, height: 180))
        XCTAssertEqual(clapSize, NSSize(width: 320, height: 180),
                       "no CA extension → clap defaults to dimensions")
        XCTAssertEqual(clapOffset, .zero)
        XCTAssertEqual(pasp, NSSize(width: 1.0, height: 1.0))
    }

    func testClappaspDictionaryNilWithoutVideoTrack() {
        let movie = AVMutableMovie()
        let mutator = MovieMutator(with: movie)
        XCTAssertNil(mutator.clappaspDictionary())
    }

    // MARK: - applyClapPasp + undo/redo

    func testApplyClapPaspRegistersUndoAndRoundTrips() async {
        guard let mutator = await makeMutator() else { return }
        guard var dict = mutator.clappaspDictionary() else {
            return XCTFail("dict required")
        }
        dict[paspRatioKey] = NSSize(width: 4.0, height: 3.0)
        dict[clapSizeKey] = NSSize(width: 300, height: 160)
        dict[clapOffsetKey] = NSPoint(x: 2, y: 1)

        let realUM = UndoManager()
        realUM.groupsByEvent = false
        let wrapper = UndoManagerWrapper(realUM)

        realUM.beginUndoGrouping()
        let ok = mutator.applyClapPasp(dict, using: wrapper)
        realUM.endUndoGrouping()

        XCTAssertTrue(ok, "applyClapPasp must succeed on matching dimensions")
        XCTAssertTrue(realUM.canUndo)
        XCTAssertEqual(realUM.undoActionName, "Update format")

        // after apply
        guard let after = mutator.clappaspDictionary() else {
            return XCTFail("dict after apply")
        }
        let paspAfter = after[paspRatioKey] as? NSSize
        XCTAssertEqual(Double(paspAfter?.width ?? 0), 4.0, accuracy: 0.001)
        XCTAssertEqual(Double(paspAfter?.height ?? 0), 3.0, accuracy: 0.001)
        let clapAfter = after[clapSizeKey] as? NSSize
        XCTAssertEqual(Double(clapAfter?.width ?? 0), 300, accuracy: 0.001)
        XCTAssertEqual(Double(clapAfter?.height ?? 0), 160, accuracy: 0.001)

        // undo → back to defaults
        realUM.undo()
        guard let undone = mutator.clappaspDictionary() else {
            return XCTFail("dict after undo")
        }
        let paspUndone = undone[paspRatioKey] as? NSSize
        XCTAssertEqual(Double(paspUndone?.width ?? 0), 1.0, accuracy: 0.001)
        XCTAssertEqual(Double(paspUndone?.height ?? 0), 1.0, accuracy: 0.001)
        XCTAssertTrue(realUM.canRedo)

        // redo
        realUM.redo()
        guard let redone = mutator.clappaspDictionary() else {
            return XCTFail("dict after redo")
        }
        let paspRedone = redone[paspRatioKey] as? NSSize
        XCTAssertEqual(Double(paspRedone?.width ?? 0), 4.0, accuracy: 0.001)
        XCTAssertEqual(Double(paspRedone?.height ?? 0), 3.0, accuracy: 0.001)
    }

    func testApplyClapPaspMissingKeyReturnsFalse() async {
        guard let mutator = await makeMutator() else { return }
        let realUM = UndoManager()
        realUM.groupsByEvent = false
        let wrapper = UndoManagerWrapper(realUM)

        let bad: [AnyHashable: Any] = [
            clapSizeKey: NSSize(width: 320, height: 180),
            clapOffsetKey: NSZeroPoint,
            paspRatioKey: NSSize(width: 1, height: 1)
            // dimensionsKey missing
        ]
        XCTAssertFalse(mutator.applyClapPasp(bad, using: wrapper))
        XCTAssertFalse(realUM.canUndo, "failed apply must not register undo")
    }

    func testApplyClapPaspMismatchedDimensionsReturnsFalse() async {
        guard let mutator = await makeMutator() else { return }
        let realUM = UndoManager()
        realUM.groupsByEvent = false
        let wrapper = UndoManagerWrapper(realUM)

        let bad: [AnyHashable: Any] = [
            dimensionsKey: NSSize(width: 999, height: 999),
            clapSizeKey: NSSize(width: 320, height: 180),
            clapOffsetKey: NSZeroPoint,
            paspRatioKey: NSSize(width: 1, height: 1)
        ]
        XCTAssertFalse(mutator.applyClapPasp(bad, using: wrapper))
        XCTAssertFalse(realUM.canUndo)
    }

    // MARK: - writeMovie / cancel

    func testWriteMovieSelfContainedProducesFile() async throws {
        guard let mutator = await makeMutator(duration: 1.0) else { return }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutter2_write_\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outURL) }

        try await mutator.writeMovie(to: outURL, fileType: .mov, copySampleData: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: outURL.path)
        let size = attrs[.size] as? NSNumber
        XCTAssertNotNil(size)
        XCTAssertGreaterThan(size?.intValue ?? 0, 0, "output must be non-empty")

        let written = AVMutableMovie(url: outURL, options: nil)
        XCTAssertGreaterThan(written.duration.seconds, 0.5)
        XCTAssertEqual(written.duration.seconds, 1.0, accuracy: 0.15)
    }

    func testCancelWithNoWriterIsNoOp() async {
        let mutator = MovieMutator(with: AVMutableMovie())
        await mutator.cancel() // must not throw / crash
    }

    func testWriteMovieThenCancelIsSafe() async throws {
        guard let mutator = await makeMutator(duration: 1.0) else { return }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutter2_write_cancel_\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outURL) }

        try await mutator.writeMovie(to: outURL, fileType: .mov, copySampleData: true)
        await mutator.cancel() // writer already cleared
        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
    }
}
