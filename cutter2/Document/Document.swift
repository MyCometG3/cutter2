//
//  Document.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import AVKit
import os.log

/* ============================================ */
// MARK: - DocumentError
/* ============================================ */

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
        let domain = NSOSStatusErrorDomain
        switch self {
        case .incompatibleFileType:
            let message = NSLocalizedString("error.document.incompatible_file_type",
                                            comment: "Error message when file type is incompatible")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: unimpErr, userInfo: info)
        case .unableToOpenFile:
            let message = NSLocalizedString("error.document.unable_to_open_file",
                                            comment: "Error when file cannot be opened as AVMovie")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .emptyMovie:
            let message = NSLocalizedString("error.document.empty_movie",
                                            comment: "Error when trying to save an empty movie")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .unsupportedSaveOperation:
            let message = NSLocalizedString("error.document.unsupported_save_operation",
                                            comment: "Error when save operation type is not supported")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .unsupportedFileExtension:
            let message = NSLocalizedString("error.document.unsupported_file_extension",
                                            comment: "Error when file extension is not supported")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .fileTypeAndExtensionMismatch:
            let message = NSLocalizedString("error.document.file_type_extension_mismatch",
                                            comment: "Error when file extension doesn't match file type")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .overwriteSelfContainedWithReference:
            let message = NSLocalizedString("error.document.overwrite_self_contained_with_reference",
                                            comment: "Error when trying to overwrite self-contained with reference")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .internalError:
            let message = NSLocalizedString("error.document.internal_error",
                                            comment: "Generic internal error message")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: unimpErr, userInfo: info)
        case .modifyCaparFailed:
            let message = NSLocalizedString("error.document.modify_capar_failed",
                                            comment: "Error when modifying CAPAR extensions fails")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: unimpErr, userInfo: info)
        }
    }
}

extension Document {
    /// Throw an error with a specific reason.
    /// - Parameters:
    ///   - error: The `DocumentError` to throw.
    ///   - reason: An optional reason for the error.
    /// - Returns: Never
    internal nonisolated func throwError(_ error: DocumentError, reason: String? = nil) throws -> Never {
        try ErrorUtilities.throwError(error, reason: reason)
    }
}

/* ============================================ */
// MARK: - KVO context token (L-33)
/* ============================================ */

/// Identity-only reference type used as the per-document KVO context.
///
/// The instance is never dereferenced and has no stored state; only its
/// identity (address) is compared. A stateless `final` class conforms to
/// `Sendable` directly, so no `@unchecked` opt-out is needed. Internal (not
/// `private`) so both `Document` (token storage) and `Document+Observers.swift`
/// (registration / callback) can refer to it within the module, and the unit
/// tests (`DocumentKVOContextTests`) can verify the pointer contract directly.
final class PlayerKVOContextToken: Sendable {

    /// Raw `context` pointer derived from this token's identity. Single
    /// derivation site shared by registration, callback comparison, and the
    /// unit tests (internal test helper).
    ///
    /// `Unmanaged.passUnretained` performs no memory management and allocates
    /// nothing. Usage contract: do not store the pointer in stored or global
    /// state, pass it as a `Sendable` argument, capture it in a `Task`, or
    /// keep it beyond this token's lifetime — derive and compare it in place.
    var contextPointer: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }
}

struct SaveMode: Sendable {
    var selfContained: Bool = false
    var overwrite: Bool = false
    var useAccessory: Bool = false
    var copyData: Bool = false
}

@MainActor
class Document: NSDocument, NSOpenSavePanelDelegate, AccessoryViewDelegate, ViewControllerDelegate {
    
    /* ============================================ */
    // MARK: - Public properties
    /* ============================================ */
    
    /// Strong reference to the document's movie mutator.
    public var movieMutator: MovieMutator? = nil
    
    /// The window of the document's first window controller.
    ///
    /// Returns `nil` until a window controller has been created.
    public var window: Window? {
        return self.windowControllers.first?.window as? Window
    }

    /// The document's view controller, or `nil` when the window content is unavailable.
    public var viewController: ViewController? {
        return window?.contentViewController as? ViewController
    }

    /// The document's player view, or `nil` when the view controller is unavailable.
    public var playerView: AVPlayerView? {
        return viewController?.playerView
    }

    /// The player associated with the document's player view.
    public var player: AVPlayer? {
        return playerView?.player
    }

