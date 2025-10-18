# Phase 2.2 Week 2 Day 1: Memory Profiling

**Date**: October 18, 2025  
**Phase**: 2.2 - Performance Optimization  
**Focus**: Memory Management Analysis  
**Status**: 🔄 In Progress

---

## Objectives

1. Profile memory usage with progressively larger video files
2. Identify memory allocation hotspots
3. Detect memory leaks
4. Establish baseline metrics for optimization

---

## Test Scenarios

### Test File

**Primary Test File**: `/Users/takashi/Movies/DL-1115173527.mov`
- File Size: **825 MB**
- Format: QuickTime MOV
- Video Codec: **Apple ProRes (apcs)**
- Resolution: **1920×1080 (Full HD)**
- Duration: **63.7 seconds**
- Video Bitrate: **102.5 Mbps**
- Audio Codec: **PCM 16-bit LE (LPCM)**
- Audio Bitrate: **6.144 Mbps**
- Status: ✅ Verified and accessible
- Perfect for memory profiling: Medium-large, high-quality ProRes

### Scenario 1: File Opening and Playback

**Test File**: DL-1115173527.mov (825 MB)

**Metrics to Capture**:
- Initial memory footprint
- Peak memory during playback
- Memory after closing document
- Memory leaks (if any)

### Scenario 2: Editing Operations

**Operations to Test**:
- Cut/Copy/Paste clips
- Multiple undo/redo cycles
- Timeline scrubbing
- Marker manipulation

**Metrics to Capture**:
- Memory growth during operations
- Memory released after undo
- Clipboard memory usage

### Scenario 3: Export Operations

**Export Types**:
- Standard H.264 export (1GB source)
- HEVC export with transcode
- ProRes422 export (large output)
- Custom export with multiple tracks

**Metrics to Capture**:
- Memory usage during export
- Peak memory allocation
- Memory after export completion
- Sample buffer lifecycle

---

## Profiling Tools

### Xcode Instruments

#### 1. Allocations Instrument

**Purpose**: Track memory allocations and identify leaks

**Steps**:
```bash
# Run from Xcode
Product → Profile (⌘I)
→ Select "Allocations" template
→ Run test scenarios
```

**Key Areas to Monitor**:
- Persistent allocations
- Transient allocations
- All Heap & Anonymous VM
- AVFoundation objects lifecycle

#### 2. Leaks Instrument

**Purpose**: Detect memory leaks

**Steps**:
```bash
Product → Profile (⌘I)
→ Select "Leaks" template
→ Run test scenarios
```

**Focus On**:
- AVFoundation objects (AVPlayer, AVPlayerItem, AVMutableMovie)
- CALayer hierarchies (TimelineView)
- Closures with retain cycles
- Observer patterns

#### 3. VM Tracker

**Purpose**: Monitor virtual memory usage

**Metrics**:
- Dirty memory size
- Swapped memory
- Compressed memory

---

## Profiling Session Plan

### Session 1: Baseline Measurement (30 minutes)

**Test Case**: Open DL-1115173527.mov (825MB ProRes), play 30 seconds, close

**Test File**: `/Users/takashi/Movies/DL-1115173527.mov`

1. Launch Instruments with Allocations template
2. Start recording
3. Open test file (825MB ProRes 1080p)
4. Play video for 30 seconds
5. Stop playback
6. Close document
7. Stop recording
8. Analyze allocations

**Expected Baseline**:
- Initial: ~200MB (app + frameworks)
- Peak: ~500-800MB (ProRes buffers are larger)
- After close: ~200MB (back to baseline)

**ProRes Note**: ProRes422 is uncompressed, expect higher memory usage than H.264

### Session 2: Large File Test (30 minutes)

**Test Case**: Open 2GB MOV file, stress test

1. Launch Instruments
2. Open 2GB file
3. Rapid timeline scrubbing
4. Multiple cut/paste operations
5. Export to H.264
6. Close document
7. Analyze results

**Look For**:
- Memory leaks
- Excessive allocations
- Peak memory > 2GB
- Memory not released after close

### Session 3: Leak Detection (30 minutes)

**Test Case**: Repeated operations to detect leaks

1. Launch Instruments with Leaks template
2. Perform 10 cycles of:
   - Open file
   - Edit operation
   - Export
   - Close
3. Check for memory growth
4. Identify leak sources

---

## Data Collection

### Memory Metrics Template

```
Test: [Test Name]
Date: [Date]
File Size: [Size]
Video Format: [Codec/Resolution]

Initial Memory: ___ MB
Peak Memory: ___ MB
Final Memory: ___ MB
Memory Growth: ___ MB
Leaks Detected: Yes/No

Top Allocations:
1. [Object Type]: ___ MB
2. [Object Type]: ___ MB
3. [Object Type]: ___ MB

Notes:
- [Observations]
- [Issues found]
- [Optimization opportunities]
```

---

## Expected Findings

### Likely Memory Hotspots

1. **AVAssetReader/Writer Buffers**
   - Location: `MovieWriter.swift`, `SampleBufferChannel.swift`
   - Expected: Large temporary allocations during export
   - Optimization: Buffer pooling

2. **Video Frame Buffers**
   - Location: Playback pipeline
   - Expected: Multiple frame buffers in memory
   - Optimization: Limit buffer queue size

3. **Timeline Rendering**
   - Location: `TimelineView.swift`
   - Expected: CALayer allocations
   - Optimization: Layer reuse (already done in Week 1)

4. **Undo/Redo Stack**
   - Location: `MovieMutator.swift`
   - Expected: Retained movie states
   - Optimization: Limit undo stack depth

---

## Success Criteria

### Must Have
- [ ] Baseline memory metrics established for all scenarios
- [ ] Memory hotspots identified and documented
- [ ] Zero memory leaks detected (or all documented with plans)
- [ ] Instruments trace files saved for reference

### Should Have
- [ ] Memory usage patterns understood
- [ ] Optimization candidates prioritized
- [ ] Test files prepared for future benchmarking

### Nice to Have
- [ ] Automated memory tests added to test suite
- [ ] Memory pressure scenarios tested

---

## Next Steps (Day 2)

Based on profiling results:
1. Design buffer pooling strategy
2. Implement `SampleBufferPool.swift`
3. Add memory pressure monitoring
4. Optimize identified hotspots

---

## Tools and Commands

### Quick Profiling Commands

```bash
# Build for profiling
xcodebuild -project cutter2.xcodeproj -scheme cutter2 -configuration Release

# Memory footprint check
leaks cutter2

# Heap analysis
heap cutter2 | head -20

# Virtual memory stats
vmmap cutter2 | grep -A 20 MALLOC
```

### Instruments Templates

1. **Allocations**: Memory allocation tracking
2. **Leaks**: Memory leak detection
3. **VM Tracker**: Virtual memory monitoring
4. **Time Profiler**: CPU usage (if needed)

---

## Notes

- Focus on **measurable improvements** for Week 2 goals
- Document all findings in detail
- Save Instruments traces for future reference
- Target: 20% memory reduction for large files

---

**Status**: Ready to begin profiling  
**Estimated Time**: 2-3 hours  
**Output**: Baseline metrics and optimization roadmap
