# Codebase Review — cutter2

**Date:** 2026-08-06
**Reviewer:** Source-level documentation and code review
**Scope:** Source, tests, Markdown documentation, Xcode project, CI workflow, and test scripts
**Reviewed baseline:** `78f1d00e140afb2e2ce7ce030781895e0d981e5c` (`work`)
**Verification environment:** macOS 26.6 (build 25G72), Xcode 26.6 (build 17F113), Swift compiler 6.3.3
**Status:** Updated; follow-up verification passed after consolidating the shared test helper

---

## 1. Summary

This document records a source-level review of the **cutter2** project — a macOS video editor application built with Swift and AVFoundation. The review covers project structure, architecture, concurrency model, code quality, test coverage, documentation accuracy, and build/CI configuration.

This revision was checked against the current `work` branch at commit `78f1d00e140afb2e2ce7ce030781895e0d981e5c`. Source files, test files, Markdown documentation, build configuration, CI workflow, and test scripts were inspected. The initial test attempt failed before execution because `MovieMutatorTransformExportTests.swift` duplicated the shared `writeSampleMovie(to:duration:timescale:frameRate:)` helper from `TestMovieFixtureWriter.swift`. The local helper was removed so the test class uses the shared implementation.

The verification command was rerun after that fix:

```bash
xcodebuild test -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS' -derivedDataPath .build-full-fix -enableCodeCoverage YES CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO
```

The rerun completed successfully with 197 passed test cases and 0 failed test cases. The subsequent `xcodebuild analyze` also completed successfully. The helper consolidation and this verification record are included in the same follow-up commit.

**Current verification facts:**

- **Static test suite size:** 16 files total (15 test source files + 1 helper), with 197 statically declared `func test...` methods.
- **Runtime test result:** After removing the duplicate local helper, the August 6, 2026 rerun reported 197 passed test cases and 0 failed test cases.
- **CI workflow:** Configured for `main`, `work`, and `develop`, with Build → Test → Analyze steps. The workflow uses `macos-latest` and does not pin a specific Xcode image.
- **Strict concurrency:** `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` are enabled across all four app/test configurations.
- **Swift language mode:** `SWIFT_VERSION = 6.0` is pinned in the app and test targets.
- **Version:** `MARKETING_VERSION = 0.8.19`, `CURRENT_PROJECT_VERSION = 20260802`; these values are committed in the reviewed project state.
- **Force casts:** The earlier review recorded 14 `as!` lines (10 code lines and 4 comment lines); this count is a historical review metric and should be rechecked when the code is changed.
- **Main-thread guards:** `AsyncBridge.perform` contains an intentional main-thread precondition, while `MovieMutatorBase.swift:20` guards an impossible `mutableCopy()` type result.

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

**Total source files:** 65 Swift files across 6 source directories (plus Resources).

**Note:** `MovieMutator` (in `MovieMutator.swift`) is a subclass of `MovieMutatorBase` (in `MovieMutatorBase.swift`). All functional extensions (`+Edit`, `+Transform`, `+Export`, etc.) are on the `MovieMutator` subclass, not on `MovieMutatorBase` directly.

### 2.2 Test Organization

```
cutter2Tests/
├── cutter2Tests.swift                    # Integration tests (20 tests)
├── MovieMutatorTests.swift               # Model layer tests (22 tests)
├── MovieMutatorEditTests.swift           # Edit operation tests (5 tests)
├── MovieMutatorTransformExportTests.swift # Transform/export tests (8 tests)
├── MovieHeaderValidatorTests.swift       # Header validation tests (3 tests)
├── AsyncBridgeTests.swift                # AsyncBridge tests (4 tests)
├── TimelineViewRenderingTests.swift      # Timeline rendering tests (15 tests)
├── ViewControllerTests.swift             # ViewController tests (15 tests)
├── ViewControllerKeyEventTests.swift     # Key event tests (14 tests)
├── DocumentTests.swift                   # Document tests (6 tests)
├── ModelTests.swift                      # Model layer tests (25 tests)
├── UtilitiesTests.swift                  # Utility class tests (20 tests)
├── PerformanceTests.swift                # Performance tests (12 tests)
├── LocalizationTests.swift               # Localization tests (11 tests)
├── LoggingSystemTests.swift              # Logging tests (17 tests)
└── TestMovieFixtureWriter.swift          # Test helper (0 tests, fixture writer)
```

