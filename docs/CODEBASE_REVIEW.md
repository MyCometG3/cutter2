# Codebase Review — cutter2

**Date:** 2026-09-23 (revision 3; original review 2026-08-06)
**Reviewer:** Source-level documentation and code review
**Scope:** Source, tests, Markdown documentation, Xcode project, CI workflow, and test scripts
**Reviewed baseline:** `4d372782d068f5e5358ba6229f0696f11567c8e1` (`work`)
**Verification environment:** macOS 27.0 (build 26A428), Xcode 27.0 (build 27A266a), Swift compiler 6.4
**Status:** Updated for the 2026-09-21 baseline; clean build / clean analyze / full test passed; one remaining P2 finding documented in §8.6

---

## 1. Summary

This document records a source-level review of the **cutter2** project — a macOS video editor application built with Swift and AVFoundation. The review covers project structure, architecture, concurrency model, code quality, test coverage, documentation accuracy, and build/CI configuration.

Revision 2 (2026-09-21) re-reviewed the tree at commit `4d372782d068f5e5358ba6229f0696f11567c8e1`, covering the 7 commits landed since the originally reviewed baseline `78f1d00e140afb2e2ce7ce030781895e0d981e5c`:

- `ad0ecd0` docs: refresh cutter2 documentation
- `b96bc98` fix: consolidate shared test fixture helper
- `5799f8e` docs: complete Swift docComment audit
- `884d8e2` refactor: remove redundant Swift expressions
- `e7e05e8` docs: correct codebase review conclusion
- `55a9a6d` Fix Swift 6 Sendable conformance placement
- `4d37278` fix: prevent stale position after movie deletion

Verification for the new baseline was run with DerivedData outside the worktree:

```bash
xcodebuild clean build   -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO
xcodebuild clean analyze -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO
xcodebuild test          -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS' -enableCodeCoverage YES CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO
```

All three steps succeeded; the full test run passed 200 test cases with 0 failures. The build and test results were re-confirmed after the fix was fast-forward merged into `work`. One new P2 finding (a residual race window in the reload/seek suppression, §8.6) is documented and must be read together with the otherwise sound baseline.

**Current verification facts:**

- **Current static test suite size:** 19 files total (18 test source files + 1 helper), with 222 statically declared `func test...` methods (after T-16/S-17).
- **Runtime test result:** The September 21, 2026 run passed 200 test cases with 0 failures on `4d37278`.
- **CI workflow:** Configured for `main`, `work`, and `develop`, with Build → Test → Analyze steps plus coverage report generation/upload. The workflow uses `macos-latest` and does not pin a specific Xcode image.
- **Strict concurrency:** `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` are enabled across all four app/test configurations.
- **Swift language mode:** `SWIFT_VERSION = 6.0` is pinned in the app and test targets.
- **Version:** `MARKETING_VERSION = 0.8.19`, `CURRENT_PROJECT_VERSION = 20260802` (app target); these values are committed in the reviewed project state.
- **Force casts:** Rechecked at this baseline — 14 `as!` lines (10 code lines: 8 CF typealias casts + 2 NSDictionary casts, plus 4 whole-line comment lines), unchanged from the earlier review.
- **Intentional crash/assertion sites:** Three executable sites remain: `MovieMutatorBase.swift:23` (impossible `mutableCopy()` result), `AsyncBridge.swift:103` (deliberate main-thread API-contract guard), and `Document+ActorIsolation.swift:53` (fatalError in the non-throwing `performAsync` overload, indicating an internal bridge bug).

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
│   ├── Document+ViewControllerDelegate.swift
│   └── PlayerSeekSequencer.swift
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

**Total source files:** 66 Swift files across 6 source directories (plus Resources), including the S-17 `PlayerSeekSequencer` extraction.

**Note:** `MovieMutator` (in `MovieMutator.swift`) is a subclass of `MovieMutatorBase` (in `MovieMutatorBase.swift`). All functional extensions (`+Edit`, `+Transform`, `+Export`, etc.) are on the `MovieMutator` subclass, not on `MovieMutatorBase` directly.

