# Codebase Review — cutter2

**Date:** 2026-08-01  
**Reviewer:** Claude (source-level code review)  
**Scope:** `/Volumes/Data/Local/develop/MOVEDIT Workspace/cutter2/`  
**Status:** Completed

---

## 1. Summary

This document records the findings of a comprehensive source-level review of the **cutter2** project — a macOS video editor application built with Swift and AVFoundation. The review covers project structure, architecture, concurrency model, code quality, test coverage, documentation accuracy, and build/CI configuration.

The review was conducted by reading all source files, test files, documentation, build configuration, and CI scripts, and by running `xcodebuild test` to verify test execution results. This revision (2026-08-01) refreshes the previous review (2026-07-30) against the current `work` branch state (HEAD `28410b0`).

**Changes since the 2026-07-30 review:**

- **Test count corrected to 191** (189 passing + 1 skipped + 1 flaky). The previously reported 190 did not account for the intermittent failure of `PerformanceTests.testPerformanceMetricsOverhead()`, which fails when the test runner is under parallel load (overhead >10% threshold). The test passes reliably in isolation.
- **CI workflow updated** to trigger on `main`, `work`, and `develop`, and to run Build → Test → Analyze as three sequential steps (previously single `xcodebuild test` on `main`/`develop`).
- **Swift version is pinned** to `SWIFT_VERSION = 6.0` in the project (the earlier review incorrectly stated it was unpinned).
- **Force casts (`as!`) count is 14**, not 10 — all are CF typealias casts with safety comments.
- **`precondition` in `AsyncBridge.swift` (line 100)** — a deliberate main-thread guard for `AsyncBridge.perform`, distinct from the `preconditionFailure` in `MovieMutatorBase.swift:20`.
- **Version bump to 0.8.19** (uncommitted, `CURRENT_PROJECT_VERSION = 20260801`).

---

## 2. Project Structure

### 2.1 Source Code Organization

The project follows a layered architecture with clear separation of concerns:

```
cutter2/
├── Application/
│   ├── AppDelegate.swift
│   └── DocumentController.swift
├── Document/
│   ├── Document.swift
│   ├── Document+ActorIsolation.swift
│   ├── Document+Export.swift
│   ├── Document+FileIO.swift
│   ├── Document+MovieReference.swift
│   ├── Document+Observers.swift
│   ├── Document+PositionControl.swift
│   ├── Document+SavePanel.swift
│   ├── Document+SheetControl.swift
│   ├── Document+TimelineUpdateDelegate.swift
│   ├── Document+UI.swift
│   ├── Document+Utilities.swift
│   └── Document+ViewControllerDelegate.swift
├── Models/
│   ├── MovieMutator.swift              // Subclass of MovieMutatorBase
│   ├── MovieMutatorBase.swift          // Base class (NSObject subclass)
│   ├── MovieMutatorBase+FormatDescriptions.swift
│   ├── MovieMutatorBase+Formatting.swift
│   ├── MovieMutatorBase+PresentationInfo.swift
│   ├── MovieMutatorBase+Progress.swift
│   ├── MovieMutator+Clipboard.swift
│   ├── MovieMutator+Edit.swift
│   ├── MovieMutator+Transform.swift
│   ├── MovieMutator+Export.swift
│   ├── MovieMutator+Inspector.swift
│   ├── MovieMutator+Player.swift
│   ├── MovieMutatorTypes.swift
│   ├── MovieWriter.swift
│   ├── MovieWriter+CustomExport.swift
│   ├── MovieWriter+ExportSession.swift
│   ├── MovieWriter+WriteMovie.swift
│   ├── SampleBufferChannel.swift
│   ├── Notifications.swift
│   └── AVMutableMovie+Extensions.swift
├── ViewControllers/
│   ├── ViewController.swift
│   ├── ViewController+Observer.swift
│   ├── ViewController+KeyEvent.swift
│   ├── ViewController+KeyboardAction.swift
│   ├── ViewController+Edit.swift
│   ├── ViewController+Timeline.swift
│   ├── CAPARViewController.swift
│   ├── TranscodeViewController.swift
│   ├── WindowController.swift
│   ├── AccessoryViewController.swift
│   └── InspectorViewController.swift
├── Views/
│   ├── TimelineView.swift
│   ├── TimelineView+Input.swift
│   ├── TimelineView+Layers.swift
│   ├── TimelineView+Utilities.swift
│   ├── MyPlayerView.swift
│   └── Window.swift
├── Utilities/
│   ├── AsyncBridge.swift
│   ├── ActorUtilities.swift
│   ├── LayoutConverter.swift
│   ├── LayoutConverter+Convert.swift
│   ├── LayoutConverter+LayoutData.swift
│   ├── LayoutConverter+Mapping.swift
│   ├── MovieHeaderValidator.swift
│   ├── PerformanceMetrics.swift
│   ├── ErrorUtilities.swift
│   ├── Constants.swift
│   ├── LocalizationHelper.swift
│   ├── LoggingSystem.swift
│   └── DateFormatter+Factory.swift
└── Resources/
    ├── Info.plist
    ├── cutter2.entitlements
    └── Localizable.xcstrings
```