**Total:** 16 files (15 test source files + 1 helper), **197 statically declared test methods**. Runtime results are recorded separately in §2.3. Note: 2 method names are duplicated across different test classes (`testMovieHeaderGeneration` in `cutter2Tests.swift` and `MovieMutatorTests.swift`; `testTimeCalculationPerformance` in `MovieMutatorTests.swift` and `ViewControllerTests.swift`).

### 2.3 Test Execution Results

The static suite contains 197 `func test...` methods and no `XCTSkip` usage was found in the current source. After the duplicate local `writeSampleMovie` helper was removed, the August 6, 2026 rerun executed all 197 test cases successfully with 0 failures. The initial compile failure and its resolution are recorded in §1.

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

All 54 force-unwraps (`as!`) identified in the initial review have been replaced with `guard-let` statements. The 14 remaining `as!` lines consist of 10 code lines (8 CF typealias casts + 2 NSDictionary casts) plus 4 comment lines explaining safety. CF typealias casts (e.g., `track.formatDescriptions as! [CMFormatDescription]` in `MovieMutator+Inspector.swift`, `MovieMutator+Transform.swift`, `MovieWriter+CustomExport.swift`, `MovieMutatorBase+FormatDescriptions.swift`) are guaranteed to succeed by Swift. NSDictionary casts (`dict.copy() as! NSDictionary` in `MovieWriter+CustomExport.swift:262,268`) copy an `NSMutableDictionary` to its immutable counterpart.

### 4.2 `preconditionFailure` / `precondition` — PARTIALLY RESOLVED

The user-reachable `preconditionFailure` paths in `MovieMutatorBase.swift` have been replaced with graceful error return paths (S-08 fix, lines 153–159). Two guard-style calls remain, both on non-user-reachable or intentional paths:

