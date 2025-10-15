# Performance Optimization Implementation Plan

**Version**: 1.0  
**Date**: October 15, 2025  
**Phase**: 2.2 - Performance Optimization  
**Duration**: 2 weeks  
**Status**: 📋 Planning

---

## Overview

This document provides a detailed implementation plan for Phase 2.2 performance optimizations, based on the findings from [PERFORMANCE_ANALYSIS.md](PERFORMANCE_ANALYSIS.md).

### Goals

1. **Improve User Experience**: More responsive progress indicators and smoother UI interactions
2. **Optimize Resource Usage**: Reduce memory footprint and CPU usage
3. **Maintain Stability**: No regressions in functionality or reliability
4. **Establish Baselines**: Create performance measurement infrastructure

### Success Metrics

**Quantitative**:
- Export progress updates: 1.0s → 0.1s (10x improvement)
- Timeline frame rate: Maintain 60 FPS during interaction
- Memory usage: 20% reduction for large file operations
- Zero new memory leaks

**Qualitative**:
- Smoother export progress indication
- More responsive timeline scrubbing
- Better handling of large video files

---

## Week 1: Quick Wins & Foundation

### Day 1: Setup & Baseline Measurements

#### Task 1.1: Create Performance Testing Infrastructure
**Priority**: High  
**Effort**: 4 hours  
**Risk**: Low

**Objectives**:
- Set up performance measurement utilities
- Create baseline test cases
- Document current performance metrics

**Implementation**:

1. Create `PerformanceMetrics.swift`:
```swift
import Foundation

/// Performance measurement utility
@MainActor
class PerformanceMetrics {
    static let shared = PerformanceMetrics()
    
    private var measurements: [String: [TimeInterval]] = [:]
    
    func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            recordMeasurement(name, duration: duration)
        }
        return try operation()
    }
    
    func measureAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            recordMeasurement(name, duration: duration)
        }
        return try await operation()
    }
    
    private func recordMeasurement(_ name: String, duration: TimeInterval) {
        measurements[name, default: []].append(duration)
        print("📊 Performance: \(name) took \(String(format: "%.3f", duration))s")
    }
    
    func report() -> String {
        var output = "=== Performance Report ===\n"
        for (name, durations) in measurements.sorted(by: { $0.key < $1.key }) {
            let avg = durations.reduce(0, +) / Double(durations.count)
            let min = durations.min() ?? 0
            let max = durations.max() ?? 0
            output += "\(name):\n"
            output += "  Average: \(String(format: "%.3f", avg))s\n"
            output += "  Min: \(String(format: "%.3f", min))s, Max: \(String(format: "%.3f", max))s\n"
            output += "  Samples: \(durations.count)\n"
        }
        return output
    }
}
```

2. Create baseline tests:
```swift
// cutter2Tests/PerformanceTests.swift
import XCTest
@testable import cutter2

final class PerformanceTests: XCTestCase {
    
    func testExportProgressPollingBaseline() {
        measure {
            // Simulate current 1-second polling
            let start = Date()
            while Date().timeIntervalSince(start) < 1.0 {
                // Polling work
            }
        }
    }
    
    func testFileOpenPerformance() {
        // Add test for file opening speed
    }
    
    func testTimelineRenderingPerformance() {
        // Add test for timeline drawing
    }
}
```

**Deliverables**:
- [ ] PerformanceMetrics.swift utility
- [ ] PerformanceTests.swift with baseline tests
- [ ] Baseline performance report document

#### Task 1.2: Instrument Profiling Session
**Priority**: High  
**Effort**: 2 hours  
**Risk**: Low

**Objectives**:
- Profile application with Xcode Instruments
- Identify actual bottlenecks
- Capture baseline metrics

**Steps**:
1. Open Instruments (Xcode → Product → Profile)
2. Run Time Profiler with test scenarios:
   - Open large video file (> 1 GB)
   - Export with standard preset
   - Timeline scrubbing and marker manipulation
3. Run Allocations instrument for memory analysis
4. Save Instruments trace files for reference

**Deliverables**:
- [ ] Instruments trace files (baseline)
- [ ] Screenshot of CPU hotspots
- [ ] Screenshot of memory allocations
- [ ] Notes on identified bottlenecks

---

### Day 2: Export Progress Optimization - Part 1