### 2.2 Test Organization

```
cutter2Tests/
├── AsyncBridgeTests.swift                # AsyncBridge tests (4 tests)
├── cutter2Tests.swift                    # Integration tests (20 tests)
├── DocumentKVOContextTests.swift         # KVO context tests (3 tests)
├── DocumentTests.swift                   # Document tests (6 tests)
├── LayoutConverterMappingTests.swift     # Layout mapping tests (5 tests)
├── LocalizationTests.swift               # Localization tests (11 tests)
├── LoggingSystemTests.swift              # Logging tests (17 tests)
├── ModelTests.swift                      # Model layer tests (26 tests)
├── MovieHeaderValidatorTests.swift       # Header validation tests (3 tests)
├── MovieMutatorEditTests.swift           # Edit operation tests (8 tests)
├── MovieMutatorTests.swift               # Model layer tests (22 tests)
├── MovieMutatorTransformExportTests.swift # Transform/export tests (8 tests)
├── PerformanceTests.swift                # Performance tests (12 tests)
├── PlayerSeekSequencerTests.swift        # Reload/seek sequencer tests (11 tests)
├── TestMovieFixtureWriter.swift          # Test helper (0 tests, fixture writer)
├── TimelineViewRenderingTests.swift      # Timeline rendering tests (15 tests)
├── UtilitiesTests.swift                  # Utility tests (22 tests)
├── ViewControllerKeyEventTests.swift     # Key event tests (14 tests)
└── ViewControllerTests.swift             # ViewController tests (15 tests)
```

**Current total:** 19 files (18 test source files + 1 helper), **222 statically declared test methods**. Runtime results are recorded separately in §2.3. Note: 2 method names are duplicated across different test classes (`testMovieHeaderGeneration` in `cutter2Tests.swift` and `MovieMutatorTests.swift`; `testTimeCalculationPerformance` in `MovieMutatorTests.swift` and `ViewControllerTests.swift`). The three tests added to `MovieMutatorEditTests.swift` by `4d37278` lock in the delete marker position-correction behavior (marker at range end snaps to range start; marker before range stays; marker after range shifts backward by the selection duration). T-16 adds mapping coverage and S-17 adds direct tests for the extracted reload/seek state transitions.

### 2.3 Test Execution Results

The current source contains 222 statically declared `func test...` methods and no `XCTSkip` usage was found. The September 21, 2026 full-suite run on the earlier commit `4d37278` (macOS 27.0, Xcode 27.0) executed all 200 then-existing test cases successfully with 0 failures; the previous August 6, 2026 rerun passed the then-197 cases after the duplicate local `writeSampleMovie` helper was consolidated into the shared fixture (`b96bc98`).

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

- **Reload/seek generation gating (extracted by S-17)**: `PlayerSeekSequencer` owns the reload and seek generations, the reload task handle, suppression state, token snapshots, and stale-completion gates. `Document+UI.swift` retains AVPlayer and UI side effects and obtains a seek token before each seek or item replacement. The `readyToPlay` KVO handler reads suppression through the sequencer inside `performSyncOnMainActor` because `observeValue` is `nonisolated`. The state transitions are covered by `PlayerSeekSequencerTests`; integration ordering against a live AVPlayer, KVO delivery, and polling timer remains untested.

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

All 54 force-unwraps (`as!`) identified in the initial review have been replaced with `guard-let` statements. The 14 remaining `as!` lines consist of 10 code lines (8 CF typealias casts + 2 NSDictionary casts) plus 4 whole-line comment lines explaining safety. Rechecked at the 2026-09-21 baseline: unchanged (the `884d8e2` refactor touched nearby expressions but removed no `as!` casts). CF typealias casts (e.g., `track.formatDescriptions as! [CMFormatDescription]` in `MovieMutator+Inspector.swift`, `MovieMutator+Transform.swift`, `MovieWriter+CustomExport.swift`, `MovieMutatorBase+FormatDescriptions.swift`) are guaranteed to succeed by Swift. NSDictionary casts (`dict.copy() as! NSDictionary` in `MovieWriter+CustomExport.swift:262,268`) copy an `NSMutableDictionary` to its immutable counterpart.

