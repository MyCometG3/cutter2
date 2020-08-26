//
//  Document.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2019年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import AVKit

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
    
    //
    public var cachedTime = CMTime.invalid
    public var cachedWithinLastSampleRange: Bool = false
    public var cachedLastSampleRange: CMTimeRange? = nil
    
    /* ============================================ */
    // MARK: - Private properties
    /* ============================================ */
    
    // SavePanel with Accessory View support
    private var accessoryVC: AccessoryViewController? = nil
    
    // Support #selector(NSDocument._something:didSomething:soContinue:)
    private var closingBlock: ((Bool) -> Void)? = nil
    
    // Transcode preferred type
    private var transcoding: Bool = false
    
    // Current Dimensions type
    private var dimensionsType: dimensionsType = .clean
    
    // SavePanel support
    private var selfcontainedFlag: Bool = false
    private var overwriteFlag: Bool = false
    private var useAccessory: Bool = false
    private var copyData: Bool = false
    private var accessoryVCselfContained: Bool = false
    
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
                assert(false, "ERROR: Failed on AVMutableMovie()")
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
        
        self.closingBlock = {[unowned obj, shouldCloseSelector, contextInfo] (flag) -> Void in // @escaping
            // Swift.print(#function, #line, #file, "shouldClose =", flag)
            
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
    // MARK: - Revert
    /* ============================================ */
    
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        // Swift.print(#function, #line, #file)
        
        try super.revert(toContentsOf: url, ofType: typeName)
        
        // reset GUI when revert
        self.updateGUI(CMTime.zero, CMTimeRange.zero, true)
        self.doVolumeOffset(100)
    }
    
    /* ============================================ */
    // MARK: - Read
    /* ============================================ */
    
    override func read(from url: URL, ofType typeName: String) throws {
        // Swift.print(#function, #line, #file)
        
        // Check UTI for AVMovie fileType
        let fileType = AVFileType.init(rawValue: typeName)
        if AVMovie.movieTypes().contains(fileType) == false {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Incompatible file type detected."
            info[NSLocalizedFailureReasonErrorKey] = "(UTI:" + typeName + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: info)
        }
        
        // Swift.print("##### READ STARTED #####")
        
        // Setup document with new AVMovie
        let movie :AVMutableMovie? = AVMutableMovie(url: url, options: nil)
        if let movie = movie {
            self.removeMutationObserver()
            self.removeAllUndoRecords()
            self.movieMutator = MovieMutator(with: movie)
            self.addMutationObserver()
        } else {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Unable to open specified file as AVMovie."
            info[NSLocalizedFailureReasonErrorKey] = url.lastPathComponent + " at " + url.deletingLastPathComponent().path
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        // Swift.print("##### READ FINISHED #####")
        
        // NOTE: following initialization is performed at makeWindowControllers()
    }
    
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        return true
    }
    
    /* ============================================ */
    // MARK: - Write
    /* ============================================ */
    
    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        // Swift.print(#function, #line, #file)
        
        do {
            // Check if current AVMovie reference URL = write target URL
            selfcontainedFlag = validateIfSelfContained(for: url)
            
            // Check if current document URL = write target URL
            if let original = self.fileURL, original == url {
                overwriteFlag = true
            } else {
                overwriteFlag = false
            }
            
            // Check if accessory view is presented in SavePanel
            if saveOperation == .saveAsOperation || saveOperation == .saveToOperation {
                useAccessory = true
            } else {
                useAccessory = false
            }
            
            // Check if user requested to save as ReferenceMovie
            if useAccessory {
                copyData = accessoryVCselfContained
            } else {
                copyData = selfcontainedFlag
            }
            
            #if true
            Swift.print("NOTE: source file:", self.displayName ?? "n/a")
            Swift.print("NOTE: target file:", url.lastPathComponent)
            Swift.print("NOTE: selfcontainedFlag:", selfcontainedFlag)
            Swift.print("NOTE: overwriteFlag:", overwriteFlag)
            Swift.print("NOTE: useAccessory:", useAccessory)
            Swift.print("NOTE: copyData:", copyData)
            #endif
        }
        
        // Verify if user is attemping to overwrite sourceMovieFile with ReferenceMovieFile
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        if fileType == .mov {
            if overwriteFlag && selfcontainedFlag && copyData == false {
                // Reset cached accessoryVCselfContained to avoid unexpected behavior
                self.accessoryVCselfContained = true
                
                var info: [String:Any] = [:]
                info[NSLocalizedDescriptionKey] = "Please choose different file name."
                info[NSLocalizedFailureReasonErrorKey] = "You cannot overwrite self-contained movie with reference movie."
                throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
            }
        }
        
        // Verify UTI compatibility with AVFileType
        if AVMovie.movieTypes().contains(fileType) == false {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Incompatible file type detected."
            info[NSLocalizedFailureReasonErrorKey] = "(UTI:" + typeName + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
        
        // Sandbox support - keep source document security scope bookmark
        if saveOperation == .saveAsOperation, let srcURL = self.fileURL {
            DispatchQueue.main.async { [unowned self] in // @escaping
                // Swift.print(#function, #line, #file)
                
                let fileType: AVFileType = AVFileType.init(rawValue: typeName)
                guard fileType == .mov else { return }
                
                guard let accessoryVC = self.accessoryVC else { return }
                let saveAsRefMov: Bool = (accessoryVC.selfContained == false)
                guard saveAsRefMov else { return }
                
                // SaveAs reference movie - Need to keep readonly access to original
                let app: AppDelegate = NSApp.delegate as! AppDelegate
                app.addBookmark(for: srcURL)
            }
        }
        
        // Trigger actual write operation (saveTo, save/saveAs)
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        
        // Refresh internal movie (to sync selfcontained <> referece movie change)
        if saveOperation == .saveAsOperation {
            self.refreshMovie()
        }
    }
    
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        // Swift.print(#function, #line, #file)
        
        do {
            switch saveOperation {
            case .saveToOperation:
                // Export...
                let transcodePreset: String? = UserDefaults.standard.string(forKey: kTranscodePresetKey)
                let preset = transcodePreset ?? kTranscodePresetCustom
                if preset == kTranscodePresetCustom {
                    try exportCustom(to: url, ofType: typeName)
                } else {
                    try export(to: url, ofType: typeName, preset: preset)
                }
            case .saveOperation, .saveAsOperation:
                // Save.../Save as...
                try super.write(to: url, ofType: typeName, for: saveOperation,
                                originalContentsURL: absoluteOriginalContentsURL)
            default:
                var info: [String:Any] = [:]
                info[NSLocalizedDescriptionKey] = "Unsupported SaveOperationType detected."
                info[NSLocalizedFailureReasonErrorKey] = "No autoSave feature is implemented yet."
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: info)
            }
        } catch {
            showErrorSheet(error)
            throw error // rethrow to abort write operation
        }
    }
    
    override func write(to url: URL, ofType typeName: String) throws {
        // Swift.print(#function, #line, #file)
        
        // Show busy sheet
        let mutator :MovieMutator = self.movieMutator!
        showBusySheet("Writing...", "Please hold on second(s)...")
        mutator.unblockUserInteraction = { self.unblockUserInteraction() }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }
        
        // Swift.print("##### WRITE STARTED #####")
        
        // Check fileType (mov or other)
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        if fileType == .mov {
            // Write mov file as either self-contained movie or reference movie
            try mutator.writeMovie(to: url, fileType: fileType, copySampleData: self.copyData)
        } else {
            // Export as specified file type with AVAssetExportPresetPassthrough
            try mutator.exportMovie(to: url, fileType: fileType, presetName: nil)
        }
        
        // Swift.print("##### WRITE FINISHED #####")
    }
    
    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String,
                                         for saveOperation: NSDocument.SaveOperationType) -> Bool {
        return true
    }
    
    private func refreshMovie() {
        // Swift.print(#function, #line, #file)
        
        // SaveAs triggers internal movie refresh (to sync selfcontained <> referece movie change)
        DispatchQueue.main.async {[unowned self] in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard let url: URL = self.fileURL else { return }
            let newMovie: AVMovie? = AVMovie(url: url, options: nil)
            if let newMovie = newMovie {
                guard let mutator = self.movieMutator else { return }
                guard let data = newMovie.movHeader else { return }
                
                let time: CMTime = mutator.insertionTime
                let range: CMTimeRange = mutator.selectedTimeRange
                let newMovieRange: CMTimeRange = newMovie.range
                var newTime: CMTime = CMTimeClampToRange(time, range: newMovieRange)
                let newRange: CMTimeRange = CMTimeRangeGetIntersection(range, otherRange: newMovieRange)
                
                newTime = CMTIME_IS_VALID(newTime) ? newTime : CMTime.zero
                
                self.removeMutationObserver()
                self.removeAllUndoRecords()
                let newMutator = MovieMutator(with: newMovie)
                _ = newMutator.reloadAndNotify(from: data, range: newRange, time: newTime)
                self.movieMutator = newMutator
                self.addMutationObserver()
            }
        }
    }
    
    /* ============================================ */
    // MARK: - Save panel
    /* ============================================ */
    
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return false }
        
        // prepare accessory view controller
        if self.accessoryVC == nil {
            let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
            let sid: NSStoryboard.SceneIdentifier = "Accessory View Controller"
            let accessoryVC = storyboard.instantiateController(withIdentifier: sid) as! AccessoryViewController
            self.accessoryVC = accessoryVC
            accessoryVC.loadView()
            accessoryVC.delegate = self
        }
        guard let accessoryVC = self.accessoryVC else { return false }
        
        // prepare file types same as current source
        var uti: String = self.fileType ?? AVFileType.mov.rawValue
        if self.transcoding {
            let avFileTypeRaw: String? = UserDefaults.standard.string(forKey: kAVFileTypeKey)
            if let avFileTypeRaw = avFileTypeRaw {
                uti = AVFileType.init(avFileTypeRaw).rawValue
            }
        }
        
        // prepare accessory view
        do {
            try accessoryVC.updateDataSizeText(mutator.headerSize())
            
            accessoryVC.fileType = AVFileType.init(uti)
            if accessoryVC.fileType == .mov && self.transcoding == false {
                if let url = self.fileURL {
                    accessoryVC.selfContained = validateIfSelfContained(for: url)
                } else {
                    accessoryVC.selfContained = false
                }
            } else {
                accessoryVC.selfContained = true
            }
        } catch {
            return false
        }
        
        // prepare NSSavePanel
        savePanel.canSelectHiddenExtension = true
        savePanel.isExtensionHidden = false
        savePanel.delegate = self
        savePanel.allowedFileTypes = [uti]
        savePanel.accessoryView = accessoryVC.view
        self.savePanel = savePanel
        
        return true
    }
    
    override var shouldRunSavePanelWithAccessoryView: Bool {
        return false
    }
    
    override var fileTypeFromLastRunSavePanel: String? {
        // Swift.print(#function, #line, #file)
        
        if let accessoryVC = self.accessoryVC {
            let type: String = accessoryVC.fileType.rawValue
            return type
        } else {
            return AVFileType.mov.rawValue
        }
    }
    
    /* ============================================ */
    // MARK: - NSOpenSavePanelDelegate protocol
    /* ============================================ */
    
    // NSOpenSavePanelDelegate protocol
    public func panel(_ sender: Any, validate url: URL) throws {
        // Swift.print(#function, #line, #file)
        
        guard let accessoryVC = self.accessoryVC else {
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: nil)
        }
        
        guard let fileType = fileTypeForURL(url) else {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Unsupported file extension is detected."
            info[NSLocalizedFailureReasonErrorKey] = "(" + url.pathExtension + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        if accessoryVC.fileType != fileType {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Mismatch between file extension and file type."
            info[NSLocalizedFailureReasonErrorKey] =
                "URL(" + fileType.rawValue + ") vs Popup(" + accessoryVC.fileType.rawValue + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: info)
        }
        
        // Cache last selection state in MainThread here
        self.accessoryVCselfContained = accessoryVC.selfContained
    }
    
    // NSOpenSavePanelDelegate protocol
    public func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? {
        // Swift.print(#function, #line, #file, (okFlag ? "confirmed" : "not yet"))
        
        return filename
    }
    
    /// Get AVFileType from specified URL
    private func fileTypeForURL(_ url: URL) -> AVFileType? {
        // Swift.print(#function, #line, #file)
        
        let pathExt: String = url.pathExtension.lowercased()
        let dict: [String:AVFileType] = [
            "mov":AVFileType.mov,
            "mp4":AVFileType.mp4,
            "m4v":AVFileType.m4v,
            "m4a":AVFileType.m4a
        ]
        if let fileType = dict[pathExt] {
            return fileType
        }
        return nil
    }
    
    /* ============================================ */
    // MARK: - AccessoryViewDelegate protocol
    /* ============================================ */
    
    // AccessoryViewDelegate protocol
    public func didUpdateFileType(_ fileType: AVFileType, selfContained: Bool) {
        // Swift.print(#function, #line, #file)
        
        guard let savePanel = self.savePanel else { return }
        savePanel.allowedFileTypes = [fileType.rawValue]
    }
    
    /* ============================================ */
    // MARK: - Export/Transcode
    /* ============================================ */
    
    @IBAction func transcode(_ sender: Any?) {
        // Swift.print(#function, #line, #file)
        
        // Prepare Transcode SheetController
        let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
        let sid: NSStoryboard.SceneIdentifier = "TranscodeSheet Controller"
        let transcodeWC = storyboard.instantiateController(withIdentifier: sid) as! NSWindowController
        // transcodeWC.loadWindow()
        
        // Prepare Transcode ViewController
        guard let contVC = transcodeWC.contentViewController else { return }
        guard let transcodeVC = contVC as? TranscodeViewController else { return }
        
        // Show Transcode Sheet
        transcodeVC.beginSheetModal(for: self.window!) {(response) in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard response == NSApplication.ModalResponse.continue else { return }
            
            DispatchQueue.main.async {[unowned self] in // @escaping
                self.transcoding = true
                self.saveTo(self)
                self.transcoding = false
            }
        }
    }
    
    private func export(to url: URL, ofType typeName: String, preset: String) throws {
        // Swift.print(#function, #line, #file)
        
        // Show busy sheet
        let mutator :MovieMutator = self.movieMutator!
        showBusySheet("Exporting...", "Please hold on minute(s)...")
        mutator.unblockUserInteraction = { self.unblockUserInteraction() }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }
        mutator.updateProgress = {(progress) in self.updateProgress(progress) }
        defer {
            mutator.updateProgress = nil
        }
        
        // Swift.print("##### EXPORT STARTED #####")
        
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        do {
            // Export as specified file type with AVAssetExportPresetPassthrough
            try mutator.exportMovie(to: url, fileType: fileType, presetName: preset)
        }
        
        // Swift.print("##### EXPORT FINISHED #####")
    }
    
    private func exportCustom(to url: URL, ofType typeName: String) throws {
        // Swift.print(#function, #line, #file)
        
        // Show busy sheet
        let mutator :MovieMutator = self.movieMutator!
        showBusySheet("Exporting...", "Please hold on minute(s)...")
        mutator.unblockUserInteraction = { self.unblockUserInteraction() }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }
        mutator.updateProgress = {(progress) in self.updateProgress(progress) }
        defer {
            mutator.updateProgress = nil
        }
        
        // Swift.print("##### EXPORT STARTED #####")
        
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        do {
            let videoID: [String] = ["avc1","hvc1","apcn","apcs","apco"]
            let audioID: [String] = ["aac ","lpcm","lpcm","lpcm"]
            let lpcmBPC: [Int] = [0, 16, 24, 32]
            
            // Export as specified file type using custom setting params
            let defaults = UserDefaults.standard
            let audioRate = defaults.integer(forKey: kAudioKbpsKey)
            let videoRate = defaults.integer(forKey: kVideoKbpsKey)
            let copyField = defaults.bool(forKey: kCopyFieldKey)
            let copyNCLC = defaults.bool(forKey: kCopyNCLCKey)
            let copyOtherMedia = defaults.bool(forKey: kCopyOtherMediaKey)
            let videoEncode = defaults.bool(forKey: kVideoEncodeKey)
            let audioEncode = defaults.bool(forKey: kAudioEncodeKey)
            let videoCodec = videoID[defaults.integer(forKey: kVideoCodecKey)]
            let audioCodec = audioID[defaults.integer(forKey: kAudioCodecKey)]
            let lpcmDepth = lpcmBPC[defaults.integer(forKey: kAudioCodecKey)]
            
            var param: [String:Any] = [:]
            param[kAudioKbpsKey] = audioRate
            param[kVideoKbpsKey] = videoRate
            param[kCopyFieldKey] = copyField
            param[kCopyNCLCKey] = copyNCLC
            param[kCopyOtherMediaKey] = copyOtherMedia
            param[kVideoEncodeKey] = videoEncode
            param[kAudioEncodeKey] = audioEncode
            param[kVideoCodecKey] = videoCodec
            param[kAudioCodecKey] = audioCodec
            param[kLPCMDepthKey] = lpcmDepth
            
            try mutator.exportCustomMovie(to: url, fileType: fileType, settings: param)
        }
        
        // Swift.print("##### EXPORT FINISHED #####")
    }
    
    /* ============================================ */
    // MARK: - Resize window
    /* ============================================ */
    
    public func displayRatio(_ baseSize: CGSize?) -> CGFloat {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return 1.0 }
        
        let size = baseSize ?? mutator.dimensions(of: self.dimensionsType)
        if size == NSZeroSize { return 1.0 }
        
        let viewSize = playerView!.frame.size
        let hRatio = viewSize.width / size.width
        let vRatio = viewSize.height / size.height
        let ratio = (hRatio < vRatio) ? hRatio: vRatio
        
        return ratio
    }
    
    @IBAction func resizeWindow(_ sender: Any?) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        
        let screenRect = window!.screen!.visibleFrame
        let viewSize = playerView!.frame.size
        let windowSize = window!.frame.size
        let extraSize = NSSize(width: windowSize.width - viewSize.width,
                               height: windowSize.height - viewSize.height)
        
        // Calc new video size
        var size = mutator.dimensions(of: self.dimensionsType)
        var keepTopLeft = false
        if let menuItem = sender as? NSMenuItem {
            var ratio = displayRatio(size)
            let tag = menuItem.tag
            switch tag {
            case 0: // 50%
                size = NSSize(width: size.width/2, height: size.height/2)
            case 1: // 100%
                break
            case 2: // 200%
                size = NSSize(width: size.width*2, height: size.height*2)
            case 10: // -10%
                ratio = ceil(ratio * 10 - 1.0) / 10.0
                ratio = min(max(ratio, 0.2), 5.0)
                size = NSSize(width: size.width*ratio, height: size.height*ratio)
            case 11: // +10%
                ratio = floor(ratio * 10 + 1.0) / 10.0
                ratio = min(max(ratio, 0.2), 5.0)
                size = NSSize(width: size.width*ratio, height: size.height*ratio)
            case 99: // fit to screen
                size = NSSize(width: size.width*10, height: size.height*10)
            default: // 100% resize from top-left
                keepTopLeft = true
            }
        }
        
        // Calc new window size
        var newWindowSize = NSSize(width: extraSize.width + size.width,
                                   height: extraSize.height + size.height)
        if newWindowSize.width > screenRect.size.width || newWindowSize.height > screenRect.size.height {
            // shrink; Limit window size to fit in
            size = mutator.dimensions(of: self.dimensionsType)
            let hRatio = (screenRect.size.width - extraSize.width) / size.width
            let vRatio = (screenRect.size.height - extraSize.height) / size.height
            let ratio = (hRatio < vRatio) ? hRatio : vRatio
            size = NSSize(width: size.width * ratio, height: size.height * ratio)
            newWindowSize = NSSize(width: extraSize.width + size.width,
                                   height: extraSize.height + size.height)
        }
        
        // Transpose to anchor point
        var origin = window!.frame.origin
        do {
            if keepTopLeft { // preserve top left corner
                let newOrigin = NSPoint(x: origin.x,
                                        y: origin.y - (newWindowSize.height - windowSize.height))
                origin = newOrigin
            } else { // preserve top center point
                let newOrigin = NSPoint(x: origin.x + (windowSize.width/2) - (newWindowSize.width/2) ,
                                        y: origin.y - (newWindowSize.height - windowSize.height))
                origin = newOrigin
            }
        }
        
        // Transpose into screenRect
        do {
            let scrXmax: CGFloat = screenRect.origin.x + screenRect.size.width
            let scrYmax: CGFloat = screenRect.origin.y + screenRect.size.height
            let errXmin: Bool = (origin.x < screenRect.origin.x)
            let errXmax: Bool = (origin.x + newWindowSize.width > scrXmax)
            let errYmin: Bool = (origin.y < screenRect.origin.y)
            let errYmax: Bool = (origin.y + newWindowSize.height > scrYmax)
            if errXmin || errXmax || errYmin || errYmax {
                let hOffset: CGFloat =
                    errXmax ? (scrXmax - (origin.x + newWindowSize.width)) :
                        (errXmin ? (screenRect.origin.x - origin.x) : 0.0)
                let vOffset: CGFloat =
                    errYmax ? (scrYmax - (origin.y + newWindowSize.height)) :
                        (errYmin ? (screenRect.origin.y - origin.y) : 0.0)
                let newOrigin = NSPoint(x: origin.x + hOffset, y: origin.y + vOffset)
                origin = newOrigin
            }
        }
        
        // Apply new Rect to window
        let newWindowRect = NSRect(origin: origin, size: newWindowSize)
        window!.setFrame(newWindowRect, display: true, animate: false)
    }
    
    /* ============================================ */
    // MARK: - modify clap/pasp
    /* ============================================ */
    
    @IBAction func modifyClapPasp(_ sender: Any?) {
        // Swift.print(#function, #line, #file)
        
        guard let mutator = self.movieMutator else { return }
        
        // Prepare CAPAR SheetController
        let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
        let sid: NSStoryboard.SceneIdentifier = "CAPARSheet Controller"
        let caparWC = storyboard.instantiateController(withIdentifier: sid) as! NSWindowController
        // caparWC.loadWindow()
        
        // Prepare CAPAR ViewController
        guard let contVC = caparWC.contentViewController else { return }
        guard let caparVC = contVC as? CAPARViewController else { return }
        guard let dict: [AnyHashable:Any] = mutator.clappaspDictionary() else { return }
        guard caparVC.applySource(dict) else { return }
        
        // Show CAPAR Sheet
        caparVC.beginSheetModal(for: self.window!) {(response) in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard response == .continue else { return }
            
            // Update Clap/Pasp settings
            let result: [AnyHashable:Any] = caparVC.resultContent
            let done: Bool = mutator.applyClapPasp(result, using: self.undoManager!)
            if !done {
                var info: [String:Any] = [:]
                info[NSLocalizedDescriptionKey] = "Failed to modify CAPAR extensions."
                info[NSLocalizedFailureReasonErrorKey] = "Check if video track has same dimensions."
                let err = NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: info)
                
                self.showErrorSheet(err)
            }
        }
    }
}
