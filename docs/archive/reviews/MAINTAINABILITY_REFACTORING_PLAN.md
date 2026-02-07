# Maintainability Refactoring Plan (Detailed)

**Date**: February 7, 2026  
**Scope**: Project-level refactors focused on maintainability (no behavior changes)  
**Branching**: Perform each step in its own commit to keep history clean.

---

## Goals
- Reduce file size and cognitive load by splitting large files by responsibility.
- Keep behavior identical (no functional changes).
- Preserve public APIs and call sites; use file moves and extensions only.
- Keep Xcode project file in sync with new files.

## Non-Goals
- No feature additions or behavior changes.
- No dependency additions.
- No formatting-only churn beyond moved code.

---

## Step-by-Step Plan (Commit-Ready)

### Step 0: Prep & Baseline (Optional but Recommended)
**Work:**
- Record current build/test status (if needed).
- Confirm no uncommitted changes.

**Commit:** _No commit_ (or “chore: prep for refactor”).

---

### Step 1: Split `MovieWriter.swift` by responsibility
**Why:** Largest file with multiple subsystems; splitting improves navigation and reduces merge conflicts.

**Work:**
- Create files:
  - `MovieWriter+ExportSession.swift`
  - `MovieWriter+CustomExport.swift`
  - `MovieWriter+WriteMovie.swift`
- Move sections under matching MARK blocks into new files.
- Keep shared helpers in `MovieWriter.swift` or extract into a small helper struct if needed.
- Update Xcode project file to include new Swift files.

**Commit Message:** `refactor: split MovieWriter into focused extensions`

---

### Step 2: Decompose `Document+Utilities.swift`
**Why:** Currently a “misc” bucket with several unrelated sections.

**Work:**
- Create files:
  - `Document+ActorIsolation.swift`
  - `Document+SheetControl.swift`
  - `Document+Observers.swift`
  - `Document+PositionControl.swift`
  - `Document+MovieReference.swift`
- Move code to match existing MARK sections.
- Keep any shared helpers in the main Document utilities file or create a tiny shared helper if needed.
- Update Xcode project file.

**Commit Message:** `refactor: split Document utilities by concern`

---

### Step 3: Split `Document+Delegate.swift`
**Why:** Large delegate file increases navigation cost and merge conflicts.

**Work:**
- Create files:
  - `Document+ViewControllerDelegate.swift`
  - `Document+TimelineUpdateDelegate.swift`
- Move protocol implementations accordingly.
- Update Xcode project file.

**Commit Message:** `refactor: split Document delegates`

---

### Step 4: Split `TimelineView.swift`
**Why:** Mixes rendering, utilities, and input handling in one large file.

**Work:**
- Create files:
  - `TimelineView+Layers.swift`
  - `TimelineView+Input.swift` (mouse + keyboard)
  - `TimelineView+Utilities.swift`
- Move methods by MARK sections.
- Update Xcode project file.

**Commit Message:** `refactor: split TimelineView into layers/input/utilities`

---

### Step 5: Split `LayoutConverter.swift`
**Why:** Large utility file suggests multiple conversion domains.

**Work:**
- Identify coherent clusters (e.g., geometry vs media timing conversions).
- Create files such as:
  - `LayoutConverter+Geometry.swift`
  - `LayoutConverter+Timing.swift`
- Move methods accordingly.
- Update Xcode project file.

**Commit Message:** `refactor: split LayoutConverter by domain`

---

### Step 6: Centralize Movie Header Validation (Optional)
**Why:** Validation logic may appear in multiple locations; centralizing reduces duplication.

**Work:**
- Add `MovieHeaderValidator.swift` with:
  - `static func validate(movie: AVMutableMovie) throws`
- Replace duplicated validation checks with the helper.
- Keep errors and reasons consistent with `DocumentError` usage.
- Update Xcode project file.

**Commit Message:** `refactor: centralize movie header validation`

---

### Step 7: Final Verification
**Work:**
- Build and/or run existing test suite.
- Ensure no behavior changes or warnings introduced.

**Commit:** _No commit_ (test-only).

---

## Execution Notes
- Keep each refactor in one commit with only file moves/splits.
- Avoid renaming public symbols in the same commit; use pure extraction.
- After each step, confirm app compiles (at least incremental build).
- Update Xcode project membership for all new files.

