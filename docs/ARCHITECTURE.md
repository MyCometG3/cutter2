# cutter2 Architecture

**Last Updated**: February 5, 2026  
**Status**: ✅ Active and Maintained

---

## Table of Contents

1. [Overview](#overview)
2. [Architectural Patterns](#architectural-patterns)
3. [Layer Architecture](#layer-architecture)
4. [Component Details](#component-details)
5. [Data Flow](#data-flow)
6. [Concurrency Model](#concurrency-model)
7. [File Organization](#file-organization)

---

## Overview

cutter2 is a document-based macOS video editing application built with Swift and AVFoundation. It follows Apple's recommended architectural patterns for macOS applications while maintaining a clean separation of concerns through a layered architecture.

### Key Characteristics

- **Framework**: AVFoundation (native macOS)
- **UI Framework**: Cocoa/AppKit
- **Language**: Swift 6.2.1
- **Concurrency**: Swift Concurrency (async/await, actors, AsyncStream)
- **Architecture**: Document-based, MVC pattern with protocol-oriented design
- **Platform**: macOS 11.0+, Universal Binary (x86_64 + arm64)

---

## Architectural Patterns

### 1. Document-Based Architecture

cutter2 uses Apple's `NSDocument` architecture:

```
NSDocumentController
    └── Document (NSDocument)
            ├── WindowController (NSWindowController)
            └── ViewController (NSViewController)
```

**Benefits**:
- Automatic multi-document support
- Built-in file management
- Undo/Redo support
- Auto-save coordination (intentionally disabled for user control)

### 2. Model-View-Controller (MVC)

- **Model**: `MovieMutator`, `MovieMutatorBase`, `MovieWriter`, `SampleBufferChannel`
- **View**: `MyPlayerView`, `TimelineView`, Storyboard-defined UI
- **Controller**: `Document`, `ViewController`, `WindowController`, `InspectorViewController`

### 3. Delegate Pattern

Extensive use of delegates for component communication:

- `ViewControllerDelegate` - Document ↔ ViewController communication
- `TimelineUpdateDelegate` - Timeline ↔ ViewController communication
- Protocol-based design enables loose coupling and testability

### 4. Protocol-Oriented Design

Swift protocols define clear contracts between components:

```swift
protocol ViewControllerDelegate: AnyObject {
    func playerItem() -> AVPlayerItem?
    func currentTime() -> CMTime
    func requestUpdateGUI()
    // ... more methods
}
```

---

## Layer Architecture

### Layer 1: Application Layer

**Purpose**: Application lifecycle, document management, coordination

**Components**:
- `AppDelegate.swift` - Application initialization and global coordination
- `DocumentController.swift` - Document management and creation

**Responsibilities**:
- Launch configuration
- Document creation/opening
- Global preferences
- Menu validation

### Layer 2: Document Layer

**Purpose**: Document lifecycle, file I/O, window management

**Main File**: `Document.swift` (core)

**Extensions**:
- `Document+FileIO.swift` - Read, write, revert operations
- `Document+SavePanel.swift` - Save panel UI and configuration
- `Document+Export.swift` - Export and transcode operations
- `Document+UI.swift` - Window resizing and video transforms
- `Document+Delegate.swift` - ViewControllerDelegate implementation

**Responsibilities**:
- File loading and saving (async operations)
- Security-scoped bookmarks (sandbox)
- Export coordination
- Window lifecycle
- Undo/Redo management via `UndoManagerWrapper`

### Layer 3: Model Layer

**Purpose**: Video editing logic, movie manipulation, export

**Core Components**:

1. **MovieMutator** (~100 lines core + 6 extensions)
   - Core editing operations
   - Extensions: Clipboard, Edit, Transform, Inspector, Player, Export

2. **MovieMutatorBase** (~500 lines)
   - Base functionality for movie manipulation
   - AVFoundation integration
   - Track management

3. **MovieWriter** (~400 lines)
   - Video export and transcoding
   - Custom export settings
   - Progress tracking

4. **SampleBufferChannel** (~300 lines)
   - Low-level media sample handling
   - Audio/Video channel processing

**Responsibilities**:
- Movie editing (cut, copy, paste, delete)
- Video transforms (clean aperture, pixel aspect ratio)
- Export with multiple codecs (H.264, HEVC, ProRes)
- Audio processing (AAC, LPCM)
- Clipboard operations

### Layer 4: View Controller Layer

**Purpose**: UI logic, user interaction, playback control

**Main Controllers**:

1. **ViewController** (179 lines core + 5 extensions)
   - Primary UI controller
   - Extensions: Observer, KeyEvent, KeyboardAction, Edit, Timeline
   - Keyboard shortcuts (JKL mode, Step mode)

2. **WindowController** (~200 lines)
   - Window management
   - Toolbar coordination
   - Inspector panel control

3. **InspectorViewController** (~300 lines)
   - Video/audio metadata display
   - Track information
   - Format details

4. **ExportAccessoryViewController** (~150 lines)
   - Export settings UI
   - Codec selection
   - Quality options

**Responsibilities**:
- User input handling
- Video playback control
- Timeline manipulation
- Menu command routing
- Observer pattern for preferences

### Layer 5: View Layer

**Purpose**: Custom UI components, video display, timeline

**Custom Views**:

1. **MyPlayerView** (extends `AVPlayerView`)
   - Video playback display
   - Player controls customization
   - Playback notifications

2. **TimelineView** (~400 lines)
   - Visual timeline representation
   - Marker dragging (current position, in/out points)
   - Selection visualization
   - Mouse/keyboard interaction

**Responsibilities**:
- Custom drawing
- User interaction capture
- Visual feedback
- Accessibility support

### Layer 6: Utilities Layer

**Purpose**: Cross-cutting concerns, helper functions

**Components**:

1. **ErrorUtilities.swift**
   - Centralized error handling
   - User-friendly error messages
   - NSError conversion

2. **ActorUtilities.swift**
   - Main actor synchronization helpers
   - Thread-safe UI updates

3. **Constants.swift**
   - Application-wide constants
   - User defaults keys
   - Notification names

4. **LocalizationHelper.swift** ✨ **NEW (Phase 2.1)**
   - String localization utilities
   - Formatting helpers (percentage, file size, time)
   - Common UI string constants
   - String Catalog integration

5. **Document+Utilities.swift** (811 lines)
   - Actor isolation helpers
   - Sheet control (progress, alerts)
   - Observer management
   - Position control utilities

### Layer 7: Localization Layer ✨ **NEW (Phase 2.1)**

**Purpose**: Internationalization and multi-language support

**Components**:

1. **Localizable.xcstrings** (String Catalog)
   - Localized strings for English and Japanese
   - Error messages, UI labels, menu items, inspector labels, progress messages

2. **LocalizationHelper.swift**
   - Centralized localization API
   - Type-safe string access
   - Formatting utilities

**Supported Languages**:
- English (base language)
- Japanese (日本語)

**Coverage**:
- All error messages
- All UI buttons and labels
- All menu items
- Inspector labels
- Progress and alert messages

---

## Component Details

### Document Component

**File Structure**:
```
Document.swift                  (Core)
├── Error Definitions           (DocumentError enum)
├── Properties                  (movieMutator, player, etc.)
└── NSDocument Overrides        (lifecycle methods)

Document+FileIO.swift
├── readAsync(from:openPreparation:) (async file loading)
├── writeAsync()                (async file saving)
└── revert()                    (reload from disk)

Document+SavePanel.swift
├── prepareSavePanel()          (save dialog setup)
└── NSOpenSavePanelDelegate     (accessory view handling)

Document+Export.swift
├── exportMovie()               (export with progress)
└── transcodeMovie()            (codec conversion)

Document+UI.swift
├── resizeWindow()              (window sizing)
└── modifyTransform()           (clap/pasp adjustments)
```

**Key Design Decisions**:

1. **Async/Await for I/O**: All file operations use Swift concurrency
2. **Security-Scoped Bookmarks**: Enable file access in sandbox
3. **No Auto-Save**: Explicit user control over save operations
4. **Undo Support**: Via `UndoManagerWrapper` for complex operations

### MovieMutator Component

**Architecture**:
```
MovieMutatorBase               ~500 lines
    └── MovieMutator           ~100 lines (core)
            ├── Clipboard      ~60 lines
            ├── Edit           ~350 lines
            ├── Transform      ~220 lines
            ├── Inspector      ~270 lines
            ├── Player         ~40 lines
            └── Export         ~70 lines
```

**Core Responsibilities**:

1. **Editing Operations** (`MovieMutator+Edit.swift`)
   - `cut(from:to:)` - Remove selection, copy to clipboard
   - `copy(from:to:)` - Copy selection to clipboard
   - `paste(at:)` - Insert clipboard content
   - `delete(from:to:)` - Remove selection without clipboard

2. **Transform Operations** (`MovieMutator+Transform.swift`)
   - `modifyCleanAperture()` - Adjust visible area
   - `modifyPixelAspectRatio()` - Change pixel aspect
   - Non-destructive video transformations

3. **Export Operations** (`MovieMutator+Export.swift`)
   - Multiple codec support (H.264, HEVC, ProRes variants)
   - Audio format options (AAC, LPCM 16/24/32-bit)
   - Progress callbacks
   - Cancellation support

**Key Design Decisions**:

1. **CMTime Precision**: All timing uses `CMTime` for frame accuracy
2. **Undo Support**: All mutations support undo/redo
3. **Progress Callbacks**: Long operations provide progress updates
4. **Actor Isolation**: Proper `@MainActor` usage for thread safety

### ViewController Component

**Keyboard Handling Architecture**:

```
ViewController                 179 lines (core)
    ├── Observer               165 lines  (UserDefaults, window events)
    ├── KeyEvent               432 lines  (JKL/Step mode handling)
    ├── KeyboardAction         142 lines  (NSResponder overrides)
    ├── Edit                   76 lines   (cut/copy/paste actions)
    └── Timeline               82 lines   (timeline delegate)
```

**Key Features**:

1. **JKL Mode** (industry-standard video navigation)
   - J: Rewind (variable speed with multiple presses)
   - K: Pause/Play
   - L: Fast-forward (variable speed)

2. **Step Mode** (frame-accurate editing)
   - Arrow keys: Navigate frames
   - Shift+Arrow: Modify selection
   - Custom step sizes (UserDefaults)

3. **Timeline Integration**
   - Drag markers (current, in, out)
   - Visual feedback
   - Follow playback option

---

## Data Flow

### File Opening Flow

```
1. User selects file
   ↓
2. NSDocumentController creates Document
   ↓
3. DocumentController.prepareOpen(for:) gathers metadata (type + header)
   ↓
4. Document.readAsync(from:openPreparation:)
   ↓
5. MovieMutator.prepare(with:)
   ↓
6. Document.makeWindowControllers()
   ↓
7. ViewController.viewDidLoad()
   ↓
8. Setup player and timeline
   ↓
9. Display video to user
```

### Editing Flow

```
1. User presses cut shortcut (⌘X)
   ↓
2. ViewController.cut(_:)
   ↓
3. ViewControllerDelegate.cut(from:to:)
   ↓
4. Document receives delegate call
   ↓
5. MovieMutator.cut(from:to:using:)
   ↓
6. Internal movie manipulation
   ↓
7. Register undo operation
   ↓
8. Notify delegate of change
   ↓
9. ViewController.requestUpdateGUI()
   ↓
10. Timeline and player update
```

### Export Flow

```
1. User selects File > Export
   ↓
2. Document.exportMovie(to:settings:)
   ↓
3. Show progress sheet
   ↓
4. MovieWriter.export(from:to:settings:progress:)
   ↓
5. AVAssetExportSession creation
   ↓
6. Progress updates via callback
   ↓
7. Update progress UI on main actor
   ↓
8. Export completes or cancels
   ↓
9. Hide progress sheet
   ↓
10. Show result to user
```

---

## Concurrency Model

### Actor Isolation

**Main Actor Usage**:
- All UI updates must occur on `@MainActor`
- `Document` class is `@MainActor` isolated
- `ViewController` components are `@MainActor` isolated

**Background Processing**:
```swift
// File I/O on background
Task.detached {
    let movie = try AVMutableMovie(url: url)
    await MainActor.run {
        // Update UI with result
    }
}
```

### Synchronization Utilities

**performSyncOnMainActor** helper:
```swift
func performSyncOnMainActor(_ block: @Sendable @escaping () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.sync(execute: block)
    }
}
```

### Progress Reporting with AsyncStream ✨ **NEW (Nov 2025)**

**Modern AsyncStream Pattern**:
```swift
// Create stream BEFORE starting operation (critical timing requirement)
let stream = mutator.progressStream()

// Start consuming progress updates
let progressTask = Task { @MainActor in
    for await progress in stream {
        updateProgressIndicator(progress)
    }
}
defer { progressTask.cancel() }

// Now start the operation (continuation already set)
try await mutator.exportMovie(to: url, fileType: .mov, presetName: nil)
```

**Key Implementation Details**:
- ✅ Stream must be created **before** export/write operation begins
- ✅ `progressContinuation` set synchronously on MainActor
- ✅ Proper weak captures prevent memory leaks
- ✅ Diagnostic logging for lifecycle debugging
- ✅ Legacy callback API completely removed (75 lines cleaned up)

---

## File Organization

### Project Structure

```
cutter2/
├── Application/                 # App lifecycle
│   ├── AppDelegate.swift
│   └── DocumentController.swift
│
├── Document/                    # Document layer (7 files)
│   ├── Document.swift           # Core (311 lines)
│   ├── Document+FileIO.swift
│   ├── Document+SavePanel.swift
│   ├── Document+Export.swift
│   ├── Document+UI.swift
│   ├── Document+Delegate.swift
│   └── Document+Utilities.swift
│
├── Models/                      # Business logic
│   ├── MovieMutator.swift       # Core + 6 extensions
│   ├── MovieMutatorBase.swift
│   ├── MovieWriter.swift
│   └── SampleBufferChannel.swift
│
├── ViewControllers/             # UI controllers
│   ├── ViewController.swift     # Core + 5 extensions
│   ├── WindowController.swift
│   ├── InspectorViewController.swift
│   └── ExportAccessoryViewController.swift
│
├── Views/                       # Custom views
│   ├── MyPlayerView.swift
│   └── TimelineView.swift
│
├── Utilities/                   # Helpers
│   ├── ErrorUtilities.swift
│   ├── ActorUtilities.swift
│   └── Constants.swift
│
├── Resources/                   # Assets and UI
│   ├── Base.lproj/
│   │   └── Document.storyboard
│   ├── Assets.xcassets/
│   └── cutter2.entitlements
│
└── cutter2Tests/               # Unit tests (6 files)
    ├── cutter2Tests.swift
    ├── MovieMutatorTests.swift
    ├── UtilitiesTests.swift
    ├── ActorUtilitiesTests.swift
    ├── ErrorUtilitiesTests.swift
    └── ViewControllerTests.swift
```

### Module Dependencies

```
Application Layer
    ↓
Document Layer ←→ ViewController Layer
    ↓                      ↓
Model Layer ←----------→ View Layer
    ↓                      ↓
    └──────→ Utilities ←───┘
```

**Dependency Rules**:
1. Upper layers can depend on lower layers
2. Lower layers should not depend on upper layers
3. Delegate protocols enable upward communication
4. Utilities are shared across all layers

---

## Design Principles

### 1. Separation of Concerns

Each component has a single, well-defined responsibility. File refactoring reduced monolithic files by 70-90%.

### 2. Protocol-Oriented Design

Protocols define clear contracts and enable testability:
```swift
protocol ViewControllerDelegate: AnyObject {
    func playerItem() -> AVPlayerItem?
    func currentTime() -> CMTime
    func requestUpdateGUI()
}
```

### 3. Actor Isolation

Swift Concurrency ensures thread safety:
- `@MainActor` for UI components
- `async/await` for I/O operations
- Proper synchronization for callbacks

### 4. Explicit Error Handling

Custom error types with user-friendly messages:
```swift
enum DocumentError: Error {
    case invalidFormat(String)
    case exportFailed(String)
    // ... more cases
}
```

### 5. Testability

- Modular design enables unit testing
- Protocol-based dependencies allow mocking
- 6 test files with comprehensive coverage

---

## Performance Considerations

### 1. Lazy Loading

- Video frames loaded on-demand
- Timeline rendering optimized for visible range

### 2. Background Processing

- File I/O on background threads
- Export operations don't block UI

### 3. Memory Management

- Proper cleanup in `deinit`
- Weak references in closures prevent retain cycles
- Resource deallocation on document close

### 4. Caching Strategy

- Player items cached for quick access
- Timeline position calculations cached

---

## Security

### Sandbox Compliance

**Security-Scoped Bookmarks**:
- Enable persistent file access in sandbox
- Automatic bookmark renewal
- User permission prompts

**Entitlements**:
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.device.audio-input`
- `com.apple.security.device.camera`
- Network access for media streaming

---

## Future Architecture Considerations

### Potential Improvements

1. **Plugin Architecture**
   - Support for custom codecs
   - Third-party effect extensions

2. **Cloud Integration**
   - iCloud document support
   - Collaborative editing

3. **SwiftUI Migration**
   - Gradual migration from AppKit
   - Modern declarative UI

4. **Enhanced Testing**
   - UI testing with XCUITest
   - Performance regression tests
   - Integration test suite

---

## References

- [Apple Document-Based Apps Guide](https://developer.apple.com/documentation/appkit/documents_data_and_pasteboard)
- [AVFoundation Programming Guide](https://developer.apple.com/av-foundation/)
- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [REFACTORING_PLAN.md](archive/phase-1.2/REFACTORING_PLAN.md) - Detailed refactoring history
- [CODEBASE_REVIEW.md](archive/reviews/CODEBASE_REVIEW.md) - Comprehensive codebase analysis

---

**Document Status**: ✅ Active  
**Last Review**: February 5, 2026  
**Next Review**: As needed for major architectural changes
