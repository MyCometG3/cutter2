//
//  SampleBufferPoolTests.swift
//  cutter2Tests
//
//  Created by Takashi Mochizuki on 2025/10/18.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
import CoreMedia
@testable import cutter2

/// Unit tests for SampleBufferPool
///
/// Tests buffer pool functionality including:
/// - Buffer acquisition and release
/// - Pool hit/miss statistics
/// - Memory limits and eviction
/// - Size class handling
/// - Memory pressure response
final class SampleBufferPoolTests: XCTestCase {
    
    var pool: SampleBufferPool!
    
    override func setUp() async throws {
        try await super.setUp()
        // Create pool with smaller limits for testing
        pool = SampleBufferPool(maxTotalMemory: 1_000_000, enableMemoryPressureMonitoring: false)
    }
    
    override func tearDown() async throws {
        await pool.drain()
        pool = nil
        try await super.tearDown()
    }
    
    /* ============================================ */
    // MARK: - Basic Acquisition Tests
    /* ============================================ */
    
    /// Test that acquiring from empty pool returns nil
    func testAcquireFromEmptyPool() async throws {
        let buffer = await pool.acquire(capacity: 100_000, mediaType: .video)
        XCTAssertNil(buffer, "Acquiring from empty pool should return nil")
        
        let stats = await pool.statistics
        XCTAssertEqual(stats.totalAcquires, 1)
        XCTAssertEqual(stats.poolMisses, 1)
        XCTAssertEqual(stats.poolHits, 0)
    }
    
    /// Test buffer release and subsequent acquisition
    func testReleaseAndAcquire() async throws {
        // Create a test sample buffer
        guard let sampleBuffer = createTestSampleBuffer(capacity: 100_000, mediaType: .video) else {
            XCTFail("Failed to create test sample buffer")
            return
        }
        
        // Release buffer to pool
        await pool.release(sampleBuffer, capacity: 100_000, mediaType: .video)
        
        var stats = await pool.statistics
        XCTAssertEqual(stats.currentPoolSize, 1)
        
        // Acquire buffer from pool
        let acquiredBuffer = await pool.acquire(capacity: 100_000, mediaType: .video)
        XCTAssertNotNil(acquiredBuffer, "Should acquire buffer from pool")
        
        stats = await pool.statistics
        XCTAssertEqual(stats.poolHits, 1)
        XCTAssertEqual(stats.currentPoolSize, 0)
    }
    
    /* ============================================ */
    // MARK: - Size Class Tests
    /* ============================================ */
    
    /// Test that buffers are organized by size class
    func testSizeClassSegregation() async throws {
        // Create buffers of different sizes
        let smallBuffer = createTestSampleBuffer(capacity: 50_000, mediaType: .audio)    // Small
        let mediumBuffer = createTestSampleBuffer(capacity: 500_000, mediaType: .video)  // Medium
        let largeBuffer = createTestSampleBuffer(capacity: 2_000_000, mediaType: .video) // Large
        
        guard let smallBuffer = smallBuffer,
              let mediumBuffer = mediumBuffer,
              let largeBuffer = largeBuffer else {
            XCTFail("Failed to create test buffers")
            return
        }
        
        // Release all buffers
        await pool.release(smallBuffer, capacity: 50_000, mediaType: .audio)
        await pool.release(mediumBuffer, capacity: 500_000, mediaType: .video)
        await pool.release(largeBuffer, capacity: 2_000_000, mediaType: .video)
        
        let stats = await pool.statistics
        XCTAssertEqual(stats.currentPoolSize, 3)
        
        // Acquire medium buffer - should only get medium, not large or small
        let acquired = await pool.acquire(capacity: 500_000, mediaType: .video)
        XCTAssertNotNil(acquired)
        
        // Pool should still have 2 buffers (small and large)
        let statsAfter = await pool.statistics
        XCTAssertEqual(statsAfter.currentPoolSize, 2)
    }
    
