//
//  ConcurrencyImprovementsTests.swift
//  cutter2
//
//  Tests for Swift concurrency improvements
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Test suite for validating concurrency improvements
final class ConcurrencyImprovementsTests: XCTestCase {
    
    var testMovie: AVMutableMovie!
    var movieMutator: MovieMutator!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a test movie with sample data
        testMovie = AVMutableMovie()
        testMovie.timescale = 600
        
        // Add a test video track (simplified for testing)
        let videoTrack = testMovie.addMutableTrack(withMediaType: .video, preferredTrackID: 1)
        XCTAssertNotNil(videoTrack)
        
        movieMutator = MovieMutator(with: testMovie)
    }
    
    override func tearDown() async throws {
        movieMutator = nil
        testMovie = nil
        try await super.tearDown()
    }
    
    // MARK: - Performance Tests
    
    func testPerformAsyncOnMainActorPerformance() async throws {
        let iterations = 1000
        var results: [CMTime] = []
        
        // Test the new async pattern
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            let result = try await movieMutator.performAsyncOnMainActor {
                return CMTimeMake(value: Int64(i), timescale: 600)
            }
            results.append(result)
        }
        
        let asyncTime = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertEqual(results.count, iterations)
        
        // Verify performance is reasonable (should complete in under 1 second)
        XCTAssertLessThan(asyncTime, 1.0, "Async operations took too long: \(asyncTime) seconds")
    }
    
    func testProgressStreamPerformance() async throws {
        let expectation = XCTestExpectation(description: "Progress stream should complete")
        let progressStream = movieMutator.createProgressStream()
        
        var updateCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let task = Task {
            for await update in progressStream {
                updateCount += 1
                
                // Stop after receiving reasonable number of updates
                if updateCount >= 100 {
                    break
                }
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        task.cancel()
        
        let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertGreaterThan(updateCount, 50, "Should receive multiple progress updates")
        XCTAssertLessThan(elapsedTime, 5.0, "Progress stream should be responsive")
    }
    
    // MARK: - Correctness Tests
    
    func testMainActorIsolationMaintained() async throws {
        // Verify that operations maintain proper main actor isolation
        let result = try await movieMutator.performAsyncOnMainActor {
            XCTAssert(Thread.isMainThread, "Should be executing on main thread")
            return movieMutator.movieDuration()
        }
        
        XCTAssertNotNil(result)
    }
    
    func testProgressUpdateStructure() async throws {
        let progressStream = movieMutator.createProgressStream()
        var firstUpdate: ProgressUpdate?
        
        let task = Task {
            for await update in progressStream {
                firstUpdate = update
                break
            }
        }
        
        // Give it a moment to generate an update
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        task.cancel()
        
        XCTAssertNotNil(firstUpdate)
        if let update = firstUpdate {
            XCTAssertGreaterThanOrEqual(update.progress, 0.0)
            XCTAssertLessThanOrEqual(update.progress, 1.0)
            XCTAssertNotNil(update.currentTime)
            XCTAssertNotNil(update.selectedRange)
            XCTAssertNotNil(update.movieDuration)
        }
    }
    
    // MARK: - Cancellation Tests
    
    func testAsyncOperationCancellation() async throws {
        let expectation = XCTestExpectation(description: "Operation should be cancellable")
        
        let task = Task {
            do {
                let progressStream = movieMutator.createProgressStream()
                for await _ in progressStream {
                    // This should be cancelled
                }
                XCTFail("Stream should have been cancelled")
            } catch is CancellationError {
                expectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        // Cancel after a short delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        task.cancel()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Memory Tests
    
    func testMemoryLeakPrevention() async throws {
        weak var weakMutator: MovieMutator?
        
        do {
            let localMutator = MovieMutator(with: testMovie)
            weakMutator = localMutator
            
            // Perform some async operations
            let _ = try await localMutator.performAsyncOnMainActor {
                return localMutator.movieDuration()
            }
            
            // Start and cancel a progress stream
            let task = Task {
                let progressStream = localMutator.createProgressStream()
                for await _ in progressStream {
                    // Consume stream briefly
                }
            }
            
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            task.cancel()
        }
        
        // Force garbage collection attempt
        for _ in 0..<10 {
            autoreleasepool {
                _ = Array(0..<1000).map { $0 }
            }
        }
        
        // Check that the mutator was deallocated
        XCTAssertNil(weakMutator, "MovieMutator should be deallocated after async operations")
    }
    
    // MARK: - Integration Tests
    
    func testAsyncIntegrationWithMainActor() async throws {
        // Test that async operations integrate properly with @MainActor
        await MainActor.run {
            let duration = movieMutator.movieDuration()
            XCTAssertNotNil(duration)
        }
        
        // Test async call from main actor context
        let result = try await movieMutator.performAsyncOnMainActor {
            return movieMutator.movieRange()
        }
        
        XCTAssertNotNil(result)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandlingInAsyncOperations() async throws {
        // Test error propagation in async context
        do {
            let _ = try await movieMutator.performAsyncOnMainActor {
                throw MovieMutator.EditError.invalidRange
            }
            XCTFail("Should have thrown an error")
        } catch MovieMutator.EditError.invalidRange {
            // Expected error
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Performance Benchmarks

extension ConcurrencyImprovementsTests {
    
    func testBenchmarkAsyncVsSyncPerformance() async throws {
        let iterations = 100
        
        // Benchmark traditional sync approach (for comparison)
        let syncStartTime = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            let _ = movieMutator.performSyncOnMainActor {
                return CMTimeMake(value: Int64(i), timescale: 600)
            }
        }
        let syncTime = CFAbsoluteTimeGetCurrent() - syncStartTime
        
        // Benchmark new async approach
        let asyncStartTime = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            let _ = try await movieMutator.performAsyncOnMainActor {
                return CMTimeMake(value: Int64(i), timescale: 600)
            }
        }
        let asyncTime = CFAbsoluteTimeGetCurrent() - asyncStartTime
        
        print("Sync time: \(syncTime)s, Async time: \(asyncTime)s")
        
        // Async should be competitive or better (not significantly slower)
        XCTAssertLessThan(asyncTime, syncTime * 2.0, "Async approach should not be significantly slower")
    }
}

// MARK: - Mock Objects for Testing

class MockProgressDelegate: ModernSampleBufferChannelDelegate {
    var receivedBuffers: [CMSampleBuffer] = []
    
    func didRead(from channel: ModernSampleBufferChannel, buffer: CMSampleBuffer) async {
        receivedBuffers.append(buffer)
    }
}

// MARK: - Test Utilities

extension ConcurrencyImprovementsTests {
    
    /// Helper to create a sample CMSampleBuffer for testing
    private func createTestSampleBuffer() -> CMSampleBuffer? {
        // Simplified sample buffer creation for testing
        // In real implementation, this would create proper video/audio sample buffers
        return nil
    }
    
    /// Helper to measure async operation performance
    private func measureAsync<T>(_ operation: () async throws -> T) async rethrows -> (result: T, duration: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        return (result, duration)
    }
}