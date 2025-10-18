# Phase 2.3: Logging System Implementation Plan

**Version**: 1.0  
**Date**: October 18, 2025  
**Phase**: 2.3 - Logging System  
**Duration**: 1-2 weeks  
**Status**: 📋 Planning

---

## Executive Summary

Phase 2.3 aims to modernize cutter2's logging infrastructure by migrating from simple `print()` statements to Apple's unified logging system (`os.Logger`). This will provide structured logging, proper log levels, system integration, and better debugging capabilities.

### Current State

- **320 print() statements** across 25 Swift files
- **useLog flag** in AppDelegate for controlling debug output
- **No structured logging** or log levels
- **No system integration** with Console.app
- **Mixed purposes**: Debug traces, error reporting, progress tracking

### Goals

1. **Migrate to os.Logger**: Replace all print() statements with structured logging
2. **Implement Log Levels**: debug, info, notice, warning, error, fault
3. **System Integration**: Enable viewing logs in Console.app
4. **Performance**: Maintain zero overhead in release builds
5. **Maintainability**: Create reusable logging utilities

### Success Metrics

**Quantitative**:
- 100% migration of print() statements to Logger
- Zero performance regression in release builds
- All log categories properly defined
- 10+ unit tests for logging infrastructure

**Qualitative**:
- Easy to filter logs by category in Console.app
- Clear log levels for different scenarios
- Improved debugging experience
- Better production diagnostics

---

## 1. Current Logging Analysis

### 1.1 Print Statement Distribution

| File | Count | Primary Use |
|------|-------|-------------|
| Document+Delegate.swift | 49 | Document state, selection info |
| Document+Utilities.swift | 46 | Utility operations, debugging |
| ViewController+KeyEvent.swift | 38 | Keyboard event handling |
| Document+FileIO.swift | 21 | File I/O operations |
| MovieWriter.swift | 19 | Export progress, errors |
| ViewController+KeyboardAction.swift | 16 | Keyboard actions |
| CAPARViewController.swift | 15 | CAPAR adjustments |
| MovieMutator+Edit.swift | 15 | Edit operations |
| PerformanceMetrics.swift | 12 | Performance measurements |
| MovieMutatorBase.swift | 12 | Movie operations |
| Others (15 files) | 77 | Various |
| **Total** | **320** | |

### 1.2 Logging Categories

Based on code analysis, the following categories are identified:

1. **Document Operations** (67 statements)
   - File open/close
   - Save/export operations
   - Document state changes

2. **Video Processing** (46 statements)
   - Movie editing operations
   - Transform operations
   - Export/transcode progress

3. **User Interaction** (54 statements)
   - Keyboard events
   - Mouse events
   - UI state changes

4. **Performance** (12 statements)
   - Timing measurements
   - Resource usage

5. **Error Reporting** (31 statements)
   - Error conditions
   - Validation failures

6. **Debug Traces** (110 statements)
   - Function entry/exit
   - State inspection
   - Development debugging

### 1.3 Current Logging Patterns

```swift
// Pattern 1: Simple debug trace (commented out)
// Swift.print(#function, #line, #file)

// Pattern 2: Conditional with useLog flag
if useLog {
    print("DEBUG: Bookmark validation...")
}

// Pattern 3: Direct print with timestamp
Swift.print(ts(), "diff", CMTimeGetSeconds(range.duration))

// Pattern 4: Error reporting
Swift.print("ERROR:", error)

// Pattern 5: Progress/status reporting
Swift.print("##### result:", statusStr, "progress:", progressStr)

// Pattern 6: Performance metrics
print("📊 Performance: \(name) took \(String(format: "%.3f", duration))s")
```

---

## 2. Proposed Logging Architecture

### 2.1 Logger Categories

Define separate loggers for different subsystems:

```swift
// Utilities/LoggingSystem.swift

import os.log

/// Centralized logging system for cutter2
///
/// Note: Not marked as @MainActor to allow usage from nonisolated contexts
enum LoggingSystem {
    // MARK: - Subsystem
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mycometg3.cutter2"
    
    // MARK: - Loggers by Category
    
    /// Document operations (open, save, export)
    static let document = Logger(subsystem: subsystem, category: "document")
    
    /// Video processing and editing operations
    static let video = Logger(subsystem: subsystem, category: "video")
    
    /// User interface and interaction events
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
    /// Performance measurements and metrics
    static let performance = Logger(subsystem: subsystem, category: "performance")
    
    /// File I/O operations
    static let fileIO = Logger(subsystem: subsystem, category: "fileIO")
    
    /// Bookmark and security-scoped resource management
    static let security = Logger(subsystem: subsystem, category: "security")
    
    /// Export and transcode operations
    static let export = Logger(subsystem: subsystem, category: "export")
    
    /// Keyboard and input handling
    static let input = Logger(subsystem: subsystem, category: "input")
    
    /// General application lifecycle
    static let app = Logger(subsystem: subsystem, category: "app")
}
```

### 2.2 Log Levels

Use appropriate log levels for different scenarios:

| Level | Use Case | Example |
|-------|----------|---------|
| **debug** | Development debugging, detailed traces | Function entry/exit, variable values |
| **info** | Informational messages | Operation started, file opened |
| **notice** | Significant but normal events | Export completed, document saved |
| **warning** | Potential issues, non-fatal errors | Deprecated API used, fallback activated |
| **error** | Error conditions | File I/O error, invalid input |
| **fault** | Critical failures | Unrecoverable errors, app state corruption |

### 2.3 Logging Conventions

```swift
// ✅ Good: Structured logging with context
LoggingSystem.document.info("Opening movie file: \(url.lastPathComponent)")

// ✅ Good: Error with details
LoggingSystem.fileIO.error("Failed to read file: \(error.localizedDescription)")

// ✅ Good: Debug with privacy
LoggingSystem.video.debug("Processing frame at time: \(time, privacy: .public)")

// ✅ Good: Performance measurement
LoggingSystem.performance.notice("Export completed in \(duration)s")

// ❌ Bad: Generic message without context
print("Error")

// ❌ Bad: Sensitive information without privacy control
print("Opening file at path: \(url.path)")
```

### 2.4 Privacy Considerations

```swift
// Public: Safe to log in production
LoggingSystem.document.info("Document count: \(count, privacy: .public)")

// Private: Redacted in production (default)
LoggingSystem.fileIO.debug("File path: \(url.path)")

// Sensitive: Always redacted
LoggingSystem.security.debug("Bookmark data: \(data, privacy: .sensitive)")
```

---

## 3. Implementation Plan

### Week 1: Infrastructure & High-Priority Migration

#### Day 1: Setup Logging Infrastructure (4 hours)

**Task 1.1: Create LoggingSystem utility**
- [ ] Create `Utilities/LoggingSystem.swift`
- [ ] Define subsystem and categories
- [ ] Add documentation and usage examples
- [ ] Create unit tests for logging infrastructure

**Task 1.2: Update build configuration**
- [ ] Add conditional compilation flags for logging
- [ ] Configure release build to minimize logging overhead
- [ ] Update scheme settings for log level control

**Deliverables**:
- ✅ LoggingSystem.swift with 9 category loggers
- ✅ Unit tests (LoggingSystemTests.swift)
- ✅ Build configuration updates

#### Day 2-3: Migrate Document & FileIO (8 hours)

**Task 2.1: Document layer migration (4 hours)**
- [ ] Document+FileIO.swift (21 print statements)
- [ ] Document+Utilities.swift (46 print statements)
- [ ] Document+Delegate.swift (49 print statements)
- [ ] Document+Export.swift (8 print statements)
- [ ] Document+SavePanel.swift (6 print statements)
- [ ] Document.swift (6 print statements)

**Migration pattern**:
```swift
// Before
Swift.print(#function, #line, #file)
Swift.print("ERROR:", error)

// After
LoggingSystem.document.debug("\(#function) called")
LoggingSystem.document.error("Operation failed: \(error)")
```

**Task 2.2: Test migrated code**
- [ ] Build and run application
- [ ] Verify logs appear in Console.app
- [ ] Test filtering by category
- [ ] Verify no performance regression