#### Task 2.1: Refactor Progress Polling Interval
**Priority**: High  
**Effort**: 3 hours  
**Risk**: Low

**Current Code** (MovieWriter.swift:212):
```swift
// Current: 1 second polling
try? await Task.sleep(nanoseconds: UInt64(self.exportSessionTimerRefreshInterval * 1_000_000_000))
// exportSessionTimerRefreshInterval = 1.0
```

**Optimized Code**:
```swift
// New: Configurable polling with default 0.1s
public var exportSessionTimerRefreshInterval: Double = 0.1  // 100ms

// Enhanced polling with adaptive intervals
public func exportSessionPollingStart() {
    exportSessionPollingStop()
    
    exportSessionPollingTask = Task<Void, Never> { @Sendable [weak self] in
        guard let self else { return }
        
        var lastProgress: Double = -1.0
        var stagnantCount = 0
        
        while let progress = await self.currentProgressIfExporting() {
            await self.updateProgress?(progress)
            
            // Adaptive polling: slow down if no progress change
            let interval: Double
            if abs(progress - lastProgress) < 0.001 {
                stagnantCount += 1
                // Slow down after 10 stagnant updates (1 second)
                interval = stagnantCount > 10 ? 0.5 : self.exportSessionTimerRefreshInterval
            } else {
                stagnantCount = 0
                interval = self.exportSessionTimerRefreshInterval
            }
            
            lastProgress = progress
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}
```

**Steps**:
1. Update `exportSessionTimerRefreshInterval` default value
2. Implement adaptive polling logic
3. Add configuration option (optional)
4. Test with various export scenarios

**Deliverables**:
- [ ] Updated MovieWriter.swift
- [ ] Tests for new polling behavior
- [ ] Performance comparison (1s vs 0.1s)

#### Task 2.2: Smooth Progress Animation
**Priority**: Medium  
**Effort**: 2 hours  
**Risk**: Low

**Objective**: Add interpolation for smoother progress bar animation

**Implementation**:
```swift
// Document+Export.swift - Enhanced progress callback
private func setupProgressCallback() {
    var lastReportedProgress: Double = 0
    let smoothingFactor: Double = 0.3  // Exponential smoothing
    
    mutator.updateProgress = { [weak self] progress in
        guard let self = self else { return }
        
        // Smooth progress updates to avoid jumps
        let smoothed = lastReportedProgress + smoothingFactor * (progress - lastReportedProgress)
        lastReportedProgress = smoothed
        
        performSyncOnMainActor {
            self.updateProgress(smoothed)
        }
    }
}
```

**Deliverables**:
- [ ] Smooth progress animation implementation
- [ ] Visual test of progress bar behavior

---

### Day 3: Timeline Performance Analysis

#### Task 3.1: Profile TimelineView Rendering
**Priority**: High  
**Effort**: 4 hours  
**Risk**: Low

**Objectives**:
- Identify TimelineView rendering bottlenecks
- Measure draw call frequency and duration
- Analyze layer composition performance

**Implementation**:

1. Add performance instrumentation:
```swift
// TimelineView.swift
import os.signpost

extension TimelineView {
    private static let performanceLog = OSLog(subsystem: "com.mycometg3.cutter2", 
                                             category: "TimelinePerformance")
    
    override func draw(_ dirtyRect: NSRect) {
        os_signpost(.begin, log: Self.performanceLog, name: "TimelineDraw")
        defer { os_signpost(.end, log: Self.performanceLog, name: "TimelineDraw") }
        
        super.draw(dirtyRect)
        // Existing drawing code...
    }
    
    func updateMarkerPosition(_ marker: marker, to position: Float64) {
        os_signpost(.begin, log: Self.performanceLog, name: "UpdateMarker")
        defer { os_signpost(.end, log: Self.performanceLog, name: "UpdateMarker") }
        
        // Existing update code...
    }
}
```

2. Profile with Instruments:
   - Run Time Profiler during timeline interaction
   - Identify expensive draw operations
   - Check for redundant redraws

**Deliverables**:
- [ ] Instrumented TimelineView.swift
- [ ] Instruments trace with timeline operations
- [ ] Analysis document of findings

#### Task 3.2: Implement Dirty Rect Optimization
**Priority**: Medium  
**Effort**: 3 hours  
**Risk**: Medium

**Current**: Full view redraw on every update  
**Optimized**: Only redraw changed regions

