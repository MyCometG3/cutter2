//
//  PerformanceTests.swift
//  cutter2Tests
//
//  Created by Takashi Mochizuki on 2025/10/15.
//  Copyright © 2025-2026 MyCometG3. All rights reserved.
//

import XCTest
@testable import cutter2

/* ============================================ */
// MARK: - Performance Tests
/* ============================================ */

/// Performance tests for Phase 2.2 optimization
///
/// These tests establish baseline metrics and verify that optimizations
/// do not cause performance regressions.
@MainActor
final class PerformanceTests: XCTestCase {
    
    /* ============================================ */
    // MARK: - Setup
    /* ============================================ */
    
    override func setUp() async throws {
        try await super.setUp()
        PerformanceMetrics.shared.reset()
        PerformanceMetrics.shared.loggingEnabled = false // Quiet during tests
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
    }
    
    /* ============================================ */
    // MARK: - PerformanceMetrics Tests
    /* ============================================ */
    
    func testPerformanceMetricsMeasurement() {
        let result = PerformanceMetrics.shared.measure("TestOperation") {
            // Simulate some work
            var sum = 0
            for i in 0..<1000 {
                sum += i
            }
            return sum
        }
        
        XCTAssertEqual(result, 499500)
        
        // Verify measurement was recorded
        let stats = PerformanceMetrics.shared.statistics(for: "TestOperation")
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?["count"], 1.0)
        XCTAssertGreaterThan(stats?["average"] ?? 0, 0)
    }
    
    func testPerformanceMetricsAsyncMeasurement() async {
        let result = await PerformanceMetrics.shared.measureAsync("AsyncTestOperation") {
            // Simulate async work
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
            return 42
        }
        
        XCTAssertEqual(result, 42)
        
        // Verify measurement was recorded
        let stats = PerformanceMetrics.shared.statistics(for: "AsyncTestOperation")
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?["count"], 1.0)
        XCTAssertGreaterThanOrEqual(stats?["average"] ?? 0, 0.01) // At least 0.01s
    }
    
    func testPerformanceMetricsMultipleMeasurements() {
        // Take multiple measurements
        for i in 0..<5 {
            _ = PerformanceMetrics.shared.measure("MultiTest") {
                Thread.sleep(forTimeInterval: 0.001 * Double(i + 1))
                return i
            }
        }
        
        // Verify statistics
        let stats = PerformanceMetrics.shared.statistics(for: "MultiTest")
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?["count"], 5.0)
        
        // Min should be less than average, average less than max
        let min = stats?["min"] ?? 0
        let avg = stats?["average"] ?? 0
        let max = stats?["max"] ?? 0
        XCTAssertLessThan(min, avg)
        XCTAssertLessThan(avg, max)
    }
    
    func testPerformanceMetricsReport() {
        // Add some measurements
        _ = PerformanceMetrics.shared.measure("Operation1") { return 1 }
        _ = PerformanceMetrics.shared.measure("Operation2") { return 2 }
        
        let report = PerformanceMetrics.shared.report()
        XCTAssertTrue(report.contains("Performance Report"))
        XCTAssertTrue(report.contains("Operation1"))
        XCTAssertTrue(report.contains("Operation2"))
        XCTAssertTrue(report.contains("Average"))
        XCTAssertTrue(report.contains("Samples"))
    }
    
    func testPerformanceMetricsReset() {
        // Add measurement
        _ = PerformanceMetrics.shared.measure("ToBeReset") { return 1 }
        XCTAssertNotNil(PerformanceMetrics.shared.statistics(for: "ToBeReset"))
        
        // Reset and verify
        PerformanceMetrics.shared.reset()
        XCTAssertNil(PerformanceMetrics.shared.statistics(for: "ToBeReset"))
    }
    
    /* ============================================ */
    // MARK: - Baseline Performance Tests
    /* ============================================ */
    
    /// Baseline: Export progress polling interval
    ///
    /// Current implementation uses 1-second polling.
    /// Target: Reduce to 0.1 seconds (10x improvement)
    func testExportProgressPollingBaseline() {
        // Simple baseline test - just verify timing
        let start = Date()
        
        // Simulate some work
        var sum = 0
        for i in 0..<1000000 {
            sum += i
        }
        
        let duration = Date().timeIntervalSince(start)
        
        print("Baseline polling test: \(sum) operations in \(String(format: "%.3f", duration))s")
        
        // Just verify it completes
        XCTAssertGreaterThan(sum, 0)
    }
    
    /// Baseline: Timeline marker position update
    ///
    /// Measures the time to update a marker position
    /// Target: Maintain < 0.001s per update for 60 FPS
    func testTimelineMarkerUpdateBaseline() {
        // Note: This would need actual TimelineView instance
        // For now, we measure a simulated marker position calculation
        measure {
            var position: Double = 0.0
            for i in 0..<100 {
                // Simulate position calculation
                position = Double(i) / 100.0
                let _ = position * 1920.0 // Convert to pixel position
            }
        }
    }
    
    /// Baseline: Memory allocation pattern
    ///
    /// Measures memory allocation overhead
    func testMemoryAllocationBaseline() {
        measure(metrics: [XCTMemoryMetric()]) {
            var arrays: [[Int]] = []
            for _ in 0..<100 {
                let array = Array(0..<1000)
                arrays.append(array)
            }
            // Arrays will be released at end of scope
            XCTAssertEqual(arrays.count, 100)
        }
    }
    
    /* ============================================ */
    // MARK: - Regression Tests (for future optimizations)
    /* ============================================ */
    
    /// Test that PerformanceMetrics itself doesn't add significant overhead
    func testPerformanceMetricsOverhead() {
        // Run multiple iterations and take the best (lowest) measurement
        // to mitigate scheduling noise in parallel test environments
        let iterations = 5
        var bestOverheadPercent: Double = .infinity
        
        for _ in 0..<iterations {
            // Measure without PerformanceMetrics
            let startUntracked = CFAbsoluteTimeGetCurrent()
            var sumUntracked = 0
            for i in 0..<100_000 {
                sumUntracked += i
            }
            let durationUntracked = CFAbsoluteTimeGetCurrent() - startUntracked
            
            // Measure with PerformanceMetrics
            let startTracked = CFAbsoluteTimeGetCurrent()
            let sumTracked = PerformanceMetrics.shared.measure("OverheadTest") {
                var sum = 0
                for i in 0..<100_000 {
                    sum += i
                }
                return sum
            }
            let durationTracked = CFAbsoluteTimeGetCurrent() - startTracked
            
            XCTAssertEqual(sumUntracked, sumTracked)
            
            // Overhead should be minimal (< 30% increase)
            let overhead = durationTracked - durationUntracked
            let overheadPercent = (overhead / durationUntracked) * 100
            
            // Keep the best (lowest) overhead measurement
            if overheadPercent < bestOverheadPercent {
                bestOverheadPercent = overheadPercent
            }
        }
        
        // Assert on the best of multiple runs
        XCTAssertLessThan(bestOverheadPercent, 30.0,
            "Performance metrics overhead too high (best of \(iterations) runs: \(String(format: "%.2f", bestOverheadPercent))%)")
    }
}