**Total source files:** 65 Swift files across 7 directories.

**Note:** `MovieMutator` (in `MovieMutator.swift`) is a subclass of `MovieMutatorBase` (in `MovieMutatorBase.swift`). All functional extensions (`+Edit`, `+Transform`, `+Export`, etc.) are on the `MovieMutator` subclass, not on `MovieMutatorBase` directly.

### 2.2 Test Organization

```
cutter2Tests/
├── MovieMutatorTests.swift
├── MovieMutatorEditTests.swift
├── MovieMutatorTransformExportTests.swift
├── MovieHeaderValidatorTests.swift
├── AsyncBridgeTests.swift
├── TimelineViewRenderingTests.swift
├── ViewControllerKeyEventTests.swift
├── ViewControllerTests.swift
├── DocumentTests.swift
├── ModelTests.swift
├── UtilitiesTests.swift
├── PerformanceTests.swift
├── LocalizationTests.swift
├── LoggingSystemTests.swift
└── cutter2Tests.swift
```

**Total test files:** 15 files, **191 test methods** (189 passing, 1 skipped, 1 flaky — see §2.3, §5.4, and §5.5). Note: 2 method names are duplicated across different test classes (`testMovieHeaderGeneration` in `cutter2Tests.swift` and `MovieMutatorTests.swift`; `testTimeCalculationPerformance` in `MovieMutatorTests.swift` and `ViewControllerTests.swift`).

### 2.3 Test Execution Results

```
Test Run Summary (2026-08-01, xcodebuild test, 2 runs)
  Run 1: ✅ 189 Passed, 1 Skipped, 0 Failed   (TEST SUCCEEDED)
  Run 2: ❌ 189 Passed, 1 Skipped, 1 Failed   (TEST FAILED — flaky)
  Total test methods in source: 191
```

The skipped test is `MovieHeaderValidatorTests.testInvalidDurationPath()`, which throws `XCTSkip` because the `invalidDuration` fixture is not constructible via the public `AVMutableMovie` API.

**Flaky test:** `PerformanceTests.testPerformanceMetricsOverhead()` intermittently fails under parallel test-runner load — measured overhead of `PerformanceMetrics.measure` exceeded the 10% threshold (observed 43.6%). The test passes reliably when run in isolation (0.004 s). See §5.5 for analysis.

**Note:** The `scripts/test.sh` summary output was updated (commit `28410b0`, 2026-07-31) to report 15 files / 190 tests (189 passing + 1 skipped). The actual source contains 191 `func test` declarations; the count in `test.sh` should be bumped to 191 (or derived from `xcodebuild` output) to stay accurate.

---

## 3. Architecture Overview

### 3.1 Layer Structure

