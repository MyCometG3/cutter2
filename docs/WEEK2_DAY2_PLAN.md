# Phase 2.2 Week 2 Day 2: Export Memory Profiling & Buffer Pool Design

**Date**: October 18, 2025  
**Phase**: 2.2 - Performance Optimization  
**Focus**: Export Operation Memory Optimization  
**Status**: 🔄 In Progress

---

## Objectives

Based on Day 1 results showing excellent baseline memory management, Day 2 focuses on:

1. Profile memory usage during export operations
2. Design and implement sample buffer pooling system
3. Optimize `MovieWriter` and `SampleBufferChannel` memory allocation
4. Reduce peak memory during large file exports

---

## Current State Analysis

### Day 1 Findings Summary

✅ **Baseline Memory**: Excellent (134-203 MB for playback/editing)  
✅ **No Memory Leaks**: All resources properly cleaned up  
✅ **Memory-Mapped I/O**: Efficient (825 MB file → 44 MB resident)

### Export Pipeline Components

#### 1. **MovieWriter.swift** (1,352 lines)

**Key Classes/Actors**:
- `MovieWriter` (actor): Main export coordinator
- `MovieWriterParams`: Export parameters structure
- `MovieWriterError`: Error handling

**Export Methods**:
1. `exportMovie(to:fileType:presetName:)` - Standard export with AVAssetExportSession
2. `exportCustomMovie(to:fileType:param:)` - Custom export with AVAssetReader/Writer
3. Export progress polling with adaptive intervals (100ms → 500ms)

**Memory Concerns**:
- AVAssetExportSession: Managed by AVFoundation (minimal control)
- Custom export: Uses `SampleBufferChannel` for sample transfer
- Progress polling task: Lightweight, no memory concerns

#### 2. **SampleBufferChannel.swift** (103 lines)

**Purpose**: Transfers sample buffers from AVAssetReader to AVAssetWriter

**Current Implementation**:
```swift
while awInput.isReadyForMoreMediaData {
    let sb: CMSampleBuffer? = arOutput.copyNextSampleBuffer()
    if let sb = sb {
        delegate.didRead(from: self, buffer: sb)
        awInput.append(sb)
    }
}
```

**Memory Pattern**:
- **Allocation**: `copyNextSampleBuffer()` creates new CMSampleBuffer
- **Transfer**: Buffer passed to writer input
- **Deallocation**: Buffer released after append (ARC)
- **Issue**: No buffer reuse, each sample allocates new memory

**Optimization Opportunity**: ⭐⭐⭐⭐ HIGH
- Current: Allocate → Use → Deallocate for each buffer
- Proposed: Pool buffers → Reuse → Return to pool

---

## Export Memory Profiling Plan

### Test Scenarios

#### Scenario 1: Standard Export (AVAssetExportSession)

**Test Case**: Export to H.264 using preset

```swift
// In Document.swift or test harness
let presetName = AVAssetExportPresetHEVCHighestQuality
try await writer.exportMovie(to: url, fileType: .mp4, presetName: presetName)
```

**Metrics to Capture**:
- Peak memory during export
- Memory growth pattern
- Memory after completion
- Export time and throughput

**Expected Behavior**:
- AVFoundation manages buffers internally
- Limited optimization opportunities
- Baseline for comparison with custom export

#### Scenario 2: Custom Export (AVAssetReader/Writer)

**Test Case**: Custom export with H.264/AAC encoding

```swift
let param: [String: Any] = [
    kVideoCodecKey: kVideoCodec_H264,
    kAudioCodecKey: kAudioCodec_AAC,
    // ... other settings
]
try await writer.exportCustomMovie(to: url, fileType: .mp4, param: param)
```

**Metrics to Capture**:
- Sample buffer allocation rate
- Peak memory usage
- Buffer allocation hotspots
- Memory fragmentation

**Expected Behavior**:
- High allocation rate (60 video + audio samples/sec)
- Significant optimization potential with pooling

#### Scenario 3: Large File Export

**Test Case**: Export 825MB ProRes file to H.264

**Metrics to Capture**:
- Total memory allocated for buffers
- Peak memory vs. baseline
- Memory pressure events
- Export completion time

---

## Buffer Pool Design

### Architecture

#### 1. **SampleBufferPool Class**

**Purpose**: Manage reusable CMSampleBuffer instances

**Design Pattern**: Object Pool Pattern