**Deliverables**:
- ✅ 136 print statements migrated to Logger
- ✅ All document operations properly logged
- ✅ Console.app filtering verified

#### Day 4: Migrate Video Processing (4 hours)

**Task 3.1: Video layer migration**
- [ ] MovieWriter.swift (19 print statements)
- [ ] MovieMutator+Edit.swift (15 print statements)
- [ ] MovieMutator+Transform.swift (11 print statements)
- [ ] MovieMutatorBase.swift (12 print statements)
- [ ] SampleBufferChannel.swift (if any)

**Focus areas**:
- Export progress logging
- Transform operation logging
- Error condition logging
- Performance-critical paths

**Deliverables**:
- ✅ 57 print statements migrated
- ✅ Export progress properly logged
- ✅ Video operations traceable in Console.app

#### Day 5: Migrate UI & Testing (4 hours)

**Task 4.1: UI layer migration**
- [ ] ViewController+KeyEvent.swift (38 print statements)
- [ ] ViewController+KeyboardAction.swift (16 print statements)
- [ ] ViewController+Observer.swift (2 print statements)
- [ ] ViewController.swift (1 print statement)
- [ ] WindowController.swift (4 print statements)

**Task 4.2: Other controllers**
- [ ] CAPARViewController.swift (15 print statements)
- [ ] InspectorViewController.swift (5 print statements)
- [ ] TranscodeViewController.swift (3 print statements)
- [ ] AccessoryViewController.swift (1 print statement)

**Task 4.3: Comprehensive testing**
- [ ] Run all unit tests (60 tests)
- [ ] Manual testing of key workflows
- [ ] Console.app log verification
- [ ] Performance testing

**Deliverables**:
- ✅ 85 print statements migrated
- ✅ All UI interactions properly logged
- ✅ All tests passing

### Week 2: Remaining Migration & Polish

#### Day 6: Migrate Application & Utilities (4 hours)

**Task 5.1: Application layer**
- [ ] AppDelegate.swift (10 print statements)
  - Remove useLog flag
  - Migrate bookmark logging
- [ ] DocumentController.swift (5 print statements)

**Task 5.2: Utilities & Views**
- [ ] PerformanceMetrics.swift (12 print statements)
  - Integrate with LoggingSystem.performance
- [ ] LayoutConverter.swift (7 print statements)
- [ ] TimelineView.swift (4 print statements)

**Deliverables**:
- ✅ 38 print statements migrated
- ✅ useLog flag removed
- ✅ PerformanceMetrics integrated with Logger

#### Day 7: Documentation & Examples (3 hours)

**Task 6.1: Update documentation**
- [ ] Create LOGGING_GUIDE.md
  - Usage examples
  - Best practices
  - Console.app filtering guide
  - Privacy guidelines
- [ ] Update DEVELOPMENT_GUIDE.md
  - Add logging section
  - Reference LOGGING_GUIDE.md
- [ ] Update CONTRIBUTING.md
  - Logging conventions
  - Code review checklist

**Task 6.2: Code comments**
- [ ] Add logging examples to key files
- [ ] Document log categories in LoggingSystem.swift
- [ ] Update inline documentation

**Deliverables**:
- ✅ LOGGING_GUIDE.md created
- ✅ Development docs updated
- ✅ Code examples added

#### Day 8: Testing & Validation (4 hours)

**Task 7.1: Comprehensive testing**
- [ ] Run full test suite (60+ tests)
- [ ] Performance benchmarking
- [ ] Memory leak detection
- [ ] Console.app log validation

**Task 7.2: Real-world testing**
- [ ] Open large video files
- [ ] Perform export operations
- [ ] Test error conditions
- [ ] Verify log filtering

**Task 7.3: Build validation**
- [ ] Debug build: All logs visible
- [ ] Release build: Minimal overhead
- [ ] Archive build: Production-ready

**Deliverables**:
- ✅ All tests passing
- ✅ Performance baseline maintained
- ✅ Zero memory leaks
- ✅ Production build validated

#### Day 9: Cleanup & Finalization (2 hours)

