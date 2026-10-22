# Codebase Review — cutter2

**Date:** 2026-10-22 (revision 7; revision 6: 2026-10-17; revision 5: 2026-09-29; original review 2026-08-06)
**Reviewer:** Source-level documentation and code review
**Scope:** Current `work` integration branch after PR #73, including source, tests, Markdown documentation, Xcode project, CI workflow, and test scripts
**Reviewed baseline:** `e5dc551` (`work`; PR #73 squash merge); the 0.8.21 version/build commit follows it
**Verification environment:** macOS 27.0.1 (build 26A434), Xcode 27.2 (build 27B48), Swift compiler 6.4.2
**Status:** Rebaselined for the 0.8.21 release. The tested code baseline is PR #73 (`e5dc551`); the release commit changes only the version/build metadata. Clean build, clean analyze, and `build-for-testing` succeeded on Xcode 27.2 with no Swift source warnings, and the 2026-10-22 `test-without-building` run passed 320/320 tests with 0 failures and 0 skips. The xcresult records no runtime warnings, so the QoS priority-inversion warning previously reported by `MovieWriterCustomProgressTests.swift` is resolved by PR #73. The existing live-player integration gaps remain as described in §5.3 and §8.6.

---

## 1. Summary

This document records a source-level review of the **cutter2** project — a macOS video editor application built with Swift and AVFoundation. The review covers project structure, architecture, concurrency model, code quality, test coverage, documentation accuracy, and build/CI configuration.

Revision 5 (2026-09-29) is the historical review of the 0.8.20 release baseline. Revision 6 (2026-10-17) updates the current branch inventory, file organization, bridge call paths, line references, and verification results after the small-file consolidation. Revision 7 (2026-10-22) rebaselines the review on `work` for the 0.8.21 release, replacing the beta marketing version with the final 0.8.21 / build 20261022 metadata and re-running the verification on Xcode 27.2. The revision 5 commit list and measurements below are retained as historical records, not as the current branch state.

- `b724483` Refactor cutter2: concurrency, export, and media cleanup overhaul (#63) — squash-merged the previously reviewed line together with the reload/seek generation work; re-asserts suppression immediately before `replaceCurrentItem`.
- `38221e9` Fix cutter2 release blockers (#64) — CR-4, M-24, M-25, M-26, M-27, M-28, T-17, H-11; expands `DocumentTests` (6 → 12), `MovieWriterWriteTests`, `PlayerSeekSequencerTests`, and `MovieMutatorTransformExportTests`.
- `4747c9a` 0.8.20b — version/build bump.
- `011aff7` Fix main-thread blocking in fixture-writing tests (#65) — moves synchronous fixture encoding off the main actor and resolves the runtime warning reports.
- `fb44143` 0.8.20 — release version/build metadata update.

Verification for this baseline was run with the current toolchain:

```bash
xcodebuild clean build   -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO
xcodebuild clean analyze -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO
xcodebuild test          -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS' -enableCodeCoverage YES CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO
```

All three steps succeeded. The full test run executed **269 test cases with 269 passed and 0 failed** (0 skipped). The 2026-09-27 run initially emitted 3 runtime performance warnings. Follow-up triage identified `libRPAC.dylib` (Xcode runtime performance analysis), not `libMainThreadChecker.dylib`, as the reporting component.

**Current verification facts (revision 7, 2026-10-22):**

- **Current static test suite size:** 24 files total (23 test source files + 1 helper), with 320 test methods (TimelineViewRenderingTests 18, up from 15; M-32 added 3 zero-width and negative-width position regression tests).
- **Current runtime test result:** 320 passed, 0 failed, 0 skipped (2026-10-22, `e5dc551`; recorded in the xcresult referenced by the local test run).
- **Current runtime warning:** The same xcresult records no runtime warnings; PR #73 removed the QoS priority-inversion warning previously reported by `MovieWriterCustomProgressTests.swift`. The earlier PR #65 A/B measurement of 0 runtime performance reports (55 before the fixture-writing fix) is historical and is not this run's result.
- **Runtime warning triage:** `PERFC_ENABLE_DUPLICATE_DETECTION=0` reproduced 55 reports in an approximately 220 ms burst. PID correlation mapped the reporting processes to the three fixture-generating test files, where `DispatchQueue.global().sync` synchronously blocked the main actor during `AVAssetWriter` encoding. After PR #65 moved fixture generation to detached utility tasks, the same diagnostic measurement produced 0 reports.
- **CI workflow:** Configured for `main`, `work`, and `develop`, with Build → Test → Analyze steps plus coverage report generation/upload. The workflow uses `macos-latest` and does not pin a specific Xcode image.
- **Strict concurrency:** `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` are enabled across all four app/test configurations.
- **Swift language mode:** `SWIFT_VERSION = 6.0` is pinned in the app and test targets.
- **Version:** `MARKETING_VERSION = 0.8.21`, `CURRENT_PROJECT_VERSION = 20261022` (app target; committed in the project). The beta suffix was removed for the release; the version/build commit follows the reviewed `work` head `e5dc551`.
- **Force casts:** 14 `as!` lines (10 code lines: 8 CF typealias casts + 2 NSDictionary casts, plus 4 whole-line comment lines) — unchanged from the earlier review.
- **Intentional crash/assertion sites:** Three executable sites remain: `MovieMutatorBase.swift:23` (impossible `mutableCopy()` result), `ConcurrencyBridge.swift:104` (deliberate main-thread API-contract guard), and `Document+FileIO.swift:604` (fatalError in the non-throwing `performAsync` overload, indicating an internal bridge bug). Line numbers reflect the 2026-10-17 consolidation.

---

## 2. Project Structure

### 2.1 Source Code Organization

The project follows a layered architecture with clear separation of concerns:

```
cutter2/
├── Application/
│   ├── AppDelegate.swift
│   ├── BookmarkStore.swift
│   └── DocumentController.swift
├── Document/
│   ├── Document.swift                  // Includes modifier(_:)
│   ├── Document+Export.swift
│   ├── Document+FileIO.swift           // Includes validateIfSelfContained(for:) and performAsync
│   ├── Document+Observers.swift        // Includes cleanup()
│   ├── Document+PositionControl.swift
│   ├── Document+SavePanel.swift
│   ├── Document+SheetControl.swift     // Includes afterSheetContinue(_:perform:)
│   ├── Document+TimelineUpdateDelegate.swift
│   ├── Document+UI.swift               // Includes inspectorDictionary()
│   ├── Document+ViewControllerDelegate.swift
│   └── PlayerSeekSequencer.swift
├── Models/
│   ├── MovieMutator.swift              // Subclass of MovieMutatorBase; includes clipboard and makePlayerItem()
│   ├── MovieMutatorBase.swift          // Base class (NSObject subclass)
│   ├── MovieMutatorBase+FormatDescriptions.swift
│   ├── MovieMutatorBase+Formatting.swift
│   ├── MovieMutatorBase+PresentationInfo.swift
│   ├── MovieMutatorBase+Progress.swift
│   ├── MovieMutator+Edit.swift
│   ├── MovieMutator+Transform.swift
│   ├── MovieMutator+Export.swift
│   ├── MovieMutator+Inspector.swift
│   ├── MovieMutatorTypes.swift
│   ├── MovieWriter.swift
│   ├── MovieWriter+CustomExport.swift
│   ├── MovieWriter+ExportSession.swift
│   ├── MovieWriter+WriteMovie.swift
│   ├── VideoChannelMetadataBuilder.swift
│   ├── SampleBufferChannel.swift
│   ├── Notifications.swift
│   ├── ProgressSink.swift
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
│   ├── ConcurrencyBridge.swift         // AsyncBridge + ActorUtilities
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
    ├── Localizable.xcstrings        # Hand-curated app strings
    ├── Base.lproj/Main.storyboard   # Main UI (storyboard)
    ├── mul.lproj/Main.xcstrings     # Storyboard-extracted strings
    └── Assets.xcassets/             # App icon
```

**Total source files:** 63 Swift files across 6 source directories (plus Resources), including the S-17 `PlayerSeekSequencer` extraction, `VideoChannelMetadataBuilder`, `BookmarkStore`, and `ProgressSink`. The 2026-10-17 consolidation (`refactor/consolidate-small-files`) reduced the count from 69 by merging `MovieMutator+Clipboard` and `+Player` into `MovieMutator.swift`, merging `Document+MovieReference`, `Document+Utilities`, and `Document+ActorIsolation` into their destination extensions, and merging `AsyncBridge` and `ActorUtilities` into `ConcurrencyBridge.swift`.

**Note:** `MovieMutator` (in `MovieMutator.swift`) is a subclass of `MovieMutatorBase` (in `MovieMutatorBase.swift`). All functional extensions (`+Edit`, `+Transform`, `+Export`, etc.) are on the `MovieMutator` subclass, not on `MovieMutatorBase` directly.

### 2.2 Test Organization

```
cutter2Tests/
├── AsyncBridgeTests.swift                # AsyncBridge tests (4 tests)
├── cutter2Tests.swift                    # Integration tests (20 tests)
├── DocumentKVOContextTests.swift         # KVO context tests (3 tests)
├── DocumentReloadSeekIntegrationTests.swift # Document reload/seek integration seam tests (5 tests)
├── DocumentTests.swift                   # Document tests (16 tests)
├── LayoutConverterMappingTests.swift     # Layout mapping tests (7 tests)
├── LocalizationTests.swift               # Localization tests (11 tests)
├── LoggingSystemTests.swift              # Logging tests (17 tests)
├── ModelTests.swift                      # Model layer tests (26 tests)
├── MovieHeaderValidatorTests.swift       # Header validation tests (9 tests)
├── MovieMutatorEditTests.swift           # Edit operation and presentation traversal tests (11 tests)
├── MovieMutatorTests.swift               # Model layer tests (22 tests)
├── MovieMutatorTransformExportTests.swift # Transform/export tests (10 tests)
├── MovieWriterCustomProgressTests.swift  # Custom-export progress sink tests (15 tests)
├── PerformanceTests.swift                # Performance tests (16 tests)
├── MovieWriterVideoChannelMetadataTests.swift # Video channel metadata tests (25 tests)
├── MovieWriterWriteTests.swift           # Movie writer failure-state tests (3 tests)
├── PlayerSeekSequencerTests.swift        # Reload/seek sequencer tests (19 tests)
├── SecurityScopedBookmarkTests.swift     # Security-scoped bookmark tests (12 tests)
├── TestMovieFixtureWriter.swift          # Test helper (0 tests, fixture writer)
├── TimelineViewRenderingTests.swift      # Timeline rendering tests (18 tests)
├── UtilitiesTests.swift                  # Utility tests (22 tests)
├── ViewControllerKeyEventTests.swift     # Key event tests (14 tests)
└── ViewControllerTests.swift             # ViewController tests (15 tests)
```

**Current total:** 24 files (23 test source files + 1 helper), **320 test methods**. Runtime results are recorded separately in §2.3. The count reflects the current working tree (M-32 added 3 TimelineView regression tests). Note: 2 method names are duplicated across different test classes (`testMovieHeaderGeneration` in `cutter2Tests.swift` and `MovieMutatorTests.swift`; `testTimeCalculationPerformance` in `MovieMutatorTests.swift` and `ViewControllerTests.swift`). #64 adds watchdog, stale-token, failure-fallback, and cleanup regression coverage (`PlayerSeekSequencerTests`), empty-window lifecycle coverage (`DocumentTests`, CR-4), cancellation classification (M-26), and temporary finalization (H-11).

### 2.3 Test Execution Results

The current source contains 320 test methods (TimelineViewRenderingTests 15→18 via M-32) and no `XCTSkip` usage. Historical runs: the 2026-09-27 full-suite run on the 0.8.20b head passed 269/269; October 1, 2026 feature-branch runs passed 275/275 (PR #67), 274/274 (standalone T-19 baseline), and 280/280 (combined T-19 on PR #67). The current branch run on 2026-10-22 passed 320/320 with 0 failures and 0 skips; its xcresult records no runtime warnings (see §1). The earlier PR #65 A/B measurement of runtime performance reports (55 before, 0 after the fixture-writing fix) is historical and separate from the current test run.

---

## 3. Architecture Overview

### 3.1 Layer Structure

| Layer | Responsibility | Key Files |
|-------|---------------|-----------|
| **Application** | App lifecycle, document creation, security-scoped URL bracketing | `AppDelegate.swift`, `BookmarkStore.swift`, `DocumentController.swift` |
| **Document** | Core document model, NSDocument subclass, undo/redo, file I/O, export orchestration, reload/seek state | `Document.swift` + 9 extensions and `PlayerSeekSequencer.swift` |
| **Models** | Media manipulation logic (timeline editing, transforms, export) | `MovieMutatorBase.swift` + 4 extensions, `MovieMutator.swift` + 4 extensions (clipboard and player support are in the class body), `MovieWriter.swift` + 3 extensions, `VideoChannelMetadataBuilder.swift`, `ProgressSink.swift` |
| **ViewControllers** | UI coordination, user input handling | `ViewController.swift` + 5 extensions, transcode/CAPAR/inspector dialogs |
| **Views** | Rendering (timeline, player, window) | `TimelineView.swift` + 3 extensions, `MyPlayerView.swift`, `Window.swift` |
| **Utilities** | Cross-cutting helpers (concurrency, layout, validation, logging) | Various utility files |

### 3.2 Concurrency Model

The project uses Swift's modern concurrency model with a clear isolation strategy:

- **`@MainActor`**: Applied to `Document`, `ViewController`, `WindowController`, `MovieMutatorBase`, and all UI-related extensions. This ensures all UI updates and document mutations occur on the main thread.

- **`actor MovieWriter`**: A dedicated actor for export state management, isolating export session lifecycle from the main actor.

- **`AsyncBridge`**: A custom utility bridging async/await to synchronous contexts (used by `Document.read(from:ofType:)` for file-open preparation and by the `performAsync` wrapper behind `Document.write(to:ofType:for:originalContentsURL:)`). Defined in `Utilities/ConcurrencyBridge.swift`.

- **`ActorUtilities.performSyncOnMainActor`**: A utility for safely calling main-actor-isolated code from synchronous contexts. Defined in `Utilities/ConcurrencyBridge.swift`.

- **Reload/seek generation gating (S-17, hardened in #63/#64)**: `PlayerSeekSequencer` (itself `@MainActor`) owns the reload and seek generations, the reload task handle, the suppression state, a suppression watchdog, a token-snapshot type (`SeekToken`), and stale-completion gates. `Document+UI.swift` retains AVPlayer and UI side effects: it advances the seek generation via `beginItemReplacement` before swapping the player item, re-asserts suppression via `suppressForReload()` immediately before `replaceCurrentItem`, arms `armSuppressionWatchdog`, and releases only the current generation. The `readyToPlay` KVO handler reads suppression through the sequencer inside `performSyncOnMainActor` because `observeValue` is `nonisolated`. The state transitions are covered by `PlayerSeekSequencerTests`; integration ordering against a live AVPlayer, KVO delivery, and polling timer remains untested.

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

All 54 force-unwraps (`as!`) identified in the initial review have been replaced with `guard-let` statements. The 14 remaining `as!` lines consist of 10 code lines (8 CF typealias casts + 2 NSDictionary casts) plus 4 whole-line comment lines explaining safety — unchanged at the current baseline. CF typealias casts (e.g., `track.formatDescriptions as! [CMFormatDescription]` in `MovieMutator+Inspector.swift`, `MovieMutator+Transform.swift`, `MovieWriter+CustomExport.swift`, `MovieMutatorBase+FormatDescriptions.swift`) are guaranteed to succeed by Swift. NSDictionary casts (`dict.copy() as! NSDictionary` in `MovieWriter+CustomExport.swift:262,268`) copy an `NSMutableDictionary` to its immutable counterpart.

### 4.2 `preconditionFailure` / `precondition` / `fatalError` — PARTIALLY RESOLVED

The user-reachable `preconditionFailure` paths in `MovieMutatorBase.swift` have been replaced with graceful error return paths (S-08 fix). Three intentional executable sites remain, all on non-user-reachable or deliberate paths:

- **`MovieMutatorBase.swift:23`** — `preconditionFailure("mutableCopy() of AVMutableMovie returned non-AVMutableMovie")`. Guards an impossible condition (AVFoundation's `mutableCopy()` should never return a non-`AVMutableMovie` type) and is not on a user-reachable path.
- **`ConcurrencyBridge.swift:104`** — `precondition(allowMainThread || !Thread.isMainThread, ...)`. This is a deliberate API contract guard: `AsyncBridge.perform` must not be called on the main thread unless the caller explicitly opts into the deadlock risk via `allowMainThread: true`.
- **`Document+FileIO.swift:604`** — `fatalError("Non-throwing performAsync unexpectedly threw: ...")` in the non-throwing `performAsync` overload. The catch is intentionally fatal: a non-throwing block cannot produce a `PerformAsyncError` under normal operation, so reaching it indicates an internal bridge bug rather than a recoverable caller error. Pre-existing; documented here for completeness.

### 4.3 Security-Scoped Access — CORRECTED

The app is sandboxed with the `com.apple.security.files.bookmarks.app-scope` entitlement. Security-scoped resource access is centralized in a single helper, `bracketSecurityScopedAccess<T>(for:_:)` in `AppDelegate.swift` (declared at line 232), which pairs `startAccessingSecurityScopedResource()` with a `defer`-scoped `stopAccessingSecurityScopedResource()`. It is used by the three MovieWriter export paths — `MovieWriter+ExportSession.swift:250`, `MovieWriter+CustomExport.swift:500`, and `MovieWriter+WriteMovie.swift:122` — and `AppDelegate` also performs direct start/stop bracketing at lines 119/127 and 239/245. No `NSFileCoordinator` is used anywhere in the codebase, and no security-scoped access lives in `Document+FileIO.swift` (an earlier revision of this review cited that location; it has been corrected here).

### 4.4 Build Settings

- **Deployment target:** macOS 14.0
- **Swift version:** Pinned to `SWIFT_VERSION = 6.0` in all targets (correcting the earlier review, which stated the version was unpinned).
- **Compiler flags:** `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` enabled in all 4 build configurations.

---

## 5. Test Coverage Analysis

### 5.1 Test Coverage by Area

| Area | Test File | Test Count | Coverage Status |
|------|-----------|------------|-----------------|
| **AsyncBridge** | `AsyncBridgeTests.swift` | 4 | ✅ Covered |
| **MovieMutator (core)** | `MovieMutatorTests.swift` | 22 | ✅ Covered |
| **MovieMutator (edit)** | `MovieMutatorEditTests.swift` | 11 | ✅ Covered |
| **MovieMutator (transform/export)** | `MovieMutatorTransformExportTests.swift` | 10 | ✅ Covered (cancel-order regression from #69) |
| **TimelineView rendering/mouse input** | `TimelineViewRenderingTests.swift` | 18 | ✅ Covered (M-32 zero-width and negative-width position guard) |
| **ViewController key events** | `ViewControllerKeyEventTests.swift` | 14 | ✅ Covered |
| **ViewController (general)** | `ViewControllerTests.swift` | 15 | ✅ Covered |
| **Document** | `DocumentTests.swift` | 16 | ✅ Covered (expanded in #64: cancellation-error classification, empty-window lifecycle (CR-4), position-cache reset; PR #71 adds the progress terminal-state and `NSProgress` monotonicity cases) |
| **Document KVO context** | `DocumentKVOContextTests.swift` | 3 | ✅ Covered |
| **LayoutConverter mappings** | `LayoutConverterMappingTests.swift` | 7 | ✅ Covered (T-16) |
| **Player seek sequencing** | `PlayerSeekSequencerTests.swift` + `DocumentReloadSeekIntegrationTests.swift` | 19 + 5 | ✅ Generation, item-replacement, watchdog, failure fallback, and cleanup transitions covered (expanded in #64); T-19 adds the live-player reload wiring (§5.3). KVO `readyToPlay` re-seek and real-media playback remain untested |
| **Model** | `ModelTests.swift` | 26 | ✅ Covered |
| **Utilities** | `UtilitiesTests.swift` | 22 | ✅ Covered |
| **Performance** | `PerformanceTests.swift` | 16 | ✅ Covered (T-20 adds four non-gating real `TimelineView` / `MovieMutator` baselines) |
| **Localization** | `LocalizationTests.swift` | 11 | ✅ Covered |
| **LoggingSystem** | `LoggingSystemTests.swift` | 17 | ✅ Covered |
| **cutter2 (integration)** | `cutter2Tests.swift` | 20 | ✅ Covered |
| **MovieHeaderValidator** | `MovieHeaderValidatorTests.swift` | 9 | ✅ Covered |
| **MovieWriter video channel metadata** | `MovieWriterVideoChannelMetadataTests.swift` | 25 | ✅ Covered |
| **MovieWriter failure states** | `MovieWriterWriteTests.swift` | 3 | ✅ Covered (expanded in #64, H-11) |
| **MovieWriter custom-export progress** | `MovieWriterCustomProgressTests.swift` | 15 | ✅ Covered (PR #71: `ProgressSink` admission gate, concurrent publish ordering, non-finite and out-of-range rejection, `didRead` wiring) |
| **Security-scoped bookmarks** | `SecurityScopedBookmarkTests.swift` | 12 | ✅ Covered (PR #71: Save As registration policy — `bookmarkSourceTarget` decision matrix and duplicate detection) |
| **Overall** | 24 files (23 test source + 1 helper) | **320 test methods** | ✅ Current branch run passed 320/320 (2026-10-22; 0 failed, 0 skipped); xcresult records no runtime warnings. Historical runs: 274/274 (standalone T-19), 275/275 (PR #67), and 280/280 (combined branch). KVO `readyToPlay` re-seek and real-media playback remain untested |

### 5.2 Test Execution

- `scripts/test.sh` orchestrates build → test → analyze via `xcodebuild`
- CI workflow (`.github/workflows/test.yml`) runs on push/PR to `main`, `work`, and `develop` branches (Build → Test → Analyze, using `build-for-testing` + `test-without-building` to avoid double compilation)
- The current source contains 320 test methods (TimelineViewRenderingTests 15→18 via M-32) and no `XCTSkip` usage
- `scripts/test.sh` reports the current inventory of 23 test source files + 1 helper and 320 tests
- Historical suite runs: 269/269 (2026-09-27, 0.8.20b), 274/274 (2026-10-01, standalone T-19), 275/275 (2026-10-01, PR #67), and 280/280 (2026-10-01, combined T-19 on PR #67)
- Current branch verification (2026-10-22): clean build, clean analyze, and `build-for-testing` succeeded; `test-without-building` passed 320/320 (0 failures, 0 skips). No Swift source compiler warnings were found in the build or analyze logs. The xcresult reports no runtime warnings (see §1); the earlier QoS priority-inversion warning in `MovieWriterCustomProgressTests.swift` was fixed by PR #73.

### 5.3 Test Coverage Gaps

| Area | Current Coverage | Gap |
|------|-----------------|-----|
| **Document+FileIO** | Revert/read error paths (`readAsync` UTI + header validation) | ✅ Covered by T-14 (`validateMovieType` / `MovieHeaderValidator` tests) and the CR-4 empty-window lifecycle test. Full revert sheet-display flow still untested (a `Document` instance is now constructible — see §5.4 — but the sheet presentation path has no seam) |
| **TimelineView+Input** | Mouse event handling (`mouseDown`, `mouseDragged`) | ✅ Covered by T-14 (marker selection → `doSetCurrent`, drag updates `startPosition`/`currentPosition`, no-op when unselected) |
| **MovieMutator edit marker correction** | `doRemove` position-correction branches | ✅ Covered (3 regression tests in `MovieMutatorEditTests.swift`) |
| **PlayerSeekSequencer state transitions** | Reload/seek generations, item replacement, task cancellation gates, suppression transitions, stale tokens, watchdog, failure fallback, cleanup preservation | ✅ Unit-tested by 19 cases in `PlayerSeekSequencerTests.swift`; the live-player reload wiring is covered by T-19 (`DocumentReloadSeekIntegrationTests`) |
| **Document × live AVPlayer integration** | Async ordering of `updatePlayer`, KVO delivery, and polling timer | ◑ Partially covered by T-19 (`DocumentReloadSeekIntegrationTests`, 5 cases): the reload generation propagation across the awaited player-item regeneration, superseded-reload item application, and the initial-setup wiring (player attachment, polling timer, immediate suppression release) are now fixed through a test-only seam. KVO `readyToPlay` re-seek delivery and playback with real media remain untested (out of scope, §0) |
| **Document+UI** | Window resize handling (`windowDidResize`) | ❌ Not tested — layout update propagation on window resize |
| **Document+SavePanel** | Export save panel flow | ❌ Not tested — save panel presentation and cancellation paths |
| **MovieMutator clipboard** (in `MovieMutator.swift`) | Copy/paste operations | ❌ Not tested — clipboard serialization and deserialization |
| **Document+PositionControl** | Playback position scrubbing | ❌ Not tested — position updates during playback |

> **Recommendation:** Unit-level seek, cancellation classification, position-cache reset, empty-window lifecycle, H-11 temporary finalization/self-contained selection, and — via the T-19 test-only seam — the reload ordering between `Document` and a live AVPlayer are covered. The remaining gaps in this area are KVO `readyToPlay` re-seek delivery (the AVPlayer observer count is not observable through public APIs) and playback with real media, both of which would need a UI/integration harness. Window resize, save panel, clipboard, and scrubbing coverage remain open.

### 5.4 Skipped Test — RESOLVED

The always-skipped `MovieHeaderValidatorTests.testInvalidDurationPath()` was removed by S-12. The test threw `XCTSkip` because the `invalidDuration` fixture is not constructible via the public `AVMutableMovie` API. After removal, the suite contains no `XCTSkip` usage, and the `errorDescription` behavior is exercised by the `MovieHeaderValidatorTests` cases. (T-21, October 1, 2026) The `invalidDuration` validation error path is now covered directly: the branch decision was extracted into the internal `MovieHeaderValidator.validate(trackCount:duration:)` helper, and six direct helper tests exercise it with `.invalid` / `.indefinite` / ±`.infinity` (all rejected) and `.zero` (accepted), so the path no longer depends on a public-API fixture.

**Document constructibility (updated for #64 / CR-4):** An earlier revision of this review recorded that `Document` instances could not be constructed in the unit-test environment because the `window` computed property force-indexed `windowControllers[0]`, raising `NSRangeException` on the empty array during `NSDocument.init()`. CR-4 (shipped in #64) changed `Document.window` to `self.windowControllers.first?.window as? Window`, which safely returns `nil` until a window controller exists. As a result, `Document()` can now be constructed in tests, and `DocumentTests` exercises it directly (`testWindowIsNilBeforeWindowControllerCreation`, `testResetPositionCacheClearsAllCachedPositionState`). The full revert sheet-display flow still has no test seam, but it is no longer blocked by the construction crash.

### 5.5 Flaky Test — RESOLVED

`PerformanceTests.testPerformanceMetricsOverhead()` previously failed intermittently under parallel test-runner load — measured overhead of `PerformanceMetrics.measure` exceeded the 10% threshold (observed 43.6%) because `CFAbsoluteTimeGetCurrent()`-based timing of a 10,000-iteration loop was dominated by scheduling noise. Fixed by M-22: workload increased to 100,000 iterations, best-of-5 measurement (lowest overhead selected), and threshold relaxed to 30%. Verified passing in isolation (5 runs) and in the full suite (2 runs); it also passed in the 2026-09-27 full-suite run.

---

## 6. Documentation Accuracy

### 6.1 Removed Documents

The following documents were removed on 2026-08-05 because they were outdated and unmaintained:

- **`ARCHITECTURE.md`** — Last updated 2026-02-05, contained stale file names, line counts, and layer descriptions. Information is now maintained in this document (§3 Architecture Overview).
- **`API_REFERENCE.md`** — Last updated 2026-02-05, contained outdated protocol signatures and error types. API details should be sourced from inline documentation and this review.

### 6.2 Documentation Review

`ConcurrencyGuidelines.md`, `CONTRIBUTING.md`, `DEVELOPMENT_GUIDE.md`, and `TESTING_GUIDE.md` were checked for internal links, code fences, test-count consistency, command reproducibility, and alignment with the current implementation. The Markdown set contains 7 files when `README.md` and `.github/copilot-instructions.md` are included; the 5 files under `docs/` are listed separately in §11.

Revision 4 also re-aligned this document with the current 0.8.20b head, correcting: the test inventory (`DocumentTests` 6 → 12, and the source-file total 66/65 → 67 with the previously omitted `VideoChannelMetadataBuilder.swift`), the app version/build, the security-scoped access location (§4.3, §8.3), the `Document` constructibility note (§5.4), and the reload/seek suppression description (§3.2, §8.6). The corresponding test-count annotation was synchronized in `DEVELOPMENT_GUIDE.md` and `TESTING_GUIDE.md` so the per-file breakdown sums to the documented 269.

Revision 5 additionally closed two stale recommendations: the DateFormatter duplication item is already resolved by the shared factory (L-02 / PR #38), and the Utilities public-API documentation item is not applicable because the 10 public declarations found by the scan already have documentation comments; the remaining Utilities declarations are internal.

---

## 7. Build & CI Configuration

### 7.1 Xcode Project

- Project file: `cutter2.xcodeproj/project.pbxproj`
- Deployment target: app and test targets explicitly set `MACOSX_DEPLOYMENT_TARGET = 14.0` in both Debug and Release configurations. The project-level Debug/Release settings retain `$(RECOMMENDED_MACOSX_DEPLOYMENT_TARGET)` as a fallback.
- Swift version: pinned to `SWIFT_VERSION = 6.0` (all app/test target configurations)
- Version: `MARKETING_VERSION = 0.8.21`, `CURRENT_PROJECT_VERSION = 20261022` (committed in the project)
- `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` enabled in all 4 build configurations

### 7.2 CI Workflow

`.github/workflows/test.yml`:
- Triggers on `push` and `pull_request` to `main`, `work`, and `develop` branches
- Runs three sequential steps: `xcodebuild clean build-for-testing` → `xcodebuild test-without-building` (with code coverage) → `xcodebuild analyze`
- Single job with macOS runner (`macos-latest`, Xcode selected via `xcode-select`; no pinned image)
- Generates and uploads an `lcov` coverage report as an artifact; coverage generation is optional (`|| echo "...skipped"`, `if-no-files-found: ignore`)

### 7.3 Test Script

`scripts/test.sh`:
- Runs `xcodebuild clean build` → `xcodebuild test` → `xcodebuild analyze` sequentially (xcodebuild does not parallelize these well)
- Each step is guarded with `if ! ...; then exit 1; fi` so failures are reported with a custom message (works with `set -e`)
- Uses color-coded echo statements for output formatting
- Generates coverage reports via `xcrun llvm-cov`
- Reports a summary; its inventory distinguishes 23 test source files from 1 helper and reports 320 tests

---

## 8. Detailed Findings

### 8.1 Concurrency Correctness

**Finding:** The `@MainActor` isolation on `MovieMutatorBase` ensures all mutations are serialized on the main thread. The `actor MovieWriter` correctly isolates export state. The `AsyncBridge` pattern is used appropriately for NSDocument overrides. The reload/seek generation gating (§3.2) was reviewed scenario-by-scenario: interrupted seeks (`finished == false`), delayed stale completions (`finished == true` arriving after a newer seek or item replacement), consecutive user seeks within one reload generation, the suppressed `readyToPlay` re-seek, and the suppression watchdog as a liveness fallback — each closes its prior window, and every escaping completion captures `self`/player/mutator weakly, so no retain cycles were found.

**Placement of `Document` protocol conformances:** `Document` declares `ViewControllerDelegate` in its class declaration (`Document.swift`) and keeps only plain extensions for the delegate method bodies. Because `ViewControllerDelegate` refines `TimelineUpdateDelegate, Sendable`, the single conformance site satisfies both protocols, eliminating the Swift 6 "conformance must be declared in the same file" split.

**Assessment:** Concurrency model is sound; the §8.6 reload-suppression ordering issue is resolved, while live `Document`/AVPlayer integration coverage remains open. No isolation violations detected.

### 8.2 Error Handling

**Finding:** Error handling throughout the codebase uses typed Swift errors (`DocumentError`, `MovieWriterError`) defined in `Document.swift` and `MovieWriter.swift` respectively. Error propagation is consistent via `throws`/`try await`. #64 added explicit user-cancellation classification so cancelled exports no longer surface an error sheet.

**Assessment:** Error handling is robust and well-structured.

### 8.3 Resource Management

**Finding:** Security-scoped resource access is centralized in `AppDelegate.bracketSecurityScopedAccess` (see §4.3) and used by the MovieWriter export paths with `defer`-scoped cleanup. `MovieWriter` actor manages export session lifecycle correctly with explicit cancellation, and #64 finalizes flatten failures and MOV saves atomically (H-11).

**Assessment:** Resource management is correct.

### 8.4 Logging

**Finding:** `LoggingSystem.swift` provides a structured logging interface. `DateFormatter+Factory.swift` provides factory methods for date formatters, including a `logFormatter` used by the logging system.

**Assessment:** The logging system already uses the shared `DateFormatter.logFormatter` factory (PR #38 / L-02). The remaining `Thread.threadDictionary` cache is intentional: it avoids sharing a mutable `DateFormatter` across threads without introducing a new shared synchronization mechanism. No further unification work is required.

### 8.5 Performance

**Finding:** `PerformanceMetrics.swift` provides instrumentation for tracking operation durations (`measure`/`measureAsync`/`recordMeasurement`). Instrumentation call sites are in `MovieMutator+Export.swift`; performance-related tests live in `PerformanceTests.swift`.

**Assessment:** Performance tooling is present and `PerformanceTests.swift` covers 16 scenarios (metrics measurement/report/reset, export progress, timeline marker/position, memory allocation, and, added by T-20, four non-gating real-processing baselines: the real `TimelineView` `updateTimeline` + `layout` + layer commit path and the `MovieMutator` `movieClip` / `deleteSelection` / `applyClapPasp` operations, measured with `XCTClockMetric` + `XCTMemoryMetric` and recorded without thresholds). The simulation-based scenarios remain functional assertions. The overhead test, previously flaky, was stabilized by M-22 (§5.5); T-20 retires its remaining relative (30%) threshold in favor of a recorded observation, so the suite no longer gates on relative overhead.

### 8.6 Reload Suppression Ordering — Resolved in PR #63, reinforced in PR #64

**Historical finding:** A user-initiated seek that *completes* while a reload task is still awaiting `makePlayerItem()` could release `suppressQueryPosition`, and the reload could apply the new player item without re-asserting it.

**Current sequence (`Document+UI.swift` + `PlayerSeekSequencer.swift`):**

1. `updateGUI(reload: true)` asserts suppression, calls `beginReload()` to advance the reload generation and cancel the previous task, then spawns and registers the reload task. That task awaits `mutator.makePlayerItem()`.
2. While that await is in flight, a user seek calls `beginUserSeek()` to snapshot the current reload generation; its `finished == true` completion passes the generation gate (`isCurrent`) and calls `releaseSuppression(for:)`.
3. The reload task resumes, calls `beginItemReplacement(expectedReloadGeneration:)` to advance the seek generation (so any in-flight seek completion becomes a no-op), re-asserts suppression via `suppressForReload()` immediately before replacing the player item, and arms `armSuppressionWatchdog(for:)` as a liveness fallback before `replaceCurrentItem`.
4. The post-reload seek's completion checks `isCurrent(token)` and then `liftSuppression(for:)`; stale callbacks remain full no-ops through the generation check.

Under the historical implementation, `queryPosition()` could poll the new item and adopt a pre-seek `currentTime()`, reintroducing the stale-marker class of bug this mechanism exists to prevent. PR #63 shipped the suppression re-assertion; PR #64 (M-27/M-28) reinforced it with per-item-replacement generation bumping, a suppression watchdog, and a failure fallback (`releaseCurrentSuppressionAfterFailure`).

**Remaining gap:** Partially closed by T-19 (`DocumentReloadSeekIntegrationTests`, 5 cases): the reload generation propagation across the awaited player-item regeneration, the superseded-reload item-application guard, and the initial-setup wiring (player attachment, polling timer start, immediate suppression release) are now exercised against a live `AVPlayer` through a test-only seam. The sequencer state transitions remain unit-tested in `PlayerSeekSequencerTests` (19 cases). Unverified items that stay open: KVO `readyToPlay` re-seek delivery (the observer count is not observable through public APIs), playback and re-seek with real media, and the `nil` return path of `beginItemReplacement(expectedReloadGeneration:)` (unreachable in the current structure because `beginReload()` always cancels the previous reload task first — its unit behavior is covered by `PlayerSeekSequencerTests.testStaleReloadCannotBeginItemReplacement`).

---

## 9. Recommendations

### 9.1 High Priority

1. ~~**Update documentation** (`ARCHITECTURE.md`, `API_REFERENCE.md`)~~ — Resolved (2026-08-05): Both documents removed. Information is now maintained in this review document.
2. **Extend the integration coverage** that T-19 started. `PlayerSeekSequencer` state transitions are unit-tested, and T-19 covers the reload ordering between `Document` and a live AVPlayer through a narrow player/item factory seam (rather than broad `MovieMutator` protocolization or a full XCUITest harness). What is still missing is KVO `readyToPlay` re-seek delivery and playback against real media, which would need a UI/integration harness. Window resize, save panel, clipboard, and scrubbing tests also remain open.

### 9.2 Medium Priority

3. ~~**Triage the runtime performance warnings.**~~ — **RESOLVED (2026-09-29, PR #65 / `011aff7`).** The reports originated in `libRPAC.dylib`, not `libMainThreadChecker.dylib`. With `PERFC_ENABLE_DUPLICATE_DETECTION=0`, 55 reports were reproduced in an approximately 220 ms burst; PID correlation identified the three fixture-generating test processes and the shared cause: `DispatchQueue.global().sync` blocked the main actor during synchronous `AVAssetWriter` fixture encoding. Moving fixture generation to detached utility tasks reduced the A/B measurement from 55 reports to 0.
4. ~~**Unify date formatter usage** between `LoggingSystem` and `DateFormatter+Factory.swift.**~~ — **RESOLVED (PR #38 / L-02).** `LoggingSystem` already calls the shared `DateFormatter.logFormatter`; the thread-local cache is intentional.
5. ~~**Expand performance tests** to cover TimelineView rendering and MovieMutator operations, using non-gating measurements that do not introduce CI timing thresholds.~~ — **DONE (T-20, October 2, 2026, `feature/t20-performance-baseline-plan`).** `PerformanceTests.swift` gained four non-gating baselines (`testTimelineViewMarkerRenderBaseline`, `testMovieMutatorMovieClipBaseline`, `testMovieMutatorDeleteSelectionBaseline`, `testMovieMutatorApplyClapPaspBaseline`) that measure the real `TimelineView` `updateTimeline` + `layout` + layer commit path and the real `MovieMutator` clip/delete/transform operations with `XCTClockMetric` + `XCTMemoryMetric`; the values are recorded in the test output / result bundle with no CI timing thresholds (M-22 lesson), and the suite grew from 280 to 284 test methods. Paste/cut baselines remain out of scope (shared `NSPasteboard` state; see §8.5 and the T-20 plan `_plans/t-20_performance_baseline_plan.md`).

### 9.3 Low Priority

6. ~~**Add documentation comments** to public APIs in `Utilities/` that lack them.~~ — **NOT APPLICABLE (2026-09-29).** All 10 public declarations found in `Utilities/` already have documentation comments; the remaining declarations are internal to the application module.

---

## 10. Conclusion

The cutter2 codebase has a layered architecture, explicit concurrency settings, and 320 test methods across 23 test source files plus one helper. Strict concurrency (`complete`) and warnings-as-errors are enabled across all build configurations. Revision 5's 0.8.20 verification (269/269) is historical. On the current `work` branch after PR #73 (`e5dc551`), clean build, clean analyze, and `build-for-testing` succeeded and the full test run passed 320/320 with 0 failures and 0 skips. The current xcresult contains no runtime warnings. The consolidation reduces the Swift source inventory from 69 to 63 files without changing the public API or runtime behavior.

The project has 0 recorded release blockers. PR #73 on `work` (`e5dc551`) fixes the test QoS priority-inversion warning, and the release drops the beta suffix from the marketing version (0.8.21, build 20261022). The 2026-10-22 verification on Xcode 27.2 passed all 320 tests (0 failures, 0 skips), and the xcresult records no runtime warnings. The release-blocker fixes, T-19/T-20 coverage additions, PR #65 runtime-warning triage, and subsequent test-count progression described in revision 5 remain historical context. Current known coverage gaps are KVO `readyToPlay` re-seek, real-media playback, window resize, save panel, clipboard serialization, and scrubbing (§5.3, §8.6).

---

## 11. Files Reviewed

### Source Files (63 files)
- Application: `AppDelegate.swift`, `BookmarkStore.swift`, `DocumentController.swift`
- Document: `Document.swift` + 9 extensions (conformance to `ViewControllerDelegate` declared in the class body; `Document+ViewControllerDelegate.swift` and `Document+TimelineUpdateDelegate.swift` hold the delegate method implementations; `performAsync` is in `Document+FileIO.swift`, `afterSheetContinue` in `Document+SheetControl.swift`, `cleanup()` in `Document+Observers.swift`, `inspectorDictionary()` in `Document+UI.swift`) and `PlayerSeekSequencer.swift`
- Models: `MovieMutator.swift` (subclass of MovieMutatorBase; includes clipboard helpers and `makePlayerItem()`), `MovieMutatorBase.swift` + 4 extensions (`+FormatDescriptions`, `+Formatting`, `+PresentationInfo`, `+Progress`), `MovieMutator+Edit.swift`, `MovieMutator+Transform.swift`, `MovieMutator+Export.swift`, `MovieMutator+Inspector.swift`, `MovieMutatorTypes.swift`, `MovieWriter.swift` + 3 extensions (`+CustomExport`, `+ExportSession`, `+WriteMovie`), `VideoChannelMetadataBuilder.swift`, `SampleBufferChannel.swift`, `Notifications.swift`, `ProgressSink.swift`, `AVMutableMovie+Extensions.swift`
- ViewControllers: `ViewController.swift` + 5 extensions, `CAPARViewController.swift`, `TranscodeViewController.swift`, `WindowController.swift`, `AccessoryViewController.swift`, `InspectorViewController.swift`
- Views: `TimelineView.swift` + 3 extensions, `MyPlayerView.swift`, `Window.swift`
- Utilities: `ConcurrencyBridge.swift` (`AsyncBridge`, `PerformAsyncError`, `ActorUtilities`), `LayoutConverter.swift` + 3 extensions (`+Convert`, `+LayoutData`, `+Mapping`), `MovieHeaderValidator.swift`, `PerformanceMetrics.swift`, `ErrorUtilities.swift`, `Constants.swift`, `LocalizationHelper.swift`, `LoggingSystem.swift`, `DateFormatter+Factory.swift`
- Resources: `Info.plist`, `cutter2.entitlements`, `Localizable.xcstrings` (hand-curated app strings), `Base.lproj/Main.storyboard` (main UI), `mul.lproj/Main.xcstrings` (storyboard-extracted strings), `Assets.xcassets` (app icon)

### Test Files (24 files: 23 test source files + 1 helper; 320 test methods)
- `AsyncBridgeTests.swift` (4 tests), `cutter2Tests.swift` (20 tests), `DocumentKVOContextTests.swift` (3 tests), `DocumentReloadSeekIntegrationTests.swift` (5 tests), `DocumentTests.swift` (16 tests)
- `LayoutConverterMappingTests.swift` (7 tests), `LocalizationTests.swift` (11 tests), `LoggingSystemTests.swift` (17 tests), `ModelTests.swift` (26 tests)
- `MovieHeaderValidatorTests.swift` (9 tests), `MovieMutatorEditTests.swift` (11 tests), `MovieMutatorTests.swift` (22 tests), `MovieMutatorTransformExportTests.swift` (10 tests), `MovieWriterCustomProgressTests.swift` (15 tests)
- `SecurityScopedBookmarkTests.swift` (12 tests), `MovieWriterVideoChannelMetadataTests.swift` (25 tests), `MovieWriterWriteTests.swift` (3 tests), `PerformanceTests.swift` (16 tests), `PlayerSeekSequencerTests.swift` (19 tests), `TimelineViewRenderingTests.swift` (18 tests)
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
- `cutter2.xcodeproj/project.pbxproj` (version 0.8.21 / build 20261022 — app target, committed in the project; the test target carries placeholder `1.0` / `1`)
- `.github/workflows/test.yml` (build/test/analyze, branches `main`/`work`/`develop`; coverage artifact generation is optional)
- `scripts/test.sh` (build/test/analyze; summary reports 23 test source files + 1 helper and 320 tests)

### Revision History
- **Revision 6 (2026-10-17):** Rebased the current-state summary on `refactor/consolidate-small-files` (`cee7d28`); synchronized current test/build verification and runtime-warning status; corrected the source organization, bridge call paths, and crash-site references for the file consolidation. Revision 5's release baseline and historical test runs remain recorded above.
- **Revision 7 (2026-10-22):** Rebaselined on `work` for the 0.8.21 release (`e5dc551`); replaced the beta marketing version with 0.8.21 / build 20261022; re-verified on Xcode 27.2 (clean build, clean analyze, `build-for-testing`, and 320/320 tests with no runtime warnings recorded). Revision 6's consolidation baseline and the historical test runs remain recorded above.