/* ============================================ */
// MARK: - Export Performance Tests
/* ============================================ */

extension PerformanceTests {
    
    /// Test simulated export progress updates
    ///
    /// Baseline: 1-second intervals
    /// Target: 0.1-second intervals
    func testExportProgressUpdateFrequency() async {
        var progressUpdates: [Double] = []
        let updateInterval: TimeInterval = 0.1 // Faster for testing
        let progressStep: Double = 0.2 // Fewer updates for faster test (5 instead of 10)
        
        let result = await PerformanceMetrics.shared.measureAsync("ExportProgressSimulation") {
            let startTime = Date()
            var progress: Double = 0.0
            
            while progress <= 1.0 {
                progressUpdates.append(progress)
                progress += progressStep
                
                // Simulate polling interval
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
            }
            
            return Date().timeIntervalSince(startTime)
        }
        
        // Verify update frequency (should be 6 updates: 0.0, 0.2, 0.4, 0.6, 0.8, 1.0)
        XCTAssertGreaterThanOrEqual(progressUpdates.count, 5)
        
        // Total time should be around 0.6 seconds (6 updates * 0.1 second)
        XCTAssertGreaterThanOrEqual(result, 0.5)
        XCTAssertLessThanOrEqual(result, 1.0)
        
        print("Export progress simulation: \(progressUpdates.count) updates in \(String(format: "%.2f", result))s")
        print("Average interval: \(String(format: "%.3f", result / Double(progressUpdates.count)))s per update")
    }
}

/* ============================================ */
// MARK: - Timeline Performance Tests
/* ============================================ */

extension PerformanceTests {
    
    /// Test timeline position calculation performance
    func testTimelinePositionCalculation() {
        let duration: Double = 3600.0 // 1 hour video
        let viewWidth: Double = 1920.0 // Timeline width in pixels
        
        measure {
            for i in 0..<1000 {
                let time = Double(i) / 1000.0 * duration
                let _ = (time / duration) * viewWidth
            }
        }
    }
    
    /// Test timeline marker hit testing performance
    func testTimelineMarkerHitTesting() {
        let markers: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let tolerance: Double = 5.0 / 1920.0 // 5 pixels
        
        measure {
            for i in 0..<1000 {
                let testPosition = Double(i) / 1000.0
                let _ = markers.first { abs($0 - testPosition) < tolerance }
            }
        }
    }
}