**Task 8.1: Code cleanup**
- [ ] Remove all commented print() statements
- [ ] Remove useLog flag and related code
- [ ] Clean up debug-only logging
- [ ] Final code review

**Task 8.2: Documentation finalization**
- [ ] Update README.md with logging info
- [ ] Create Phase 2.3 completion summary
- [ ] Update CODEBASE_REVIEW.md
- [ ] Archive planning documents

**Deliverables**:
- ✅ Clean codebase
- ✅ Complete documentation
- ✅ Phase 2.3 completion report

---

## 4. Migration Strategy

### 4.1 File-by-File Migration

**Priority Order**:
1. **High Priority** (Week 1, Days 2-5)
   - Document layer (136 statements)
   - Video processing (57 statements)
   - UI controllers (85 statements)

2. **Medium Priority** (Week 2, Day 6)
   - Application layer (15 statements)
   - Utilities (23 statements)

3. **Low Priority** (Week 2, Day 9)
   - Commented-out print statements
   - Debug-only traces

### 4.2 Testing Strategy

**After each migration batch**:
1. Build and run application
2. Test affected functionality
3. Verify logs in Console.app
4. Run unit tests
5. Check for regressions

**Console.app filtering**:
```
# Filter by subsystem
subsystem:com.mycometg3.cutter2

# Filter by category
category:document
category:video
category:export

# Filter by log level
level:error
level:fault

# Combined filters
subsystem:com.mycometg3.cutter2 AND category:export AND level:info
```

### 4.3 Rollback Plan

If issues arise:
1. Each migration is a separate commit
2. Can revert individual file changes
3. Feature flag for enabling/disabling new logging
4. Keep print() statements temporarily (commented) for reference

---

## 5. Technical Considerations

### 5.1 Performance Impact

**Debug builds**:
- Minimal impact: Logger is optimized for low overhead
- String interpolation only evaluated if log level is enabled
- No concerns for development

**Release builds**:
- Logger automatically reduces overhead
- Debug-level logs compiled out in release
- Use `#if DEBUG` for development-only logging

```swift
#if DEBUG
LoggingSystem.video.debug("Detailed frame info: \(frameInfo)")
#endif

// Info and above always available
LoggingSystem.video.info("Export started")
```

### 5.2 Privacy & Security

**Data classification**:
- **Public**: Counts, durations, status codes
- **Private**: File names, paths (default)
- **Sensitive**: User data, security tokens

**Example**:
```swift
// Safe: Count is public
LoggingSystem.document.info("Loaded \(count, privacy: .public) documents")

// Safe: Path is private by default (redacted in production)
LoggingSystem.fileIO.debug("Opening file: \(url.path)")

// Required: Explicit private
LoggingSystem.security.debug("Bookmark data size: \(data.count, privacy: .private)")
```

### 5.3 Backward Compatibility

**Minimum Requirements**:
- macOS 11.0+ (already required)
- os.Logger available since macOS 11.0
- No additional dependencies

**Migration path**:
- All print() removed
- useLog flag removed
- Conditional compilation for debug-only logs

---

## 6. Logging Best Practices

### 6.1 What to Log

**✅ DO Log**:
- Operation start/completion
- Error conditions with context
- Important state changes
- Performance metrics
- User-initiated actions

**❌ DON'T Log**:
- Every function call (too verbose)
- Sensitive user data
- Redundant information
- In tight loops (performance)

### 6.2 Log Message Format

**Good messages**:
```swift
// Context-rich
LoggingSystem.document.info("Opening movie file: \(filename, privacy: .public)")

// Actionable error
LoggingSystem.fileIO.error("Failed to write file: \(error.localizedDescription)")

// Measurable performance
LoggingSystem.performance.notice("Export completed in \(duration, format: .fixed(precision: 2))s")
```

**Poor messages**:
```swift
// Too vague
LoggingSystem.document.info("Operation completed")

// No context
LoggingSystem.video.error("Error occurred")

// Too verbose
LoggingSystem.ui.debug("Button clicked at x=\(x) y=\(y) with modifiers=\(mods)")
```

### 6.3 Log Levels Guide

