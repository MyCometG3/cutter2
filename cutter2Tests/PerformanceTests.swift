//
//  PerformanceTests.swift
//  cutter2Tests
//
//  Created by Takashi Mochizuki on 2025/10/15.
//  Copyright © 2025-2026 MyCometG3. All rights reserved.
//

import AppKit
import AVFoundation
import CoreMedia
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

    /// Undo managers used by the mutation baselines, retained for the whole
    /// process. The undo closures registered on them capture AVFoundation
    /// objects (clip movies, header data); letting those deallocate while
    /// XCTest's error-observation task group is still alive aborts the runner.
    static var keptUndoManagers: [UndoManager] = []
    
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
    
    /// Records the overhead of PerformanceMetrics itself as an observation.
    ///
    /// The measurement (untracked / tracked loops, best-of-5 selection) is
    /// preserved, but the recorded percentage is no longer asserted: the 30%
    /// threshold (raised from 10% in M-22 after parallel-load flakiness) is
    /// retired in favor of the recorded value, so the overhead is observed in
    /// the test output rather than gating the suite (M-22 lesson).
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
        
        // Record the best-of-5 overhead as an observation. This used to be a 30%
        // threshold assertion (raised from 10% in M-22 after parallel-load
        // flakiness); T-20 adds real AVFoundation workload to this suite, so the
        // relative threshold is retired in favor of the recorded value (M-22
        // lesson: no performance assertions that can fail on scheduling noise).
        print("PerformanceMetrics overhead (best of \(iterations) runs): \(String(format: "%.2f", bestOverheadPercent))%")
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

/* ============================================ */
// MARK: - Real Processing Performance Baselines (T-20)
/* ============================================ */

extension PerformanceTests {

