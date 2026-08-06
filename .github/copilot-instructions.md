# GitHub Copilot Instructions for cutter2

## Project Overview

cutter2 is a sophisticated macOS video editing application written in Swift, leveraging Apple's AVFoundation framework. It serves as a QuickTime movie editor with powerful keyboard shortcuts, designed for precise video editing workflows.

**Current Status**:
- **Version**: 0.8.19
- **Swift language mode**: 6.0 (`SWIFT_VERSION = 6.0`)
- **Minimum environment**: macOS 14.0; Xcode 16.0 or later
- **Verified environment (August 6, 2026)**: macOS 26.6 (build 25G72), Xcode 26.6 (build 17F113), Swift compiler 6.3.3
- **Phase history**: Phase 2.1 (Internationalization) and Phase 2.2 (Performance Optimization) were recorded as complete on October 15 and October 17, 2025; these entries are historical milestones, not current verification results
- **Current test note**: 197 statically declared test methods are present; the current HEAD requires a duplicate test-helper declaration to be fixed before runtime test success can be reverified

## Architecture & Design Patterns

### Core Architecture
- **Document-based Application**: Built using NSDocument architecture for file management
- **MVC Pattern**: Clear separation between Models (MovieMutator), Views (PlayerView/TimelineView), and Controllers (ViewController/WindowController)
- **Delegate Pattern**: Extensive use of delegates for communication between components
- **Protocol-Oriented Design**: Heavy reliance on Swift protocols for modular design

### Key Components
- `Document.swift`: Central document class managing movie files, I/O operations, and document lifecycle
- `MovieMutator.swift`/`MovieMutatorBase.swift`: Core movie manipulation and editing logic
- `ViewController.swift`: Main UI controller handling playback and user interactions
- `WindowController.swift`: Window management and document-window coordination
- `MyPlayerView.swift`: Custom AVPlayerView for video playback
- `TimelineView.swift`: Custom timeline interface for video navigation

## Frameworks & Dependencies

### Primary Frameworks
- **AVFoundation**: Core video/audio processing and movie manipulation
- **AVKit**: Video playback UI components (AVPlayerView)
- **Cocoa**: Native macOS UI framework
- **CoreMedia**: Low-level media timing and data structures

### Key Types
- `AVMutableMovie`: Primary movie container for editing operations
- `CMTime`/`CMTimeRange`: Precise timing for video editing
- `AVPlayerItem`/`AVPlayer`: Playback engine components
- `AVAssetExportSession`: Video export and transcoding

## Coding Conventions & Patterns

### Swift Concurrency
- **Async/Await**: Preferred for all I/O operations (file reading, writing, export)
- **@MainActor**: Used extensively for UI operations and document management
- **Task**: For concurrent operations and main thread dispatch
- **@Sendable**: Applied to closures crossing actor boundaries

### Error Handling
- **DocumentError Enum**: Custom error types with NSError conversion
- **ErrorUtilities**: Centralized error handling and user presentation
- **Try-Catch**: Comprehensive error handling with user-friendly messages

### Memory Management
- **Weak References**: Extensive use in closures to prevent retain cycles
- **Automatic Reference Counting**: Proper lifecycle management for AVFoundation objects
- **Resource Cleanup**: Explicit cleanup in `deinit` and document closing

### Naming Conventions
- **Descriptive Names**: Full words preferred over abbreviations
- **Action Prefixes**: `do`, `update`, `validate`, `apply` for action methods
- **Boolean Properties**: `is`, `has`, `should` prefixes
- **Constants**: `k` prefix for string constants (e.g., `kTranscodePresetKey`)

## Code Style Guidelines

### Method Organization
```swift
/* ============================================ */
// MARK: - Section Name
/* ============================================ */
```

### Documentation
- Comprehensive inline documentation for public methods
- Parameter descriptions using `/// - Parameter name: description`
- Return value documentation using `/// - Returns: description`

### Access Control
- **Private**: Implementation details and helper methods
- **Public**: External API and delegate methods
- **Internal**: Default scope for most properties and methods

### Property Organization
- Public properties first, then private
- Computed properties after stored properties
- Lazy properties clearly marked

## Common Patterns & Implementations

### Document Lifecycle
```swift
override func makeWindowControllers() {
    // 1. Setup movie mutator
    // 2. Create window controller from storyboard
    // 3. Configure view controller delegate
    // 4. Initialize GUI state
}
```