### 4.2 `preconditionFailure` / `precondition` / `fatalError` — PARTIALLY RESOLVED

The user-reachable `preconditionFailure` paths in `MovieMutatorBase.swift` have been replaced with graceful error return paths (S-08 fix). Three intentional executable sites remain, all on non-user-reachable or deliberate paths:

- **`MovieMutatorBase.swift:23`** — `preconditionFailure("mutableCopy() of AVMutableMovie returned non-AVMutableMovie")`. Guards an impossible condition (AVFoundation's `mutableCopy()` should never return a non-`AVMutableMovie` type) and is not on a user-reachable path.
- **`AsyncBridge.swift:103-105`** — `precondition(allowMainThread || !Thread.isMainThread, ...)`. This is a deliberate API contract guard: `AsyncBridge.perform` must not be called on the main thread unless the caller explicitly opts into the deadlock risk via `allowMainThread: true`.
- **`Document+ActorIsolation.swift:53`** — `fatalError("Non-throwing performAsync unexpectedly threw: ...")` in the non-throwing `performAsync` overload. The catch is intentionally fatal: a non-throwing block cannot produce a `PerformAsyncError` under normal operation, so reaching it indicates an internal bridge bug rather than a recoverable caller error. Pre-existing since `871bcd9`; documented here for completeness.

### 4.3 Security-Scoped Access

Security-scoped resource access is properly wrapped with `NSFileCoordinator` and `startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource` in `Document+FileIO.swift`. The pattern correctly handles cleanup in `defer` blocks.

### 4.4 Build Settings

- **Deployment target:** macOS 14.0
- **Swift version:** Pinned to `SWIFT_VERSION = 6.0` in all targets (correcting the earlier review, which stated the version was unpinned).
- **Compiler flags:** `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` enabled in all 4 build configurations (synced from master PR #53).

---

## 5. Test Coverage Analysis

### 5.1 Test Coverage by Area

| Area | Test File | Test Count | Coverage Status |
|------|-----------|------------|-----------------|
| **AsyncBridge** | `AsyncBridgeTests.swift` | 4 | ✅ Covered |
| **MovieMutator (core)** | `MovieMutatorTests.swift` | 22 | ✅ Covered |
| **MovieMutator (edit)** | `MovieMutatorEditTests.swift` | 8 | ✅ Covered |
| **MovieMutator (transform/export)** | `MovieMutatorTransformExportTests.swift` | 8 | ✅ Covered |
| **TimelineView rendering/mouse input** | `TimelineViewRenderingTests.swift` | 15 | ✅ Covered |
| **ViewController key events** | `ViewControllerKeyEventTests.swift` | 14 | ✅ Covered |
| **ViewController (general)** | `ViewControllerTests.swift` | 15 | ✅ Covered |
| **Document** | `DocumentTests.swift` | 6 | ✅ Covered |
| **Document KVO context** | `DocumentKVOContextTests.swift` | 3 | ✅ Covered |
| **LayoutConverter mappings** | `LayoutConverterMappingTests.swift` | 5 | ✅ Covered (T-16) |
| **Player seek sequencing** | `PlayerSeekSequencerTests.swift` | 11 | ✅ State transitions covered (S-17); live player integration remains untested |
| **Model** | `ModelTests.swift` | 26 | ✅ Covered |
| **Utilities** | `UtilitiesTests.swift` | 22 | ✅ Covered |
| **Performance** | `PerformanceTests.swift` | 12 | ✅ Covered |
| **Localization** | `LocalizationTests.swift` | 11 | ✅ Covered |
| **LoggingSystem** | `LoggingSystemTests.swift` | 17 | ✅ Covered |
| **cutter2 (integration)** | `cutter2Tests.swift` | 20 | ✅ Covered |
| **MovieHeaderValidator** | `MovieHeaderValidatorTests.swift` | 3 | ✅ Covered |
| **Overall** | 19 files (18 test source + 1 helper) | **222 statically declared methods** | ✅ 200 passed, 0 failed on 2026-09-21 baseline; T-16/S-17 targeted tests pass |

### 5.2 Test Execution

- `scripts/test.sh` orchestrates build → test → analyze via `xcodebuild`
- CI workflow (`.github/workflows/test.yml`) runs on push/PR to `main`, `work`, and `develop` branches (Build → Test → Analyze, using `build-for-testing` + `test-without-building` to avoid double compilation)
- The current source contains 222 statically declared test methods and no `XCTSkip` usage; the September 21, 2026 full-suite run on `4d37278` passed all 200 test cases present at that earlier baseline (the August 6, 2026 rerun passed the then-197 cases)
- `scripts/test.sh` reports the current static inventory of 18 test source files + 1 helper and 222 methods; the verified 211-test run after T-16 preceded the 11 S-17 tests

### 5.3 Test Coverage Gaps

| Area | Current Coverage | Gap |
|------|-----------------|-----|
| **Document+FileIO** | Revert/read error paths (`readAsync` UTI + header validation) | ✅ Covered by T-14 (`validateMovieType` / `MovieHeaderValidator` tests). Full revert sheet-display flow still untested (requires Document instance, which crashes in test env — see §5.4 note) |
| **TimelineView+Input** | Mouse event handling (`mouseDown`, `mouseDragged`) | ✅ Covered by T-14 (marker selection → `doSetCurrent`, drag updates `startPosition`/`currentPosition`, no-op when unselected) |
| **MovieMutator edit marker correction** | `doRemove` position-correction branches | ✅ Covered by `4d37278` (3 regression tests in `MovieMutatorEditTests.swift`) |
| **PlayerSeekSequencer state transitions** | Reload/seek generations, task cancellation gates, suppression transitions, stale tokens, cleanup preservation | ✅ Unit-tested by 11 cases in `PlayerSeekSequencerTests.swift`; CODEBASE_REVIEW §8.6 residual race is pinned as current behavior, not fixed |
| **Document × live AVPlayer integration** | Async ordering of `updatePlayer`, KVO delivery, and polling timer | ❌ Not tested — requires a live `Document`/AVPlayer integration seam, which the unit-test environment does not provide (§5.4). The residual P2 window in §8.6 remains unprotected by an integration test |
| **Document+UI** | Window resize handling (`windowDidResize`) | ❌ Not tested — layout update propagation on window resize |
| **Document+SavePanel** | Export save panel flow | ❌ Not tested — save panel presentation and cancellation paths |
| **MovieMutator+Clipboard** | Copy/paste operations | ❌ Not tested — clipboard serialization and deserialization |
| **Document+PositionControl** | Playback position scrubbing | ❌ Not tested — position updates during playback |

> **Recommendation:** Document+FileIO revert, TimelineView+Input mouse handling, delete marker correction, and the extracted PlayerSeekSequencer state transitions are covered. Highest-value remaining gap is integration ordering between `Document`, a live AVPlayer, KVO, and the polling timer; it needs a player/reload seam or UI/integration test. The §8.6 residual race remains intentionally unfixed by S-17 and needs a separate behavior-change decision. Window resize, save panel, clipboard, and scrubbing coverage remain open as before.

### 5.4 Skipped Test — RESOLVED

The always-skipped `MovieHeaderValidatorTests.testInvalidDurationPath()` was removed by S-12 (consistent with master PR #53). The test threw `XCTSkip` because the `invalidDuration` fixture is not constructible via the public `AVMutableMovie` API. After removal, the suite contains no `XCTSkip` usage; the `invalidDuration` validation error path in `MovieHeaderValidator` remains uncovered, but the `errorDescription` behavior is exercised by the remaining `MovieHeaderValidatorTests` cases.

**Testing note (T-14):** `Document` instances cannot be constructed in the unit-test environment — the `window` computed property force-indexes `windowControllers[0]`, raising `NSRangeException` on the empty array during `NSDocument.init()`. This applies to full-suite runs as well and is not bypassed by bootstrapping `NSApplication`/`NSDocumentController`. Consequently, tests that exercise `Document` behavior use extracted/isolated logic instead: `Document.validateMovieType(_:)` (UTI check shared by `readAsync` and `read(from:ofType:)`) and `MovieHeaderValidator` (header validation). The full revert sheet-display flow remains untestable without refactoring `Document`.

### 5.5 Flaky Test — RESOLVED

`PerformanceTests.testPerformanceMetricsOverhead()` previously failed intermittently under parallel test-runner load — measured overhead of `PerformanceMetrics.measure` exceeded the 10% threshold (observed 43.6%) because `CFAbsoluteTimeGetCurrent()`-based timing of a 10,000-iteration loop was dominated by scheduling noise. Fixed by M-22: workload increased to 100,000 iterations, best-of-5 measurement (lowest overhead selected), and threshold relaxed to 30%. Verified passing in isolation (5 runs) and in the full suite (2 runs).

---

## 6. Documentation Accuracy

### 6.1 Removed Documents

The following documents were removed on 2026-08-05 because they were outdated and unmaintained:

- **`ARCHITECTURE.md`** — Last updated 2026-02-05, contained stale file names, line counts, and layer descriptions. Information is now maintained in this document (§3 Architecture Overview).
- **`API_REFERENCE.md`** — Last updated 2026-02-05, contained outdated protocol signatures and error types. API details should be sourced from inline documentation and this review.

### 6.2 Documentation Review

`ConcurrencyGuidelines.md`, `CONTRIBUTING.md`, `DEVELOPMENT_GUIDE.md`, and `TESTING_GUIDE.md` were checked for internal links, code fences, test-count consistency, command reproducibility, and alignment with the current implementation. The review found and corrected stale environment labels, placeholder clone commands, incomplete `test-without-building` instructions, an omitted test helper, and an unsafe `AVMutableMovie` concurrency example.

The Markdown set contains 7 files when `README.md` and `.github/copilot-instructions.md` are included; the 5 files under `docs/` are listed separately in §11.

---

## 7. Build & CI Configuration

### 7.1 Xcode Project

- Project file: `cutter2.xcodeproj/project.pbxproj`
- Deployment target: app and test targets explicitly set `MACOSX_DEPLOYMENT_TARGET = 14.0` in both Debug and Release configurations. The project-level Debug/Release settings retain `$(RECOMMENDED_MACOSX_DEPLOYMENT_TARGET)` as a fallback.
- Swift version: pinned to `SWIFT_VERSION = 6.0` (all app/test target configurations)
- Version: `MARKETING_VERSION = 0.8.19`, `CURRENT_PROJECT_VERSION = 20260802` (committed in the reviewed project state)
- `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` enabled in all 4 build configurations (synced from master PR #53)

### 7.2 CI Workflow

`.github/workflows/test.yml`:
- Triggers on `push` and `pull_request` to `main`, `work`, and `develop` branches (updated from `main`/`develop` in commit `28410b0`)
- Runs three sequential steps: `xcodebuild clean build-for-testing` → `xcodebuild test-without-building` (with code coverage) → `xcodebuild analyze`
- Single job with macOS runner (`macos-latest`, Xcode selected via `xcode-select`)
- Generates and uploads an `lcov` coverage report as an artifact

### 7.3 Test Script

`scripts/test.sh`:
- Runs `xcodebuild clean build` → `xcodebuild test` → `xcodebuild analyze` sequentially (xcodebuild does not parallelize these well)
- Each step is guarded with `if ! ...; then exit 1; fi` so failures are reported with a custom message (works with `set -e`)
- Uses color-coded echo statements for output formatting
- Generates coverage reports via `xcrun llvm-cov`
- Reports a summary; its static counts distinguish 18 test source files from 1 helper and report 222 methods

---

## 8. Detailed Findings

### 8.1 Concurrency Correctness

**Finding:** The `@MainActor` isolation on `MovieMutatorBase` ensures all mutations are serialized on the main thread. The `actor MovieWriter` correctly isolates export state. The `AsyncBridge` pattern is used appropriately for NSDocument overrides. The reload/seek generation gating added by `4d37278` (§3.2) was reviewed scenario-by-scenario: interrupted seeks (`finished == false`), delayed stale completions (`finished == true` arriving after a newer seek or item replacement), consecutive user seeks within one reload generation, and the suppressed `readyToPlay` re-seek — each closes its prior window, and every escaping completion captures `self`/player/mutator weakly, so no retain cycles were found.

**Placement of `Document` protocol conformances (verified after `55a9a6d`):** `Document` now declares `ViewControllerDelegate` in its class declaration (`Document.swift:96-97`) and keeps only plain extensions for the delegate method bodies. Because `ViewControllerDelegate` refines `TimelineUpdateDelegate, Sendable` (`ViewController.swift:19-20`), the single conformance site satisfies both protocols, eliminating the Swift 6 "conformance must be declared in the same file" split.

**Assessment:** Concurrency model is sound except for one residual window documented in §8.6 (P2). No isolation violations detected.

### 8.2 Error Handling

**Finding:** Error handling throughout the codebase uses typed Swift errors (`DocumentError`, `MovieWriterError`) defined in `Document.swift` and `MovieWriter.swift` respectively. Error propagation is consistent via `throws`/`try await`.

**Assessment:** Error handling is robust and well-structured.

### 8.3 Resource Management

**Finding:** Security-scoped resource access in `Document+FileIO.swift` uses proper `defer` cleanup. `MovieWriter` actor manages export session lifecycle correctly with explicit cancellation.

**Assessment:** Resource management is correct.

### 8.4 Logging

**Finding:** `LoggingSystem.swift` provides a structured logging interface. `DateFormatter+Factory.swift` provides factory methods for date formatters, including a `logFormatter` used by the logging system.

**Observation:** The `LoggingSystem` uses its own internal timestamp formatting via `DateFormatter.logFormatter`, which is separate from the general-purpose formatters in `DateFormatter+Factory.swift`. This is a minor duplication that could be unified.

### 8.5 Performance

**Finding:** `PerformanceMetrics.swift` provides instrumentation for tracking operation durations (`measure`/`measureAsync`/`recordMeasurement`). Instrumentation call sites are in `MovieMutator+Export.swift`; performance-related tests live in `PerformanceTests.swift`.

**Assessment:** Performance tooling is present (`PerformanceMetrics` with `measure`/`measureAsync`/`recordMeasurement`) and `PerformanceTests.swift` covers 12 scenarios (metrics measurement/report/reset, export progress, timeline marker/position, memory allocation). However, most are functional assertions; genuine timing-baseline coverage is limited. The overhead test, previously flaky, was stabilized by M-22 (§5.5).

### 8.6 Residual Race Window in Reload Suppression — P2 (open; not changed by S-17)

**Finding:** A user-initiated seek that *completes* while a reload task is still awaiting `makePlayerItem()` releases `suppressQueryPosition`, and the reload does not re-assert it before applying the new player item.

**Sequence (`Document+UI.swift` + `PlayerSeekSequencer.swift`):**

1. `updateGUI(reload: true)` asserts suppression, calls `beginReload()` to advance the reload generation and cancel the previous task, then spawns and registers the reload task. That task awaits `mutator.makePlayerItem()`.
2. While that await is in flight, the user seeks (`resumeAfterSeek`). The seek snapshots the current reload generation, and its `finished == true` completion passes both generation gates and calls `releaseSuppression()`.
3. The reload task resumes, replaces the player item, and starts the post-reload seek. The current implementation does not re-assert suppression between the user seek completion and the post-reload seek completion.
4. In that interval, `queryPosition()` can poll the new item and adopt a pre-seek `currentTime()`, reintroducing the stale-marker class of bug this mechanism exists to prevent. The post-reload seek completion only lifts suppression and marks the view dirty, so it cannot repair the model.

The window is narrow (it requires a completed user seek overlapping the `makePlayerItem()` await, then a poll landing between item readiness and seek completion), and pre-replacement polls on the *old* item are benign (their `currentTime()` equals the user's intended seek target). It is nonetheless the same failure class as the delete-key regression fixed in `4d37278`.

**Suggested fix (either suffices; do not apply both blindly):**

- Re-assert suppression through `PlayerSeekSequencer.suppressForReload()` in `updatePlayer(generation:)` in the same main-actor turn as `replaceCurrentItem` (before the swap, after the `Task.isCancelled` guard). The existing cancellation/`catch` paths already call `liftSuppression(for:)`, so re-assertion cannot strand the timer. Keep the seek-generation bump before the swap to preserve stale-callback no-op behavior.
- Or change suppression-release ownership so a user-seek completion cannot release suppression while a reload is pending; this requires exposing or modeling the pending-reload state in the sequencer.

**Tracking:** Not covered by automated tests (§5.3); field reproduction (delete → immediate marker drag/JKL during reload) is the current check.

---

## 9. Recommendations

### 9.1 High Priority

1. ~~**Update documentation** (`ARCHITECTURE.md`, `API_REFERENCE.md`)~~ — Resolved (2026-08-05): Both documents removed. Information is now maintained in this review document.
2. **Close the residual race window (§8.6)** — Re-assert query-position suppression in `updatePlayer(generation:)` before applying the replaced player item, or change suppression-release ownership. S-17 intentionally preserves current behavior; this requires a separate behavior-change decision and a field-reproduction pass of delete → drag/JKL during reload.
3. **Add integration tests** for ordering between `Document`, a live AVPlayer, KVO, and the polling timer. `PlayerSeekSequencer` state transitions are now unit-tested; exercising the integration requires a player/reload seam or UI/integration harness. Window resize, save panel, clipboard, and scrubbing tests also remain open.

### 9.2 Medium Priority

4. ~~**Synchronize test counts in `scripts/test.sh`**~~ — Resolved by T-16/S-17: the script reports 18 test source files + 1 helper and 222 statically declared methods.
5. **Unify date formatter usage** between `LoggingSystem` and `DateFormatter+Factory.swift`.
6. **Expand performance tests** to cover TimelineView rendering and MovieMutator operations.

### 9.3 Low Priority

7. **Add documentation comments** to public APIs in `Utilities/` that lack them.

---

## 10. Conclusion

The cutter2 codebase demonstrates a layered architecture with explicit concurrency settings and 222 statically declared test methods across 18 test source files plus one helper. Strict concurrency (`complete`) and warnings-as-errors are enabled across all build configurations. The 2026-09-21 revision verified baseline `4d37278` with a clean build, clean analyze, and a full test run passing 200 test cases with 0 failures (DerivedData outside the worktree), and re-confirmed the results after the fix was fast-forward merged into `work`.

The 7 commits since the previous baseline remain documented above. T-16 adds full tag/label mapping tests, and S-17 extracts the reload/seek state transitions into `PlayerSeekSequencer` with 11 unit tests. These tests do not exercise integration ordering against a live AVPlayer, KVO, or polling timer. The §8.6 residual race remains open and intentionally unchanged by S-17; window resize, save panel, clipboard, and scrubbing coverage also remain open. Test counts in `scripts/test.sh` and the test guides now match the current static inventory.

---

## 11. Files Reviewed

### Source Files (65 files)
- Application: `AppDelegate.swift`, `DocumentController.swift`
- Document: `Document.swift` + 12 extensions (conformance to `ViewControllerDelegate` declared in the class body since `55a9a6d`; `Document+ViewControllerDelegate.swift` and `Document+TimelineUpdateDelegate.swift` hold the delegate method implementations)
- Models: `MovieMutator.swift` (subclass of MovieMutatorBase), `MovieMutatorBase.swift` + 4 extensions (`+FormatDescriptions`, `+Formatting`, `+PresentationInfo`, `+Progress`), `MovieMutator+Clipboard.swift`, `MovieMutator+Edit.swift`, `MovieMutator+Transform.swift`, `MovieMutator+Export.swift`, `MovieMutator+Inspector.swift`, `MovieMutator+Player.swift`, `MovieMutatorTypes.swift`, `MovieWriter.swift` + 3 extensions (`+CustomExport`, `+ExportSession`, `+WriteMovie`), `SampleBufferChannel.swift`, `Notifications.swift`, `AVMutableMovie+Extensions.swift`
- ViewControllers: `ViewController.swift` + 5 extensions, `CAPARViewController.swift`, `TranscodeViewController.swift`, `WindowController.swift`, `AccessoryViewController.swift`, `InspectorViewController.swift`
- Views: `TimelineView.swift` + 3 extensions, `MyPlayerView.swift`, `Window.swift`
- Utilities: `AsyncBridge.swift`, `ActorUtilities.swift`, `LayoutConverter.swift` + 3 extensions (`+Convert`, `+LayoutData`, `+Mapping`), `MovieHeaderValidator.swift`, `PerformanceMetrics.swift`, `ErrorUtilities.swift`, `Constants.swift`, `LocalizationHelper.swift`, `LoggingSystem.swift`, `DateFormatter+Factory.swift`
- Resources: `Info.plist`, `cutter2.entitlements`, `Localizable.xcstrings`

### Test Files (19 files: 18 test source files + 1 helper; 222 statically declared methods)
- `AsyncBridgeTests.swift` (4 tests), `cutter2Tests.swift` (20 tests), `DocumentKVOContextTests.swift` (3 tests), `DocumentTests.swift` (6 tests)
- `LayoutConverterMappingTests.swift` (5 tests), `LocalizationTests.swift` (11 tests), `LoggingSystemTests.swift` (17 tests), `ModelTests.swift` (26 tests)
- `MovieHeaderValidatorTests.swift` (3 tests), `MovieMutatorEditTests.swift` (8 tests), `MovieMutatorTests.swift` (22 tests), `MovieMutatorTransformExportTests.swift` (8 tests)
- `PerformanceTests.swift` (12 tests), `PlayerSeekSequencerTests.swift` (11 tests), `TimelineViewRenderingTests.swift` (15 tests)
- `UtilitiesTests.swift` (22 tests), `ViewControllerKeyEventTests.swift` (14 tests), `ViewControllerTests.swift` (15 tests)
- `TestMovieFixtureWriter.swift` (0 tests, fixture writer helper)

### Markdown Documentation (7 files)
- `README.md` (project overview, Quick Start, features, and environment)
- `.github/copilot-instructions.md` (Copilot-specific project guidance)
- `docs/CODEBASE_REVIEW.md` (this document — architecture and verification record)
- `docs/ConcurrencyGuidelines.md` (concurrency rules)
- `docs/CONTRIBUTING.md` (contribution workflow)
- `docs/DEVELOPMENT_GUIDE.md` (development workflow)
- `docs/TESTING_GUIDE.md` (test structure and commands)

### Configuration
- `cutter2.xcodeproj/project.pbxproj` (version 0.8.19 / build 20260802 — app target, committed in the reviewed state; the test target carries placeholder `1.0` / `1`)
- `.github/workflows/test.yml` (build/test/analyze, branches `main`/`work`/`develop`; coverage artifact generation is optional)
- `scripts/test.sh` (build/test/analyze; summary reports 18 test source files + 1 helper and 222 statically declared methods)
