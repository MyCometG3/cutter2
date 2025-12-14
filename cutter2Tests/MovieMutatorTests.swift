//
//  MovieMutatorTests.swift
//  cutter2Tests
//
//  Created on 2025-10-13.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Unit tests for MovieMutator class and AVFoundation extensions
final class MovieMutatorTests: XCTestCase {
    
    var testMovie: AVMutableMovie?
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        // Create a minimal test movie
        testMovie = AVMutableMovie()
    }
    
    override func tearDownWithError() throws {
        testMovie = nil
    }
    
    // MARK: - AVMutableMovie Extension Tests
    
    func testMovieRangeEmpty() throws {
        let movie = AVMutableMovie()
        let range = movie.range
        
        XCTAssertTrue(range == CMTimeRange.zero)
    }
    
    func testMovieHeaderGeneration() throws {
        let movie = AVMutableMovie()
        
        // movHeader property exists and works
        let header = movie.movHeader
        
        // Even an empty movie should generate a header
        XCTAssertNotNil(header)
        if let headerData = header {
            XCTAssertTrue(headerData.count > 0)
        }
    }
    
    func testFindReferenceURLsEmptyMovie() throws {
        let movie = AVMutableMovie()
        let urls = movie.findReferenceURLs()
        
        // Empty movie should not have reference URLs
        XCTAssertNil(urls)
    }
    
    // MARK: - Time Handling Tests
    
    func testValidCMTime() throws {
        let validTime = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        XCTAssertTrue(validTime.isValid)
        XCTAssertEqual(validTime.timescale, 600)
        XCTAssertEqual(validTime.seconds, 1.0, accuracy: 0.001)
    }
    
    func testInvalidCMTime() throws {
        let invalidTime = CMTime.invalid
        
        XCTAssertFalse(invalidTime.isValid)
    }
    
    func testZeroCMTime() throws {
        let zeroTime = CMTime.zero
        
        XCTAssertTrue(zeroTime.isValid)
        XCTAssertEqual(zeroTime.seconds, 0.0)
    }
    
    func testCMTimeComparison() throws {
        let time1 = CMTime(seconds: 1.0, preferredTimescale: 600)
        let time2 = CMTime(seconds: 2.0, preferredTimescale: 600)
        let time3 = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        XCTAssertTrue(time1 < time2)
        XCTAssertTrue(time1 == time3)
        XCTAssertFalse(time1 > time2)
    }
    
    func testCMTimeAddition() throws {
        let time1 = CMTime(seconds: 1.0, preferredTimescale: 600)
        let time2 = CMTime(seconds: 2.0, preferredTimescale: 600)
        let result = time1 + time2
        
        XCTAssertEqual(result.seconds, 3.0, accuracy: 0.001)
    }
    
    func testCMTimeSubtraction() throws {
        let time1 = CMTime(seconds: 3.0, preferredTimescale: 600)
        let time2 = CMTime(seconds: 1.0, preferredTimescale: 600)
        let result = time1 - time2
        
        XCTAssertEqual(result.seconds, 2.0, accuracy: 0.001)
    }
    
    // MARK: - CMTimeRange Tests
    
    func testCMTimeRangeCreation() throws {
        let start = CMTime(seconds: 1.0, preferredTimescale: 600)
        let duration = CMTime(seconds: 5.0, preferredTimescale: 600)
        let range = CMTimeRange(start: start, duration: duration)
        
        XCTAssertTrue(range.isValid)
        XCTAssertEqual(range.start.seconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(range.duration.seconds, 5.0, accuracy: 0.001)
    }
    
    func testCMTimeRangeEnd() throws {
        let start = CMTime(seconds: 1.0, preferredTimescale: 600)
        let duration = CMTime(seconds: 5.0, preferredTimescale: 600)
        let range = CMTimeRange(start: start, duration: duration)
        let end = range.end
        
        XCTAssertEqual(end.seconds, 6.0, accuracy: 0.001)
    }
    
    func testCMTimeRangeContainsTime() throws {
        let start = CMTime(seconds: 1.0, preferredTimescale: 600)
        let duration = CMTime(seconds: 5.0, preferredTimescale: 600)
        let range = CMTimeRange(start: start, duration: duration)
        
        let timeInside = CMTime(seconds: 3.0, preferredTimescale: 600)
        let timeOutside = CMTime(seconds: 7.0, preferredTimescale: 600)
        
        XCTAssertTrue(range.containsTime(timeInside))
        XCTAssertFalse(range.containsTime(timeOutside))
    }
    
    func testCMTimeRangeUnion() throws {
        let range1 = CMTimeRange(
            start: CMTime(seconds: 1.0, preferredTimescale: 600),
            duration: CMTime(seconds: 3.0, preferredTimescale: 600)
        )
        let range2 = CMTimeRange(
            start: CMTime(seconds: 3.0, preferredTimescale: 600),
            duration: CMTime(seconds: 3.0, preferredTimescale: 600)
        )
        
        let union = CMTimeRangeGetUnion(range1, otherRange: range2)
        
        XCTAssertEqual(union.start.seconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(union.end.seconds, 6.0, accuracy: 0.001)
    }
    
    func testCMTimeRangeIntersection() throws {
        let range1 = CMTimeRange(
            start: CMTime(seconds: 1.0, preferredTimescale: 600),
            duration: CMTime(seconds: 5.0, preferredTimescale: 600)
        )
        let range2 = CMTimeRange(
            start: CMTime(seconds: 3.0, preferredTimescale: 600),
            duration: CMTime(seconds: 5.0, preferredTimescale: 600)
        )
        
        let intersection = CMTimeRangeGetIntersection(range1, otherRange: range2)
        
        XCTAssertTrue(intersection.isValid)
        XCTAssertEqual(intersection.start.seconds, 3.0, accuracy: 0.001)
        XCTAssertEqual(intersection.end.seconds, 6.0, accuracy: 0.001)
    }
    
    // MARK: - AVMutableMovieTrack Tests
    
    func testAddVideoTrack() throws {
        let movie = AVMutableMovie()
        let track = movie.addMutableTrack(
            withMediaType: .video,
            copySettingsFrom: nil,
            options: nil
        )
        
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.mediaType, .video)
    }
    
    func testAddAudioTrack() throws {
        let movie = AVMutableMovie()
        let track = movie.addMutableTrack(
            withMediaType: .audio,
            copySettingsFrom: nil,
            options: nil
        )
        
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.mediaType, .audio)
    }
    
    func testMultipleTracksRange() throws {
        let movie = AVMutableMovie()
        
        let videoTrack = movie.addMutableTrack(
            withMediaType: .video,
            copySettingsFrom: nil,
            options: nil
        )
        let audioTrack = movie.addMutableTrack(
            withMediaType: .audio,
            copySettingsFrom: nil,
            options: nil
        )
        
        XCTAssertNotNil(videoTrack)
        XCTAssertNotNil(audioTrack)
        
        // Verify tracks were added
        XCTAssertTrue(movie.tracks.count == 2)
        
        // Range for empty tracks - may be zero, invalid, or empty
        let range = movie.range
        // Empty tracks should result in an empty or zero range
        XCTAssertTrue(range == CMTimeRange.zero || range.isEmpty || !range.isValid)
    }
    
    // MARK: - Notification Tests
    
    func testMovieWasMutatedNotificationName() throws {
        let notificationName = Notification.Name.movieWasMutated
        XCTAssertEqual(notificationName.rawValue, "movieWasMutated")
    }
    
    // MARK: - Performance Tests
    
    func testTimeCalculationPerformance() throws {
        measure {
            for _ in 0..<1000 {
                _ = CMTime(seconds: 1.0, preferredTimescale: 600)
            }
        }
    }
    
    func testTimeRangeCalculationPerformance() throws {
        measure {
            for _ in 0..<1000 {
                let start = CMTime(seconds: 1.0, preferredTimescale: 600)
                let duration = CMTime(seconds: 5.0, preferredTimescale: 600)
                _ = CMTimeRange(start: start, duration: duration)
            }
        }
    }
    
    func testMovieRangePerformance() throws {
        let movie = AVMutableMovie()
        
        // Add multiple tracks
        for _ in 0..<10 {
            _ = movie.addMutableTrack(
                withMediaType: .video,
                copySettingsFrom: nil,
                options: nil
            )
        }
        
        measure {
            _ = movie.range
        }
    }
    
    func testMovieHeaderGenerationPerformance() throws {
        let movie = AVMutableMovie()
        _ = movie.addMutableTrack(
            withMediaType: .video,
            copySettingsFrom: nil,
            options: nil
        )
        
        measure {
            _ = movie.movHeader
        }
    }
    
    // MARK: - Track Offset Tests
    
    func testCMTimeParserTimecode() throws {
        let timescale: CMTimeScale = 600
        
        // Test HH:MM:SS format
        let time1 = try CMTimeParser.parse("00:01:30", timescale: timescale)
        XCTAssertEqual(time1.seconds, 90.0, accuracy: 0.001)
        
        // Test HH:MM:SS.mmm format
        let time2 = try CMTimeParser.parse("00:01:30.500", timescale: timescale)
        XCTAssertEqual(time2.seconds, 90.5, accuracy: 0.001)
        
        // Test H:MM:SS format (single digit hour)
        let time3 = try CMTimeParser.parse("1:02:03", timescale: timescale)
        XCTAssertEqual(time3.seconds, 3723.0, accuracy: 0.001)
    }
    
    func testCMTimeParserFrames() throws {
        let timescale: CMTimeScale = 600
        
        // Test positive frames
        let time1 = try CMTimeParser.parse("30f", timescale: timescale)
        XCTAssertEqual(time1.value, 30)
        XCTAssertEqual(time1.timescale, timescale)
        
        // Test negative frames
        let time2 = try CMTimeParser.parse("-15f", timescale: timescale)
        XCTAssertEqual(time2.value, -15)
        XCTAssertEqual(time2.timescale, timescale)
    }
    
    func testCMTimeParserSeconds() throws {
        let timescale: CMTimeScale = 600
        
        // Test positive seconds
        let time1 = try CMTimeParser.parse("1.5", timescale: timescale)
        XCTAssertEqual(time1.seconds, 1.5, accuracy: 0.001)
        
        // Test negative seconds
        let time2 = try CMTimeParser.parse("-2.3", timescale: timescale)
        XCTAssertEqual(time2.seconds, -2.3, accuracy: 0.001)
        
        // Test integer seconds
        let time3 = try CMTimeParser.parse("10", timescale: timescale)
        XCTAssertEqual(time3.seconds, 10.0, accuracy: 0.001)
    }
    
    func testCMTimeParserInvalid() throws {
        let timescale: CMTimeScale = 600
        
        // Test invalid formats
        XCTAssertThrowsError(try CMTimeParser.parse("invalid", timescale: timescale))
        XCTAssertThrowsError(try CMTimeParser.parse("", timescale: timescale))
        XCTAssertThrowsError(try CMTimeParser.parse("1:2:3:4", timescale: timescale))
    }
    
    func testTrackDescriptors() throws {
        let movie = AVMutableMovie()
        movie.timescale = 600
        
        // Add tracks in mixed order
        _ = movie.addMutableTrack(withMediaType: .audio, copySettingsFrom: nil, options: nil)
        _ = movie.addMutableTrack(withMediaType: .video, copySettingsFrom: nil, options: nil)
        _ = movie.addMutableTrack(withMediaType: .audio, copySettingsFrom: nil, options: nil)
        
        let mutator = MovieMutator(with: movie)
        let descriptors = mutator.trackDescriptors()
        
        // Should return 3 tracks
        XCTAssertEqual(descriptors.count, 3)
        
        // First should be video (ordered video → audio → timecode → other)
        XCTAssertEqual(descriptors[0].mediaType, .video)
        
        // Next two should be audio
        XCTAssertEqual(descriptors[1].mediaType, .audio)
        XCTAssertEqual(descriptors[2].mediaType, .audio)
        
        // All should have zero offset initially
        for descriptor in descriptors {
            XCTAssertEqual(descriptor.currentOffset, CMTime.zero)
        }
    }
    
    func testTrackDescriptorCaching() throws {
        let movie = AVMutableMovie()
        movie.timescale = 600
        _ = movie.addMutableTrack(withMediaType: .video, copySettingsFrom: nil, options: nil)
        
        let mutator = MovieMutator(with: movie)
        
        // First call
        let descriptors1 = mutator.trackDescriptors()
        
        // Second call should return cached result (same instance)
        let descriptors2 = mutator.trackDescriptors()
        
        XCTAssertEqual(descriptors1.count, descriptors2.count)
        XCTAssertEqual(descriptors1[0].id, descriptors2[0].id)
    }
}
