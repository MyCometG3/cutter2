# Maintainability Refactoring Review (Project-Level)

**Date**: February 6, 2026  
**Scope**: Project-level static review (archive excluded)  
**Goal**: Identify refactoring ideas that improve long-term maintainability without changing behavior.

---

## Summary
The codebase is well structured with clear MARK sections, but a few large files concentrate multiple responsibilities. The top maintainability gains come from splitting these files by concern and extracting shared helpers for validation and parsing.

## Evidence (Largest Files by Line Count)
- `Models/MovieWriter.swift` (~1343 lines)
- `Models/MovieMutatorBase.swift` (~974 lines)
- `Document/Document+Utilities.swift` (~826 lines)
- `Views/TimelineView.swift` (~715 lines)
- `Utilities/LayoutConverter.swift` (~649 lines)
- `Document/Document+Delegate.swift` (~635 lines)

---

## Refactoring Opportunities (Prioritized)

### 1) Split MovieWriter by responsibility (High Impact)
**Why:** Multiple subsystems live in one file (export session, custom export, write movie). This increases cognitive load and makes targeted changes harder.

**Proposal:**
- `MovieWriter+ExportSession.swift`
- `MovieWriter+CustomExport.swift`
- `MovieWriter+WriteMovie.swift`
- Extract shared progress/result logging into a small helper to avoid duplication.

### 2) Decompose Document+Utilities (High Impact)
**Why:** It contains multiple unrelated sections (actor isolation, sheet control, observers, position control, movie reference utilities). This is effectively a “misc” bucket.

**Proposal:** Split into focused files that match existing MARK sections:
- `Document+ActorIsolation.swift`
- `Document+SheetControl.swift`
- `Document+Observers.swift`
- `Document+PositionControl.swift`
- `Document+MovieReference.swift`

### 3) Split Document+Delegate by protocol or feature (Medium Impact)
**Why:** Large delegate file makes it hard to find related actions and increases merge conflicts.

**Proposal:**
- `Document+ViewControllerDelegate.swift`
- `Document+TimelineUpdateDelegate.swift`
- Optional: group editing actions into `Document+EditActions.swift` for clarity.

### 4) Extract Movie Header Parsing/Validation (Medium Impact)
**Why:** Header parsing and validation is scattered (DocumentController vs Document). Centralizing reduces duplication and clarifies “what is a valid movie.”

**Proposal:**
- Create `MovieHeaderValidator` (utility) with methods like `validate(movie:)` and `validate(headerData:)`.
- Use it in `prepareOpen(for:)` and `readAsync` to keep checks consistent.

### 5) Split TimelineView into rendering vs input (Medium Impact)
**Why:** TimelineView mixes rendering, layer setup, utilities, mouse, and keyboard handling.

**Proposal:**
- `TimelineView+Layers.swift`
- `TimelineView+Input.swift` (mouse/keyboard)
- `TimelineView+Utilities.swift`

### 6) Break up LayoutConverter (Low–Medium Impact)
**Why:** Single large utility file suggests multiple conversion responsibilities.

**Proposal:**
- Split by domain (e.g., geometry conversions vs media timing conversions) or by use site.

---

## Suggested Next Steps
1. Start with `MovieWriter.swift` and `Document+Utilities.swift` because they are large and frequently touched.
2. Add a `MovieHeaderValidator` for consistency of open flow validations.
3. Apply view/controller splits as follow-up (TimelineView, Document+Delegate).

---

## Non-Goals
- No behavioral changes or API changes.
- No dependency additions.

