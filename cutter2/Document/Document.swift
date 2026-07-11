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
// MARK: -
/* ============================================ */

@MainActor
class Document: NSDocument, NSOpenSavePanelDelegate, AccessoryViewDelegate {
    
    /* ============================================ */
    // MARK: - Public properties
    /* ============================================ */
    
    /// Strong reference to MovieMutator
    public var movieMutator: MovieMutator? = nil
    
    // Computed properties
    public var window: Window? {
        return self.windowControllers[0].window as? Window
    }
    public var viewController: ViewController? {
        return window?.contentViewController as? ViewController
    }
    public var playerView: AVPlayerView? {
        return viewController?.playerView
    }
    public var player: AVPlayer? {
        return playerView?.player
    }
    public var playerItem: AVPlayerItem? {
        return player?.currentItem
    }
    
    // Polling timer
    public var timer: Timer? = nil
    public var pollingInterval: TimeInterval = 1.0/15
    
    // KVO Context
    public var kvoContext = 0
    
    // SavePanel with Accessory View support
    public weak var savePanel: NSSavePanel? = nil
    
    /// Alert for progress dialog
    public var alert: NSAlert? = nil
    
    /// Progress indicator for visual feedback
    public var progressIndicator: NSProgressIndicator? = nil
    
    /// Timestamp of last progress update (nanoseconds)
    public var lastUpdateAt: UInt64 = 0
    
    /// Last reported progress value for smooth animation
    /// Used for exponential smoothing to avoid jarring progress jumps
    public var lastReportedProgress: Float = 0.0
    
    // NSProgress support for save/export operations
    public var saveProgress: Progress? = nil
    
    //
    public var cachedTime = CMTime.invalid
    public var cachedWithinLastSampleRange: Bool = false
    public var cachedLastSampleRange: CMTimeRange? = nil
    
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
    internal var selfcontainedFlag: Bool = false
    internal var overwriteFlag: Bool = false
    internal var useAccessory: Bool = false
    internal var copyData: Bool = false
    internal var accessoryVCselfContained: Bool = false
    
    //
    internal var mutationObserver: NSObjectProtocol? = nil
    
    /// The latest scheduled player reload task. Replaced/cancelled when a new
    /// reload request arrives so stale AVPlayerItems are never applied after a
    /// newer edit has already requested another refresh.
    internal var playerReloadTask: Task<Void, Never>? = nil
    
    /// Monotonic generation counter for player reload requests. Used so only
    /// the newest in-flight reload task may clear `playerReloadTask`.
    internal var playerReloadGeneration: UInt64 = 0
    
    /// Suppress queryPosition while a reload/seek is in progress.
    internal var suppressQueryPosition: Bool = false
    
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
                preconditionFailure("ERROR: Failed on AVMutableMovie()")
            }
        }
        
        // Returns the Storyboard that contains your Document window.
        let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
        
        // Instantiate and Register Window Controller
        let sid: NSStoryboard.SceneIdentifier = "Document Window Controller"
        guard let windowController = storyboard.instantiateController(withIdentifier: sid) as? WindowController else {
            preconditionFailure("Failed to instantiate WindowController")
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

    deinit {
        DispatchQueue.main.async { [weak self] in
            self?.cleanup()
        }
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
