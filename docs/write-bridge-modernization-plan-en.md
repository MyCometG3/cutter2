# cutter2: Document.write() Async Bridge Modernization Plan

Last Updated: 2024-01-27

## TL;DR
- **Objective**: Bridge long-running operations (export/write) within AppKit's synchronous API `Document.write(...)` in a way that is consistent and safe with Swift Concurrency, and integrate with UI/document lifecycle.
- **Current State**: Using `performAsync` (Task.detached + DispatchSemaphore + SendableBox) for async→sync blocking conversion. `canAsynchronouslyWrite` returns true, enabling AppKit's background processing.
- **Issues**: Task inheritance disruption by Task.detached, lack of NSProgress integration, absence of standard cancellation mechanism.
- **Recommended Approach**: Build upon the current implementation, incrementally introducing `NSProgress` integration and cancellation support. Replacement with `NSDocument.performActivity` is positioned as an optional alternative.

---

## Scope and Target

### Target Code
- `cutter2/Document.swift`
  - `override nonisolated func write(...) throws`
  - `override nonisolated func writeSafely(...) throws`
  - `private func writeAsync(...) async throws`
  - `private func export(...) async throws`
  - `private func exportCustom(...) async throws`
- `cutter2/Document+Utilities.swift`
  - `performAsync` (throwing/non-throwing)
  - `performSyncOnMainActor`

### Out of Scope
- Individual editing logic in `MovieMutator` (cancellation support may be added as needed)
- UI/Storyboard structure (Busy Sheet can remain as-is)

## Current Operation Flow (Summary)

1. `writeSafely(...)` performs preprocessing (UTI/overwrite validation) synchronously on MainActor (via `performSyncOnMainActor`).
2. `write(...)` calls `performAsync { ... await export/writeAsync }` and waits for completion with a semaphore.
3. `writeAsync/export/exportCustom` display Busy Sheet and reflect progress to UI via `mutator.updateProgress`.
4. With `canAsynchronouslyWrite(...) == true`, AppKit executes write() on a background queue.
5. Async processing is executed within the `MovieWriter` actor, using AVAssetExportSession or AVAssetWriter.

## Key Issues

### Concerns with Current Sync Bridge
- `Task.detached` disrupts parent task cancellation and priority inheritance.
  - However, given the constraint of calling from a `nonisolated` context, using detached is necessary by design.
- Semaphore waiting is incompatible with task cooperative cancellation.
- `SendableBox` uses `@unchecked Sendable`, requiring careful validation.

### Absence of NSProgress / Standard Cancellation Mechanism
- No use of `NSProgress`, resulting in weak standard progress UI and system integration.
- User cancellation is not implemented.
  - `MovieWriter` internally has `writeCancelled` flag and `cancelCustomMovie` method, but the external calling interface is incomplete.
  - `AVAssetExportSession` cancellation is possible but not integrated.

### NSDocument Activity Management
- `canAsynchronouslyWrite` already returns true, and AppKit properly handles background processing.
- Migration to `performActivity` is not mandatory; the current approach fundamentally works.

## Improvement Strategy (Recommended)

### Basic Policy
The current implementation (`canAsynchronouslyWrite` + `performAsync`) already works fundamentally. Adopt a gradual and conservative approach to avoid large-scale refactoring risks.

### Step 1: NSProgress Integration (Priority: High)
Integrate progress reporting with `NSProgress` to achieve standard progress management.

1. Add `private var saveProgress: Progress?` to `Document`.
2. Create `Progress(totalUnitCount: 100)` at the start of write/export.
3. Update `progress.completedUnitCount` within the `mutator.updateProgress` callback.
4. Cleanup with `saveProgress = nil` on completion/failure.
5. Consider integration with NSDocument's standard `progress` property (`self.progress = saveProgress`).

**Notes:**
- `Progress` is thread-safe, but updates should be performed on MainActor.
- `mutator.updateProgress` is already executed on MainActor via `performSyncOnMainActor`.

### Step 2: Cancellation Support (Priority: Medium)
Enable user cancellation of long-running operations.