```swift
/// Thread-safe buffer pool for CMSampleBuffer reuse
actor SampleBufferPool {
    // Pool of available buffers
    private var availableBuffers: [PooledBuffer] = []
    
    // Statistics
    private(set) var totalAllocations: Int = 0
    private(set) var poolHits: Int = 0
    private(set) var poolMisses: Int = 0
    
    /// Acquire a buffer from pool or create new one
    func acquire(size: Int, mediaType: AVMediaType) -> PooledBuffer
    
    /// Return buffer to pool for reuse
    func release(_ buffer: PooledBuffer)
    
    /// Clear all buffers (memory pressure handler)
    func drain()
}
```

#### 2. **PooledBuffer Wrapper**

```swift
/// Wrapper for CMSampleBuffer with pool management
class PooledBuffer {
    let buffer: CMSampleBuffer
    let capacity: Int
    let mediaType: AVMediaType
    weak var pool: SampleBufferPool?
    
    init(capacity: Int, mediaType: AVMediaType)
    
    deinit {
        // Return to pool automatically
        pool?.release(self)
    }
}
```

### Pool Configuration

**Pool Limits**:
- **Video Buffers**: Max 10 buffers (~10 MB for 1080p ProRes frames)
- **Audio Buffers**: Max 20 buffers (~200 KB total for PCM)
- **Total Capacity**: ~10-15 MB pool overhead

**Size Classes**:
- Small: < 100 KB (audio, small video frames)
- Medium: 100 KB - 1 MB (HD video frames)
- Large: > 1 MB (4K video frames, ProRes)

**Eviction Policy**:
- LRU (Least Recently Used) when pool exceeds limits
- Immediate drain on memory pressure warnings

---

## Implementation Plan

### Phase 1: Add Memory Profiling to Export (2 hours)

**Tasks**:
1. Create `scripts/export_profile.sh` script
2. Add memory monitoring to export operations
3. Profile standard export vs. custom export
4. Identify allocation hotspots

**Deliverables**:
- Export profiling script
- Baseline export memory metrics
- Hotspot analysis document

### Phase 2: Implement SampleBufferPool (3 hours)

**Tasks**:
1. Create `SampleBufferPool.swift` in Models/
2. Implement pool acquisition/release logic
3. Add statistics tracking
4. Add memory pressure monitoring

**Files to Create**:
- `cutter2/Models/SampleBufferPool.swift`
- `cutter2Tests/SampleBufferPoolTests.swift`

**Key Methods**:
```swift
// Acquire buffer
let buffer = await pool.acquire(size: bufferSize, mediaType: .video)

// Use buffer
// ... process sample data ...

// Release automatically via deinit or explicitly
await pool.release(buffer)
```

### Phase 3: Integrate Pool with SampleBufferChannel (2 hours)

**Tasks**:
1. Modify `SampleBufferChannel` to use pool
2. Update buffer lifecycle management
3. Add pool statistics logging
4. Test with various file formats

**Changes to SampleBufferChannel.swift**:
```swift
class SampleBufferChannel {
    private let bufferPool: SampleBufferPool
    
    init(readerOutput: AVAssetReaderOutput, 
         writerInput: AVAssetWriterInput, 
         trackID: CMPersistentTrackID,
         bufferPool: SampleBufferPool) {
        // ...
        self.bufferPool = bufferPool
    }
    
    // Use pooled buffers in transfer loop
    private func transferSamples() async {
        while awInput.isReadyForMoreMediaData {
            let sb = arOutput.copyNextSampleBuffer()
            if let sb = sb {
                let pooledBuffer = await bufferPool.acquire(from: sb)
                awInput.append(pooledBuffer.buffer)
                await bufferPool.release(pooledBuffer)
            }
        }
    }
}
```

### Phase 4: Testing & Validation (2 hours)

**Test Cases**:
1. Unit tests for `SampleBufferPool`
2. Integration tests with export operations
3. Memory leak detection
4. Performance benchmarks

**Success Criteria**:
- [ ] Pool hit rate > 80%
- [ ] Peak memory reduced by 20%+
- [ ] No memory leaks
- [ ] Export time unchanged or improved

---

## Expected Results

### Memory Improvements

**Before Optimization**:
- Export 825 MB file: Peak ~400-600 MB
- Each buffer allocated/deallocated individually
- High allocation rate: 60+ buffers/sec

