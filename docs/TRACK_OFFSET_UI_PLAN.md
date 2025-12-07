# Track Offset UI Implementation Plan

## Overview
This document describes how to add UI and model support for per-track timeline offsets (add / modify / remove) in `cutter2`, considering current architecture, undo support, and data integrity.

## Goals
- List every `AVMutableMovieTrack` with metadata needed for editing.
- Allow users to enter positive/negative offsets per track with validation and formatting assistance.
- Apply offsets while preserving referenced media, document undo/redo history, and UI consistency.
- Keep the plan aligned with existing storyboard-driven UI patterns and localization.

## Architecture

### 1. Model Layer (`MovieMutator`)
Create `cutter2/Models/MovieMutator+TrackOffset.swift` to encapsulate shifting logic.

**New Types/APIs**
- `struct TrackDescriptor { let id: CMPersistentTrackID; let mediaType: AVMediaType; let duration: CMTime; var currentOffset: CMTime }`
- `public func trackDescriptors() -> [TrackDescriptor]` (exposes ordered tracks; replace current `private orderedTracks()` usage where needed).
- `public func applyTrackOffsets(_ offsets: [CMPersistentTrackID: CMTime], undoManager: UndoManagerWrapper)`
    - Treats the input dictionary as a transaction: all offsets must validate or none are applied. Validation runs first for every track, then the mutation phase executes in a fixed order (video → audio → timecode → other) to keep timeline math deterministic.
    - For positive offsets: synthesize silence by calling `insertTimeRange(CMTimeRange(start: .zero, duration: offset), of: emptyClip, at: .zero, copySampleData: true)` where `emptyClip` is a cached silent reference track matching media type. Preferred over non-existent `insertEmptyTimeRange`.
    - For negative offsets: duplicate the removal range into an `AVMutableMovie` clip (`extractClip(for:trackID, range:)`) before calling `removeTimeRange`; this clip becomes part of the undo payload.
    - After the transactional edit succeeds, adjust movie-level duration if needed and call `internalMovieDidChange` exactly once.

**Undo/Redo Strategy**
- Mirror `MovieMutator+Edit`: capture `internalMovie.movHeader`, `selectedTimeRange`, `insertionTime`, and a serialized version of removed segments (per track offset) before mutation. Payload format: `[TrackOffsetUndoPayload(trackID, delta, removedClipData?)]` where `removedClipData` is the `.movHeader` of the extracted clip.
- Register inverse operations with `UndoManagerWrapper`. For referenced movies (`track.isSelfContained == false`), store extracted sample data to reinsert, preventing permanent loss.
- When offsets change the playhead context, shift `insertionTime` and `selectedTimeRange` by the same delta as the track currently containing the marker; if marker track is unknown fall back to clamping within movie range.

**Persistence**
- Track offsets are destructive edits. No separate metadata file is required, but document saving already writes the modified `AVMutableMovie`. Ensure inspector/timeline reflect the new state immediately via notification.

### 2. UI Layer (`TrackOffsetViewController`)
Follow existing storyboard-driven approach for coherence and localization.

**Storyboard**
- Add a new scene `TrackOffset Controller` (Utility panel) to `Main.storyboard`, similar to Inspector/Transcode sheets.
- UI Elements:
    - `NSTableView` with columns: Track ID, Media Type, Duration, Current Offset (read-only), New Offset (editable text field with formatter), Reference/Self-contained indicator.
    - Footer buttons: `Apply`, `Cancel`, and `Reset` (clears edits).
    - Optional status label showing validation errors.

**Controller Responsibilities**
- Fetch descriptors via `Document.movieMutator?.trackDescriptors()`.
- Provide `Formatter`/`ValueTransformer` converting between `CMTime` and strings. Supported syntax: `HH:MM:SS.mmm`, `SSS.s` (plain seconds), and `<number>f` for frame counts at the document timeScale. Regex priority: timecode (`^\d{1,2}:\d{2}:\d{2}(\.\d+)?$`) → frames (`^-?\d+f$`) → seconds (fallback). Reuse `shortTimeString` for display and add a new parser utility in the model layer.
- Validate in real time: highlight invalid entries (e.g., removing more seconds than available, NaN input).
- On Apply: build dictionary of deltas, call `applyTrackOffsets`, handle thrown errors via `Document.showErrorSheet`. When the model reports a validation failure, surface the offending track’s ID/media type in the alert so users can fix it quickly.
- `TrackDescriptor.currentOffset` is computed by scanning `track.segments` from the start, summing consecutive segments whose `timeMapping.source.duration == .zero`. The sum is cached per track while the document stays open; invalidated when `internalMovie` mutates.