**Implementation**:
```swift
// TimelineView.swift
extension TimelineView {
    func updateMarkerPosition(_ marker: marker, to position: Float64) {
        let oldRect = rectForMarker(marker, at: currentPosition)
        let newRect = rectForMarker(marker, at: position)
        
        // Only invalidate the affected regions
        setNeedsDisplay(oldRect)
        setNeedsDisplay(newRect)
        
        currentPosition = position
        // Don't call setNeedsDisplay(bounds) - too expensive
    }
    
    private func rectForMarker(_ marker: marker, at position: Float64) -> NSRect {
        // Calculate minimal rect for marker
        let x = convert(position: position)
        return NSRect(x: x - 2, y: 0, width: 4, height: bounds.height)
    }
}
```

**Deliverables**:
- [ ] Dirty rect optimization implementation
- [ ] Performance comparison (before/after)
- [ ] Visual verification of correct rendering

---

### Day 4: Timeline Optimization - Part 2

#### Task 4.1: Layer Caching Strategy
**Priority**: Medium  
**Effort**: 4 hours  
**Risk**: Medium

**Objective**: Cache expensive layer operations

**Implementation**:
```swift
// TimelineView.swift
extension TimelineView {
    private var cachedBackgroundLayer: CALayer?
    private var cacheInvalidated: Bool = true
    
    func invalidateCache() {
        cacheInvalidated = true
        cachedBackgroundLayer = nil
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Use cached background if available
        if !cacheInvalidated, let cached = cachedBackgroundLayer {
            cached.render(in: NSGraphicsContext.current!.cgContext)
        } else {
            // Render background to cache
            let bgLayer = CALayer()
            renderBackground(to: bgLayer)
            cachedBackgroundLayer = bgLayer
            cacheInvalidated = false
            
            bgLayer.render(in: NSGraphicsContext.current!.cgContext)
        }
        
        // Draw dynamic elements (markers) on top
        drawMarkers(dirtyRect)
    }
}
```

**Deliverables**:
- [ ] Layer caching implementation
- [ ] Cache invalidation strategy
- [ ] Performance measurements

#### Task 4.2: Optimize CALayer Usage
**Priority**: Low  
**Effort**: 2 hours  
**Risk**: Low

**Objective**: Review and optimize CALayer hierarchy

**Steps**:
1. Audit current layer structure
2. Flatten unnecessary layer hierarchies
3. Use sublayers for static elements
4. Enable layer rasterization where appropriate

**Deliverables**:
- [ ] Optimized layer structure
- [ ] Documentation of layer hierarchy

---

### Day 5: Week 1 Testing & Documentation

#### Task 5.1: Performance Regression Tests
**Priority**: High  
**Effort**: 3 hours  
**Risk**: Low

**Objectives**:
- Verify all optimizations work correctly
- Measure performance improvements
- Check for regressions

**Test Cases**:
1. Export progress update frequency
2. Timeline rendering frame rate
3. Memory usage during operations
4. UI responsiveness

**Deliverables**:
- [ ] Updated PerformanceTests.swift
- [ ] Test results report
- [ ] Performance comparison table

#### Task 5.2: Week 1 Documentation
**Priority**: Medium  
**Effort**: 2 hours  
**Risk**: Low

**Deliverables**:
- [ ] Update PERFORMANCE_OPTIMIZATION_PLAN.md with Week 1 results
- [ ] Document code changes
- [ ] Update inline documentation
- [ ] Create Week 1 summary report

---

## Week 2: Deep Optimizations

### Day 1: Memory Management Analysis

#### Task 6.1: Memory Profiling with Instruments
**Priority**: High  
**Effort**: 3 hours  
**Risk**: Low

**Objectives**:
- Profile memory usage with large files
- Identify peak memory allocations
- Check for memory leaks

**Steps**:
1. Run Allocations instrument
2. Test with progressively larger files:
   - 500 MB video
   - 1 GB video
   - 2 GB video
   - 4K/8K video
3. Run Leaks instrument
4. Analyze memory patterns

**Deliverables**:
- [ ] Memory profiling report
- [ ] Identified memory hotspots
- [ ] Leak detection results

#### Task 6.2: Identify Memory Optimization Opportunities
**Priority**: High  
**Effort**: 2 hours  
**Risk**: Low