    /// Test media type segregation
    func testMediaTypeSegregation() async throws {
        guard let videoBuffer = createTestSampleBuffer(capacity: 100_000, mediaType: .video),
              let audioBuffer = createTestSampleBuffer(capacity: 100_000, mediaType: .audio) else {
            XCTFail("Failed to create test buffers")
            return
        }
        
        // Release both
        await pool.release(videoBuffer, capacity: 100_000, mediaType: .video)
        await pool.release(audioBuffer, capacity: 100_000, mediaType: .audio)
        
        // Acquire video buffer
        let acquiredVideo = await pool.acquire(capacity: 100_000, mediaType: .video)
        XCTAssertNotNil(acquiredVideo)
        
        // Pool should still have audio buffer
        let stats = await pool.statistics
        XCTAssertEqual(stats.currentPoolSize, 1)
        
        // Acquire audio buffer
        let acquiredAudio = await pool.acquire(capacity: 100_000, mediaType: .audio)
        XCTAssertNotNil(acquiredAudio)
        
        let finalStats = await pool.statistics
        XCTAssertEqual(finalStats.currentPoolSize, 0)
    }
    
    /* ============================================ */
    // MARK: - Memory Limit Tests
    /* ============================================ */
    
    /// Test that pool respects maximum pool size per size class
    func testSizeClassPoolLimit() async throws {
        // BufferSizeClass.medium has maxPoolSize of 10
        // Release 15 medium buffers
        for _ in 0..<15 {
            if let buffer = createTestSampleBuffer(capacity: 500_000, mediaType: .video) {
                await pool.release(buffer, capacity: 500_000, mediaType: .video)
            }
        }
        
        // Pool should not exceed 10 for medium size class
        let stats = await pool.statistics
        XCTAssertLessThanOrEqual(stats.currentPoolSize, 10)
    }
    
    /// Test that pool respects total memory limit
    func testTotalMemoryLimit() async throws {
        // Pool max is 1 MB for testing
        // Try to add 2 MB worth of buffers
        for _ in 0..<3 {
            if let buffer = createTestSampleBuffer(capacity: 800_000, mediaType: .video) {
                await pool.release(buffer, capacity: 800_000, mediaType: .video)
            }
        }
        
        // Should have evicted oldest buffers to stay under limit
        let memoryUsage = await pool.currentMemoryUsageForTesting
        XCTAssertLessThanOrEqual(memoryUsage, 1_000_000)
    }
    
    /* ============================================ */
    // MARK: - Statistics Tests
    /* ============================================ */
    
    /// Test hit rate calculation
    func testHitRateCalculation() async throws {
        // Create and release a buffer
        guard let buffer = createTestSampleBuffer(capacity: 100_000, mediaType: .video) else {
            XCTFail("Failed to create test buffer")
            return
        }
        
        await pool.release(buffer, capacity: 100_000, mediaType: .video)
        
        // Do 5 acquires: 1 hit, 4 misses
        _ = await pool.acquire(capacity: 100_000, mediaType: .video)  // Hit
        _ = await pool.acquire(capacity: 100_000, mediaType: .video)  // Miss
        _ = await pool.acquire(capacity: 100_000, mediaType: .video)  // Miss
        _ = await pool.acquire(capacity: 100_000, mediaType: .video)  // Miss
        _ = await pool.acquire(capacity: 100_000, mediaType: .video)  // Miss
        
        let stats = await pool.statistics
        XCTAssertEqual(stats.totalAcquires, 5)
        XCTAssertEqual(stats.poolHits, 1)
        XCTAssertEqual(stats.poolMisses, 4)
        XCTAssertEqual(stats.hitRate, 0.2, accuracy: 0.01)
    }
    
    /// Test peak pool size tracking
    func testPeakPoolSizeTracking() async throws {
        // Add 3 buffers
        for _ in 0..<3 {
            if let buffer = createTestSampleBuffer(capacity: 100_000, mediaType: .video) {
                await pool.release(buffer, capacity: 100_000, mediaType: .video)
            }
        }
        
        var stats = await pool.statistics
        XCTAssertEqual(stats.currentPoolSize, 3)
        XCTAssertEqual(stats.peakPoolSize, 3)
        
        // Acquire 2 buffers
        _ = await pool.acquire(capacity: 100_000, mediaType: .video)
        _ = await pool.acquire(capacity: 100_000, mediaType: .video)
        
        stats = await pool.statistics
        XCTAssertEqual(stats.currentPoolSize, 1)
        XCTAssertEqual(stats.peakPoolSize, 3)  // Peak should remain
    }
    