1. Add public cancellation method to `MovieWriter`:
   ```swift
   public func cancelExport() {
       writeCancelled = true
       exportSession?.cancelExport()
   }
   ```
2. Add `cancel()` method to `MovieMutator` to forward to internal `MovieWriter`.
3. Add Cancel button to Busy Sheet, calling `saveProgress?.cancel()` and `mutator.cancel()` on press.
4. On cancellation detection:
   - Close silently without showing error sheet.
   - Maintain document's Dirty flag (unsaved state).
   - Special-case `writeCancelled` error to bypass normal error handling.

### Step 3: Documentation and Code Comments (Priority: High)
Clarify the intent of the current implementation.

1. Document `performAsync` with the following rationale:
   - Necessity of calling async processing from `nonisolated` context.
   - Reason for using `Task.detached` (AppKit already executes on background queue).
   - Relationship with `canAsynchronouslyWrite`.
2. Add comments explaining `SendableBox` thread-safety.

### Alternative: Replacement with performActivity (Priority: Low)
An option for those seeking a more standard approach.

- Use `performActivity(withSynchronousWaiting: true)` within `write(...)`.
- Start a `Task` internally, calling `done()` upon completion.
- No changes required to existing `writeAsync/export/exportCustom`.

**Benefits:**
- Integration with NSDocument's standard activity management.
- Coordination with OS document save monitoring.

**Drawbacks:**
- Significant rewriting required.
- Low ROI since existing implementation already works.
- Debugging cost under Swift 6.0's strict concurrency checks.

**Decision Criteria:**
- Consider only if actual problems occur after implementing Steps 1-3.

## Pseudo Code (NSProgress Integration Example)
> Implementation sample. No actual code changes in this plan.

### Step 1: NSProgress Integration

```swift
// in Document.swift
private var saveProgress: Progress? = nil

private func writeAsync(to url: URL, ofType typeName: String) async throws {
    guard let mutator = self.movieMutator else { preconditionFailure("Unexpected nil mutator detected.") }
    
    // Create NSProgress
    let progress = Progress(totalUnitCount: 100)
    self.saveProgress = progress
    // Optional: Integrate with NSDocument standard progress
    // self.progress = progress
    defer {
        self.saveProgress = nil
        // self.progress = nil
    }
    
    // Show busy sheet
    showBusySheet("Writing...", "Please hold on second(s)...")
    mutator.unblockUserInteraction = { @Sendable [weak self] in
        self?.unblockUserInteraction()
    }
    defer {
        mutator.unblockUserInteraction = nil
        hideBusySheet()
    }
    mutator.updateProgress = { @Sendable [weak self] (progressValue) in
        guard let self else { preconditionFailure("Unexpected nil self detected.") }
        performSyncOnMainActor {
            updateProgress(progressValue)
            // Update NSProgress
            if let progress = self.saveProgress {
                progress.completedUnitCount = Int64(progressValue * 100)
            }
        }
    }
    defer {
        mutator.updateProgress = nil
    }
    
    // Existing write logic...
    let fileType: AVFileType = AVFileType.init(rawValue: typeName)
    if fileType == .mov {
        try await mutator.writeMovie(to: url, fileType: fileType, copySampleData: self.copyData)
    } else {
        try await mutator.exportMovie(to: url, fileType: fileType, presetName: nil)
    }
}
```

### Step 2: Cancellation Support