```swift
// debug: Development only, detailed traces
LoggingSystem.video.debug("Processing frame \(frameNumber)")

// info: Informational, operation tracking
LoggingSystem.document.info("Document saved successfully")

// notice: Significant events
LoggingSystem.export.notice("Export completed: \(filename)")

// warning: Potential issues, recoverable
LoggingSystem.video.warning("Codec not available, using fallback")

// error: Error conditions, operation failed
LoggingSystem.fileIO.error("Failed to read file: \(error)")

// fault: Critical failures, app stability at risk
LoggingSystem.document.fault("Document state corrupted: \(details)")
```

---

## 7. Testing Plan

### 7.1 Unit Tests

Create `LoggingSystemTests.swift`:

```swift
import XCTest
import os.log
@testable import cutter2

final class LoggingSystemTests: XCTestCase {
    
    func testLoggerCategories() {
        // Verify all categories are properly configured
        XCTAssertNotNil(LoggingSystem.document)
        XCTAssertNotNil(LoggingSystem.video)
        XCTAssertNotNil(LoggingSystem.ui)
        // ... test all categories
    }
    
    func testLoggingDoesNotCrash() {
        // Verify logging doesn't cause crashes
        LoggingSystem.document.debug("Test debug message")
        LoggingSystem.document.info("Test info message")
        LoggingSystem.document.error("Test error message")
    }
    
    func testPerformanceLogging() {
        // Verify minimal performance impact
        measure {
            for _ in 0..<1000 {
                LoggingSystem.performance.debug("Performance test")
            }
        }
    }
    
    func testPrivacyLevels() {
        // Verify privacy controls work
        let sensitiveData = "secret"
        LoggingSystem.security.debug("Data: \(sensitiveData, privacy: .sensitive)")
        // In tests, verify message format (implementation specific)
    }
}
```

### 7.2 Integration Tests

**Manual testing checklist**:
- [ ] Open Console.app
- [ ] Launch cutter2
- [ ] Verify logs appear under subsystem "com.mycometg3.cutter2"
- [ ] Filter by category "document"
- [ ] Open a video file
- [ ] Verify file operations logged
- [ ] Perform edit operation
- [ ] Verify edit logged
- [ ] Export video
- [ ] Verify export progress logged
- [ ] Trigger error condition
- [ ] Verify error logged with context

### 7.3 Performance Tests

Add to `PerformanceTests.swift`:

```swift
func testLoggingPerformance() {
    measure {
        for _ in 0..<10000 {
            LoggingSystem.performance.info("Performance test message")
        }
    }
    // Should complete in < 100ms
}

func testLoggingWithPrivacy() {
    let data = Data(count: 1000)
    measure {
        for _ in 0..<1000 {
            LoggingSystem.security.debug("Data size: \(data.count, privacy: .private)")
        }
    }
    // Should have minimal overhead
}
```

---

## 8. Console.app Usage Guide

### 8.1 Viewing Logs

**Open Console.app**:
1. Applications → Utilities → Console.app
2. Select your Mac in sidebar
3. Click "Start" to begin streaming logs

**Filter to cutter2**:
```
subsystem:com.mycometg3.cutter2
```

### 8.2 Useful Filters

**By category**:
```
subsystem:com.mycometg3.cutter2 AND category:document
subsystem:com.mycometg3.cutter2 AND category:video
subsystem:com.mycometg3.cutter2 AND category:export
```

**By log level**:
```
subsystem:com.mycometg3.cutter2 AND level:error
subsystem:com.mycometg3.cutter2 AND level:>=warning
```

**By message content**:
```
subsystem:com.mycometg3.cutter2 AND message CONTAINS "export"
subsystem:com.mycometg3.cutter2 AND message BEGINSWITH "Failed"
```

**Time range**:
```
subsystem:com.mycometg3.cutter2 AND eventMessage CONTAINS "error" AND timestamp >= 2025-10-18
```

### 8.3 Saving Logs

**Export logs**:
1. File → Save...
2. Select time range
3. Choose format (text, JSON)
4. Save for analysis

