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

**Status**: ✅ Document.swift refactoring completed  
**Next Action**: Proceed to MovieMutator.swift refactoring

---

# Code Refactoring Plan - MovieMutator.swift

**Date**: October 13, 2025  
**Target**: Phase 1.2 - Code Refactoring (Week 1-2)  
**Goal**: Split MovieMutator.swift into logical, maintainable extensions

---

## Current State Analysis

### File Structure Overview

```
cutter2/Models/
├── MovieMutator.swift           1,000 lines  (Main class + multiple extensions)
├── MovieMutatorBase.swift         ~500 lines  (Base class)
├── MovieWriter.swift              ~400 lines  (Export/Write operations)
└── SampleBufferChannel.swift      ~300 lines  (Sample buffer handling)
```

### MovieMutator.swift Section Breakdown

| Start | End  | Lines | Section Name                        | Category          |
|-------|------|-------|-------------------------------------|-------------------|
| 1     | 18   | 18    | Imports & PasteboardType extension | Setup             |
| 19    | 47   | 29    | UndoManagerWrapper class           | Utilities         |
| 48    | 67   | 20    | performSyncOnMainActor extension   | Actor Isolation   |
| 68    | 74   | 7     | Class declaration comment          | Core              |
| 75    | 133  | 59    | private movieClip method           | Clip Operations   |
| 134   | 171  | 38    | private PasteBoard methods         | Clipboard         |
| 172   | 188  | 17    | public PasteBoard methods          | Clipboard         |
| 189   | 290  | 102   | private remove/insert clip methods | Edit Operations   |
| 291   | 419  | 129   | public edit action methods         | Edit Operations   |
| 420   | 481  | 62    | private clap/pasp methods          | Transform         |
| 482   | 636  | 155   | public clap/pasp methods           | Transform         |
| 637   | 899  | 263   | Inspector utilities extension      | Inspector         |
| 900   | 934  | 35    | AVPlayer support extension         | Player            |
| 935   | 1000 | 66    | export/write support extension     | Export            |

**Total**: 1,000 lines

### Category Grouping

1. **Core Setup** (47 lines)
   - Imports (18 lines)
   - UndoManagerWrapper class (29 lines)

2. **Actor Isolation** (27 lines)
   - performSyncOnMainActor extension (20 lines)
   - Class declaration (7 lines)

3. **Clipboard Operations** (55 lines)
   - private PasteBoard methods (38 lines)
   - public PasteBoard methods (17 lines)

4. **Edit Operations** (290 lines)
   - movieClip method (59 lines)
   - private remove/insert methods (102 lines)
   - public edit action methods (129 lines)

5. **Transform Operations** (217 lines)
   - private clap/pasp methods (62 lines)
   - public clap/pasp methods (155 lines)

6. **Inspector Utilities** (263 lines)
   - Inspector extension on MovieMutatorBase

7. **Player Support** (35 lines)
   - AVPlayer support extension

8. **Export Support** (66 lines)
   - export/write support extension

---

## Refactoring Strategy

### Proposed File Structure

```
cutter2/Models/
├── MovieMutator.swift                 ~100 lines  (Core class + Actor utilities)
│   ├── Imports
│   ├── UndoManagerWrapper class
│   ├── Actor isolation extension
│   └── Class declaration
│
├── MovieMutator+Clipboard.swift       ~60 lines   (NEW)
│   ├── private PasteBoard methods
│   └── public PasteBoard methods
│
├── MovieMutator+Edit.swift            ~350 lines  (NEW)
│   ├── private movieClip method
│   ├── private remove/insert methods
│   └── public edit action methods
│
├── MovieMutator+Transform.swift       ~220 lines  (NEW)
│   ├── private clap/pasp methods
│   └── public clap/pasp methods
│
├── MovieMutator+Inspector.swift       ~270 lines  (NEW)
│   └── Inspector utilities extension
│
├── MovieMutator+Player.swift          ~40 lines   (NEW)
│   └── AVPlayer support extension
│
├── MovieMutator+Export.swift          ~70 lines   (NEW)
│   └── export/write support extension
│
├── MovieMutatorBase.swift              ~500 lines  (EXISTING - Keep as is)
├── MovieWriter.swift                   ~400 lines  (EXISTING - Keep as is)
└── SampleBufferChannel.swift           ~300 lines  (EXISTING - Keep as is)
```

**After Refactoring Total**: ~1,110 lines (slight increase due to file headers)

---

## Detailed Refactoring Plan

### Step 1: Create MovieMutator+Clipboard.swift

**Purpose**: Consolidate all clipboard/pasteboard operations

**Content to Extract** (lines 134-188, ~55 lines):
- private PasteBoard methods (lines 134-171)
- public PasteBoard methods (lines 172-188)

**Dependencies**:
- Uses `internalMovie` property
- Uses `validateRange()` method
- NSPasteboard framework

**Benefits**:
- Clear separation of clipboard logic
- Easy to extend with new clipboard formats
- Reduces main MovieMutator.swift

---

### Step 2: Create MovieMutator+Edit.swift

**Purpose**: Handle all movie editing operations (cut, copy, paste, delete)

**Content to Extract** (lines 75-419, ~345 lines):
- private movieClip method (lines 75-133)
- private remove/insert clip methods (lines 189-290)
- public edit action methods (lines 291-419)

**Dependencies**:
- Uses `internalMovie` property
- Uses `undoManagerWrapper` property
- Uses clipboard operations (from Step 1)
- CMTimeRange validation