```swift
// in MovieWriter.swift (actor)
public func cancelExport() {
    writeCancelled = true
    exportSession?.cancelExport()
    // For custom export, delegate to existing cancelCustomMovie logic
}

// in MovieMutator.swift
public func cancel() {
    Task { @Sendable [weak self] in
        await self?.movieWriter?.cancelExport()
    }
}

// in Document+Utilities.swift - Update showBusySheet
public func showBusySheet(_ message: String?, _ info: String?) {
    Task { @MainActor in
        guard let window = self.window else { return }
        
        let alert: NSAlert = NSAlert()
        alert.messageText = message ?? "Processing...(message)"
        alert.informativeText = info ?? "Hold on seconds...(informative)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cancel") // Add Cancel button
        let handler: (NSApplication.ModalResponse) -> Void = {[weak self] (response) in
            if response == .alertFirstButtonReturn {
                // User clicked Cancel
                self?.saveProgress?.cancel()
                self?.movieMutator?.cancel()
            }
        }
        alert.beginSheetModal(for: window, completionHandler: handler)
        
        self.alert = alert
    }
}

// in Document.swift - Handle cancellation in write()
override nonisolated func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                    originalContentsURL absoluteOriginalContentsURL: URL?) throws {
    do {
        try performAsync { @Sendable [weak self] in
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            
            // Existing write logic...
        }
    } catch let error as NSError {
        // Check if error is due to cancellation
        if error.domain == "MovieWriterError" && error.localizedDescription.contains("cancelled") {
            // Silent return - don't show error sheet
            // Document remains dirty (unsaved)
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        }
        throw error
    }
}
```

## Phased Migration Plan

### Phase 1: NSProgress Integration (Risk: Low)
- **Goal**: Standardize progress reporting and prepare for system integration
- **Changes**:
  - `Document.swift`: Add `saveProgress` property
  - `writeAsync/export/exportCustom`: Create and update NSProgress
- **Verification**:
  - Progress display works correctly
  - Coexistence with existing Busy Sheet
  - No memory leaks

### Phase 2: Documentation (Risk: None)
- **Goal**: Clarify current implementation intent for easier future maintenance
- **Changes**:
  - `Document+Utilities.swift`: Add comments to `performAsync` and `SendableBox`
  - `Document.swift`: Explain relationship between `canAsynchronouslyWrite` and `write()`
- **Verification**:
  - Comprehension confirmation in code review

### Phase 3: Cancellation Support (Risk: Medium)
- **Goal**: Improve user experience (enable interruption of long operations)
- **Changes**:
  - `MovieWriter.swift`: Add `cancelExport()` method
  - `MovieMutator.swift`: Add `cancel()` method
  - `Document+Utilities.swift`: Add Cancel button to Busy Sheet
  - `Document.swift`: Special handling for cancellation errors
- **Verification**:
  - Resources properly released on cancellation
  - Document state correctly maintained (Dirty flag)
  - Works correctly when retrying save

### Phase 4: performActivity Consideration (Optional, Risk: High)
- **Prerequisite**: Only if actual problems occur after Phases 1-3
- **Goal**: Full migration to NSDocument standard pattern
- **Changes**:
  - `Document.swift`: Complete rewrite of `write()`
- **Verification**:
  - Comprehensive testing of all save scenarios
  - Sandbox environment verification
  - Performance comparison

### Decision Criteria Between Phases
- Phase 1 → Phase 2: Automatic transition (no risk)
- Phase 2 → Phase 3: Depends on user feedback (cancellation feature requests)
- Phase 3 → Phase 4: Only when actual problems occur (not recommended)

## Compatibility and Expected Behavior

- Public API/format remains unchanged.
- Timing of save/export start, completion, and failure remains the same.
- User Experience:
  - Phase 1-2: No changes (internal implementation improvements only)
  - Phase 3: Cancel button addition (opt-in feature addition)
- Performance: Maintain parity with existing implementation. NSProgress overhead is negligible.

## Test Plan

### Normal Cases
- Self-contained mov save / reference movie save
- mp4/m4v/m4a conversion (using presets)
- Custom export (various codecs/bitrate settings)
- Save / Save As / Save To operations

### Error Cases
- UTI mismatch, extension mismatch
- Empty movie (duration = 0)
- Self-contained → reference overwrite block
- Insufficient disk space, insufficient write permissions
- Corrupted media files

### Progress/Long Operations (Phase 1)
- Smooth progress updates for exports exceeding 10 minutes
- NSProgress completedUnitCount updates correctly
- Progress update frequency is appropriate (100ms interval)

### Cancellation (Phase 3)
- Safe cancellation during export
- No error sheet displayed after cancellation
- Document maintains Dirty state
- Works correctly when retrying save after cancellation
- AVAssetExportSession/AVAssetWriter resources properly released