**Log collection**:
```bash
# Command line log collection
log show --predicate 'subsystem == "com.mycometg3.cutter2"' --last 1h > cutter2.log

# Continuous monitoring
log stream --predicate 'subsystem == "com.mycometg3.cutter2"'
```

---

## 9. Risks & Mitigation

### 9.1 Identified Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Performance regression | High | Low | Performance tests, profiling |
| Missing logs | Medium | Medium | Code review, checklist |
| Log spam | Low | Medium | Log level guidelines |
| Privacy leak | High | Low | Privacy annotations, review |
| Breaking changes | Medium | Low | Incremental migration, testing |

### 9.2 Mitigation Strategies

**Performance**:
- Performance tests before/after migration
- Profile with Instruments
- Use appropriate log levels
- Conditional compilation for debug logs

**Completeness**:
- Systematic file-by-file migration
- Checklist for each file
- Code review for missed print() statements
- grep verification after migration

**Quality**:
- Logging best practices guide
- Code review checklist
- Example code snippets
- Team training

---

## 10. Success Criteria

### 10.1 Completion Checklist

**Infrastructure**:
- [ ] LoggingSystem.swift created with all categories
- [ ] Unit tests for logging infrastructure
- [ ] Build configuration updated
- [ ] Documentation created

**Migration**:
- [ ] All 320 print() statements migrated
- [ ] useLog flag removed
- [ ] All commented print() statements removed
- [ ] All files reviewed and tested

**Testing**:
- [ ] All unit tests passing (60+ tests)
- [ ] New logging tests passing (10+ tests)
- [ ] Performance baseline maintained
- [ ] Zero memory leaks
- [ ] Console.app verification complete

**Documentation**:
- [ ] LOGGING_GUIDE.md created
- [ ] DEVELOPMENT_GUIDE.md updated
- [ ] CONTRIBUTING.md updated
- [ ] Phase 2.3 completion report
- [ ] CODEBASE_REVIEW.md updated

### 10.2 Quality Metrics

**Code Quality**:
- Zero print() statements remaining
- All logs properly categorized
- Consistent message format
- Privacy annotations applied

**Performance**:
- No regression in app launch time
- No regression in export performance
- Logging overhead < 1% in debug builds
- Minimal overhead in release builds

**Usability**:
- Easy to filter logs in Console.app
- Clear log messages with context
- Appropriate log levels used
- Helpful for debugging production issues

---

## 11. Timeline Summary

### Detailed Schedule

| Week | Day | Duration | Tasks | Deliverables |
|------|-----|----------|-------|--------------|
| 1 | 1 | 4h | Logging infrastructure | LoggingSystem.swift, tests |
| 1 | 2-3 | 8h | Document & FileIO migration | 136 statements migrated |
| 1 | 4 | 4h | Video processing migration | 57 statements migrated |
| 1 | 5 | 4h | UI & controllers migration | 85 statements migrated |
| 2 | 6 | 4h | App & utilities migration | 38 statements migrated |
| 2 | 7 | 3h | Documentation | LOGGING_GUIDE.md |
| 2 | 8 | 4h | Testing & validation | All tests passing |
| 2 | 9 | 2h | Cleanup & finalization | Phase 2.3 complete |

**Total Effort**: 33 hours (~2 weeks at 4 hours/day)

### Milestones

- **End of Week 1**: Core migration complete (278/320 statements)
- **Mid Week 2**: All migration complete (320/320 statements)
- **End of Week 2**: Testing, documentation, and release

---

## 12. References