**Menu Integration**
- Add “Track Offset…” under the **Configure** or **Edit** menu in `Main.storyboard` (preferred) or programmatically during app launch.
- Action flows: `Document` (first responder) → `@IBAction func showTrackOffsetPanel(_ sender: Any?)` → instantiate controller and present as sheet (consistent with CAPAR/Transcode). Ensure the menu item’s First Responder action is wired to `showTrackOffsetPanel:` so existing Responder Chain picks it up.

### 3. Data Flow
1. User chooses “Track Offset…”.
2. Document presents the Track Offset sheet (storyboard-instantiated controller).
3. Controller builds table rows from `trackDescriptors()` and zeroes a working dictionary for pending offsets.
4. User edits offsets; formatter converts strings → `CMTime`, updates pending values.
5. Apply button validates each offset, calls `applyTrackOffsets` on `MovieMutator`, and awaits completion (UI disabled during operation). Undo entries are registered inside the model call.
6. After success, controller dismisses sheet. `MovieMutator` posts `.movieWasMutated`; existing observers refresh Timeline/Player/Inspector automatically.
7. Inspector gains new fields (optional) by extending `Document.inspectorDictionary()` to include per-track offsets (future task).

## Implementation Steps

### Step 1: Model Enhancements
- Add `TrackDescriptor`, `trackDescriptors()`, and `applyTrackOffsets` APIs.
- Introduce a reusable `CMTimeParser` utility supporting timecode / seconds / frames and expose it to the controller.
- Handle positive/negative offsets with proper segment capture, especially for referenced tracks.
- Emit `.movieWasMutated` with updated insertion/selection values.
- Unit tests in `MovieMutatorTests` for:
    - Shifting self-contained and referenced tracks.
    - Undo/redo returning to original state.
    - Validation failures (too-large negative offsets, invalid CMTime).

### Step 2: UI + Storyboard
- Add `TrackOffsetViewController` scene, nib outlets, and localized strings (keys: `track.offset.title`, column headers `track.offset.column.trackID/mediaType/duration/current/new/reference`, button labels `apply/cancel/reset`, validation errors `offset.invalid`, `offset.exceedsDuration`, confirmation dialog `offset.removeEntireTrack`).
- Implement controller with `NSTableViewDataSource/Delegate`, formatters, and validation feedback.
- Hook up Apply/Cancel, using `Document` reference to call model layer.

### Step 3: Menu & Presentation
- Insert “Track Offset…” menu item in storyboard (Configure menu after clap/pasp is recommended) with action `showTrackOffsetPanel:` on First Responder.
- Implement `Document.showTrackOffsetPanel(_:)` to load the controller and run it as a sheet.
- Ensure sheet respects sandbox permissions (no new entitlements needed).

### Step 4: QA
- Manual tests on self-contained vs reference movies, multi-track scenarios, large offsets, and undo/redo.
- Cover boundary cases: negative offsets equal to entire track duration (requires explicit confirmation UI or warning), zero offsets, and mixed positive/negative applications in one batch.
- Verify inspector/timeline update sequence and playback after shifts.
- Confirm localization for new strings and ensure VoiceOver labels exist.

> **Dependency note:** Step 1 must land before Step 2 can hook up bindings; Step 2 & Step 3 may proceed in parallel once the parsing/validation APIs exist. Step 4 runs after all previous steps merge.

## Technical Considerations
- **Referenced Tracks:** Removing samples from reference movies can orphan media. Always duplicate the removed range into a temporary `AVMutableMovie` clip before deletion so undo can reinsert, similar to cut/delete. If extracted clip data exceeds a safety threshold (e.g., 250 MB), prompt the user before proceeding to avoid runaway memory use.
- **Concurrency:** All `applyTrackOffsets` calls run on `@MainActor`. Long operations should surface progress through existing busy-sheet infrastructure if needed.
- **Validation:** Clamp offsets to track duration; disallow sub-resolution adjustments smaller than `movieResolution()`, and prompt the user when an offset would remove an entire track so destructive edits are intentional.
- **Formatting:** Provide both timecode (`HH:MM:SS.FF`) and seconds input (auto-detected) to reduce user error.
- **Notifications:** After mutation, call `internalMovieDidChange` so timeline/player refresh as they already do for edit ops.

## Future Improvements
- Display per-track offsets in Inspector and Timeline overlays.
- Allow live preview (temporary shifts while scrubbing) once performance implications are understood.
- Persist preferred offset presets/user shortcuts for rapid alignment operations.
