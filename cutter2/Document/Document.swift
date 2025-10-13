//
//  Document.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import AVKit

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
            let info = [NSLocalizedDescriptionKey: "Incompatible file type detected."]
            return NSError(domain: domain, code: unimpErr, userInfo: info)
        case .unableToOpenFile:
            let info = [NSLocalizedDescriptionKey: "Unable to open specified file as AVMovie."]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .emptyMovie:
            let info = [NSLocalizedDescriptionKey: "Empty movie cannot be saved."]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .unsupportedSaveOperation:
            let info = [NSLocalizedDescriptionKey: "Unsupported SaveOperationType detected."]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .unsupportedFileExtension:
            let info = [NSLocalizedDescriptionKey: "Unsupported file extension is detected."]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .fileTypeAndExtensionMismatch:
            let info = [NSLocalizedDescriptionKey: "Mismatch between file extension and file type."]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .overwriteSelfContainedWithReference:
            let info = [NSLocalizedDescriptionKey: "Please choose different file name."]
            return NSError(domain: domain, code: paramErr, userInfo: info)
        case .internalError:
            let info = [NSLocalizedDescriptionKey: "Internal error occurred."]
            return NSError(domain: domain, code: unimpErr, userInfo: info)
        case .modifyCaparFailed:
            let info = [NSLocalizedDescriptionKey: "Failed to modify CAPAR extensions."]
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
    
    //
    public var alert: NSAlert? = nil
    
    //
    public var lastUpdateAt: UInt64 = 0
    
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
        // Swift.print(#function, #line, #file)
        
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
        let windowController = storyboard.instantiateController(withIdentifier: sid) as! WindowController
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
        // Swift.print(#function, #line, #file)
        
        // Prepare C function and closingBlock()
        let obj: AnyObject = delegate as AnyObject
        let Class: AnyClass = object_getClass(delegate)!
        let method = class_getMethodImplementation(Class, shouldCloseSelector!)
        typealias signature = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        let function = unsafeBitCast(method, to: signature.self)
        
        self.closingBlock = {[obj, shouldCloseSelector, contextInfo, weak self] (flag) -> Void in // @escaping
            // Swift.print(#function, #line, #file, "shouldClose =", flag)
            
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            function(obj, shouldCloseSelector!, self, flag, contextInfo)
        }
        
        // Let super call Self.document(_:shouldClose:ContextInfo:)
        let delegate: Any = self
        let shouldCloseSelector: Selector = #selector(Document.document(_:shouldClose:contextInfo:))
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }
    
    @objc func document(_ document: NSDocument, shouldClose flag: Bool, contextInfo: UnsafeMutableRawPointer?) {
        // Swift.print(#function, #line, #file, "shouldClose =", flag)
        
        if flag {
            self.cleanup() // my cleanup method
        }
        
        if let closingBlock = self.closingBlock {
            closingBlock(flag)
            self.closingBlock = nil
        }
    }
    
    override func close() {
        // Swift.print(#function, #line, #file)
        
        super.close()
    }
    
    deinit {
        // Swift.print(#function, #line, #file)
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