### Apple Documentation
- [Unified Logging and Activity Tracing](https://developer.apple.com/documentation/os/logging)
- [Logger](https://developer.apple.com/documentation/os/logger)
- [Generating Log Messages from Your Code](https://developer.apple.com/documentation/os/logging/generating_log_messages_from_your_code)
- [Privacy and Your App's Logs](https://developer.apple.com/documentation/os/logging/generating_log_messages_from_your_code#3665948)

### WWDC Sessions
- WWDC 2020: [Explore logging in Swift](https://developer.apple.com/videos/play/wwdc2020/10168/)
- WWDC 2016: [Unified Logging and Activity Tracing](https://developer.apple.com/videos/play/wwdc2016/721/)

### Internal Documentation
- [CODEBASE_REVIEW.md](CODEBASE_REVIEW.md) - Section 10.2, Item 6
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) - To be updated
- [CONTRIBUTING.md](CONTRIBUTING.md) - To be updated

---

## Appendix A: Example Migrations

### A.1 Document Operations

**Before**:
```swift
// Document+FileIO.swift
func readAsync(from url: URL, ofType typeName: String) async throws {
    Swift.print(#function, #line, #file)
    // ... operation ...
    Swift.print("ERROR:", error)
}
```

**After**:
```swift
// Document+FileIO.swift
func readAsync(from url: URL, ofType typeName: String) async throws {
    LoggingSystem.document.debug("\(#function) called for \(url.lastPathComponent)")
    // ... operation ...
    LoggingSystem.fileIO.error("Failed to read file: \(error.localizedDescription)")
}
```

### A.2 Export Progress

**Before**:
```swift
// MovieWriter.swift
Swift.print("#####", "result:", statusStr, "progress:", progressStr, "elapsed:", intervalStr)
```

**After**:
```swift
// MovieWriter.swift
LoggingSystem.export.info("Export \(status): progress=\(progress, format: .percent) elapsed=\(interval, format: .fixed(precision: 1))s")
```

### A.3 Keyboard Events

**Before**:
```swift
// ViewController+KeyEvent.swift
// Swift.print(#function, #line, #file)
override func keyDown(with event: NSEvent) {
    Swift.print("Key pressed: \(event.keyCode)")
}
```

**After**:
```swift
// ViewController+KeyEvent.swift
override func keyDown(with event: NSEvent) {
    LoggingSystem.input.debug("Key down: code=\(event.keyCode, privacy: .public)")
}
```

### A.4 Performance Metrics

**Before**:
```swift
// PerformanceMetrics.swift
print("📊 Performance: \(name) took \(String(format: "%.3f", duration))s")
```

**After**:
```swift
// PerformanceMetrics.swift
LoggingSystem.performance.notice("\(name) completed in \(duration, format: .fixed(precision: 3))s")
```

### A.5 Error Conditions

**Before**:
```swift
// MovieWriter.swift
Swift.print("ERROR: Incompatible presetName detected with AVAsset.")
```

**After**:
```swift
// MovieWriter.swift
LoggingSystem.video.error("Incompatible preset '\(presetName)' for asset type")
```

---

## Appendix B: Build Configuration

### B.1 Debug Build Settings

Add to build settings for Debug configuration:

```swift
// In Build Settings → Other Swift Flags → Debug
-DDEBUG
```

### B.2 Release Build Settings

Ensure logging is optimized:

```swift
// In Build Settings → Other Swift Flags → Release
-DRELEASE

// Optimization Level → Release
-O (Optimize for Speed)
```

### B.3 Scheme Settings

**Debug Scheme**:
- Enable all log levels
- Capture logs to Console.app
- Include debug-only logging

**Release Scheme**:
- Disable debug logging
- Optimize for performance
- Minimal logging overhead

---

## Appendix C: Migration Checklist Template

Use this checklist for each file migration:

### File: ___________________________

**Pre-Migration**:
- [ ] Count print() statements: _____
- [ ] Review logging purposes
- [ ] Identify appropriate categories
- [ ] Plan log levels

**Migration**:
- [ ] Replace print() with Logger calls
- [ ] Apply privacy annotations
- [ ] Use appropriate log levels
- [ ] Add context to log messages
- [ ] Remove or comment useLog checks

**Testing**:
- [ ] Build succeeds
- [ ] No compiler warnings
- [ ] Manual testing of functionality
- [ ] Logs visible in Console.app
- [ ] Filtering works correctly

**Verification**:
- [ ] No print() statements remain
- [ ] All logs properly categorized
- [ ] Performance not affected
- [ ] Code review completed

**Commit**:
- [ ] Changes committed
- [ ] Commit message descriptive
- [ ] Related to GitHub issue (if any)

---

**Document End**

This plan provides a comprehensive roadmap for Phase 2.3. Adjust timeline and priorities based on actual progress and findings during implementation.