### Async File Operations
```swift
// Document file I/O is split into preparation (background) + readAsync (MainActor):
// - DocumentController.prepareOpen(for:) collects OpenPreparation off the main actor
// - Document.readAsync(from:openPreparation:) applies the prepared metadata
struct OpenPreparation: Sendable {
    let typeName: String
    let modificationDate: Date?
    let movHeader: Data?
}

func readAsync(from url: URL, openPreparation: OpenPreparation) async throws {
    // Validate UTI via Document.validateMovieType(_:) (shared with read(from:ofType:))
    // Validate movie header via MovieHeaderValidator
    // Apply movieMutator on the main actor
    // Handle errors with custom DocumentError types
}
```

### Video Export Patterns
```swift
// Show progress UI
showBusySheet("Exporting...", "Please wait a few minutes...")
mutator.updateProgress = { progress in
    performSyncOnMainActor { updateProgress(progress) }
}
defer { hideBusySheet() }
```

### Undo Support
```swift
// Use UndoManagerWrapper for complex operations
mutator.applySomething(parameters, using: self.undoManagerWrapper)
```

## Movie Editing Specifics

### Time Handling
- Always use `CMTime` for precise timing
- Validate times with `CMTIME_IS_VALID()`
- Use `CMTimeClampToRange()` for boundary checking
- Default timescale: 600 for compatibility

### Movie Mutations
- All editing operations through MovieMutator
- Support for both self-contained and reference movies
- Automatic bookmark management for sandbox security

### Export Options
- Multiple codec support: H.264, HEVC, ProRes variants
- Audio codec options: AAC, LPCM with various bit depths
- Custom export settings via UserDefaults preferences

## UI Interaction Patterns

### Keyboard Shortcuts
- JKL mode for timeline navigation (industry standard)
- Step mode for frame-by-frame editing
- Custom key handling in ViewController

### Window Management
- Dynamic resizing based on video dimensions
- Multiple zoom levels (50%, 100%, 200%, fit-to-screen)
- Screen-aware positioning

### Progress Feedback
- Busy sheets for long operations
- Progress indicators with percentage updates
- User cancellation support

## Sandbox & Security

### File Access
- Security-scoped bookmarks for file persistence
- Automatic bookmark validation and renewal
- User permission prompts for file system access

### Entitlements
- Video/audio capture capabilities
- File system access permissions
- Network access for media streaming

## Testing & Validation

### Error Scenarios
- Invalid file formats and corrupted media
- Insufficient disk space during export
- Network interruptions during streaming
- Memory pressure with large files

### Performance Considerations
- Lazy loading of video frames
- Background processing for heavy operations
- Memory-efficient timeline rendering
- Optimal export settings for different use cases

## Best Practices for Development

### When Adding New Features
1. Follow existing delegate patterns for communication
2. Use async/await for any I/O operations
3. Implement proper error handling with DocumentError
4. Add undo support for user actions
5. Update GUI state consistently
6. Consider sandbox security implications

### Code Review Checklist
- Proper memory management (weak references)
- Main actor usage for UI operations
- Error handling completeness
- Documentation for public APIs
- Consistent naming conventions
- Performance impact assessment

### Common Gotchas
- AVFoundation objects must be created on appropriate threads
- CMTime arithmetic requires careful validation
- Sandbox permissions need explicit user grants
- Document closing requires proper cleanup
- Export operations need progress feedback

## File Extensions & Types

### Supported Formats
- `.mov`: QuickTime movies (primary format)
- `.mp4`: MPEG-4 videos
- `.m4v`: iTunes video format
- `.m4a`: Audio-only format

### Internal Organization
- **Application/**: App delegate and document controller
- **Document/**: Document class and related extensions
- **Models/**: Core business logic (MovieMutator, MovieWriter, SampleBufferChannel)
- **ViewControllers/**: All view controllers (ViewController, WindowController, InspectorViewController, etc.)
- **Views/**: Custom views (MyPlayerView, TimelineView)
- **Utilities/**: Helper classes and utilities (ErrorUtilities, Constants, ActorUtilities, etc.)
- **Resources/**: Storyboards (`Base.lproj/`), assets (`Assets.xcassets/`), and other resources
- Entitlements in `cutter2.entitlements`