### Regression Tests
- No impact on existing read/playback/edit functions
- Undo/Redo works correctly
- Multiple document concurrent processing
- File access in Sandbox environment (security-scoped bookmarks)

## Quality Gates

### Phase 1 (NSProgress Integration)
- Build: Project builds without errors (Swift 6.0 strict concurrency)
- Lint/Format: Compliance with existing style guide (section MARK, documentation comments)
- Unit Test: Verification of progress update logic
- Manual Test: Progress displayed correctly in main save scenarios
- Memory: Leak check with Instruments

### Phase 2 (Documentation)
- Code Review: Clarity and accuracy of comments
- Documentation: Technical decision rationale is explained

### Phase 3 (Cancellation Support)
- Build: Builds without errors
- API Test: Verification of newly added cancel methods
- Integration Test: Cancellation propagates consistently from Cancel button to MovieWriter
- Stress Test: Multiple cancel/retry cycles work without issues
- Resource Test: No file handles or temp files remain after cancellation

### Common to All Phases
- Regression: No side effects on existing read/playback/GUI operations
- Performance: No performance degradation compared to existing implementation
- Sandbox: security-scoped bookmarks function correctly

## Risks and Mitigation

### Phase 1 (NSProgress Integration) Risks
- **Risk**: NSProgress update frequency too high, affecting performance
  - **Mitigation**: Maintain existing update frequency limit (100ms interval)
- **Risk**: Progress updates on MainActor block UI
  - **Mitigation**: Already properly handled by `performSyncOnMainActor`
- **Risk**: Memory leak (Progress object retention)
  - **Mitigation**: Reliable cleanup in defer blocks, verification with Instruments

### Phase 3 (Cancellation Support) Risks
- **Risk**: Resource leak on cancellation
  - **Mitigation**:
    - Leverage existing `writeCancelled` flag in `MovieWriter`
    - Verify proper cleanup of AVAssetExportSession/AVAssetWriter
    - Reliable resource release in defer blocks
- **Risk**: Document state inconsistency after cancellation
  - **Mitigation**:
    - Treat cancellation as `NSUserCancelledError`
    - Maintain document's Dirty flag
    - Clean up partially written files
- **Risk**: Issues with multiple cancel/retry cycles
  - **Mitigation**: Verification with stress tests, confirm state reset

### Phase 4 (performActivity) Risks
- **Risk**: Unexpected side effects from large-scale refactoring
  - **Mitigation**: This phase is not recommended. If implemented, ensure adequate validation period
- **Risk**: Compilation errors under Swift 6.0 strict concurrency checks
  - **Mitigation**: Gradual implementation, preliminary validation with small prototypes

### Common Risks
- **Risk**: File access issues in Sandbox environment
  - **Mitigation**: Verify security-scoped bookmarks maintenance, don't change existing access patterns

## Rollback Strategy

### Phase 1 (NSProgress Integration) Rollback
- Remove NSProgress-related code
- Revert `updateProgress` changes
- Remove `saveProgress` property
- **Duration**: Several hours
- **Risk**: Low (removal of added code only)

### Phase 3 (Cancellation Support) Rollback
- Remove Cancel button
- Remove `cancelExport()` / `cancel()` methods
- Remove cancellation error handling
- **Duration**: 1 day
- **Risk**: Low (removal of feature addition only)

### Phase 4 (performActivity) Rollback
- Revert entire `write()` method to previous implementation
- Restore `performAsync` utility (if removed)
- **Duration**: Several days (comprehensive testing required)
- **Risk**: Medium (core functionality change)

### Rollback Decision Criteria
- **Phase 1**: Performance issues with progress updates, memory leaks
- **Phase 3**: Unstable behavior after cancellation, resource leaks
- **Phase 4**: Increased save failure rate, unexpected crashes

### Version Control
- Record each phase as separate commits
- Tagging: `phase1-nsprogress`, `phase2-docs`, `phase3-cancel`
- On issues, revert to relevant commit or fix with cherry-pick

## Future Extensions