**Focus Areas**:
- AVAssetReader/Writer buffer sizes
- Sample buffer lifecycle
- Image/texture caching
- Temporary allocations

**Deliverables**:
- [ ] Memory optimization candidates list
- [ ] Priority ranking

---

### Day 2-3: Memory Optimizations Implementation

#### Task 7.1: Sample Buffer Pooling
**Priority**: High  
**Effort**: 6 hours  
**Risk**: Medium

**Objective**: Implement buffer pool to reduce allocations

**Implementation**:
```swift
// Create new file: SampleBufferPool.swift
import AVFoundation

actor SampleBufferPool {
    private var videoBufferPool: [CVPixelBuffer] = []
    private var audioBufferPool: [CMSampleBuffer] = []
    private let maxPoolSize = 10
    
    func acquireVideoBuffer(width: Int, height: Int, pixelFormat: OSType) -> CVPixelBuffer? {
        if let buffer = videoBufferPool.popLast() {
            return buffer
        }
        
        // Create new buffer if pool is empty
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
        ]
        CVPixelBufferCreate(nil, width, height, pixelFormat, options as CFDictionary, &pixelBuffer)
        return pixelBuffer
    }
    
    func releaseVideoBuffer(_ buffer: CVPixelBuffer) {
        guard videoBufferPool.count < maxPoolSize else { return }
        videoBufferPool.append(buffer)
    }
    
    // Similar methods for audio buffers
}
```

**Integration Points**:
- SampleBufferChannel.swift
- MovieWriter.swift (custom export path)

**Deliverables**:
- [ ] SampleBufferPool.swift implementation
- [ ] Integration with existing code
- [ ] Memory usage comparison
- [ ] Tests for buffer pool

#### Task 7.2: Memory Pressure Monitoring
**Priority**: Medium  
**Effort**: 4 hours  
**Risk**: Low

**Objective**: Add memory pressure detection and response

**Implementation**:
```swift
// Create new file: MemoryMonitor.swift
import Foundation

@MainActor
class MemoryMonitor {
    static let shared = MemoryMonitor()
    
    private var pressureSource: DispatchSourceMemoryPressure?
    private(set) var currentPressure: DispatchSource.MemoryPressureEvent = []
    
    var onMemoryWarning: (() -> Void)?
    var onMemoryCritical: (() -> Void)?
    
    func startMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], 
                                                             queue: .main)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            self.currentPressure = event
            
            if event.contains(.warning) {
                print("⚠️ Memory pressure: Warning")
                self.onMemoryWarning?()
            }
            if event.contains(.critical) {
                print("🔴 Memory pressure: Critical")
                self.onMemoryCritical?()
            }
        }
        source.resume()
        pressureSource = source
    }
    
    func stopMonitoring() {
        pressureSource?.cancel()
        pressureSource = nil
    }
}
```

**Integration**:
- Start monitoring in AppDelegate
- Clear caches on memory warning
- Reduce buffer sizes on critical pressure

**Deliverables**:
- [ ] MemoryMonitor.swift implementation
- [ ] Integration with main application
- [ ] Memory pressure response handlers
- [ ] Testing with memory stress

---

### Day 4: Advanced Optimizations

#### Task 8.1: AsyncStream for Progress Updates
**Priority**: Medium  
**Effort**: 5 hours  
**Risk**: Medium

**Objective**: Replace polling with async stream

**Implementation**:
```swift
// MovieWriter.swift
extension MovieWriter {
    var exportProgress: AsyncStream<Double> {
        AsyncStream { continuation in
            let task = Task {
                while let session = self.exportSession {
                    let progress = session.progress
                    continuation.yield(progress)
                    
                    guard session.status == .exporting else {
                        continuation.finish()
                        return
                    }
                    
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

// Usage in Document+Export.swift
Task {
    for await progress in mutator.exportProgress {
        await MainActor.run {
            self.updateProgress(progress)
        }
    }
}
```

**Deliverables**:
- [ ] AsyncStream implementation
- [ ] Migration from polling
- [ ] Tests for async stream
- [ ] Performance comparison

#### Task 8.2: Optimize File I/O Operations
**Priority**: Low  
**Effort**: 3 hours  
**Risk**: Low

**Objective**: Review and optimize file operations

**Areas to Optimize**:
- Bookmark management
- File attribute reading
- Temporary file handling

**Deliverables**:
- [ ] Optimized file I/O code
- [ ] Benchmark results