**Benefits**:
- Groups all editing logic together
- Easier to add new editing operations
- Clear separation from transform operations

---

### Step 3: Create MovieMutator+Transform.swift

**Purpose**: Handle video transform operations (clap, pasp)

**Content to Extract** (lines 420-636, ~217 lines):
- private clap/pasp methods (lines 420-481)
- public clap/pasp methods (lines 482-636)

**Dependencies**:
- Uses `internalMovie` property
- Uses `undoManagerWrapper` property
- CoreMedia framework for transform data

**Benefits**:
- Isolates complex transform logic
- Easy to add new transform types
- Clear API for transform operations

---

### Step 4: Create MovieMutator+Inspector.swift

**Purpose**: Provide inspector/introspection utilities

**Content to Extract** (lines 637-899, ~263 lines):
- Inspector utilities extension
- Media data paths
- Track information
- Codec information

**Dependencies**:
- Extends `MovieMutatorBase`
- Uses `internalMovie` property
- AVFoundation inspection APIs

**Benefits**:
- Groups all inspection/metadata logic
- Easy to add new inspector features
- Clear separation from editing operations

---

### Step 5: Create MovieMutator+Player.swift

**Purpose**: AVPlayer support and playback utilities

**Content to Extract** (lines 900-934, ~35 lines):
- AVPlayer support extension
- makePlayerItem method
- playback-related utilities

**Dependencies**:
- Uses `internalMovie` property
- AVKit framework

**Benefits**:
- Isolates player-specific logic
- Easy to extend playback features
- Small, focused extension

---

### Step 6: Create MovieMutator+Export.swift

**Purpose**: Export and write support

**Content to Extract** (lines 935-1000, ~66 lines):
- export/write support extension
- MovieWriter integration
- Export/transcode operations

**Dependencies**:
- Uses `MovieWriter` class
- Uses progress callbacks
- Async operations

**Benefits**:
- Groups export functionality
- Easy to add new export formats
- Clear separation from editing

---

### Step 7: Cleanup MovieMutator.swift

**Final MovieMutator.swift Content** (~100 lines):
- Imports (18 lines)
- NSPasteboard.PasteboardType extension (3 lines)
- UndoManagerWrapper class (29 lines)
- performSyncOnMainActor extension (20 lines)
- MovieMutator class declaration (7 lines)
- Essential initialization and setup (~23 lines)

**All other functionality**: Moved to extensions

---

## Implementation Order

### Day 1
1. ✅ Analyze current structure (DONE)
2. Create `MovieMutator+Clipboard.swift`
3. Test clipboard operations

### Day 2
4. Create `MovieMutator+Edit.swift`
5. Test editing operations (cut, copy, paste, delete)

### Day 3
6. Create `MovieMutator+Transform.swift`
7. Test transform operations (clap, pasp)

### Day 4
8. Create `MovieMutator+Inspector.swift`
9. Create `MovieMutator+Player.swift`
10. Test inspector and player features

### Day 5
11. Create `MovieMutator+Export.swift`
12. Final cleanup of MovieMutator.swift
13. Run full test suite
14. Update documentation

---

## Testing Strategy

### After Each Refactoring Step

1. **Compilation Check**
   ```bash
   xcodebuild build -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS'
   ```

2. **Functionality Test**
   - Open a movie file
   - Cut/Copy/Paste operations
   - Edit operations
   - Transform operations
   - Inspector features
   - Playback
   - Export

3. **Run Unit Tests**
   ```bash
   xcodebuild test -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS'
   ```

---

## Risk Assessment

### Low Risk
- ✅ Pure code movement (no logic changes)
- ✅ Swift extensions maintain same access to class members
- ✅ Existing tests will catch any issues

### Medium Risk
- ⚠️ Inter-extension dependencies need careful management
- ⚠️ Actor isolation must be preserved (@MainActor)
- ⚠️ Import statements need careful organization

### Mitigation
- Test after each file extraction
- Keep git commits small and focused
- Use feature branch for safety
- Run tests frequently

---

## Success Criteria

1. ✅ MovieMutator.swift reduced from 1,000 to ~100 lines
2. ✅ Clear separation of concerns (Clipboard, Edit, Transform, Inspector, Player, Export)
3. ✅ All tests pass
4. ✅ No functionality regression
5. ✅ Code is more maintainable
6. ✅ Easier to write future tests

---

## Dependencies Analysis

### MovieMutator Dependencies

**Internal Properties Used**:
- `internalMovie: AVMutableMovie`
- `undoManagerWrapper: UndoManagerWrapper`
- `currentMovieWriter: MovieWriter?`
- `updateProgress: ((Double) -> Void)?`
- `unblockUserInteraction: (() -> Void)?`

**External Dependencies**:
- `AVFoundation` framework
- `Cocoa` framework
- `MovieMutatorBase` base class
- `MovieWriter` class
- `UndoManagerWrapper` utility

**Protocol Conformances**:
- Inherits from `MovieMutatorBase`

---

## Notes

- All extensions use `extension MovieMutator` syntax
- Inspector extension uses `extension MovieMutatorBase`
- All extensions maintain `@MainActor` isolation
- Import statements duplicated in each file for clarity
- File headers follow existing project conventions
- MARK comments preserved for navigation
- UndoManagerWrapper and actor utilities remain in core file

---

**Status**: Ready to begin implementation  
**Next Action**: Create MovieMutator+Clipboard.swift