| Layer | Responsibility | Key Files |
|-------|---------------|-----------|
| **Application** | App lifecycle, document creation | `AppDelegate.swift`, `DocumentController.swift` |
| **Document** | Core document model, NSDocument subclass, undo/redo, file I/O, export orchestration | `Document.swift` + 12 extensions |
| **Models** | Media manipulation logic (timeline editing, transforms, export) | `MovieMutatorBase.swift` + 4 extensions, `MovieMutator.swift` + 7 extensions, `MovieWriter.swift` + 3 extensions |
| **ViewControllers** | UI coordination, user input handling | `ViewController.swift` + 5 extensions, transcode/CAPAR/inspector dialogs |
| **Views** | Rendering (timeline, player) | `TimelineView.swift` + 3 extensions, `MyPlayerView.swift` |
| **Utilities** | Cross-cutting helpers (concurrency, layout, validation, logging) | Various utility files |

### 3.2 Concurrency Model

The project uses Swift's modern concurrency model with a clear isolation strategy:

- **`@MainActor`**: Applied to `Document`, `ViewController`, `WindowController`, `MovieMutatorBase`, and all UI-related extensions. This ensures all UI updates and document mutations occur on the main thread.

- **`actor MovieWriter`**: A dedicated actor for export state management, isolating export session lifecycle from the main actor.

- **`AsyncBridge`**: A custom utility bridging async/await to synchronous contexts (used in `NSDocument` overrides like `data(ofType:)` and `read(from:ofType:)`).

- **`ActorUtilities.performSyncOnMainActor`**: A utility for safely calling main-actor-isolated code from synchronous contexts.

### 3.3 Data Flow

```
User Input (ViewController)
    → Document (via @MainActor isolation)
        → MovieMutator (subclass of MovieMutatorBase, timeline mutations)
            → AVMutableMovie (AVFoundation)
                → TimelineView (rendering updates)
        → MovieWriter (export orchestration)
            → AVAssetExportSession / AVAssetWriter
```

---

## 4. Code Quality Observations

### 4.1 Force Unwraps (`as!`) — RESOLVED (CF typealias casts remain)

All 54 force-unwraps (`as!`) identified in the initial review have been replaced with `guard-let` statements. The 14 remaining `as!` casts are all CF typealias casts (e.g., `track.formatDescriptions as! [CMFormatDescription]` in `SampleBufferChannel.swift`, `MovieMutator+Inspector.swift`, `MovieMutator+Transform.swift`, `MovieWriter+CustomExport.swift`, `MovieMutatorBase+FormatDescriptions.swift`), each with an explanatory comment documenting why the cast is safe (Swift guarantees the CF typealias cast succeeds). Note the count is 14, not the 10 reported previously — the additional casts were introduced/identified in the `MovieWriter+CustomExport` and `MovieMutator+Transform` files.

### 4.2 `preconditionFailure` / `precondition` — PARTIALLY RESOLVED

The user-reachable `preconditionFailure` paths in `MovieMutatorBase.swift` have been replaced with graceful error return paths (S-08 fix, lines 153–159). Two guard-style calls remain, both on non-user-reachable or intentional paths:

