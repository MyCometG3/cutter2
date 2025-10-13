# Code Refactoring Plan - Document.swift

**Date**: October 13, 2025  
**Target**: Phase 1.2 - Code Refactoring (Week 1-2)  
**Goal**: Split Document.swift into logical, maintainable extensions

---

## Current State Analysis

### File Structure Overview

```
cutter2/Document/
├── Document.swift              1,107 lines  (Main class + core functionality)
├── Document+Delegate.swift       688 lines  (ViewControllerDelegate, TimelineUpdateDelegate)
└── Document+Utilities.swift      811 lines  (Actor isolation, Sheet control, Observers, etc.)
────────────────────────────────────────────
Total:                          2,606 lines
```

### Document.swift Section Breakdown

| Start | End  | Lines | Section Name                      | Category      |
|-------|------|-------|-----------------------------------|---------------|
| 14    | 73   | 59    | DocumentError                     | Error Def     |
| 74    | 80   | 6     | Class Declaration                 | Core          |
| 81    | 131  | 50    | Public properties                 | Core          |
| 132   | 157  | 25    | Private properties                | Core          |
| 158   | 291  | 133   | NSDocument methods/properties     | Core          |
| 292   | 305  | 13    | Revert                           | File I/O      |
| 306   | 374  | 68    | Read                             | File I/O      |
| 375   | 656  | 281   | Write                            | File I/O      |
| 657   | 731  | 74    | Save panel                       | UI/Panel      |
| 732   | 782  | 50    | NSOpenSavePanelDelegate protocol | UI/Panel      |
| 783   | 794  | 11    | AccessoryViewDelegate protocol   | UI/Panel      |
| 795   | 954  | 159   | Export/Transcode                 | Export        |
| 955   | 1066 | 111   | Resize window                    | UI/Window     |
| 1067  | 1107 | 40    | modify clap/pasp                 | Transform     |

**Total**: 1,107 lines

### Category Grouping

1. **Core** (214 lines)
   - DocumentError enum (59 lines)
   - Class declaration (6 lines)
   - Public properties (50 lines)
   - Private properties (25 lines)
   - NSDocument methods/properties (133 lines)

2. **File I/O** (362 lines)
   - Revert (13 lines)
   - Read operations (68 lines)
   - Write operations (281 lines)

3. **UI/Panel** (135 lines)
   - Save panel (74 lines)
   - NSOpenSavePanelDelegate protocol (50 lines)
   - AccessoryViewDelegate protocol (11 lines)

4. **Export** (159 lines)
   - Export/Transcode operations

5. **UI/Window** (111 lines)
   - Resize window operations

6. **Transform** (40 lines)
   - modify clap/pasp

---

## Refactoring Strategy

### Proposed File Structure

```
cutter2/Document/
├── Document.swift                    ~300 lines  (Core class definition only)
│   ├── DocumentError enum
│   ├── Class declaration
│   ├── Public properties
│   ├── Private properties
│   └── Essential NSDocument overrides
│
├── Document+FileIO.swift             ~400 lines  (NEW)
│   ├── Revert operations
│   ├── Read operations
│   └── Write operations
│
├── Document+SavePanel.swift          ~140 lines  (NEW)
│   ├── Save panel configuration
│   ├── NSOpenSavePanelDelegate protocol
│   └── AccessoryViewDelegate protocol
│
├── Document+Export.swift             ~160 lines  (NEW)
│   └── Export/Transcode operations
│
├── Document+UI.swift                 ~150 lines  (NEW)
│   ├── Resize window operations
│   └── Transform operations (clap/pasp)
│
├── Document+Delegate.swift           688 lines  (EXISTING - Keep as is)
│   ├── ViewControllerDelegate protocol
│   └── TimelineUpdateDelegate protocol
│
└── Document+Utilities.swift          811 lines  (EXISTING - Keep as is)
    ├── Actor isolation utilities
    ├── Sheet control
    ├── Observers
    └── Position control
```

**After Refactoring Total**: ~2,649 lines (slight increase due to file headers)

---

## Detailed Refactoring Plan

### Step 1: Create Document+FileIO.swift

**Purpose**: Consolidate all file I/O operations (read, write, revert)

**Content to Extract** (lines 292-656, ~365 lines):
- Revert operations (lines 292-305)
- Read operations (lines 306-374)
- Write operations (lines 375-656)

**Dependencies**:
- Uses `movieMutator` property
- Uses `undoManagerWrapper` property
- Uses `fileURL` property
- Calls error handling utilities

**Benefits**:
- Clear separation of file I/O concerns
- Easier to test file operations
- Reduces main Document.swift to ~742 lines

---

### Step 2: Create Document+SavePanel.swift

**Purpose**: Handle save panel UI and configuration

**Content to Extract** (lines 657-794, ~138 lines):
- Save panel configuration (lines 657-731)
- NSOpenSavePanelDelegate protocol (lines 732-782)
- AccessoryViewDelegate protocol (lines 783-794)