    /// The current player item, or `nil` when no player is attached.
    public var playerItem: AVPlayerItem? {
        return player?.currentItem
    }

    /// The timer used for periodic playback-position polling.
    public var timer: Timer? = nil

    /// The interval between playback-position polls, in seconds.
    public var pollingInterval: TimeInterval = 1.0/15

    /// Per-document KVO context token (L-33).
    ///
    /// `nonisolated` + `Sendable` so the nonisolated `observeValue` override can
    /// derive the context pointer without a MainActor hop. The address is stable
    /// for the lifetime of the Document instance — the same per-instance
    /// stability contract the legacy `kvoContext` storage provided. Never
    /// weakified, regenerated, or shared outside this instance.
    nonisolated private let playerKVOContextToken = PlayerKVOContextToken()

    /// Raw `context` pointer identifying this document's KVO registrations (L-33).
    ///
    /// Forwards to the token's `contextPointer` derivation at each use site and
    /// allocates nothing. (The pointer is not precomputed into stored state: raw
    /// pointer types are non-`Sendable`, so they cannot be kept in nonisolated
    /// stored state at all.)
    ///
    /// - Usage contract: the returned pointer must not be stored in stored or
    ///   global state, passed as a `Sendable` argument, captured in a `Task`, or
    ///   kept beyond the token lifetime. It is consumed in place by the
    ///   `addObserver`/`removeObserver` calls and the callback comparison.
    nonisolated var playerKVOContext: UnsafeMutableRawPointer {
        playerKVOContextToken.contextPointer
    }

    /// Storage used as the KVO context for document observations.
    ///
    /// Retained for source compatibility: this member is `public` and may be
    /// referenced by code outside this repository. It is no longer used as the
    /// context for document observations (see L-33). Complete removal is a
    /// public API change tracked as a separate issue.
    @available(*, deprecated, message: "KVO context is managed internally.")
    public var kvoContext = 0

    /// The save panel currently associated with the document.
    public weak var savePanel: NSSavePanel? = nil

    /// The alert used to display progress or error information.
    public var alert: NSAlert? = nil

    /// The progress indicator used for visual feedback.
    public var progressIndicator: NSProgressIndicator? = nil

    /// The timestamp of the last progress update, in nanoseconds.
    public var lastUpdateAt: UInt64 = 0

    /// The last progress value reported after exponential smoothing.
    public var lastReportedProgress: Float = 0.0

    /// The current save or export progress object.
    public var saveProgress: Progress? = nil

    /// The most recently queried movie time.
    public var cachedTime = CMTime.invalid

    /// Whether `cachedTime` lies within the cached last-sample range.
    public var cachedWithinLastSampleRange: Bool = false

    /// The last sample range used by playback-position queries.
    public var cachedLastSampleRange: CMTimeRange? = nil

    func resetPositionCache() {
        cachedTime = .invalid
        cachedWithinLastSampleRange = false
        cachedLastSampleRange = nil
    }
    
    //
    lazy var undoManagerWrapper: UndoManagerWrapper = UndoManagerWrapper(self.undoManager!)
    
    /* ============================================ */
    // MARK: - Private properties
    /* ============================================ */
    
    // SavePanel with Accessory View support
    internal var accessoryVC: AccessoryViewController? = nil
    
    // Support #selector(NSDocument._something:didSomething:soContinue:)
    private var closingBlock: ((Bool) -> Void)? = nil
    
    // Transcode preferred type
    internal var transcoding: Bool = false
    
    // Current Dimensions type
    internal var dimensionsType: dimensionsType = .clean
    
    // SavePanel support
    internal var saveMode = SaveMode()
    internal var accessoryVCselfContained: Bool = false
    
    //
    internal var mutationObserver: NSObjectProtocol? = nil
    
    /// Reload/seek suppression state machine (S-17).
    internal let playerSeekSequencer = PlayerSeekSequencer()
    
    /* ============================================ */
    // MARK: - NSDocument methods/properties
    /* ============================================ */
    
