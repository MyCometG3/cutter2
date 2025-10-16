# Timeline Performance Analysis

**Date**: October 16, 2025  
**Phase**: 2.2 Week 1 Day 3  
**File**: TimelineView.swift (719 lines)

---

## Overview

TimelineView is a custom NSView that displays a timeline with markers for:
- Current position (playhead)
- Selection start
- Selection end
- Timeline bar
- Time label

This analysis identifies performance characteristics and optimization opportunities.

---

## Current Implementation

### Architecture

**Type**: CALayer-based NSView
- `wantsLayer = true`
- Uses CAShapeLayer for markers and timeline
- Uses CATextLayer for time display
- Implements CALayerDelegate and NSViewLayerContentScaleDelegate

**Components**:
```
TimelineView (NSView)
├─ timeLabel (CATextLayer) - Time display "00:00:00.000"
├─ currentMarker (CAShapeLayer) - Playhead marker
├─ startMarker (CAShapeLayer) - Selection start
├─ endMarker (CAShapeLayer) - Selection end
├─ selection (CAShapeLayer) - Selection region
└─ timeline (CAShapeLayer) - Timeline bar
```

### Key Methods

**Layout**:
```swift
override func layout()
  ├─ Setup tracking area (on resize)
  ├─ Calculate positions for all markers
  ├─ CATransaction.begin()
  ├─ Update all layer frames (no animation)
  └─ CATransaction.commit()
```

**Update Triggers**:
- `needsLayout = true` called from multiple places
  - Line 563: After marker position update
  - Line 589: After mouse tracking
  - Line 615: After current position update
  - Line 625: After start position update
  - Line 635: After end position update

---

## Performance Characteristics

### Strengths ✅

1. **CALayer-based rendering**
   - Hardware-accelerated
   - Efficient compositing
   - No custom drawing code

2. **Animation disabled**
   - `CATransaction.setDisableActions(true)`
   - Immediate position updates
   - No animation overhead

3. **Efficient position calculation**
   - Simple linear transform: `point(of: position)`
   - Minimal computation

4. **Proper retina support**
   - `contentsScale` management
   - HiDPI-aware text rendering

### Potential Issues ⚠️

1. **Frequent layout calls**
   - `needsLayout = true` called on every marker update
   - Forces full relayout of all 6 layers
   - Occurs during:
     - Mouse dragging (continuous updates)
     - Playback (frame-by-frame)
     - Scrubbing operations

2. **Full relayout on partial changes**
   - Moving one marker triggers layout of ALL layers
   - Timeline and label rarely change
   - Wasteful when only one marker moves

3. **Path recreation**
   - Selection and timeline paths recreated on every layout
   - `NSBezierPath(rect: ...).cgPath` called repeatedly
   - Could be cached or avoided

4. **Multiple CATransaction blocks**
   - 3 separate transaction blocks in file
   - Potential for consolidation

---

## Measurements

### Current Performance (Estimated)

**Layout frequency**:
- During playback: ~30 FPS = 30 layouts/second
- During scrubbing: ~60 FPS = 60 layouts/second
- Per layout: 6 layer updates + path recreation

**Per-frame work**:
```
1. Calculate positions (6 calculations)
2. Update frames (6 layer updates)
3. Recreate paths (2 NSBezierPath → CGPath conversions)
4. Update bounds (2 boundingBox calculations)
Total: ~16 operations per frame
```

**CPU usage** (theoretical):
- Playback: 30 fps × 16 ops = 480 operations/second
- Scrubbing: 60 fps × 16 ops = 960 operations/second

### Baseline Test Results

From PerformanceTests.swift:
```
testTimelineMarkerUpdateBaseline: ~0.463s for 100 updates
testTimelinePositionCalculation: ~0.463s for 1000 calculations
testTimelineMarkerHitTesting: ~0.476s for 1000 tests
```

---

## Optimization Opportunities

### Priority 1: Selective Layer Updates

**Issue**: Every marker move triggers full layout

**Solution**: Update only changed layers
```swift
// Instead of:
needsLayout = true  // Updates ALL layers

// Do:
updateCurrentMarker(to: position)  // Updates ONLY current marker
```

**Impact**: 
- Reduce operations from 16 → 3-4 per update
- CPU usage: -70% during single marker movement

**Effort**: Medium (3-4 hours)

### Priority 2: Path Caching

**Issue**: NSBezierPath → CGPath conversion every frame

**Solution**: Cache static paths
```swift
private var cachedTimelinePath: CGPath?
private var cachedSelectionPath: CGPath?

func updateSelectionPath() {
    if needsPathRecreation {
        cachedSelectionPath = NSBezierPath(rect: rect).cgPath
        needsPathRecreation = false
    }
    selection?.path = cachedSelectionPath
}
```