**After Optimization**:
- Export 825 MB file: Peak ~300-400 MB (20-30% reduction)
- Buffer reuse rate: 80%+
- Reduced allocation rate: 10-15 new buffers/sec

### Performance Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Peak Memory | 500 MB | 350 MB | -30% |
| Allocations/sec | 60+ | 10-15 | -75% |
| Pool Hit Rate | N/A | 85% | N/A |
| Export Time | Baseline | ≤ Baseline | 0-10% faster |

---

## Implementation Details

### Memory Pressure Monitoring

Add system memory pressure monitoring to automatically drain pool:

```swift
extension SampleBufferPool {
    func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        
        source.setEventHandler { [weak self] in
            Task {
                await self?.drain()
            }
        }
        
        source.resume()
    }
}
```

### Statistics & Monitoring

Track pool effectiveness:

```swift
actor SampleBufferPool {
    struct Statistics {
        var totalAcquires: Int = 0
        var poolHits: Int = 0
        var poolMisses: Int = 0
        var currentPoolSize: Int = 0
        var peakPoolSize: Int = 0
        
        var hitRate: Double {
            guard totalAcquires > 0 else { return 0 }
            return Double(poolHits) / Double(totalAcquires)
        }
    }
    
    private(set) var statistics = Statistics()
    
    func logStatistics() {
        print("Buffer Pool Statistics:")
        print("  Total Acquires: \(statistics.totalAcquires)")
        print("  Pool Hits: \(statistics.poolHits)")
        print("  Pool Misses: \(statistics.poolMisses)")
        print("  Hit Rate: \(String(format: "%.1f%%", statistics.hitRate * 100))")
        print("  Current Size: \(statistics.currentPoolSize)")
        print("  Peak Size: \(statistics.peakPoolSize)")
    }
}
```

---

## Testing Strategy

### Unit Tests

**Test File**: `cutter2Tests/SampleBufferPoolTests.swift`

```swift
class SampleBufferPoolTests: XCTestCase {
    func testBufferAcquisition() async throws
    func testBufferRelease() async throws
    func testPoolReuse() async throws
    func testMemoryPressureDrain() async throws
    func testConcurrentAccess() async throws
    func testStatistics() async throws
}
```

### Integration Tests

**Test File**: `cutter2Tests/MovieWriterBufferPoolTests.swift`

```swift
class MovieWriterBufferPoolTests: XCTestCase {
    func testExportWithBufferPool() async throws
    func testPoolHitRate() async throws
    func testMemoryUsageReduction() async throws
}
```

---

## Success Criteria

### Must Have
- [ ] `SampleBufferPool` implemented and tested
- [ ] Integration with `SampleBufferChannel` complete
- [ ] Memory leak tests passing
- [ ] Export profiling data collected

### Should Have
- [ ] 20%+ memory reduction during export
- [ ] 80%+ pool hit rate
- [ ] Memory pressure handling working
- [ ] Statistics logging implemented

### Nice to Have
- [ ] Automated performance tests
- [ ] Pool size auto-tuning
- [ ] Advanced statistics dashboard

---

## Risks & Mitigations

### Risk 1: Buffer Pool Overhead

**Risk**: Pool management adds CPU overhead
**Mitigation**: Use lightweight actor-based pool, benchmark thoroughly

### Risk 2: Memory Leaks in Pool

**Risk**: Buffers not properly released
**Mitigation**: Comprehensive leak detection tests, automatic cleanup in deinit

### Risk 3: Incompatible Buffer Sizes

**Risk**: Buffer size mismatches reduce reuse
**Mitigation**: Size classes with tolerance ranges, fallback to new allocation

---

## Timeline

**Total Estimate**: 9 hours (1+ day)

- Phase 1 (Profiling): 2 hours
- Phase 2 (Pool Implementation): 3 hours
- Phase 3 (Integration): 2 hours
- Phase 4 (Testing): 2 hours

---

## Next Steps

1. **Immediate**: Run export profiling session
2. **Today**: Implement `SampleBufferPool`
3. **Tomorrow (Day 3)**: Integration and testing
4. **Week 2 Summary**: Document all improvements

---

**Status**: Ready to begin export profiling  
**Current Focus**: Create export profiling script and baseline metrics  
**Output**: `docs/WEEK2_DAY2_EXPORT_PROFILE_RESULTS.md`
