# API Reference for cutter2

**Last Updated**: February 5, 2026  
**Status**: 🚧 Work in Progress

> **Note**: This is a living document. Full API documentation will be generated automatically using tools like jazzy or DocC in the future. This document provides an overview of key APIs and their usage.

**Recent Updates**:
- ✅ Added LocalizationHelper utility (Phase 2.1)
- ✅ All error messages now localized
- ✅ String Catalog integration

---

## Table of Contents

1. [Document Layer](#document-layer)
2. [Model Layer](#model-layer)
3. [ViewController Layer](#viewcontroller-layer)
4. [Utilities](#utilities)
5. [Localization](#localization)
6. [Protocols](#protocols)

---

## New in This Version (June 2026)

- **AsyncBridge** — Async-to-sync bridge with timeout support
- **LayoutConverter** — Audio channel layout analysis subsystem
- **MovieHeaderValidator** — Typed movie validation errors
- **ActorUtilities** — Updated with generic throwing/non-throwing variants
- **UndoManagerWrapper** — Concurrency contract documented
- **ConcurrencyGuidelines.md** — New standalone concurrency patterns guide

---

## Document Layer

### Document

Main document class managing the video file lifecycle.

#### Core Properties

```swift
@MainActor
class Document: NSDocument {
    /// The movie mutator handling edit operations
    var movieMutator: MovieMutator?
    
    /// The AVPlayer for playback
    var player: AVPlayer?
    
    /// Window controller managing the document window
    var windowController: WindowController?
    
    /// View controller managing the main view
    var viewController: ViewController?
    
    /// Undo manager wrapper for complex undo operations
    var undoManagerWrapper: UndoManagerWrapper
}
```

#### File I/O Methods

```swift
/// Reads a movie file asynchronously using prepared open metadata
/// - Parameters:
///   - url: The URL of the file to read
///   - openPreparation: Prepared metadata from DocumentController.prepareOpen
/// - Throws: DocumentError if read fails
func readAsync(from url: URL, openPreparation: OpenPreparation) async throws

/// Writes the movie file asynchronously
/// - Parameters:
///   - url: The URL to write to
///   - typeName: The file type name
///   - saveOperation: The save operation type
/// - Throws: DocumentError if write fails
func writeAsync(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) async throws

/// Reverts the document to the last saved state
/// - Parameter sender: The object that initiated the revert
override func revert(toContentsOf url: URL, ofType typeName: String) throws
```

#### Export Methods

```swift
/// Exports the movie to a new file
/// - Parameters:
///   - url: Destination URL
///   - settings: Export settings dictionary
/// - Throws: DocumentError if export fails
func exportMovie(to url: URL, settings: [String: Any]) async throws

/// Transcodes the movie with new codec settings
/// - Parameters:
///   - url: Destination URL
///   - preset: Transcode preset name
/// - Throws: DocumentError if transcode fails
func transcodeMovie(to url: URL, preset: String) async throws
```

#### UI Methods

```swift
/// Resizes the window to match video dimensions
/// - Parameter scale: Scale factor (0.5, 1.0, 2.0, or 0 for fit)
func resizeWindow(scale: Float)

/// Modifies video transform (clean aperture or pixel aspect ratio)
/// - Parameters:
///   - type: Transform type (.clap or .pasp)
///   - values: Transform values
func modifyTransform(type: TransformType, values: [String: Any])
```

---

## Model Layer

### MovieMutator

Core class for movie editing operations.

#### Edit Operations

```swift
class MovieMutator: MovieMutatorBase {
    /// Cuts a time range from the movie
    /// - Parameters:
    ///   - start: Start time
    ///   - end: End time
    ///   - undoManager: Undo manager for the operation
    /// - Throws: EditError if operation fails
    func cut(from start: CMTime, to end: CMTime, using undoManager: UndoManagerWrapper) throws
    
    /// Copies a time range to the clipboard
    /// - Parameters:
    ///   - start: Start time
    ///   - end: End time
    /// - Throws: EditError if operation fails
    func copy(from start: CMTime, to end: CMTime) throws
    
    /// Pastes clipboard content at specified time
    /// - Parameters:
    ///   - time: Insertion time
    ///   - undoManager: Undo manager for the operation
    /// - Throws: EditError if operation fails
    func paste(at time: CMTime, using undoManager: UndoManagerWrapper) throws
    
    /// Deletes a time range
    /// - Parameters:
    ///   - start: Start time
    ///   - end: End time
    ///   - undoManager: Undo manager for the operation
    /// - Throws: EditError if operation fails
    func delete(from start: CMTime, to end: CMTime, using undoManager: UndoManagerWrapper) throws
}
```

#### Transform Operations

```swift
/// Modifies clean aperture settings
/// - Parameters:
///   - width: Clean aperture width
///   - height: Clean aperture height
///   - horizontalOffset: Horizontal offset
///   - verticalOffset: Vertical offset
///   - undoManager: Undo manager
/// - Throws: TransformError if operation fails
func modifyCleanAperture(width: Int, height: Int, 
                        horizontalOffset: Int, verticalOffset: Int,
                        using undoManager: UndoManagerWrapper) throws

/// Modifies pixel aspect ratio
/// - Parameters:
///   - hSpacing: Horizontal spacing
///   - vSpacing: Vertical spacing
///   - undoManager: Undo manager
/// - Throws: TransformError if operation fails
func modifyPixelAspectRatio(hSpacing: Int, vSpacing: Int,
                            using undoManager: UndoManagerWrapper) throws
```

#### Export Operations

```swift
/// Exports movie with custom settings
/// - Parameters:
///   - url: Destination URL
///   - videoCodec: Video codec type
///   - audioCodec: Audio codec type
///   - progressCallback: Progress update callback
/// - Throws: ExportError if export fails
func export(to url: URL, 
           videoCodec: VideoCodec, 
           audioCodec: AudioCodec,
           progress progressCallback: @escaping (Double) -> Void) async throws
```

### MovieWriter

Handles movie export and transcoding.

```swift
class MovieWriter {
    /// Exports a movie with specified settings
    /// - Parameters:
    ///   - asset: Source asset
    ///   - url: Destination URL
    ///   - settings: Export settings
    ///   - progress: Progress callback
    /// - Returns: Result indicating success or failure
    func export(asset: AVAsset, 
               to url: URL, 
               settings: ExportSettings,
               progress: @escaping (Double) -> Void) async -> Result<Void, Error>
}
```

---

## ViewController Layer

### ViewController

Main view controller managing UI and user interactions.

```swift
@MainActor
class ViewController: NSViewController {
    /// Delegate for document communication
    weak var delegate: ViewControllerDelegate?
    
    /// Player view displaying video
    @IBOutlet weak var playerView: MyPlayerView!
    
    /// Timeline view for navigation
    @IBOutlet weak var timelineView: TimelineView!
    
    /// Updates the timeline display
    /// - Parameters:
    ///   - duration: Total duration
    ///   - current: Current time
    ///   - start: Selection start
    ///   - end: Selection end
    func updateTimeline(duration: CMTime, current: CMTime, start: CMTime, end: CMTime)
}
```

#### Edit Actions

```swift
/// Cuts selected content
@IBAction func cut(_ sender: Any?)

/// Copies selected content
@IBAction func copy(_ sender: Any?)

/// Pastes clipboard content
@IBAction func paste(_ sender: Any?)

/// Deletes selected content
@IBAction func delete(_ sender: Any?)
```

---

## Utilities

### ErrorUtilities

Centralized error handling and presentation.

```swift
class ErrorUtilities {
    /// Presents an error to the user
    /// - Parameters:
    ///   - error: The error to present
    ///   - window: Optional window for modal presentation
    static func presentError(_ error: Error, window: NSWindow? = nil)
    
    /// Creates a user-friendly error description
    /// - Parameter error: The error to describe
    /// - Returns: Localized error description
    static func errorDescription(for error: Error) -> String
}
```

### ActorUtilities

Main actor synchronization helpers. Provides synchronous execution of `@MainActor`-isolated closures from any thread.

```swift
public struct ActorUtilities {
    
    /// Runs a throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A closure isolated to the main actor that may throw an error.
    /// - Returns: The result of the closure's operation.
    /// - Throws: Any error thrown by the closure.
    /// - Warning: Blocks the calling thread if not already on the main thread.
    public static func performSyncOnMainActor<T: Sendable>(
        _ block: @MainActor () throws -> T
    ) throws -> T
    
    /// Runs a non-throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A non-throwing closure isolated to the main actor.
    /// - Returns: The result of the closure's operation.
    /// - Warning: Blocks the calling thread if not already on the main thread.
    public static func performSyncOnMainActor<T: Sendable>(
        _ block: @MainActor () -> T
    ) -> T
}
```

**Implementation:** Uses `Thread.isMainThread` check + `MainActor.assumeIsolated` (Swift 6 idiom) with `DispatchQueue.main.sync` fallback for background callers.

### AsyncBridge

Async-to-sync bridge for running async work from non-async contexts (e.g., `NSDocument` overrides).

```swift
enum AsyncBridge {
    /// Performs an async operation synchronously with timeout support.
    /// - Parameters:
    ///   - timeout: Optional timeout in seconds. Throws `PerformAsyncError.timeout` on expiry.
    ///   - allowMainThread: If true, allows calling from main thread (deadlock risk).
    ///   - block: The async operation to perform.
    /// - Returns: The result of the async operation.
    /// - Throws: `PerformAsyncError.timeout` or `PerformAsyncError.operationFailed`.
    /// - Precondition: Must not be called from main thread unless `allowMainThread: true`.
    static func perform<T: Sendable>(
        timeout: TimeInterval? = nil,
        allowMainThread: Bool = false,
        _ block: @Sendable @escaping () async throws -> T
    ) throws -> T
}
```

**Error types:**
```swift
enum PerformAsyncError: Error {
    case timeout(TimeInterval)
    case operationFailed(String)
}
```

**Usage in `Document+ActorIsolation.swift`:**
```swift
nonisolated func performAsync<T: Sendable>(
    timeout: TimeInterval? = nil,
    _ block: @Sendable @escaping () async throws -> T
) throws -> T {
    try AsyncBridge.perform(timeout: timeout, block)
}
```

### LayoutConverter

Audio channel layout analysis subsystem (4 files, ~770 lines). Pure functions, zero stored properties — automatically `Sendable` compliant.

**Core type:**
```swift
public struct LayoutConverter: Sendable {
    public init() {}
    typealias LayoutPtr = UnsafePointer<AudioChannelLayout>
    typealias MutableLayoutPtr = UnsafeMutablePointer<AudioChannelLayout>
    typealias DescriptionsPtr = UnsafeBufferPointer<AudioChannelDescription>
    typealias MutableDescriptionsPtr = UnsafeMutableBufferPointer<AudioChannelDescription>
}
```

**Public API (`LayoutConverter+Convert.swift`):**
```swift
extension LayoutConverter {
    /// Converts an AudioChannelLayout to AAC channel layout tag.
    /// - Parameter layout: The audio channel layout data.
    /// - Returns: The AAC channel layout tag, or nil if conversion fails.
    public func convertAsAACTag(from layout: AudioChannelLayoutData) -> AudioChannelLayoutTag?
    
    /// Returns a standard channel layout for the given channel count.
    /// - Parameter channelCount: Number of audio channels.
    /// - Returns: AudioChannelLayoutData for the standard layout.
    public func layoutForChannelCount(_ channelCount: Int) -> AudioChannelLayoutData?
}
```

**Binary layout utilities (`LayoutConverter+LayoutData.swift`):**
```swift
extension LayoutConverter {
    /// Calculates the byte size required for a layout with the given description count.
    /// - Parameter descCount: Number of channel descriptions (0 = header only).
    /// - Returns: Byte size (12 for header, 32 + (n-1)*20 for n descriptions).
    public func dataSize(descCount: Int) -> Int
    
    /// Creates AudioChannelLayoutData from raw bytes with validation.
    /// - Parameters:
    ///   - layoutBytes: Raw audio channel layout bytes.
    ///   - size: Expected size in bytes.
    /// - Returns: Validated AudioChannelLayoutData, or nil if invalid.
    public func dataFor(layoutBytes: UnsafeRawPointer, size: Int) -> AudioChannelLayoutData?
}
```

**Tag↔Label mapping (`LayoutConverter+Mapping.swift`):**
- 120+ `AudioChannelLayoutTag` cases mapped to `AudioChannelLabel` sets
- `AudioChannelLabel` extensions for display names and localization
- Used by `MovieWriter` (actor) for AAC/HE-AAC channel layout configuration during custom export

### MovieHeaderValidator

Movie file validation with typed errors.

```swift
public struct MovieHeaderValidator {
    /// Validation error types.
    public enum ValidationError: LocalizedError {
        case noTracks       // Not a movie file (e.g., image, audio-only)
        case invalidDuration // Corrupted movie with invalid duration
        
        public var errorDescription: String? { ... }
    }
    
    /// Validates a movie and returns the specific error if invalid.
    /// - Parameter movie: The movie to validate.
    /// - Returns: ValidationError if invalid, nil if valid.
    public static func validate(_ movie: AVMutableMovie) -> ValidationError?
    
    /// Quick validity check.
    /// - Parameter movie: The movie to validate.
    /// - Returns: true if movie has tracks and valid duration.
    public static func isValid(_ movie: AVMutableMovie) -> Bool
}
```

**Usage in `DocumentController.prepareOpen`:**
```swift
if let error = MovieHeaderValidator.validate(movie) {
    // Present specific error: .noTracks or .invalidDuration
}
```

### UndoManagerWrapper

Wrapper for complex undo operations with `@MainActor` isolation.

```swift
@MainActor
final class UndoManagerWrapper {
    /// The underlying NSUndoManager (weak reference to avoid retain cycles).
    private unowned let undoManager: NSUndoManager
    
    public init(_ undoManager: NSUndoManager) {
        self.undoManager = undoManager
    }
    
    /// Registers an undo operation with a target and handler.
    /// - Parameters:
    ///   - target: The target object (typically `self` of the mutator).
    ///   - handler: The undo handler called with the target.
    /// - Note: Handler is executed on the main actor via `ActorUtilities.performSyncOnMainActor`.
    public func registerUndo<T: AnyObject>(
        withTarget target: T,
        handler: @escaping @MainActor @Sendable (T) -> Void
    )
    
    /// Sets the action name for the current undo group.
    /// - Parameter name: The action name (e.g., "Cut", "Paste", "Format").
    public func setActionName(_ name: String)
    
    /// Removes all actions registered for a specific target.
    /// - Parameter target: The target object whose actions to remove.
    public func removeAllActions(withTarget target: AnyObject)
}
```

**Concurrency contract:**
- All methods are `@MainActor` isolated (class is `@MainActor`)
- `registerUndo` handler is `@MainActor @Sendable` — safe to capture `self`
- Internal implementation uses `ActorUtilities.performSyncOnMainActor` for thread safety
- Suitable for use in `@Sendable` closures (e.g., `Task { @MainActor in ... }`)

---

## Localization

### LocalizationHelper

**New in Phase 2.1**: Utility for localization support with String Catalog integration.

```swift
enum LocalizationHelper {
    // MARK: - String Localization
    
    /// Localize a string with the given key and comment
    /// - Parameters:
    ///   - key: The localization key
    ///   - comment: Description for translators
    /// - Returns: Localized string
    static func localized(_ key: String, comment: String = "") -> String
    
    /// Localize a string with format arguments
    /// - Parameters:
    ///   - key: The localization key
    ///   - comment: Description for translators
    ///   - arguments: Format arguments
    /// - Returns: Formatted localized string
    static func localizedFormat(_ key: String, comment: String = "", _ arguments: CVarArg...) -> String
    
    // MARK: - Common UI Strings
    
    /// Common button labels
    enum Button {
        static let ok: String
        static let cancel: String
        static let save: String
        static let export: String
        static let `continue`: String
        static let stop: String
    }
    
    // MARK: - Number and Date Formatting
    
    /// Format a percentage value for display
    /// - Parameter value: The percentage value (0.0 to 1.0)
    /// - Returns: Formatted percentage string
    static func formatPercentage(_ value: Double) -> String
    
    /// Format a time interval for display
    /// - Parameter interval: Time interval in seconds
    /// - Returns: Formatted time string (e.g., "1:23" or "1:23:45")
    static func formatTimeInterval(_ interval: TimeInterval) -> String
    
    /// Format file size for display
    /// - Parameter bytes: Size in bytes
    /// - Returns: Formatted size string with appropriate unit
    static func formatFileSize(_ bytes: Int64) -> String
}
```

#### Usage Examples

```swift
// Simple string localization
let errorMessage = LocalizationHelper.localized("error.document.incompatible_file_type",
                                               comment: "File type error")

// Formatted string
let progress = LocalizationHelper.localizedFormat("progress.format.percent",
                                                  comment: "Progress with percentage",
                                                  75)

// Using button constants
let cancelButton = LocalizationHelper.Button.cancel

// Formatting helpers
let percentage = LocalizationHelper.formatPercentage(0.75)  // "75%"
let fileSize = LocalizationHelper.formatFileSize(1024 * 1024)  // "1 MB"
let time = LocalizationHelper.formatTimeInterval(125.5)  // "2:05"
```

### String Extension

Convenience extension for localization.

```swift
extension String {
    /// Convenience method to get localized string
    /// - Parameter comment: Description for translators
    /// - Returns: Localized string
    func localized(comment: String = "") -> String
    
    /// Convenience method to get localized string with format arguments
    /// - Parameters:
    ///   - comment: Description for translators
    ///   - arguments: Format arguments
    /// - Returns: Formatted localized string
    func localizedFormat(comment: String = "", _ arguments: CVarArg...) -> String
}
```

#### Usage Example

```swift
// Using string extension
let localized = "error.document.empty_movie".localized(comment: "Empty movie error")
```

### String Catalog Structure

**Localizable.xcstrings** - 55 localized keys covering:
- Error messages (17 items)
- UI buttons (4 items)
- Progress messages (5 items)
- Accessory view labels (4 items)
- Menu items (19 items)
- Inspector labels (5 items)
- Error reasons (1 item)

Supported languages:
- English (base language)
- Japanese (日本語)

---

## Protocols

### ViewControllerDelegate

Protocol for Document ↔ ViewController communication.

```swift
@MainActor
protocol ViewControllerDelegate: AnyObject {
    /// Returns the current player item
    func playerItem() -> AVPlayerItem?
    
    /// Returns the current playback time
    func currentTime() -> CMTime
    
    /// Returns the selection start time
    func startTime() -> CMTime
    
    /// Returns the selection end time
    func endTime() -> CMTime
    
    /// Requests GUI update
    func requestUpdateGUI()
    
    /// Performs cut operation
    func cut(from: CMTime, to: CMTime)
    
    /// Performs copy operation
    func copy(from: CMTime, to: CMTime)
    
    /// Performs paste operation
    func paste(at: CMTime)
    
    /// Performs delete operation
    func delete(from: CMTime, to: CMTime)
}
```

### TimelineUpdateDelegate

Protocol for Timeline ↔ ViewController communication.

```swift
protocol TimelineUpdateDelegate: AnyObject {
    /// Called when cursor position changes
    func didUpdateCursor(to time: CMTime)
    
    /// Called when selection start changes
    func didUpdateStart(to time: CMTime)
    
    /// Called when selection end changes
    func didUpdateEnd(to time: CMTime)
    
    /// Returns presentation info at specified time
    func presentationInfo(at time: CMTime) -> PresentationInfo?
}
```

---

## Error Types

### DocumentError

Errors related to document operations.

```swift
enum DocumentError: Error {
    case invalidFormat(String)
    case readFailed(String, underlying: Error?)
    case writeFailed(String, underlying: Error?)
    case exportFailed(String, underlying: Error?)
    case invalidURL
    case bookmarkFailed
    
    var localizedDescription: String {
        // Returns user-friendly error message
    }
}
```

### EditError

Errors related to editing operations.

```swift
enum EditError: Error {
    case invalidTimeRange
    case clipboardEmpty
    case operationFailed(String)
    case undoFailed
}
```

---

## Types and Enums

### VideoCodec

Supported video codecs for export.

```swift
enum VideoCodec: String {
    case h264 = "avc1"
    case hevc = "hvc1"
    case proRes422 = "apcn"
    case proRes422LT = "apcs"
    case proRes422Proxy = "apco"
}
```

### AudioCodec

Supported audio codecs for export.

```swift
enum AudioCodec: String {
    case aac = "aac"
    case lpcm16 = "lpcm16"
    case lpcm24 = "lpcm24"
    case lpcm32 = "lpcm32"
}
```

### ExportSettings

Export configuration structure.

```swift
struct ExportSettings {
    let videoCodec: VideoCodec
    let audioCodec: AudioCodec
    let videoBitRate: Int?
    let audioBitRate: Int?
    let preserveTransforms: Bool
    let fileType: AVFileType
}
```

---

## Usage Examples

### Opening and Editing a Movie

```swift
// Open document
let document = try await Document(contentsOf: url, ofType: "mov")

// Get the mutator
guard let mutator = document.movieMutator else { return }

// Cut a section
let start = CMTime(seconds: 10, preferredTimescale: 600)
let end = CMTime(seconds: 20, preferredTimescale: 600)
try mutator.cut(from: start, to: end, using: document.undoManagerWrapper)

// Save changes
try await document.save(to: url, ofType: "mov", for: .saveOperation)
```

### Exporting with Custom Settings

```swift
let settings = ExportSettings(
    videoCodec: .hevc,
    audioCodec: .aac,
    videoBitRate: 10_000_000,
    audioBitRate: 256_000,
    preserveTransforms: true,
    fileType: .mp4
)

try await document.exportMovie(to: outputURL, settings: settings)
```

### Handling Errors

```swift
do {
    try await document.save(to: url, ofType: "mov", for: .saveOperation)
} catch let error as DocumentError {
    ErrorUtilities.presentError(error, window: document.windowController?.window)
} catch {
    ErrorUtilities.presentError(error)
}
```

---

## Future Enhancements

This API reference will be expanded to include:

- [ ] Complete API documentation for all public methods
- [ ] Detailed parameter descriptions
- [ ] Return value documentation
- [ ] Error cases and handling
- [ ] Code examples for common use cases
- [ ] Integration with automated documentation tools (jazzy/DocC)

---

## Contributing to API Documentation

When adding or modifying APIs:

1. Add inline documentation using Swift doc comments
2. Update this reference with new public APIs
3. Provide usage examples for complex APIs
4. Document error cases and edge cases

Example:
```swift
/// Brief description of the method
///
/// Detailed explanation with multiple paragraphs if needed.
/// Explain the purpose, behavior, and any important notes.
///
/// - Parameters:
///   - param1: Description of first parameter
///   - param2: Description of second parameter
/// - Returns: Description of return value
/// - Throws: Description of errors that can be thrown
///
/// # Example
/// ```swift
/// let result = try method(param1: value1, param2: value2)
/// ```
///
/// - Note: Additional notes or warnings
/// - SeeAlso: Related methods or types
public func method(param1: Type1, param2: Type2) throws -> ReturnType {
    // Implementation
}
```

---

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture overview
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) - Development practices
- [CODEBASE_REVIEW.md](archive/reviews/CODEBASE_REVIEW.md) - Detailed code analysis

---

**Document Status**: 🚧 Work in Progress  
**Last Updated**: February 5, 2026  
**Next Review**: After major API changes or releases

**Note**: Full API documentation generation using DocC or jazzy is planned for future releases.
