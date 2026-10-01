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
    
    // Pins the VALID == false route: an invalid CMTime rejects the duration.
    func testValidateHelperRejectsInvalidTime() {
        let error = MovieHeaderValidator.validate(trackCount: 1, duration: .invalid)
        guard case .invalidDuration? = error else {
            return XCTFail("expected .invalidDuration, got \(String(describing: error))")
        }
    }
    
    // Pins the NUMERIC == false route with VALID == true: an indefinite CMTime
    // is an implied value and is rejected as an invalid duration.
    func testValidateHelperRejectsIndefiniteDuration() {
        let error = MovieHeaderValidator.validate(trackCount: 1, duration: .indefinite)
        guard case .invalidDuration? = error else {
            return XCTFail("expected .invalidDuration, got \(String(describing: error))")
        }
    }
    
    // Pins the NUMERIC == false route for implied values: both ±infinity
    // durations are rejected as invalid durations.
    func testValidateHelperRejectsInfiniteDurations() {
        let positive = MovieHeaderValidator.validate(trackCount: 1, duration: .positiveInfinity)
        guard case .invalidDuration? = positive else {
            return XCTFail("expected .invalidDuration for positiveInfinity, got \(String(describing: positive))")
        }
        let negative = MovieHeaderValidator.validate(trackCount: 1, duration: .negativeInfinity)
        guard case .invalidDuration? = negative else {
            return XCTFail("expected .invalidDuration for negativeInfinity, got \(String(describing: negative))")
        }
    }
    
    // Pins the current semantics: a zero duration with at least one track
    // is valid and numeric, so validation passes.
    func testValidateHelperAcceptsZeroDurationWithTrack() {
        let error = MovieHeaderValidator.validate(trackCount: 1, duration: .zero)
        guard error == nil else {
            return XCTFail("expected nil, got \(String(describing: error))")
        }
    }
    
    // Pins the branch ordering: a track count of zero yields .noTracks even
    // when the duration is also invalid.
    func testValidateHelperPrioritizesNoTracksOverInvalidDuration() {
        let error = MovieHeaderValidator.validate(trackCount: 0, duration: .invalid)
        guard case .noTracks? = error else {
            return XCTFail("expected .noTracks, got \(String(describing: error))")
        }
    }
    
    // Pins the branch ordering: a track count of zero yields .noTracks even
    // for a valid, numeric duration.
    func testValidateHelperPrioritizesNoTracksOverValidDuration() {
        let error = MovieHeaderValidator.validate(trackCount: 0, duration: .zero)
        guard case .noTracks? = error else {
            return XCTFail("expected .noTracks, got \(String(describing: error))")
        }
    }
}
