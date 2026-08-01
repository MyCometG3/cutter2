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
    /// Copies the current selection to the clipboard
    func copySelection()
    
    /// Cuts the current selection, copying it to the clipboard
    /// - Parameter undoManager: Undo manager for the operation
    func cutSelection(using undoManager: UndoManagerWrapper)
    
    /// Pastes clipboard content at the insertion time
    /// - Parameter undoManager: Undo manager for the operation
    func pasteAtInsertionTime(using undoManager: UndoManagerWrapper)
    
    /// Deletes the current selection
    /// - Parameter undoManager: Undo manager for the operation
    func deleteSelection(using undoManager: UndoManagerWrapper)
}
```

#### Transform Operations

```swift
/// Reads clean aperture / pixel aspect atoms from the movie
/// - Returns: Dictionary of clap/pasp values, or nil if absent
func clappaspDictionary() -> [AnyHashable: Any]?

/// Applies clean aperture / pixel aspect changes
/// - Parameters:
///   - dict: Clap/pasp dictionary (from `clappaspDictionary()`)
///   - undoManager: Undo manager for the operation
/// - Returns: true if the operation succeeded
func applyClapPasp(_ dict: [AnyHashable: Any], using undoManager: UndoManagerWrapper) -> Bool
```

#### Export Operations

```swift
/// Exports movie with a preset (H.264, HEVC, ProRes)
/// - Parameters:
///   - url: Destination URL
///   - fileType: Output file type (.mov, .mp4, .m4v, .m4a)
///   - preset: Preset name (nil for standard export)
func exportMovie(to url: URL, fileType type: AVFileType, presetName preset: String?) async throws

/// Exports movie with custom settings (codec, bitrate, clap/pasp)
/// - Parameters:
///   - url: Destination URL
///   - fileType: Output file type
///   - settings: Custom export settings dictionary
func exportCustomMovie(to url: URL, fileType type: AVFileType, settings param: [String: any Sendable]) async throws

/// Saves movie (self-contained or reference)
/// - Parameters:
///   - url: Destination URL
///   - fileType: Output file type
///   - copySampleData: true for self-contained, false for reference movie
func writeMovie(to url: URL, fileType type: AVFileType, copySampleData selfContained: Bool) async throws