---

### Day 5: Final Testing & Documentation

#### Task 9.1: Comprehensive Performance Testing
**Priority**: High  
**Effort**: 4 hours  
**Risk**: Low

**Test Scenarios**:
1. Export performance (all presets)
2. Large file handling (> 2 GB)
3. Timeline interaction (scrubbing, markers)
4. Memory usage patterns
5. UI responsiveness
6. Multi-hour export sessions

**Deliverables**:
- [ ] Complete test suite execution
- [ ] Performance metrics report
- [ ] Before/after comparison
- [ ] Memory leak verification

#### Task 9.2: Phase 2.2 Documentation
**Priority**: High  
**Effort**: 3 hours  
**Risk**: Low

**Documents to Create/Update**:
1. PERFORMANCE_OPTIMIZATION_COMPLETE.md
2. Update README.md with performance improvements
3. Update ARCHITECTURE.md if needed
4. Code documentation updates

**Deliverables**:
- [ ] All documentation updated
- [ ] Performance improvement summary
- [ ] Known limitations documented
- [ ] Future optimization suggestions

---

## Risk Management

### Risk Mitigation Strategies

#### High Risk: Timeline Rendering Changes
**Mitigation**:
- Incremental changes with testing after each
- Keep original code as fallback
- Extensive visual testing

#### Medium Risk: Memory Management Changes
**Mitigation**:
- Thorough testing with Instruments
- Gradual rollout of buffer pooling
- Memory pressure monitoring

#### Low Risk: Progress Polling Changes
**Mitigation**:
- Simple, isolated change
- Easy to revert if issues arise
- No architectural changes

### Rollback Plan

If critical issues are discovered:
1. Revert specific optimization via git
2. Document issue in GitHub issue tracker
3. Re-evaluate approach
4. Implement alternative solution

---

## Testing Strategy

### Unit Tests
- Performance regression tests
- Memory leak tests
- Buffer pool functionality tests
- Progress update tests

### Integration Tests
- Full export workflow with optimizations
- Timeline interaction tests
- Large file handling tests

### Manual Testing
- Visual verification of UI smoothness
- Export with various presets
- Timeline scrubbing at various zoom levels
- Memory usage monitoring

### Performance Benchmarks
- Export speed (should not regress)
- Memory usage (should reduce by ~20%)
- UI frame rate (maintain 60 FPS)
- Progress update frequency (10x improvement)

---

## Success Criteria

### Must Have (Phase 2.2 Completion)
- [ ] Export progress updates 10x more frequent (0.1s)
- [ ] No performance regressions in export speed
- [ ] No new memory leaks introduced
- [ ] All tests passing
- [ ] Documentation updated

### Should Have (Quality Goals)
- [ ] 20% memory reduction for large files
- [ ] Timeline maintains 60 FPS during interaction
- [ ] Smooth progress bar animation
- [ ] Memory pressure monitoring active

### Nice to Have (Bonus Goals)
- [ ] AsyncStream fully integrated
- [ ] Buffer pooling implemented
- [ ] Additional optimizations identified

---

## Timeline Summary

```
Week 1: Foundation & Quick Wins
├── Day 1: Setup, Baseline, Profiling
├── Day 2: Export Progress Optimization
├── Day 3: Timeline Analysis
├── Day 4: Timeline Optimization
└── Day 5: Testing & Documentation

Week 2: Deep Optimizations
├── Day 1: Memory Analysis
├── Day 2-3: Memory Optimizations
├── Day 4: Advanced Optimizations
└── Day 5: Final Testing & Docs
```

**Total Estimated Effort**: 60-70 hours over 2 weeks

---

## Next Steps

### Immediate Actions
1. Review and approve this plan
2. Set up development branch: `feature/phase-2.2-performance`
3. Begin Day 1 tasks: performance infrastructure setup

### Week 1 Kickoff
1. Create PerformanceMetrics utility
2. Run baseline Instruments profiling
3. Start export progress optimization

### Communication
- Daily progress updates in commit messages
- Weekly summary in documentation
- Issue tracking for any blockers

---

**Status**: 📋 Ready for Implementation  
**Approval Required**: Yes  
**Start Date**: TBD  
**Estimated Completion**: 2 weeks from start  
**Next Document**: PERFORMANCE_OPTIMIZATION_COMPLETE.md (after Phase 2.2)
