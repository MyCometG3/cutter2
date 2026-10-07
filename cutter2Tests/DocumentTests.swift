//
//  DocumentTests.swift
//  cutter2Tests
//
//  Created by GitHub Copilot on 2025/10/13.
//  Copyright © 2025-2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Unit tests for Document class and its extensions
@MainActor
final class DocumentTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    // MARK: - Document Type Tests
    
    func testReadableTypes() throws {
        let types = Document.readableTypes
        
        XCTAssertTrue(types.contains("com.apple.quicktime-movie"))
        XCTAssertTrue(types.contains("public.mpeg-4"))
    }
    
    func testWritableTypes() throws {
        let types = Document.writableTypes
        
        XCTAssertTrue(types.contains("com.apple.quicktime-movie"))
    }

    func testUserCancellationErrorAcceptsMovieWriterDomain() {
        let error = NSError(
            domain: MovieWriterError.errorDomain,
            code: NSUserCancelledError
        )

        XCTAssertTrue(Document.isUserCancellationError(error))
    }

    func testUserCancellationErrorAcceptsCocoaDomain() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError
        )

        XCTAssertTrue(Document.isUserCancellationError(error))
    }

    func testUserCancellationErrorRejectsWrongCode() {
        let error = NSError(
            domain: MovieWriterError.errorDomain,
            code: MovieWriterError.errorInfo[.movieWriterFailed]?.code ?? 4
        )

        XCTAssertFalse(Document.isUserCancellationError(error))
    }

    func testUserCancellationErrorRejectsWrongDomain() {
        let error = NSError(
            domain: "UnknownDomain",
            code: NSUserCancelledError
        )

        XCTAssertFalse(Document.isUserCancellationError(error))
    }

    func testWindowIsNilBeforeWindowControllerCreation() {
        let document = Document()

        XCTAssertNil(document.window)
    }

    func testResetPositionCacheClearsAllCachedPositionState() {
        let document = Document()
        document.cachedTime = CMTime(seconds: 3, preferredTimescale: 600)
        document.cachedWithinLastSampleRange = true
        document.cachedLastSampleRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 4, preferredTimescale: 600)
        )

        document.resetPositionCache()

        XCTAssertEqual(document.cachedTime, .invalid)
        XCTAssertFalse(document.cachedWithinLastSampleRange)
        XCTAssertNil(document.cachedLastSampleRange)
    }
    
    // MARK: - Document read error handling (T-14)
    
    /// Verifies that `validateMovieType` throws for an invalid UTI (`incompatibleFileType`).
    /// Note: `ErrorUtilities.throwError` converts `DocumentError` to `NSError` before throwing.
    /// `DocumentError.incompatibleFileType` maps to `NSOSStatusErrorDomain` / `unimpErr` (-4).
    func testValidateMovieTypeRejectsInvalidUTI() throws {
        XCTAssertThrowsError(try Document.validateMovieType("invalid.type")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSOSStatusErrorDomain)
            XCTAssertEqual(nsError.code, unimpErr)
        }
    }
    
    /// Verifies that `validateMovieType` accepts a valid movie UTI.
    func testValidateMovieTypeAcceptsMovieUTI() throws {
        XCTAssertNoThrow(try Document.validateMovieType("com.apple.quicktime-movie"))
    }
    
    /// Verifies that a trackless AVMutableMovie fails `MovieHeaderValidator.isValid`.
    /// Since `readAsync`'s header validation delegates to `MovieHeaderValidator.isValid`,
    /// this directly tests the header validation error path (equivalent to `.unableToOpenFile`).
    ///
    /// Note: `AVMutableMovie()` (no arguments) safely constructs a trackless movie.
    /// `AVMutableMovie(data:)` is avoided because passing arbitrary bytes risks an
    /// AVFoundation exception.
    func testInvalidHeaderFailsValidation() throws {
        let movie = AVMutableMovie() // no arguments → produces a trackless movie
        XCTAssertFalse(MovieHeaderValidator.isValid(movie))
        if let error = MovieHeaderValidator.validate(movie) {
            guard case .noTracks = error else {
                return XCTFail("Unexpected validation error: \(error)")
            }
        } else {
            XCTFail("Expected noTracks validation error for track-less movie")
        }
    }
    
    // MARK: - Progress reporting (terminal state)
    
    func testFinalizeProgressSetsExactTerminalState() throws {
        let document = Document()
        let indicator = NSProgressIndicator()
        document.progressIndicator = indicator
        // A value that exponential smoothing could never reach: updateProgress converges
        // towards 1.0 without ever arriving there.
        document.lastReportedProgress = 0.42

        document.finalizeProgress(1.0)

        XCTAssertEqual(document.lastReportedProgress, 1.0)
        XCTAssertEqual(indicator.doubleValue, 100.0)
    }
    
    func testUpdateProgressNeverLowersReportedProgress() throws {
        let document = Document()
        let indicator = NSProgressIndicator()
        document.progressIndicator = indicator
        document.finalizeProgress(1.0)

        // `finalizeProgress` stamps `lastUpdateAt` with the current time, so a call that
        // follows immediately is dropped by the 100 ms throttle before it ever reaches
        // the smoothing step. Backdate the stamp so the update is admitted and the clamp
        // is actually exercised.
        document.lastUpdateAt = 1

        document.updateProgress(0.5)

        XCTAssertEqual(document.lastReportedProgress, 1.0)
        XCTAssertEqual(indicator.doubleValue, 100.0)
    }

    func testApplyProgressValueNeverLowersCompletedUnitCount() throws {
        // `NSProgress.completedUnitCount` is a separate copy of the progress state from
        // the rendered bar, so the clamp in `updateProgress` does not cover it. A buffered
        // iteration landing after a successful operation must not drag 100% back down.
        let progress = Progress(totalUnitCount: 100)

        Document.applyProgressValue(0.5, to: progress)
        XCTAssertEqual(progress.completedUnitCount, 50)

        // The terminal state a successful operation writes.
        progress.completedUnitCount = progress.totalUnitCount
        XCTAssertEqual(progress.completedUnitCount, 100)

        Document.applyProgressValue(0.5, to: progress)
        XCTAssertEqual(progress.completedUnitCount, 100, "a late buffered update must not regress a finished operation")

        Document.applyProgressValue(0.8, to: progress)
        XCTAssertEqual(progress.completedUnitCount, 100)
    }

    func testApplyProgressValueAdvancesMonotonically() throws {
        let progress = Progress(totalUnitCount: 100)

        for value in [Float(0.0), 0.25, 0.25, 0.5, 0.4, 1.0] as [Float] {
            Document.applyProgressValue(value, to: progress)
        }

        XCTAssertEqual(progress.completedUnitCount, 100)
    }
    
    // MARK: - DocumentError Tests
    
    func testDocumentErrorTypes() throws {
        enum TestDocumentError: NSErrorConvertible {
            case testError
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.document",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Test error"]
                )
            }
        }
        
        let error = TestDocumentError.testError
        XCTAssertEqual(error.nsError.code, 1)
    }
}