/// Cancels an in-progress export
func cancel() async
```

### MovieWriter

Handles movie export and transcoding as an actor, isolating export session lifecycle from the main actor.

```swift
actor MovieWriter: SampleBufferChannelDelegate {
    public init(params: MovieWriterParams)
    
    /// Exports movie with a preset (AVAssetExportSession)
    func exportMovie(to url: URL, fileType type: AVFileType, presetName preset: String?) async throws
    
    /// Exports movie with custom settings (AVAssetReader/Writer)
    func exportCustomMovie(to url: URL, fileType type: AVFileType, settings param: [String: any Sendable]) async throws
    
    /// Saves movie (self-contained or reference)
    func writeMovie(to url: URL, fileType type: AVFileType, copySampleData selfContained: Bool) async throws
    
    /// Cancels an in-progress export
    func cancelExport()
    
    /// Cancels an in-progress custom export
    func cancelCustomMovie()
    
    /// Starts/stops export session polling
    func exportSessionPollingStart()
    func exportSessionPollingStop()
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

Shared utilities for error handling.

```swift
public struct ErrorUtilities {
    /// Throw an error with a specific reason.
    /// - Parameters:
    ///   - error: The error conforming to NSErrorConvertible to throw.
    ///   - reason: An optional reason for the error.
    /// - Returns: Never
    public static func throwError<E: NSErrorConvertible>(_ error: E, reason: String? = nil) throws -> Never
}
```

### ActorUtilities

Main actor synchronization helpers for code that needs to run `@MainActor`-isolated work from any thread.

```swift
public struct ActorUtilities {
    public static func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated { try block() }
        } else {
            return try DispatchQueue.main.sync {
                try MainActor.assumeIsolated { try block() }
            }
        }
    }

    public static func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { block() }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { block() }
            }
        }
    }
}
```

**Implementation:** Uses `Thread.isMainThread` plus `MainActor.assumeIsolated`, falling back to `DispatchQueue.main.sync` when the caller is off the main thread.

### AsyncBridge

Async-to-sync bridge for invoking async work from non-async contexts such as document lifecycle overrides.

```swift
enum PerformAsyncError: Error {
    case timeout(TimeInterval)
    case operationFailed(String)
}

enum AsyncBridge {
    static func perform<T: Sendable>(
        timeout: TimeInterval? = nil,
        allowMainThread: Bool = false,
        _ block: @Sendable @escaping () async throws -> T
    ) throws -> T {
        precondition(
            allowMainThread || !Thread.isMainThread,
            "AsyncBridge.perform must not be called from the main thread."
        )
        // Runs the async block on a detached Task and waits for completion.
    }
}
```

**Behavior:** The implementation uses `Task.detached` and a semaphore-backed result box, and may throw `PerformAsyncError.timeout` or `PerformAsyncError.operationFailed`.

### LayoutConverter

Cross-cutting audio-layout helper used by export and media-processing code. The core type is a `Sendable` value type declared in `cutter2/Utilities/LayoutConverter.swift`, with additional conversion/layout helpers implemented in `LayoutConverter+*.swift` files.

```swift
public struct LayoutConverter: Sendable {
    public init() {}

    typealias LayoutPtr = UnsafePointer<AudioChannelLayout>
    typealias MutableLayoutPtr = UnsafeMutablePointer<AudioChannelLayout>
    typealias DescriptionsPtr = UnsafeBufferPointer<AudioChannelDescription>
    typealias MutableDescriptionsPtr = UnsafeMutableBufferPointer<AudioChannelDescription>
}
```

### MovieHeaderValidator

Movie file validation helper used during document open/prepare flows.

```swift
struct MovieHeaderValidator {
    enum ValidationError: LocalizedError {
        case noTracks
        case invalidDuration
    }

    static func validate(_ movie: AVMutableMovie) -> ValidationError? {
        if movie.tracks.isEmpty {
            return .noTracks
        }
        if !CMTIME_IS_VALID(movie.duration) || !CMTIME_IS_NUMERIC(movie.duration) {
            return .invalidDuration
        }
        return nil
    }

    static func isValid(_ movie: AVMutableMovie) -> Bool {
        validate(movie) == nil
    }
}
```

**Usage in `DocumentController.prepareOpen`:**
```swift
if let error = MovieHeaderValidator.validate(movie) {
    // Present specific error: .noTracks or .invalidDuration
}
```

### UndoManagerWrapper

Wrapper for undo registration that keeps undo handling on the main actor.

```swift
@MainActor
final class UndoManagerWrapper {
    private let undoManager: UndoManager

    init(_ undoManager: UndoManager) {
        self.undoManager = undoManager
    }

    func registerUndo<T: AnyObject>(
        withTarget target: T,
        handler: @MainActor @escaping (T) -> Void
    ) {
        undoManager.registerUndo(withTarget: target, handler: handler)
    }

    func setActionName(_ actionName: String) {
        undoManager.setActionName(actionName)
    }

    func removeAllActions(withTarget target: AnyObject) {
        undoManager.removeAllActions(withTarget: target)
    }
}
```

**Concurrency contract:**
- The wrapper itself is `@MainActor` isolated.
- `registerUndo` takes a main-actor handler rather than a generic `@Sendable` closure.
- The implementation delegates to `UndoManager` directly; it does not use `ActorUtilities.performSyncOnMainActor` internally.

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
protocol ViewControllerDelegate: TimelineUpdateDelegate, Sendable {
    func hasSelection() -> Bool
    func hasDuration() -> Bool
    func hasClipOnPBoard() -> Bool
    //
    func debugInfo()
    func timeOfPosition(_ percentage: Float64) -> CMTime
    func positionOfTime(_ time: CMTime) -> Float64
    //
    func doCut() throws
    func doCopy() throws
    func doPaste() throws
    func doDelete() throws
    func selectAll()
    //
    func doStepByCount(_ count: Int64, _ resetStart: Bool, _ resetEnd: Bool)
    func doStepBySecond(_ offset: Float64, _ resetStart: Bool, _ resetEnd: Bool)
    func doVolumeOffset(_ percent: Int)
    //
    func doMoveLeft(_ optFlag: Bool, _ shiftFlag: Bool, _ resetStart: Bool, _ resetEnd: Bool)
    func doMoveRight(_ optFlag: Bool, _ shiftFlag: Bool, _ resetStart: Bool, _ resetEnd: Bool)
    //
    func doSetSlow(_ ratio: Float)
    func doSetRate(_ offset: Int)
    func doTogglePlay()
}
```

### TimelineUpdateDelegate

Protocol for Timeline ↔ ViewController communication.

```swift
@MainActor
protocol TimelineUpdateDelegate: AnyObject {
    // called on mouse down/drag event
    func didUpdateCursor(to position: Float64)
    func didUpdateStart(to position: Float64)
    func didUpdateEnd(to position: Float64)
    func didUpdateSelection(from fromPos: Float64, to toPos: Float64)
    //
    func presentationInfo(at position: Float64) -> PresentationInfo?
    func previousInfo(of range: CMTimeRange) -> PresentationInfo?
    func nextInfo(of range: CMTimeRange) -> PresentationInfo?
    //
    func doSetCurrent(to goTo: anchor)
    func doSetStart(to goTo: anchor)
    func doSetEnd(to goTo: anchor)
}
```

---

## Error Types

### DocumentError

Errors related to document operations.

```swift
enum DocumentError: Error, NSErrorConvertible {
    case incompatibleFileType
    case unableToOpenFile
    case emptyMovie
    case unsupportedSaveOperation
    case unsupportedFileExtension
    case fileTypeAndExtensionMismatch
    case overwriteSelfContainedWithReference
    case internalError
    case modifyCaparFailed
    
    var nsError: NSError {
        // Returns NSError with localized message
    }
}
```

### MovieWriterError

Errors related to movie writing and export operations.

```swift
enum MovieWriterError: Error, NSErrorConvertible {
    case compatibilityError
    case assetReaderWriterUnavailable
    case anotherExportSessionRunning
    case movieWriterFailed
    case assetReaderWriterFailed
    case operationCancelled
    case unknown
    
    static let errorDomain = "MovieWriterError"
    
    var nsError: NSError {
        // Returns NSError with localized message
    }
}
```

---

## Types and Enums

### boxSize

Movie box size breakdown (header / video / audio / other tracks).

```swift
public struct boxSize {
    public internal(set) var headerSize: Int64 = 0
    public internal(set) var videoSize: Int64 = 0, videoCount: Int64 = 0
    public internal(set) var audioSize: Int64 = 0, audioCount: Int64 = 0
    public internal(set) var otherSize: Int64 = 0, otherCount: Int64 = 0
    
    public init(headerSize: Int64 = 0, videoSize: Int64 = 0, videoCount: Int64 = 0,
                audioSize: Int64 = 0, audioCount: Int64 = 0,
                otherSize: Int64 = 0, otherCount: Int64 = 0)
}
```

### dimensionsType

Type of dimensions for `dimensions(of:)`.

```swift
public enum dimensionsType {
    case clean
    case production
    case encoded
}
```

### RefOrSelfCont

Option set describing whether the movie contains reference and/or self-contained tracks.

```swift
public struct RefOrSelfCont: OptionSet, Sendable {
    public let rawValue: Int
    public static let hasReferenceTrack = RefOrSelfCont(rawValue: 1<<0)
    public static let hasSelfContTrack = RefOrSelfCont(rawValue: 1<<1)
    
    public init(rawValue: Int)
}
```

### PresentationInfo

Timeline presentation information for a time range.

```swift
public struct PresentationInfo {
    public private(set) var timeRange: CMTimeRange
    public private(set) var startSecond: Float64
    public private(set) var endSecond: Float64
    public private(set) var movieDuration: Float64
    public private(set) var startPosition: Float64
    public private(set) var endPosition: Float64
    
    public init(range: CMTimeRange, of movie: AVMutableMovie)
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

// Set selection range
let start = CMTime(seconds: 10, preferredTimescale: 600)
let end = CMTime(seconds: 20, preferredTimescale: 600)
mutator.selectedTimeRange = CMTimeRange(start: start, end: end)

// Cut the selection
mutator.cutSelection(using: document.undoManagerWrapper)

// Save changes
try await document.save(to: url, ofType: "mov", for: .saveOperation)
```

### Exporting with Custom Settings

```swift
let settings: [String: any Sendable] = [
    kVideoCodecKey: "avc1", // FourCC: avc1 / hvc1 / apcn / apcs / apco
    kAudioCodecKey: "aac ", // FourCC: "aac " (AAC) / "lpcm" (LPCM)
    kVideoKbpsKey: 10_000,
    kAudioKbpsKey: 256,
    kCopyOtherMediaKey: true,
]

try await document.movieMutator?.exportCustomMovie(to: outputURL, fileType: .mp4, settings: settings)
```

### Handling Errors

```swift
do {
    try await document.save(to: url, ofType: "mov", for: .saveOperation)
} catch {
    document.showErrorSheet(error)
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
- [CODEBASE_REVIEW.md](CODEBASE_REVIEW.md) - Detailed source-level code review findings

---

**Document Status**: 🚧 Work in Progress  
**Last Updated**: February 5, 2026  
**Next Review**: After major API changes or releases

**Note**: Full API documentation generation using DocC or jazzy is planned for future releases.