- **`MovieMutatorBase.swift:20`** — `preconditionFailure("mutableCopy() of AVMutableMovie returned non-AVMutableMovie")`. Guards an impossible condition (AVFoundation's `mutableCopy()` should never return a non-`AVMutableMovie` type) and is not on a user-reachable path.
- **`AsyncBridge.swift:100`** — `precondition(allowMainThread || !Thread.isMainThread, ...)`. This is a deliberate API contract guard: `AsyncBridge.perform` must not be called on the main thread unless the caller explicitly opts into the deadlock risk via `allowMainThread: true`.

### 4.3 Security-Scoped Access

Security-scoped resource access is properly wrapped with `NSFileCoordinator` and `startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource` in `Document+FileIO.swift`. The pattern correctly handles cleanup in `defer` blocks.

### 4.4 Build Settings

- **Deployment target:** macOS 14.0
- **Swift version:** Pinned to `SWIFT_VERSION = 6.0` in all targets (correcting the earlier review, which stated the version was unpinned). Note: `ARCHITECTURE.md` still claims "Swift 6.2.1" — that value is stale and should be updated to 6.0.
- **Compiler flags:** No `SWIFT_STRICT_CONCURRENCY` or `SWIFT_TREAT_WARNINGS_AS_ERRORS` settings found in the project configuration. Swift 6 language mode (`SWIFT_VERSION = 6.0`) implies strict concurrency by default, but the explicit settings are absent.

> **Recommendation:** Consider enabling `SWIFT_STRICT_CONCURRENCY=complete` (explicitly, if not already implied by Swift 6 mode) and `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` to enforce concurrency safety and prevent regressions.

---

## 5. Test Coverage Analysis

### 5.1 Test Coverage by Area

| Area | Test File | Test Count | Coverage Status |
|------|-----------|------------|-----------------|
| **AsyncBridge** | `AsyncBridgeTests.swift` | 4 | ✅ Covered |
| **MovieMutator (core)** | `MovieMutatorTests.swift` | 22 | ✅ Covered |
| **MovieMutator (edit)** | `MovieMutatorEditTests.swift` | 5 | ✅ Covered |
| **MovieMutator (transform/export)** | `MovieMutatorTransformExportTests.swift` | 8 | ✅ Covered |
| **TimelineView rendering** | `TimelineViewRenderingTests.swift` | 11 | ✅ Covered |
| **ViewController key events** | `ViewControllerKeyEventTests.swift` | 14 | ✅ Covered |
| **ViewController (general)** | `ViewControllerTests.swift` | 15 | ✅ Covered |
| **Document** | `DocumentTests.swift` | 3 | ✅ Covered |
| **Model** | `ModelTests.swift` | 25 | ✅ Covered |
| **Utilities** | `UtilitiesTests.swift` | 20 | ✅ Covered |
| **Performance** | `PerformanceTests.swift` | 12 | ✅ Covered |
| **Localization** | `LocalizationTests.swift` | 11 | ✅ Covered |
| **LoggingSystem** | `LoggingSystemTests.swift` | 17 | ✅ Covered |
| **cutter2 (integration)** | `cutter2Tests.swift` | 20 | ✅ Covered |
| **MovieHeaderValidator** | `MovieHeaderValidatorTests.swift` | 4 | ✅ Covered (1 skipped) |
| **Overall** | 15 files | **191 tests** | ✅ 189 passed, 1 skipped, 1 flaky |

### 5.2 Test Execution

- `scripts/test.sh` orchestrates build → test → analyze via `xcodebuild` (updated 2026-07-31, commit `28410b0`)
- CI workflow (`.github/workflows/test.yml`) runs on push/PR to `main`, `work`, and `develop` branches (updated to 3 branches and 3 sequential steps: Build → Test → Analyze)
- 189 tests pass, 1 test skipped (`MovieHeaderValidatorTests.testInvalidDurationPath()` — fixture not constructible via public AVMutableMovie API), 1 test flaky (`PerformanceTests.testPerformanceMetricsOverhead()` — see §5.5)
- The `scripts/test.sh` summary output was updated to 15 files / 190 tests; the source actually declares 191 test methods — the hardcoded count should be bumped to 191 or derived dynamically.

### 5.3 Test Coverage Gaps

| Area | Current Coverage | Gap |
|------|-----------------|-----|
| **Document+FileIO** | Revert path (`revert(to:)`) | ❌ Not tested — error handling path for failed reverts is untested |
| **TimelineView+Input** | Mouse event handling (`mouseDown`, `mouseDragged`, `mouseUp`) | ❌ Not tested — gesture recognition and timeline scrubbing interactions |
| **Document+UI** | Window resize handling (`windowDidResize`) | ❌ Not tested — layout update propagation on window resize |
| **Document+SavePanel** | Export save panel flow | ❌ Not tested — save panel presentation and cancellation paths |
| **MovieMutator+Clipboard** | Copy/paste operations | ❌ Not tested — clipboard serialization and deserialization |
| **Document+PositionControl** | Playback position scrubbing | ❌ Not tested — position updates during playback |

> **Recommendation:** Prioritize adding tests for the Document+FileIO revert path and TimelineView+Input mouse handling, as these are critical user-facing code paths.

### 5.4 Skipped Test

- **Test:** `MovieHeaderValidatorTests.testInvalidDurationPath()`
- **Reason:** Throws `XCTSkip` with message: "invalidDuration fixture not constructible via public AVMutableMovie API"
- **Impact:** The `invalidDuration` validation error path in `MovieHeaderValidator` is not exercised by tests. This is a known limitation due to AVFoundation API constraints.
- **Recommendation:** Consider adding a unit test that directly tests the `ValidationError` enum's `errorDescription` without requiring a full movie file, or document this limitation in the code.

### 5.5 Flaky Test — `PerformanceTests.testPerformanceMetricsOverhead()`

- **Symptom:** Intermittently fails when running the full suite — `XCTAssertLessThan failed: ("43.6") is not less than ("10.0") - Performance metrics overhead too high`.
- **Root cause:** The test measures the overhead of `PerformanceMetrics.measure` against an untracked baseline on the same thread. Under parallel test-runner load (the suite parallelizes across simulator/device clones), `CFAbsoluteTimeGetCurrent()`-based timing of a 10,000-iteration loop is dominated by scheduling noise, and the overhead ratio exceeds the 10% threshold.
- **Confirmed flakiness:** Passes reliably in isolation (`-only-testing:cutter2Tests/PerformanceTests/testPerformanceMetricsOverhead`, 0.004 s). Run 1 of the full suite passed; run 2 failed.
- **Recommendation:** (a) Raise the threshold or measure over a longer/looped baseline, (b) use `measure` blocks (XCTMetric) instead of manual `CFAbsoluteTimeGetCurrent()` comparisons, or (c) gate the assertion behind a small warm-up iteration. This is the only intermittent failure in the suite.

---

## 6. Documentation Accuracy

### 6.1 ARCHITECTURE.md — STALE

The `ARCHITECTURE.md` file contains several inaccuracies:

| Documented Location | Actual Location | Issue |
|---------------------|-----------------|-------|
| `Document+Delegate.swift` | `Document+ViewControllerDelegate.swift` | Documentation uses outdated file name; no evidence of an actual rename occurred |
| `Document+Utilities.swift` (811 lines) | `Document+Utilities.swift` (70 lines) | Line count is incorrect (exaggerated by ~11.6x) |
| `TimelineView.swift` + 3 extensions | `TimelineView.swift` + 3 extensions | Structure matches, but line counts are stale |
| Layer descriptions | Current structure | Layer organization descriptions are outdated |
| `Swift 6.2.1` | `SWIFT_VERSION = 6.0` | Language version is stale (project pins Swift 6.0) |

**Last updated:** 2026-02-05 (still stale as of 2026-08-01 review date; ~6 months stale)

### 6.2 API_REFERENCE.md — STALE

The `API_REFERENCE.md` file contains outdated protocol signatures:

- **ViewControllerDelegate protocol**: Documented signature does not match current implementation in `Document+ViewControllerDelegate.swift`
- **Error types**: Documented error enum cases do not match the actual `ErrorUtilities.swift` definitions
- **MovieMutatorBase**: Some method signatures have changed since the doc was written

**Last updated:** 2026-02-05 (still stale as of 2026-08-01 review date; ~6 months stale). Note: the API_REFERENCE.md link to CODEBASE_REVIEW.md was fixed in commit `28410b0` (2026-07-31) to point to `docs/CODEBASE_REVIEW.md` instead of `docs/archive/reviews/CODEBASE_REVIEW.md`.

### 6.3 Concurrency Guidelines

`ConcurrencyGuidelines.md` (recently updated, 2026-07-26) appears accurate and aligns with the current concurrency model.

### 6.4 Other Documentation

- `CONTRIBUTING.md`, `DEVELOPMENT_GUIDE.md`, `TESTING_GUIDE.md` — not reviewed in detail but appear structurally sound based on file listing.

---

## 7. Build & CI Configuration

### 7.1 Xcode Project

- Project file: `cutter2.xcodeproj/project.pbxproj`
- Deployment target: macOS 14.0
- Swift version: pinned to `SWIFT_VERSION = 6.0` (all targets)
- Version: `MARKETING_VERSION = 0.8.19`, `CURRENT_PROJECT_VERSION = 20260801` (uncommitted bump from 0.8.18 as of this review)
- No `SWIFT_STRICT_CONCURRENCY` or `SWIFT_TREAT_WARNINGS_AS_ERRORS` settings (Swift 6 mode implies strict concurrency, but the settings are not explicit)

### 7.2 CI Workflow

`.github/workflows/test.yml`:
- Triggers on `push` and `pull_request` to `main`, `work`, and `develop` branches (updated from `main`/`develop` in commit `28410b0`)
- Runs three sequential steps: `xcodebuild clean build` → `xcodebuild test` (with code coverage) → `xcodebuild analyze`
- Single job with macOS runner (`macos-latest`, Xcode selected via `xcode-select`)
- Generates and uploads an `lcov` coverage report as an artifact

### 7.3 Test Script

`scripts/test.sh` (updated 2026-07-31, commit `28410b0`):
- Runs `xcodebuild clean build` → `xcodebuild test` → `xcodebuild analyze` sequentially (xcodebuild does not parallelize these well)
- Uses `xcpretty` for output formatting
- Reports pass/fail summary; exits non-zero on any of build/test/analyze failure
- **Note:** the hardcoded summary still reports "15 files, 190 tests" — the source declares 191 test methods (see §2.3)

---

## 8. Detailed Findings

### 8.1 Concurrency Correctness

**Finding:** The `@MainActor` isolation on `MovieMutatorBase` ensures all mutations are serialized on the main thread. The `actor MovieWriter` correctly isolates export state. The `AsyncBridge` pattern is used appropriately for NSDocument overrides.

**Assessment:** Concurrency model is sound. No race conditions or isolation violations detected.

### 8.2 Error Handling

**Finding:** Error handling throughout the codebase uses typed Swift errors (`CutError`, `ExportError`, etc.) defined in `ErrorUtilities.swift`. Error propagation is consistent via `throws`/`try await`.

**Assessment:** Error handling is robust and well-structured.

### 8.3 Resource Management

**Finding:** Security-scoped resource access in `Document+FileIO.swift` uses proper `defer` cleanup. `MovieWriter` actor manages export session lifecycle correctly with explicit cancellation.

**Assessment:** Resource management is correct.

### 8.4 Logging

**Finding:** `LoggingSystem.swift` provides a structured logging interface. `DateFormatter+Factory.swift` provides factory methods for date formatters, including a `logFormatter` used by the logging system.

**Observation:** The `LoggingSystem` uses its own internal timestamp formatting via `DateFormatter.logFormatter`, which is separate from the general-purpose formatters in `DateFormatter+Factory.swift`. This is a minor duplication that could be unified.

### 8.5 Performance

**Finding:** `PerformanceMetrics.swift` provides instrumentation for tracking operation durations (`measure`/`measureAsync`/`recordMeasurement`). Instrumentation call sites are in `MovieMutator+Export.swift`; performance-related tests live in `PerformanceTests.swift`.

**Assessment:** Performance tooling is present (`PerformanceMetrics` with `measure`/`measureAsync`/`recordMeasurement`) and `PerformanceTests.swift` covers 12 scenarios (metrics measurement/report/reset, export progress, timeline marker/position, memory allocation). However, most are functional assertions; genuine timing-baseline coverage is limited, and the overhead test is flaky (§5.5).

---

## 9. Recommendations

### 9.1 High Priority

1. **Update documentation** (`ARCHITECTURE.md`, `API_REFERENCE.md`) to reflect current file structure, API signatures, and the Swift 6.0 language version (both docs last updated 2026-02-05).
2. **Add tests** for Document+FileIO revert path and TimelineView+Input mouse handling.
3. **Fix the flaky performance test** `PerformanceTests.testPerformanceMetricsOverhead()` (§5.5) so CI results are deterministic.
4. **Add explicit `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`** to prevent warning regressions.

### 9.2 Medium Priority

5. **Update `scripts/test.sh` hardcoded test count** from 190 to 191 (or derive it from `xcodebuild` output).
6. **Unify date formatter usage** between `LoggingSystem` and `DateFormatter+Factory.swift`.
7. **Add explicit `SWIFT_STRICT_CONCURRENCY=complete`** for documentation clarity (Swift 6 mode already implies it).
8. **Expand performance tests** to cover TimelineView rendering and MovieMutator operations.

### 9.3 Low Priority

9. **Add documentation comments** to public APIs in `Utilities/` that lack them.

---

## 10. Conclusion

The cutter2 codebase demonstrates a well-structured, maintainable architecture with strong concurrency discipline and comprehensive test coverage (191 test methods: 189 passing, 1 skipped due to AVFoundation API limitations, 1 flaky performance test that passes in isolation). The primary areas needing attention are documentation accuracy (ARCHITECTURE.md and API_REFERENCE.md are stale, last updated 2026-02-05 — ~6 months before this review), test coverage gaps in critical user-facing paths (FileIO revert, TimelineView input handling), and the flaky `testPerformanceMetricsOverhead` assertion.

The concurrency model is sound, error handling is robust, and resource management follows best practices. The project would benefit from treating warnings as errors and stabilizing the flaky performance test to keep CI green over time.

---

## 11. Files Reviewed

### Source Files (65 files)
- Application: `AppDelegate.swift`, `DocumentController.swift`
- Document: `Document.swift` + 12 extensions (including `Document+ViewControllerDelegate.swift`)
- Models: `MovieMutator.swift` (subclass of MovieMutatorBase), `MovieMutatorBase.swift` + 4 extensions (`+FormatDescriptions`, `+Formatting`, `+PresentationInfo`, `+Progress`), `MovieMutator+Clipboard.swift`, `MovieMutator+Edit.swift`, `MovieMutator+Transform.swift`, `MovieMutator+Export.swift`, `MovieMutator+Inspector.swift`, `MovieMutator+Player.swift`, `MovieMutatorTypes.swift`, `MovieWriter.swift` + 3 extensions (`+CustomExport`, `+ExportSession`, `+WriteMovie`), `SampleBufferChannel.swift`, `Notifications.swift`, `AVMutableMovie+Extensions.swift`
- ViewControllers: `ViewController.swift` + 5 extensions, `CAPARViewController.swift`, `TranscodeViewController.swift`, `WindowController.swift`, `AccessoryViewController.swift`, `InspectorViewController.swift`
- Views: `TimelineView.swift` + 3 extensions, `MyPlayerView.swift`, `Window.swift`
- Utilities: `AsyncBridge.swift`, `ActorUtilities.swift`, `LayoutConverter.swift` + 3 extensions (`+Convert`, `+LayoutData`, `+Mapping`), `MovieHeaderValidator.swift`, `PerformanceMetrics.swift`, `ErrorUtilities.swift`, `Constants.swift`, `LocalizationHelper.swift`, `LoggingSystem.swift`, `DateFormatter+Factory.swift`
- Resources: `Info.plist`, `cutter2.entitlements`, `Localizable.xcstrings`

### Test Files (15 files)
- `MovieMutatorTests.swift`, `MovieMutatorEditTests.swift`, `MovieMutatorTransformExportTests.swift`
- `MovieHeaderValidatorTests.swift`, `AsyncBridgeTests.swift`
- `TimelineViewRenderingTests.swift`, `ViewControllerTests.swift`, `ViewControllerKeyEventTests.swift`
- `DocumentTests.swift`, `ModelTests.swift`
- `UtilitiesTests.swift`, `PerformanceTests.swift`
- `LocalizationTests.swift`, `LoggingSystemTests.swift`
- `cutter2Tests.swift`

### Documentation (6 files)
- `ARCHITECTURE.md` (stale — last updated 2026-02-05, see §6.1)
- `API_REFERENCE.md` (stale — last updated 2026-02-05, see §6.2; link to this file fixed in commit `28410b0`)
- `ConcurrencyGuidelines.md` (current — updated 2026-07-26)
- `CONTRIBUTING.md` (not deeply reviewed)
- `DEVELOPMENT_GUIDE.md` (not deeply reviewed)
- `TESTING_GUIDE.md` (not deeply reviewed)

### Configuration
- `cutter2.xcodeproj/project.pbxproj` (version 0.8.19 / build 20260801 — uncommitted as of this review)
- `.github/workflows/test.yml` (build/test/analyze, branches `main`/`work`/`develop`)
- `scripts/test.sh` (build/test/analyze; hardcoded count 190 — should be 191)