    override init() {
        super.init()
        
        self.hasUndoManager = true
        
        let def = UserDefaults.standard
        def.register(defaults: [
            kTranscodePresetKey: kTranscodePresetCustom,
            kTranscodeTypeKey:4, // = Custom
            kTrancode0Key:3,
            kTrancode1Key:2,
            kTrancode2Key:0,
            kTrancode3Key:6,
            kAVFileTypeKey:AVFileType.mov,
            kHEVCReadyKey:false,
            
            kLPCMDepthKey:0, // "aac "
            kAudioKbpsKey:192, // 192Kbps
            kVideoKbpsKey:4096, // 4096Kbps
            kCopyFieldKey:true,
            kCopyNCLCKey:true,
            kCopyOtherMediaKey:true,
            kVideoEncodeKey:true,
            kAudioEncodeKey:true,
            kVideoCodecKey:0, // "avc1"
            kAudioCodecKey:0, // "aac "
        ])
    }
    
    // nonisolated
    override class var autosavesInPlace: Bool {
        return false
    }
    
    override func makeWindowControllers() {
        
        if self.fileURL == nil {
            // Prepare null AVMutableMovie
            let scale: CMTimeScale = 600
            let movie: AVMutableMovie? = AVMutableMovie()
            if let movie = movie {
                movie.timescale = scale
                movie.preferredRate = 1.0
                movie.preferredVolume = 1.0
                movie.interleavingPeriod = CMTimeMakeWithSeconds(0.5, preferredTimescale: scale)
                movie.preferredTransform = CGAffineTransform.identity
                movie.isModified = false
                
                //
                self.removeMutationObserver()
                self.removeAllUndoRecords()
                self.movieMutator = MovieMutator(with: movie)
                self.addMutationObserver()
            } else {
                LoggingSystem.video.error("AVMutableMovie() returned nil")
                NSSound.beep()
                return
            }
        }
        
        // Returns the Storyboard that contains your Document window.
        let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
        
        // Instantiate and Register Window Controller
        let sid: NSStoryboard.SceneIdentifier = "Document Window Controller"
        guard let windowController = storyboard.instantiateController(withIdentifier: sid) as? WindowController else {
            NSSound.beep()
            return
        }
        self.addWindowController(windowController)
        
        // Set viewController.delegate to self
        self.viewController?.delegate = self
        self.viewController?.setup()
        
        // Resize window 100%
        if let _ = windowController.window {
            let menu = NSMenuItem(title: "dummy", action: nil, keyEquivalent: "")
            menu.tag = -1 // Resize to 100% keeping Top-Left corner
            self.resizeWindow(menu)
        }
        
        //
        self.updateGUI(CMTime.zero, CMTimeRange.zero, true)
        self.doVolumeOffset(100)
    }
    
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        
        // Prepare C function and closingBlock()
        let obj: AnyObject = delegate as AnyObject
        let Class: AnyClass = object_getClass(delegate)!
        let method = class_getMethodImplementation(Class, shouldCloseSelector!)
        typealias signature = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        let function = unsafeBitCast(method, to: signature.self)
        
        self.closingBlock = {[obj, shouldCloseSelector, contextInfo, weak self] (flag) -> Void in // @escaping
            
            guard let self else { return }
            function(obj, shouldCloseSelector!, self, flag, contextInfo)
        }
        
        // Let super call Self.document(_:shouldClose:ContextInfo:)
        let delegate: Any = self
        let shouldCloseSelector: Selector = #selector(Document.document(_:shouldClose:contextInfo:))
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }
    
    @objc func document(_ document: NSDocument, shouldClose flag: Bool, contextInfo: UnsafeMutableRawPointer?) {
        
        if flag {
            self.cleanup() // my cleanup method
        }
        
        if let closingBlock = self.closingBlock {
            closingBlock(flag)
            self.closingBlock = nil
        }
    }
    
    internal var didCleanup: Bool = false
    
    override func close() {
        cleanup()
        super.close()
    }
    
    @MainActor
    deinit {
        self.cleanup()
    }
    
    /* ============================================ */
    /* ============================================ */
    // MARK: - File I/O Operations
    // NOTE: Revert, Read, and Write operations are now in Document+FileIO.swift
    /* ============================================ */
    
    /* ============================================ */
    // MARK: - Save Panel Operations
    // NOTE: Save panel and delegate implementations are now in Document+SavePanel.swift
    /* ============================================ */
    
    /* ============================================ */
    // MARK: - Export/Transcode Operations
    // NOTE: Export and transcode operations are now in Document+Export.swift
    /* ============================================ */
    
    /* ============================================ */
    // MARK: - UI Operations
    // NOTE: Window resize and transform operations are now in Document+UI.swift
    /* ============================================ */
}