### Short-term (After Phases 1-3)
- Integrate NSProgress with NSWindow's standard progress UI (toolbar/title bar display)
- Visual improvements to progress bar (embed in Busy Sheet)
- Display estimated remaining time (`estimatedTimeRemaining` property)

### Mid-term
- Optimized progress estimation per export preset
- Background export (continue even after closing document)
- Manage parallel exports of multiple documents

### Long-term (When Considering Phase 4)
- Full migration to `NSDocument.performActivity` (if necessity is confirmed)
- Integration with system-level progress monitoring
- App Intents / Shortcuts support (automation support)

### Metrics and Monitoring
- Progress telemetry (logging/metrics) for bottleneck analysis
- Export time statistics collection
- User cancellation frequency analysis (after Phase 3)

## Reference: Affected Areas List

### Phase 1 (NSProgress Integration)
- `Document.swift`
  - Add `saveProgress` property (private)
  - Modify `writeAsync(to:ofType:)` (NSProgress creation, update, cleanup)
  - Modify `export(to:ofType:preset:)` (same as above)
  - Modify `exportCustom(to:ofType:)` (same as above)

### Phase 2 (Documentation)
- `Document+Utilities.swift`
  - Expand documentation comments for `performAsync` method
  - Add comments to `SendableBox` class
- `Document.swift`
  - Add comments to `canAsynchronouslyWrite(to:ofType:for:)`
  - Add comments to `write(to:ofType:for:originalContentsURL:)`

### Phase 3 (Cancellation Support)
- `MovieWriter.swift` (actor)
  - Add `cancelExport()` method (public)
  - Leverage existing `writeCancelled` flag
- `MovieMutator.swift`
  - Add `cancel()` method (public)
- `Document+Utilities.swift`
  - Modify `showBusySheet(_:_:)` (add Cancel button)
- `Document.swift`
  - Modify `write(to:ofType:for:originalContentsURL:)` (cancellation error handling)

### Phase 4 (performActivity, Optional)
- `Document.swift`
  - Complete rewrite of `write(to:ofType:for:originalContentsURL:)`
- `Document+Utilities.swift`
  - Check `performAsync` usage, deprecate if necessary

### Unaffected Areas (No Changes Required)
- `MovieMutatorBase.swift` (no changes)
- `ViewController.swift` (no changes)
- `WindowController.swift` (no changes)
- UI/Storyboard (even when adding Cancel button in Phase 3, implemented programmatically)
- Individual editing logic (various operation methods in MovieMutator)

---

## Technical Implementation Notes

### Swift 6.0 Concurrency Compliance
- Project uses Swift 6.0 with strict concurrency checks enabled
- Comply with `@Sendable`, `@MainActor`, and actor isolation requirements
- Minimize use of `@unchecked Sendable`, document in detail when necessary

### SendableBox Current State
- Existing implementation in `Document+Utilities.swift`
- Thread-safe Result passing with `@unchecked Sendable` + `DispatchQueue`
- `AtomicBox` in pseudo code is not implemented (can substitute with SendableBox)

### Leveraging ActorUtilities
- `ActorUtilities.swift` already exists
- Provides `performSyncOnMainActor` implementation
- Uses `Thread.isMainThread` check and `MainActor.assumeIsolated`

### MovieWriter Actor Design
- `MovieWriter` is already implemented as an actor
- `writeCancelled` flag and `cancelCustomMovie` method already exist
- `AVAssetExportSession` progress monitoring implemented with polling task
- Cancellation support can leverage existing infrastructure

### Sandbox and Security-Scoped Bookmarks
- Need to maintain bookmark validity during long operations
- `canAsynchronouslyWrite` + background execution allows AppKit to manage properly
- For reference movie Save As, maintain access to original file (already handled by existing implementation)

### NSProgress Thread-Safety
- `Progress` class is thread-safe
- However, recommend updates on MainActor when involving UI updates
- Continue using existing `performSyncOnMainActor` pattern

---

This plan adopts a phased approach based on actual codebase verification to achieve maximum effect with minimal changes. It respects the already functional implementation while aiming for standard progress management and improved user experience.