    /// Baseline: Real TimelineView marker update and off-screen layout
    ///
    /// Records the clock and memory observations for the real
    /// `updateTimeline(current:from:to:isValid:)` + `layout()` + layer commit
    /// path of a layer-backed `TimelineView`. The values are non-gating
    /// observations recorded in the test result output: no CPU metric, no
    /// clock/memory threshold, and no relative comparison. This is an
    /// off-screen layer/layout baseline, not a GPU compositor or onscreen
    /// frame-time measurement.
    func testTimelineViewMarkerRenderBaseline() async {
        guard let fixture = await makePerformanceFixture() else { return }
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let movie = AVMutableMovie(url: fixture.url, options: nil)
        let duration = movie.range.duration.seconds
        // Functional precondition, BEFORE any duration-based arithmetic: an
        // unreadable or zero-length fixture must abort the test here, not flow
        // into the prewarm ratios (which would divide by zero) or the metric.
        guard duration > 0.0 else {
            return XCTFail("fixture movie has no duration")
        }
        let timeline = TimelineView(frame: CGRect(x: 0, y: 0, width: 1920, height: 50))
        // Prewarm marker selection and the first off-screen layout outside the metric.
        _ = timeline.updateTimeline(current: 0.5, from: 1.0 / duration,
                                    to: 4.0 / duration, isValid: true)
        timeline.layout()
        var phase = false
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()],
                options: baselineMeasureOptions()) {
            let current = phase ? 4.0 / duration : 3.0 / duration
            let start = phase ? 2.0 / duration : 1.0 / duration
            let end = phase ? 5.0 / duration : 4.0 / duration
            phase.toggle()
            startMeasuring()
            _ = timeline.updateTimeline(current: current, from: start,
                                        to: end, isValid: true)
            timeline.layout()
            CATransaction.flush()
            stopMeasuring()
        }
        // Functional assertions, outside the metric block (no performance
        // thresholds): the real update path must have left the timeline in a
        // valid state with finite positions, and the marker/selection/timeline
        // sub-layers the production render path maintains must all exist.
        XCTAssertTrue(timeline.isValid)
        XCTAssertTrue(timeline.currentPosition.isFinite)
        XCTAssertTrue(timeline.startPosition.isFinite)
        XCTAssertTrue(timeline.endPosition.isFinite)
        XCTAssertNotNil(timeline.currentMarker)
        XCTAssertNotNil(timeline.startMarker)
        XCTAssertNotNil(timeline.endMarker)
        XCTAssertNotNil(timeline.selection)
        XCTAssertNotNil(timeline.timeline)
    }

    /// Baseline: MovieMutator movie clip creation (trim equivalent)
    ///
    /// Records the clock and memory observations for the real
    /// `movieClip(_:)` operation on a 6-second fixture: mutable copy,
    /// before/after trims, and clip validation. The values are non-gating
    /// observations: no CPU metric, no clock/memory threshold, and no
    /// relative comparison. The operation is non-destructive to the source
    /// mutator, so no per-iteration state reset is required.
    func testMovieMutatorMovieClipBaseline() async {
        guard let fixture = await makePerformanceFixture() else { return }
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let source = AVMutableMovie(url: fixture.url, options: nil)
        let mutator = MovieMutator(with: source)
        let range = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600),
                                duration: CMTime(seconds: 2, preferredTimescale: 600))
        var lastDuration: Double = 0
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()],
                options: baselineMeasureOptions()) {
            startMeasuring()
            lastDuration = mutator.movieClip(range)?.range.duration.seconds ?? 0
            stopMeasuring()
        }
        // Functional assertion, outside the metric block (not a performance
        // threshold): the produced clip must be non-nil and about 2 seconds.
        XCTAssertEqual(lastDuration, 2.0, accuracy: 0.1)
    }

    /// Baseline: MovieMutator delete selection
    ///
    /// Records the clock and memory observations for the real
    /// `deleteSelection(using:)` operation on a 6-second fixture: clip
    /// creation, `removeTimeRange`, marker correction, `refreshMovie`, and
    /// undo registration. The values are non-gating observations: no CPU
    /// metric, no clock/memory threshold, and no relative comparison. The
    /// operation mutates the movie, so each iteration gets a fresh mutator
    /// and a dedicated undo manager built outside the measured region.
    func testMovieMutatorDeleteSelectionBaseline() async {
        guard let fixture = await makePerformanceFixture() else { return }
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let source = AVMutableMovie(data: fixture.data, options: nil)
        var lastDuration: Double = 0
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()],
                options: baselineMeasureOptions()) {
            // Per-iteration setup stays inside the block; the measured region
            // covers only the deleteSelection call itself. NOTE: an undo group
            // must be open around `deleteSelection` — registering undo on a
            // `groupsByEvent = false` manager with no open group aborts the
            // test runner (TaskGroupBase::~TaskGroupBase in XCTest's
            // error-observation task group).
            let mutator = MovieMutator(with: source)
            mutator.insertionTime = CMTime(seconds: 2, preferredTimescale: 600)
            mutator.selectedTimeRange = CMTimeRange(
                start: CMTime(seconds: 2, preferredTimescale: 600),
                duration: CMTime(seconds: 1, preferredTimescale: 600))
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            Self.keptUndoManagers.append(undoManager)
            undoManager.beginUndoGrouping()
            startMeasuring()
            mutator.deleteSelection(using: UndoManagerWrapper(undoManager))
            stopMeasuring()
            undoManager.endUndoGrouping()
            lastDuration = mutator.movieRange().duration.seconds
        }
        XCTAssertEqual(lastDuration, 5.0, accuracy: 0.1)
    }

    /// Baseline: MovieMutator clean aperture / pixel aspect ratio transform
    ///
    /// Records the clock and memory observations for the real
    /// `applyClapPasp(_:using:)` operation on a 320x180 H.264 fixture: video
    /// format verification, format description replacement, and the undo
    /// reload/refresh. The values are non-gating observations: no CPU metric,
    /// no clock/memory threshold, and no relative comparison. The operation
    /// mutates the movie, so each iteration gets a fresh mutator and a
    /// dedicated undo manager built outside the measured region.
    func testMovieMutatorApplyClapPaspBaseline() async {
        guard let fixture = await makePerformanceFixture() else { return }
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let source = AVMutableMovie(data: fixture.data, options: nil)
        let settings: [AnyHashable: Any] = [
            dimensionsKey: NSSize(width: 320, height: 180),
            clapSizeKey: NSSize(width: 300, height: 160),
            clapOffsetKey: NSZeroPoint,
            paspRatioKey: NSSize(width: 4, height: 3)
        ]
        var lastResult = false
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()],
                options: baselineMeasureOptions()) {
            let mutator = MovieMutator(with: source)
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            startMeasuring()
            lastResult = mutator.applyClapPasp(settings,
                                               using: UndoManagerWrapper(undoManager))
            stopMeasuring()
        }
        // Functional assertion, outside the metric block (not a performance
        // threshold): the transform must apply to the H.264 fixture track.
        XCTAssertTrue(lastResult)
    }

    /// Creates the shared T-20 performance fixture.
    ///
    /// Encodes a 6-second 320x180 H.264 movie (600 timescale, 30 fps) to a
    /// UUID temporary URL via `writeSampleMovieOffMainActor`, so the encode
    /// never blocks the main actor. The file data is read back inside a
    /// detached utility task. The fixture covers the selection [2s, 3s] and
    /// clip range [1s, 3s] used by the baselines, and matches the AVFoundation
    /// data produced by the existing `MovieMutatorEditTests` fixtures.
    private func makePerformanceFixture(
        duration: TimeInterval = 6.0,
        timescale: CMTimeScale = 600,
        frameRate: Int = 30
    ) async -> (url: URL, data: Data)? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutter2_perf_t20_\(UUID().uuidString).mov")
        let written = await writeSampleMovieOffMainActor(to: url, duration: duration,
                                                         timescale: timescale, frameRate: frameRate)
        guard written else {
            try? FileManager.default.removeItem(at: url)
            XCTFail("failed to write sample movie fixture")
            return nil
        }
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
        guard let data, !data.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            XCTFail("failed to read sample movie fixture data")
            return nil
        }
        return (url, data)
    }

    /// Shared measurement options for the T-20 baselines.
    ///
    /// `iterationCount` fixes the sample count; manual start/stop keeps the
    /// per-iteration setup (fresh mutator, undo manager) out of the measured
    /// region. The options are for sample consistency only: no best-of-N
    /// selection and no threshold decision.
    private func baselineMeasureOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        // Both manual invocation options are required: with `.manuallyStart`
        // alone the framework auto-stops after the block, and the test's own
        // `stopMeasuring()` inside the block then aborts the runner.
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        return options
    }
}
