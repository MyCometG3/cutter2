//
//  MovieHeaderValidatorTests.swift
//  cutter2Tests
//
//  Created by Takashi Mochizuki on 2026/07/20.
//  Copyright © 2026 MyCometG3. All rights reserved.
//

//  MovieHeaderValidatorTests.swift (T-03)
//  cutter2Tests

import XCTest
import AVFoundation
import CoreMedia
@testable import cutter2

final class MovieHeaderValidatorTests: XCTestCase {
    
    func testValidateEmptyMovieReturnsNoTracks() {
        let movie = AVMutableMovie()
        let error = MovieHeaderValidator.validate(movie)
        guard case .noTracks? = error else {
            return XCTFail("expected .noTracks, got \(String(describing: error))")
        }
        XCTAssertFalse(MovieHeaderValidator.isValid(movie))
    }
    
    func testValidateMovieWithTrackReturnsNil() {
        let movie = AVMutableMovie()
        movie.timescale = 600
        guard movie.addMutableTrack(
            withMediaType: .video, copySettingsFrom: nil, options: nil
        ) != nil else {
            return XCTFail("failed to add video track")
        }
        let range = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 1.0, preferredTimescale: 600)
        )
        movie.insertEmptyTimeRange(range)
        
        XCTAssertFalse(movie.tracks.isEmpty, "precondition: fixture must have tracks")
        XCTAssertNil(MovieHeaderValidator.validate(movie))
        XCTAssertTrue(MovieHeaderValidator.isValid(movie))
    }
    
    func testValidationErrorDescriptionsAreNonEmpty() {
        XCTAssertFalse(
            MovieHeaderValidator.ValidationError.noTracks.errorDescription?.isEmpty ?? true
        )
        XCTAssertFalse(
            MovieHeaderValidator.ValidationError.invalidDuration.errorDescription?.isEmpty ?? true
        )
    }
}