**Impact**:
- Eliminate 2 path conversions per frame
- CPU usage: -15% during updates

**Effort**: Low (1-2 hours)

### Priority 3: Layout Batching

**Issue**: Multiple `needsLayout = true` in rapid succession

**Solution**: Batch layout requests
```swift
private var layoutScheduled = false

func scheduleLayout() {
    guard !layoutScheduled else { return }
    layoutScheduled = true
    
    DispatchQueue.main.async {
        self.layoutScheduled = false
        self.needsLayout = true
    }
}
```

**Impact**:
- Coalesce multiple updates into one
- CPU usage: -30% during rapid changes

**Effort**: Low (1 hour)

### Priority 4: Dirty Rect Tracking

**Issue**: Full view invalidation on every update

**Solution**: Track changed regions
```swift
func invalidateMarker(_ marker: marker) {
    let rect = rectForMarker(marker)
    setNeedsDisplay(rect)  // Partial invalidation
}
```

**Impact**:
- Reduce invalidation area
- Compositor can skip unchanged regions
- GPU usage: -40% for small movements

**Effort**: Medium (2-3 hours)

---

## Implementation Plan

### Phase 1: Low-Hanging Fruit (2-3 hours)

1. **Path Caching** ✨
   - Cache timeline path (rarely changes)
   - Cache selection path (only width changes)
   - Recreate only when bounds change

2. **Layout Batching** ✨
   - Implement `scheduleLayout()`
   - Replace direct `needsLayout = true`
   - Test with rapid marker updates

### Phase 2: Selective Updates (3-4 hours)

3. **Granular Update Methods**
   - `updateCurrentMarkerPosition(_:)`
   - `updateStartMarkerPosition(_:)`
   - `updateEndMarkerPosition(_:)`
   - `updateSelectionRegion()`
   
4. **Smart Layout Logic**
   - Only update changed components
   - Skip unchanged layers
   - CATransaction per component

### Phase 3: Advanced Optimization (Optional, 2-3 hours)

5. **Dirty Rect Implementation**
   - Track marker rects
   - Implement `setNeedsDisplay(_:)` for partial updates
   - Test invalidation efficiency

6. **Performance Instrumentation**
   - Add os_signpost markers
   - Measure actual frame times
   - Profile with Instruments

---

## Expected Results

### Performance Gains

**After Phase 1** (Low-Hanging Fruit):
- CPU usage: -20% to -30%
- Layout operations: Coalesced and cached
- Effort: 2-3 hours

**After Phase 2** (Selective Updates):
- CPU usage: -50% to -70%
- Per-frame operations: 16 → 4-5
- Effort: Additional 3-4 hours

**After Phase 3** (Advanced):
- CPU usage: -70% to -85%
- GPU compositing: More efficient
- Effort: Additional 2-3 hours

### Target Metrics

**Current** (estimated):
- Playback: 480 ops/second
- Scrubbing: 960 ops/second
- Frame time: ~2-3ms

**After Optimization** (target):
- Playback: 150 ops/second (-70%)
- Scrubbing: 300 ops/second (-70%)
- Frame time: ~0.5-1ms (-67%)

**Margin for 60 FPS**:
- Budget: 16.67ms per frame
- Current: 2-3ms (plenty of headroom) ✅
- After: 0.5-1ms (even better) ✅

---

## Risk Assessment

### Low Risk ✅
- Path caching
- Layout batching
- Performance instrumentation

### Medium Risk ⚠️
- Selective layer updates (requires careful testing)
- Dirty rect implementation (complex invalidation logic)

### Testing Strategy

1. **Visual Verification**
   - Test all marker movements
   - Verify selection display
   - Check timeline accuracy

2. **Performance Testing**
   - Before/after measurements
   - Instruments Time Profiler
   - Frame rate monitoring

3. **Regression Testing**
   - Run existing tests
   - Add timeline-specific tests
   - Test edge cases (window resize, etc.)

---

## Recommendation

**Start with Phase 1** (Low-Hanging Fruit):
- Quick wins with low risk
- 20-30% improvement
- 2-3 hours effort
- Establishes measurement baseline

**Then evaluate Phase 2**:
- Based on Phase 1 results
- If 60 FPS already achieved, stop here
- If more optimization needed, proceed

**Phase 3 is optional**:
- Only if targeting very old hardware
- Or supporting 120Hz displays
- Diminishing returns

---

## Next Steps

1. ✅ Complete this analysis
2. ⏳ Implement Phase 1 optimizations
3. ⏳ Measure improvements
4. ⏳ Decide on Phase 2
5. ⏳ Document results

---

**Status**: Analysis Complete  
**Ready for**: Implementation  
**Estimated Total Effort**: 5-10 hours  
**Expected Improvement**: 50-70% CPU reduction
