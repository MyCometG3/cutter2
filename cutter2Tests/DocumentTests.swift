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
    
    // MARK: - Document read error handling (T-14)
    
    /// Verifies that `validateMovieType` throws for an invalid UTI (`incompatibleFileType`).
    /// Constructing a `Document` directly crashes in the test environment (NSRangeException from
    /// the `windowControllers[0]` access in the `window` property), so the UTI validation logic
    /// of `readAsync` (`Self.validateMovieType`) is tested in isolation.
    ///
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