- **`MovieMutatorBase.swift:20`** — `preconditionFailure("mutableCopy() of AVMutableMovie returned non-AVMutableMovie")`. Guards an impossible condition (AVFoundation's `mutableCopy()` should never return a non-`AVMutableMovie` type) and is not on a user-reachable path.
- **`AsyncBridge.swift:100`** — `precondition(allowMainThread || !Thread.isMainThread, ...)`. This is a deliberate API contract guard: `AsyncBridge.perform` must not be called on the main thread unless the caller explicitly opts into the deadlock risk via `allowMainThread: true`.

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
| **MovieMutator (edit)** | `MovieMutatorEditTests.swift` | 5 | ✅ Covered |
| **MovieMutator (transform/export)** | `MovieMutatorTransformExportTests.swift` | 8 | ✅ Covered |
| **TimelineView rendering/mouse input** | `TimelineViewRenderingTests.swift` | 15 | ✅ Covered |
| **ViewController key events** | `ViewControllerKeyEventTests.swift` | 14 | ✅ Covered |
| **ViewController (general)** | `ViewControllerTests.swift` | 15 | ✅ Covered |
| **Document** | `DocumentTests.swift` | 6 | ✅ Covered |
| **Model** | `ModelTests.swift` | 25 | ✅ Covered |
| **Utilities** | `UtilitiesTests.swift` | 20 | ✅ Covered |
| **Performance** | `PerformanceTests.swift` | 12 | ✅ Covered |
| **Localization** | `LocalizationTests.swift` | 11 | ✅ Covered |
| **LoggingSystem** | `LoggingSystemTests.swift` | 17 | ✅ Covered |
| **cutter2 (integration)** | `cutter2Tests.swift` | 20 | ✅ Covered |
| **MovieHeaderValidator** | `MovieHeaderValidatorTests.swift` | 3 | ✅ Covered |
| **Overall** | 16 files (15 test source + 1 helper) | **197 statically declared methods** | ✅ 197 passed, 0 failed |

### 5.2 Test Execution

- `scripts/test.sh` orchestrates build → test → analyze via `xcodebuild`
- CI workflow (`.github/workflows/test.yml`) runs on push/PR to `main`, `work`, and `develop` branches (Build → Test → Analyze, using `build-for-testing` + `test-without-building` to avoid double compilation)
- The current source contains 197 statically declared test methods and no `XCTSkip` usage; the August 6, 2026 rerun passed all 197 test cases with 0 failures after consolidating the shared fixture helper
- The `scripts/test.sh` summary distinguishes 15 test source files from 1 helper file and reports 197 test methods

### 5.3 Test Coverage Gaps

| Area | Current Coverage | Gap |
|------|-----------------|-----|
| **Document+FileIO** | Revert/read error paths (`readAsync` UTI + header validation) | ✅ Covered by T-14 (`validateMovieType` / `MovieHeaderValidator` tests). Full revert sheet-display flow still untested (requires Document instance, which crashes in test env — see §5.4 note) |
| **TimelineView+Input** | Mouse event handling (`mouseDown`, `mouseDragged`) | ✅ Covered by T-14 (marker selection → `doSetCurrent`, drag updates `startPosition`/`currentPosition`, no-op when unselected) |
| **Document+UI** | Window resize handling (`windowDidResize`) | ❌ Not tested — layout update propagation on window resize |
| **Document+SavePanel** | Export save panel flow | ❌ Not tested — save panel presentation and cancellation paths |
| **MovieMutator+Clipboard** | Copy/paste operations | ❌ Not tested — clipboard serialization and deserialization |
| **Document+PositionControl** | Playback position scrubbing | ❌ Not tested — position updates during playback |

> **Recommendation:** Document+FileIO revert and TimelineView+Input mouse handling are now covered by T-14. Remaining priorities are Document+UI window resize and Document+PositionControl scrubbing.

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
- Reports a summary; its static counts distinguish 15 test source files from 1 helper and report 197 methods

---

## 8. Detailed Findings

### 8.1 Concurrency Correctness

**Finding:** The `@MainActor` isolation on `MovieMutatorBase` ensures all mutations are serialized on the main thread. The `actor MovieWriter` correctly isolates export state. The `AsyncBridge` pattern is used appropriately for NSDocument overrides.

**Assessment:** Concurrency model is sound. No race conditions or isolation violations detected.

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

---

## 9. Recommendations

### 9.1 High Priority

1. ~~**Update documentation** (`ARCHITECTURE.md`, `API_REFERENCE.md`)~~ — Resolved (2026-08-05): Both documents removed. Information is now maintained in this review document.
2. **Add tests** for remaining untested areas: Document+UI window resize, Document+SavePanel flow, MovieMutator+Clipboard, Document+PositionControl scrubbing.

### 9.2 Medium Priority

3. **Unify date formatter usage** between `LoggingSystem` and `DateFormatter+Factory.swift`.
4. **Expand performance tests** to cover TimelineView rendering and MovieMutator operations.

### 9.3 Low Priority

5. **Add documentation comments** to public APIs in `Utilities/` that lack them.

---

## 10. Conclusion

The cutter2 codebase demonstrates a layered architecture with explicit concurrency settings and 197 statically declared test methods. Strict concurrency (`complete`) and warnings-as-errors are enabled across all build configurations. Runtime test status for the reviewed HEAD remains blocked by the duplicate `writeSampleMovie` declaration; the historical August 5 passing result must not be treated as current until the build is repaired and the suite is rerun. Remaining documented coverage gaps include Document+UI window resize, Document+SavePanel flow, MovieMutator clipboard, and Document+PositionControl scrubbing.

The concurrency model, typed error propagation, and security-scoped resource cleanup align with the implementation inspected. The next verification step is to remove or rename the duplicate test helper, then rerun build, test, and analyze.

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

### Test Files (16 files: 15 test source files + 1 helper; 197 statically declared methods)
- `cutter2Tests.swift` (20 tests), `MovieMutatorTests.swift` (22 tests), `MovieMutatorEditTests.swift` (5 tests), `MovieMutatorTransformExportTests.swift` (8 tests)
- `MovieHeaderValidatorTests.swift` (3 tests), `AsyncBridgeTests.swift` (4 tests)
- `TimelineViewRenderingTests.swift` (15 tests), `ViewControllerTests.swift` (15 tests), `ViewControllerKeyEventTests.swift` (14 tests)
- `DocumentTests.swift` (6 tests), `ModelTests.swift` (25 tests)
- `UtilitiesTests.swift` (20 tests), `PerformanceTests.swift` (12 tests)
- `LocalizationTests.swift` (11 tests), `LoggingSystemTests.swift` (17 tests)
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
- `cutter2.xcodeproj/project.pbxproj` (version 0.8.19 / build 20260802 — committed in the reviewed state)
- `.github/workflows/test.yml` (build/test/analyze, branches `main`/`work`/`develop`; coverage artifact generation is optional)
- `scripts/test.sh` (build/test/analyze; static suite count: 15 test source files + 1 helper, 197 methods)
