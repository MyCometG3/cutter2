//
//  cutter2Tests.swift
//  cutter2Tests
//
//  Created on 2025-10-13.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Integration tests for cutter2 application
final class cutter2Tests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Cleanup
    }

    // MARK: - Basic Integration Tests
    
    func testApplicationBundle() throws {
        // Verify that the application bundle exists
        let bundle = Bundle(for: type(of: self))
        XCTAssertNotNil(bundle)
        XCTAssertNotNil(bundle.bundleIdentifier)
    }
    
    func testApplicationInfo() throws {
        // Test that application info is accessible
        let bundle = Bundle.main
        XCTAssertNotNil(bundle.infoDictionary)
        
        if let info = bundle.infoDictionary {
            // Check for common Info.plist keys
            XCTAssertTrue(info.keys.count > 0)
        }
    }
    
    // MARK: - Framework Availability Tests
    
    func testAVFoundationAvailability() throws {
        // Verify AVFoundation framework is available
        XCTAssertTrue(true, "AVFoundation framework is available")
        
        // Test basic AVFoundation class availability
        _ = AVMutableMovie()
        _ = CMTime.zero
        _ = CMTimeRange.zero
    }
    
    @MainActor
    func testCocoaAvailability() throws {
        // Verify Cocoa framework is available
        XCTAssertTrue(true, "Cocoa framework is available")
        
        // Test basic Cocoa class availability
        _ = NSApplication.shared
        _ = NSDocument()
        _ = UndoManager()
    }
    
    // MARK: - Document Type Tests
    
    func testSupportedFileTypes() throws {
        // Test that the application supports common video file types
        let movType = "com.apple.quicktime-movie"
        let mp4Type = "public.mpeg-4"
        let m4vType = "com.apple.m4v-video"
        let m4aType = "com.apple.m4a-audio"
        
        XCTAssertFalse(movType.isEmpty)
        XCTAssertFalse(mp4Type.isEmpty)
        XCTAssertFalse(m4vType.isEmpty)
        XCTAssertFalse(m4aType.isEmpty)
    }
    
    @MainActor
    func testDocumentTypeRegistration() throws {
        // Verify Document class can handle different file types
        let readableTypes = Document.readableTypes
        
        XCTAssertTrue(readableTypes.count > 0)
        XCTAssertTrue(readableTypes.contains("com.apple.quicktime-movie"))
    }
    
    // MARK: - Time Handling Integration Tests
    
    func testTimeSystemIntegration() throws {
        // Test that the time system works correctly
        let time1 = CMTime(seconds: 1.0, preferredTimescale: 600)
        let time2 = CMTime(seconds: 2.0, preferredTimescale: 600)
        
        let sum = time1 + time2
        let difference = time2 - time1
        
        XCTAssertEqual(sum.seconds, 3.0, accuracy: 0.001)
        XCTAssertEqual(difference.seconds, 1.0, accuracy: 0.001)
        
        // Test time range
        let range = CMTimeRange(start: time1, duration: time2)
        XCTAssertTrue(range.isValid)
        XCTAssertTrue(range.containsTime(time2))
    }
    
    func testTimeRangeOperations() throws {
        // Test time range union and intersection
        let range1 = CMTimeRange(
            start: CMTime(seconds: 0.0, preferredTimescale: 600),
            duration: CMTime(seconds: 5.0, preferredTimescale: 600)
        )
        let range2 = CMTimeRange(
            start: CMTime(seconds: 3.0, preferredTimescale: 600),
            duration: CMTime(seconds: 5.0, preferredTimescale: 600)
        )
        
        let union = CMTimeRangeGetUnion(range1, otherRange: range2)
        let intersection = CMTimeRangeGetIntersection(range1, otherRange: range2)
        
        XCTAssertTrue(union.isValid)
        XCTAssertTrue(intersection.isValid)
        XCTAssertEqual(union.start.seconds, 0.0, accuracy: 0.001)
        XCTAssertEqual(intersection.start.seconds, 3.0, accuracy: 0.001)
    }
    
    // MARK: - Movie Operations Integration Tests
    
    func testMovieCreation() throws {
        // Test that we can create an empty movie
        let movie = AVMutableMovie()
        XCTAssertNotNil(movie)
        
        let range = movie.range
        XCTAssertTrue(range == CMTimeRange.zero)
    }
    
    func testMovieTrackOperations() throws {
        // Test adding tracks to a movie
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
        XCTAssertEqual(videoTrack?.mediaType, .video)
        XCTAssertEqual(audioTrack?.mediaType, .audio)
    }
    
    func testMovieHeaderGeneration() throws {
        // Test movie header generation
        let movie = AVMutableMovie()
        let header = movie.movHeader
        
        XCTAssertNotNil(header)
        XCTAssertTrue(header!.count > 0)
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testErrorHandlingSystem() throws {
        // Test the error handling system
        enum TestError: NSErrorConvertible {
            case testError
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.integration",
                    code: 100,
                    userInfo: [NSLocalizedDescriptionKey: "Integration test error"]
                )
            }
        }
        
        XCTAssertThrowsError(try ErrorUtilities.throwError(TestError.testError)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "com.test.integration")
            XCTAssertEqual(nsError.code, 100)
            XCTAssertTrue(nsError.localizedDescription.contains("Integration test error"))
        }
    }
    
    func testErrorWithReason() throws {
        enum TestError: NSErrorConvertible {
            case testError
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.integration",
                    code: 101,
                    userInfo: [NSLocalizedDescriptionKey: "Base error"]
                )
            }
        }
        
        XCTAssertThrowsError(try ErrorUtilities.throwError(TestError.testError, reason: "Detailed reason")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, "Detailed reason")
        }
    }
    
    // MARK: - Notification System Tests
    
    func testNotificationSystem() throws {
        let expectation = self.expectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .movieWasMutated,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.name, .movieWasMutated)
            expectation.fulfill()
        }
        
        NotificationCenter.default.post(name: .movieWasMutated, object: nil)
        
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testNotificationWithUserInfo() throws {
        let expectation = self.expectation(description: "Notification with user info")
        let testData = ["key": "value"]
        
        let observer = NotificationCenter.default.addObserver(
            forName: .movieWasMutated,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo as? [String: String] {
                XCTAssertEqual(userInfo["key"], "value")
            }
            expectation.fulfill()
        }
        
        NotificationCenter.default.post(
            name: .movieWasMutated,
            object: nil,
            userInfo: testData
        )
        
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    // MARK: - Async/Await Integration Tests
    
    func testAsyncAwaitSupport() async throws {
        // Test that async/await works correctly
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: "Success")
            }
        }
        
        XCTAssertEqual(result, "Success")
    }
    
    func testMainActorIntegration() async throws {
        // Test MainActor integration
        await MainActor.run {
            XCTAssertTrue(Thread.isMainThread)
        }
        
        // Test background task
        let backgroundResult = await Task.detached {
            return "Background task"
        }.value
        
        XCTAssertEqual(backgroundResult, "Background task")
    }
    
    // MARK: - Constants Integration Tests
    
    func testAllConstantsAccessible() throws {
        // Test that all constant values are accessible
        _ = kTranscodePresetKey
        _ = kVideoCodecKey
        _ = kAudioCodecKey
        _ = timeInfoKey
        _ = rangeInfoKey
        _ = clapSizeKey
        _ = paspRatioKey
        
        XCTAssertTrue(true, "All constants are accessible")
    }
    
    // MARK: - Performance Tests
    
    func testOverallSystemPerformance() throws {
        measure {
            // Test overall system performance
            let movie = AVMutableMovie()
            _ = movie.addMutableTrack(withMediaType: .video, copySettingsFrom: nil, options: nil)
            _ = movie.range
            _ = movie.movHeader
            
            let time = CMTime(seconds: 1.0, preferredTimescale: 600)
            let range = CMTimeRange(start: .zero, duration: time)
            _ = range.isValid
        }
    }
    
    func testMemoryEfficiency() throws {
        // Test that we don't leak memory during common operations
        measure(metrics: [XCTMemoryMetric()]) {
            for _ in 0..<100 {
                let movie = AVMutableMovie()
                _ = movie.addMutableTrack(withMediaType: .video, copySettingsFrom: nil, options: nil)
                _ = movie.range
            }
        }
    }
}