    /* ============================================ */
    // MARK: - Drain Tests
    /* ============================================ */
    
    /// Test pool drain functionality
    func testDrain() async throws {
        // Add several buffers
        for _ in 0..<5 {
            if let buffer = createTestSampleBuffer(capacity: 100_000, mediaType: .video) {
                await pool.release(buffer, capacity: 100_000, mediaType: .video)
            }
        }
        
        var stats = await pool.statistics
        XCTAssertEqual(stats.currentPoolSize, 5)
        
        // Drain pool
        await pool.drain()
        
        stats = await pool.statistics
        XCTAssertEqual(stats.currentPoolSize, 0)
        XCTAssertEqual(stats.totalDrains, 1)
        
        let memoryUsage = await pool.currentMemoryUsageForTesting
        XCTAssertEqual(memoryUsage, 0)
    }
    
    /* ============================================ */
    // MARK: - Concurrent Access Tests
    /* ============================================ */
    
    /// Test concurrent buffer acquisition and release
    func testConcurrentAccess() async throws {
        // Create initial buffers
        var buffers: [CMSampleBuffer] = []
        for _ in 0..<10 {
            if let buffer = createTestSampleBuffer(capacity: 100_000, mediaType: .video) {
                buffers.append(buffer)
                await pool.release(buffer, capacity: 100_000, mediaType: .video)
            }
        }
        
        // Perform concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Acquire tasks
            for _ in 0..<20 {
                group.addTask {
                    _ = await self.pool.acquire(capacity: 100_000, mediaType: .video)
                }
            }
            
            // Release tasks
            for buffer in buffers {
                group.addTask {
                    await self.pool.release(buffer, capacity: 100_000, mediaType: .video)
                }
            }
        }
        
        // No crash = success
        let stats = await pool.statistics
        XCTAssertGreaterThan(stats.totalAcquires, 0)
    }
    
    /* ============================================ */
    // MARK: - Performance Tests
    /* ============================================ */
    
    /// Test performance of buffer acquisition
    func testAcquisitionPerformance() async throws {
        // Pre-populate pool
        for _ in 0..<10 {
            if let buffer = createTestSampleBuffer(capacity: 100_000, mediaType: .video) {
                await pool.release(buffer, capacity: 100_000, mediaType: .video)
            }
        }
        
        measure {
            Task {
                for _ in 0..<1000 {
                    _ = await pool.acquire(capacity: 100_000, mediaType: .video)
                }
            }
        }
    }
    
    /* ============================================ */
    // MARK: - Helper Methods
    /* ============================================ */
    
    /// Create a test sample buffer with specified capacity and media type
    private func createTestSampleBuffer(capacity: Int, mediaType: AVMediaType) -> CMSampleBuffer? {
        // Create a simple test buffer
        // Note: In real usage, these come from AVAssetReader
        
        // For testing, we'll create a minimal valid CMSampleBuffer
        // This is a simplified version; real buffers are more complex
        
        let blockBufferAllocator = kCFAllocatorDefault
        var blockBuffer: CMBlockBuffer?
        
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: capacity,
            blockAllocator: blockBufferAllocator,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: capacity,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == kCMBlockBufferNoErr, let blockBuffer = blockBuffer else {
            return nil
        }
        
        // Create format description based on media type
        var formatDescription: CMFormatDescription?
        if mediaType == .video {
            // Create minimal video format description
            CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: kCMVideoCodecType_422YpCbCr8,
                width: 1920,
                height: 1080,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
        } else {
            // Create minimal audio format description
            var audioStreamBasicDescription = AudioStreamBasicDescription(
                mSampleRate: 48000.0,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4,
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,
                mChannelsPerFrame: 2,
                mBitsPerChannel: 16,
                mReserved: 0
            )
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &audioStreamBasicDescription,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
        }
        
        guard let formatDescription = formatDescription else {
            return nil
        }
        
        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime.zero,
            decodeTimeStamp: CMTime.invalid
        )
        
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
}