**Dependencies**:
- Uses save panel accessory views
- Implements delegate protocols

**Benefits**:
- Isolates UI panel logic
- Easy to modify save dialog behavior
- Reduces main Document.swift to ~604 lines

---

### Step 3: Create Document+Export.swift

**Purpose**: Handle all export and transcode operations

**Content to Extract** (lines 795-954, ~160 lines):
- Export/Transcode operations
- Progress tracking
- Export settings management

**Dependencies**:
- Uses `movieMutator` for export source
- Uses progress UI from Utilities
- Async operations

**Benefits**:
- Clear separation of export logic
- Easier to add new export formats
- Reduces main Document.swift to ~444 lines

---

### Step 4: Create Document+UI.swift

**Purpose**: UI-related operations (window resizing, transforms)

**Content to Extract** (lines 955-1107, ~152 lines):
- Resize window operations (lines 955-1066)
- modify clap/pasp operations (lines 1067-1107)

**Dependencies**:
- Uses `window` property
- Uses `movieMutator` for transformations
- Uses `undoManagerWrapper`

**Benefits**:
- Groups UI manipulation code
- Separates transform logic
- Final Document.swift: ~292 lines (core only)

---

### Step 5: Verify and Update Document.swift

**Final Document.swift Content** (~300 lines):
- DocumentError enum (59 lines)
- Class declaration with @MainActor (6 lines)
- Public properties (50 lines)
- Private properties (25 lines)
- Essential NSDocument overrides (133 lines)
  - `init()`
  - `makeWindowControllers()`
  - `canAsynchronouslyWrite(to:ofType:for:)`
  - `prepareSavePanel(_:)`
  - Basic lifecycle methods

**All other functionality**: Moved to extensions

---

## Implementation Order

### Week 1: Days 1-3
1. ✅ Analyze current structure (DONE)
2. Create `Document+FileIO.swift`
3. Move Read/Write/Revert operations
4. Test file operations (open, save, revert)

### Week 1: Days 4-5
5. Create `Document+SavePanel.swift`
6. Move save panel and delegate implementations
7. Test save dialog functionality

### Week 2: Days 1-2
8. Create `Document+Export.swift`
9. Move export/transcode operations
10. Test export functionality

### Week 2: Days 3-4
11. Create `Document+UI.swift`
12. Move window resize and transform operations
13. Test UI operations

### Week 2: Day 5
14. Final cleanup of Document.swift
15. Run full test suite
16. Update documentation
17. Commit refactored code

---

## Testing Strategy

### After Each Refactoring Step

1. **Compilation Check**
   ```bash
   xcodebuild build -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS'
   ```

2. **Functionality Test**
   - Open a movie file
   - Edit the movie
   - Save the movie
   - Export the movie
   - Test undo/redo
   - Verify UI operations

3. **Run Unit Tests**
   ```bash
   xcodebuild test -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS'
   ```

### Final Verification

- ✅ All tests pass
- ✅ No compiler warnings
- ✅ Code coverage maintained or improved
- ✅ No performance regression
- ✅ All features work as before

---

## Risk Assessment

### Low Risk
- ✅ Pure code movement (no logic changes)
- ✅ Swift extensions maintain same access to class members
- ✅ Existing tests will catch any issues

### Medium Risk
- ⚠️ Import statements need careful management
- ⚠️ Actor isolation must be preserved
- ⚠️ Async/await patterns must remain correct

### Mitigation
- Test after each file extraction
- Keep git commits small and focused
- Use feature branch for safety
- Run tests frequently

---

## Success Criteria

1. ✅ Document.swift reduced from 1,107 to ~300 lines
2. ✅ Clear separation of concerns
3. ✅ All tests pass
4. ✅ No functionality regression
5. ✅ Code is more maintainable
6. ✅ Easier to write future tests

---

## Dependencies Analysis

### Document.swift Dependencies

**Internal Properties Used**:
- `movieMutator: MovieMutator?`
- `undoManagerWrapper: UndoManagerWrapper`
- `fileURL: URL?`
- `window: Window?`
- `viewController: ViewController?`
- `player: AVPlayer?`

**External Dependencies**:
- `AVFoundation` framework
- `Cocoa` framework
- `MovieMutator` class
- `UndoManagerWrapper` utility
- `ErrorUtilities` utility

**Protocol Conformances**:
- `NSDocument` (base class)
- `NSOpenSavePanelDelegate` (save panel)
- `AccessoryViewDelegate` (custom delegate)
- `ViewControllerDelegate` (in Document+Delegate.swift)
- `TimelineUpdateDelegate` (in Document+Delegate.swift)

---

## Notes

- All extensions use `extension Document` syntax
- All extensions maintain `@MainActor` isolation where needed
- Import statements duplicated in each file for clarity
- File headers follow existing project conventions
- MARK comments preserved for navigation

---

**Status**: Ready to begin implementation  
**Next Action**: Create Document+FileIO.swift
