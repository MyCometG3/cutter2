//
//  Document.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVKit
import AVFoundation

let kCustomKey = "Custom"
let kLPCMDepthKey = "lpcmDepth"
let kAudioKbpsKey = "audioKbps"
let kVideoKbpsKey = "videoKbps"
let kCopyFieldKey = "copyField"
let kCopyNCLCKey = "copyNCLC"
let kCopyOtherMediaKey = "copyOtherMedia"

let kVideoEncodeKey = "videoEncode"
let kAudioEncodeKey = "audioEncode"
let kVideoCodecKey = "videoCodec"
let kAudioCodecKey = "audioCodec"

class Document: NSDocument, ViewControllerDelegate, NSOpenSavePanelDelegate, AccessoryViewDelegate {
    /// Strong reference to MovieMutator
    public var movieMutator : MovieMutator? = nil
    
    // Computed properties
    public var window : Window? {
        return self.windowControllers[0].window as? Window
    }
    public var viewController : ViewController? {
        return window?.contentViewController as? ViewController
    }
    public var playerView : AVPlayerView? {
        return viewController?.playerView
    }
    public var player : AVPlayer? {
        return playerView?.player
    }
    public var playerItem : AVPlayerItem? {
        return player?.currentItem
    }
    
    // Polling timer
    private var timer : Timer? = nil
    private let pollingInterval : TimeInterval = 1.0/15
    
    // KVO Context
    private var kvoContext = 0
    
    // SavePanel with Accessory View support
    private weak var savePanel : NSSavePanel? = nil
    private var accessoryVC : AccessoryViewController? = nil
    
    // Support #selector(NSDocument._something:didSomething:soContinue:)
    private var closingBlock : ((Bool) -> Void)? = nil
    
    // Transcode preferred type
    private var transcoding : Bool = false
    
    // Current Dimensions type
    private var dimensionsType : dimensionsType = .clean
    
    /* ============================================ */
    // MARK: - NSDocument methods/properties
    /* ============================================ */
    
    override init() {
        super.init()
        
        self.hasUndoManager = true
    }
    
    override class var autosavesInPlace: Bool {
        return false
    }
    
    override func makeWindowControllers() {
        // Swift.print(#function, #line)
        
        if self.fileURL == nil {
            // Prepare null AVMutableMovie
            let scale : CMTimeScale = 600
            let movie : AVMutableMovie? = AVMutableMovie()
            if let movie = movie {
                movie.timescale = scale
                movie.preferredRate = 1.0
                movie.preferredVolume = 1.0
                movie.interleavingPeriod = CMTimeMakeWithSeconds(0.5, scale)
                movie.preferredTransform = CGAffineTransform.identity
                movie.isModified = false
                
                //
                self.removeMutationObserver()
                self.movieMutator = MovieMutator(with: movie)
                self.addMutationObserver()
            } else {
                assert(false, "ERROR: Failed on AVMutableMovie()")
            }
        }
        
        // Returns the Storyboard that contains your Document window.
        let storyboard : NSStoryboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        
        // Instantiate and Register Window Controller
        let sid : NSStoryboard.SceneIdentifier = NSStoryboard.SceneIdentifier("Document Window Controller")
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
        self.updateGUI(kCMTimeZero, kCMTimeRangeZero, true)
        self.doVolumeOffset(100)
    }
    
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        //Swift.print(#function, #line)
        
        // Prepare C function and closingBlock()
        let obj : AnyObject = delegate as AnyObject
        let Class : AnyClass = object_getClass(delegate)!
        let method = class_getMethodImplementation(Class, shouldCloseSelector!)
        typealias signature = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        let function = unsafeBitCast(method, to: signature.self)
        
        self.closingBlock = {[unowned obj, shouldCloseSelector, contextInfo] (flag) -> Void in
            //Swift.print("closingBlock()", #line, "shouldClose =", flag)
            function(obj, shouldCloseSelector!, self, flag, contextInfo)
        }
        
        // Let super call Self.document(_:shouldClose:ContextInfo:)
        let delegate : Any = self
        let shouldCloseSelector : Selector = #selector(Document.document(_:shouldClose:contextInfo:))
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }
    
    @objc func document(_ document : NSDocument, shouldClose flag : Bool, contextInfo: UnsafeMutableRawPointer?) {
        //Swift.print(#function, #line, "shouldClose =", flag)

        if flag {
            self.cleanup() // my cleanup method
        }
        
        if let closingBlock = self.closingBlock {
            closingBlock(flag)
            self.closingBlock = nil
        }
    }
    
    override func close() {
        //Swift.print(#function, #line, #file)
        super.close()
    }
    
    deinit {
        //Swift.print(#function, #line, #file)
    }
    
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        // Swift.print(#function, #line, url.lastPathComponent, typeName)
        
        try super.revert(toContentsOf: url, ofType: typeName)
        
        // reset GUI when revert
        self.updateGUI(kCMTimeZero, kCMTimeRangeZero, true)
        self.doVolumeOffset(100)
    }
    
    override func read(from url: URL, ofType typeName: String) throws {
        // Swift.print(#function, #line, url.lastPathComponent, typeName)
        
        // Check UTI for AVMovie fileType
        let fileType = AVFileType.init(rawValue: typeName)
        if AVMovie.movieTypes().contains(fileType) == false {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Incompatible file type detected."
            info[NSDetailedErrorsKey] = "(UTI:" + typeName + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: info)
        }
        
        //Swift.print("##### READ STARTED #####")
        
        // Setup document with new AVMovie
        let movie :AVMutableMovie? = AVMutableMovie(url: url, options: nil)
        if let movie = movie {
            self.removeMutationObserver()
            self.movieMutator = MovieMutator(with: movie)
            self.addMutationObserver()
        } else {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Unable to open specified file as AVMovie."
            info[NSDetailedErrorsKey] = url.lastPathComponent + " at " + url.deletingLastPathComponent().path
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        //Swift.print("##### RELOADED #####")
        
        // NOTE: following initialization is performed at makeWindowControllers()
    }
    
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        // Swift.print(#function, #line, url.lastPathComponent, typeName)
        
        if saveOperation == .saveToOperation {
            let transcodePreset : String? = UserDefaults.standard.string(forKey: "transcodePreset")
            guard let preset = transcodePreset else { return }
            do {
                if preset == kCustomKey {
                    try exportCustom(to: url, ofType: typeName)
                } else {
                    try export(to: url, ofType: typeName, preset: preset)
                }
            } catch {
                // Don't use NSDocument default error handling
                DispatchQueue.main.async {
                    let alert = NSAlert(error: error)
                    if let reason = (error as NSError).localizedFailureReason {
                        alert.informativeText = reason
                    }
                    alert.beginSheetModal(for: self.window!, completionHandler: nil)
                }
            }
            return
        }
        
        try super.write(to: url, ofType: typeName, for: saveOperation,
                        originalContentsURL: absoluteOriginalContentsURL)
        
        if saveOperation == .saveAsOperation {
            self.refreshMovie()
        }
    }
    
    private func refreshMovie() {
        // Refresh internal movie (to sync selfcontained <> referece movie change)
        DispatchQueue.main.async {[unowned self] in
            guard let url : URL = self.fileURL else { return }
            let newMovie : AVMovie? = AVMovie(url: url, options: nil)
            if let newMovie = newMovie {
                guard let mutator = self.movieMutator else { return }
                let time : CMTime = mutator.insertionTime
                let range : CMTimeRange = mutator.selectedTimeRange
                let newMovieRange : CMTimeRange = newMovie.range
                let newTime : CMTime = CMTimeClampToRange(time, newMovieRange)
                let newRange : CMTimeRange = CMTimeRangeGetIntersection(range, newMovieRange)
                
                self.removeMutationObserver()
                self.movieMutator = MovieMutator(with: newMovie)
                self.addMutationObserver()
                
                self.updateGUI(newTime, newRange, true)
            }
        }
    }
    
    override func write(to url: URL, ofType typeName: String) throws {
        // Swift.print(#function, #line, url.lastPathComponent, typeName)
        guard let mutator = self.movieMutator else { return }
        
        // NOTE: We ignore the typeName here, and infer from url/file extension instead
        var fileType : AVFileType = AVFileType.init(rawValue: typeName)
        let urlFileType : AVFileType = fileTypeForURL(url) ?? fileType
        if fileType != urlFileType {
            Swift.print("##### Type mismatch detected : urlFileType:", urlFileType, ", writeType:", fileType, "#####")
            fileType = urlFileType
        }
        
        // Check UTI for AVFileType
        if AVMovie.movieTypes().contains(fileType) == false {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Incompatible file type detected."
            info[NSDetailedErrorsKey] = "(UTI:" + typeName + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
        
        //Swift.print("##### WRITE STARTED #####")
        showBusySheet("Writing...", "Please hold on second(s)...")
        mutator.unblockUserInteraction = { self.unblockUserInteraction() }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }

        // Check fileType (mov or other)
        if fileType == .mov {
            // Check savePanel accessoryView to know to save as ReferenceMovie
            var isReferenceMovie : Bool = mutator.hasExternalReference()
            if let accessoryVC = self.accessoryVC {
                isReferenceMovie = !(accessoryVC.selfContained)
            }
            
            // Write mov file as either self-contained movie or reference movie
            try mutator.writeMovie(to: url, fileType: fileType, copySampleData: !isReferenceMovie)
        } else {
            // Export as specified file type with AVAssetExportPresetPassthrough
            try mutator.exportMovie(to: url, fileType: fileType, presetName: nil)
        }
        
        //Swift.print("##### WRITE FINISHED #####")
    }
    
    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String,
                                         for saveOperation: NSDocument.SaveOperationType) -> Bool {
        return true
    }
    
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return false }
        
        // prepare accessory view controller
        if self.accessoryVC == nil {
            let storyboard : NSStoryboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
            let sid : NSStoryboard.SceneIdentifier = NSStoryboard.SceneIdentifier("Accessory View Controller")
            let accessoryVC = storyboard.instantiateController(withIdentifier: sid) as! AccessoryViewController
            self.accessoryVC = accessoryVC
            accessoryVC.loadView()
            accessoryVC.delegate = self
        }
        guard let accessoryVC = self.accessoryVC else { return false }
        
        // prepare file types same as current source
        var uti : String = self.fileType ?? AVFileType.mov.rawValue
        if self.transcoding {
            let avFileTypeRaw : String? = UserDefaults.standard.string(forKey: "avFileType")
            if let avFileTypeRaw = avFileTypeRaw {
                uti = AVFileType.init(avFileTypeRaw).rawValue
            }
        }
        
        // prepare accessory view
        do {
            try accessoryVC.updateDataSizeText(mutator.headerSize())
            
            accessoryVC.fileType = AVFileType.init(uti)
            if accessoryVC.fileType == .mov {
                accessoryVC.selfContained = !mutator.hasExternalReference()
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
        // Swift.print(#function, #line)
        
        if let accessoryVC = self.accessoryVC {
            let type : String = accessoryVC.fileType.rawValue
            return type
        } else {
            return AVFileType.mov.rawValue
        }
    }
    
    // NSOpenSavePanelDelegate protocol
    public func panel(_ sender: Any, validate url: URL) throws {
        // Swift.print(#function, #line, url.lastPathComponent)
        
        guard let accessoryVC = self.accessoryVC else {
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: nil)
        }
        
        guard let fileType = fileTypeForURL(url) else {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Unsupported file extension is detected."
            info[NSLocalizedFailureReasonErrorKey] = "(" + url.pathExtension + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        if accessoryVC.fileType != fileType {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Mismatch between file extension and file type."
            info[NSLocalizedFailureReasonErrorKey] =
                "URL(" + fileType.rawValue + ") vs Popup(" + accessoryVC.fileType.rawValue + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: info)
        }
    }
    
    public func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? {
        // Swift.print(#function, #line, filename, (okFlag ? "confirmed" : "not yet"))
        
        return filename
    }
    
    @IBAction func transcode(_ sender: Any?) {
        // Swift.print(#function, #line)
        let storyboard : NSStoryboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let sid : NSStoryboard.SceneIdentifier = NSStoryboard.SceneIdentifier("TranscodeSheet Controller")
        let transcodeWC = storyboard.instantiateController(withIdentifier: sid) as! NSWindowController
        transcodeWC.loadWindow()
        
        guard let contVC = transcodeWC.contentViewController else { return }
        contVC.loadView()
        
        guard let transcodeVC = contVC as? TranscodeViewController else { return }
        
        transcodeVC.beginSheetModal(for: self.window!, handler: {(response) in
            // Swift.print("(NSApplication.ModalResponse):", response.rawValue)
            //
            guard response == NSApplication.ModalResponse.continue else { return }
            
            DispatchQueue.main.async {[unowned self] in
                self.transcoding = true
                self.saveTo(self)
                self.transcoding = false
            }
        })
        
        // Swift.print(#function, #line)
    }
    
    private func export(to url: URL, ofType typeName: String, preset: String) throws {
        // Swift.print(#function, #line, url.lastPathComponent, typeName)
        guard let mutator = self.movieMutator else { return }
        
        let fileType : AVFileType = AVFileType.init(rawValue: typeName)

        // Check UTI for AVFileType
        if AVMovie.movieTypes().contains(fileType) == false {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Incompatible file type detected."
            info[NSDetailedErrorsKey] = "(UTI:" + typeName + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
        
        //Swift.print("##### EXPORT STARTED #####")
        showBusySheet("Exporting...", "Please hold on minute(s)...")
        mutator.unblockUserInteraction = { self.unblockUserInteraction() }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }
        
        do {
            // Export as specified file type with AVAssetExportPresetPassthrough
            try mutator.exportMovie(to: url, fileType: fileType, presetName: preset)
        }
        
        //Swift.print("##### EXPORT FINISHED #####")
    }
    
    private func exportCustom(to url: URL, ofType typeName: String) throws {
        // Swift.print(#function, #line, url.lastPathComponent, typeName)
        guard let mutator = self.movieMutator else { return }
        
        let fileType : AVFileType = AVFileType.init(rawValue: typeName)
        
        // Check UTI for AVFileType
        if AVMovie.movieTypes().contains(fileType) == false {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Incompatible file type detected."
            info[NSDetailedErrorsKey] = "(UTI:" + typeName + ")"
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
        
        //Swift.print("##### EXPORT STARTED #####")
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
        
        do {
            let videoID : [String] = ["avc1","hvc1","apcn","apcs","apco"]
            let audioID : [String] = ["aac ","lpcm","lpcm","lpcm"]
            let lpcmBPC : [Int] = [0, 16, 24, 32]
            
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
            
            var param : [String:Any] = [:]
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
        
        //Swift.print("##### EXPORT FINISHED #####")
    }
    
    /* ============================================ */
    // MARK : - AccessoryViewDelegate protocol
    /* ============================================ */

    public func didUpdateFileType(_ fileType: AVFileType, selfContained: Bool) {
        guard let savePanel = self.savePanel else { return }
        savePanel.allowedFileTypes = [fileType.rawValue]
    }
    
    /* ============================================ */
    // MARK: - Resize window
    /* ============================================ */
    
    public func displayRatio(_ baseSize : CGSize?) -> CGFloat {
        guard let mutator = self.movieMutator else { return 1.0 }
        
        let size = baseSize ?? mutator.dimensions(of: self.dimensionsType)
        if size == NSZeroSize { return 1.0 }
        
        let viewSize = playerView!.frame.size
        let hRatio = viewSize.width / size.width
        let vRatio = viewSize.height / size.height
        let ratio = (hRatio < vRatio) ? hRatio : vRatio
        
        return ratio
    }
    
    @IBAction func resizeWindow(_ sender: Any?) {
        // Swift.print(#function, #line)
        
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
            let scrXmax : CGFloat = screenRect.origin.x + screenRect.size.width
            let scrYmax : CGFloat = screenRect.origin.y + screenRect.size.height
            let errXmin : Bool = (origin.x < screenRect.origin.x)
            let errXmax : Bool = (origin.x + newWindowSize.width > scrXmax)
            let errYmin : Bool = (origin.y < screenRect.origin.y)
            let errYmax : Bool = (origin.y + newWindowSize.height > scrYmax)
            if errXmin || errXmax || errYmin || errYmax {
                let hOffset : CGFloat =
                    errXmax ? (scrXmax - (origin.x + newWindowSize.width)) :
                    (errXmin ? (screenRect.origin.x - origin.x) : 0.0)
                let vOffset : CGFloat =
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
    
    @IBAction func modifyClapPasp(_ sender : Any?) {
         Swift.print(#function, #line)
        
        guard let mutator = self.movieMutator else { return }

        let storyboard : NSStoryboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let sid : NSStoryboard.SceneIdentifier = NSStoryboard.SceneIdentifier("CAPARSheet Controller")
        let caparWC = storyboard.instantiateController(withIdentifier: sid) as! NSWindowController
        caparWC.loadWindow()
        
        guard let contVC = caparWC.contentViewController else { return }
        contVC.loadView()
        
        guard let caparVC = contVC as? CAPARViewController else { return }
        
        guard let dict : [AnyHashable:Any] = mutator.clappaspDictionary() else { return }
        guard caparVC.applySource(dict) else { return }
        
        caparVC.beginSheetModal(for: self.window!, handler: {(response) in
            // Swift.print(#function, #line)
            guard response == .continue else { return }
            
            let result : [AnyHashable:Any] = caparVC.resultContent
            mutator.applyClapPasp(result, using: self.undoManager!)
        })
    }
    
    /* ============================================ */
    // MARK: - private method - utilities
    /* ============================================ */
    
    private var alert : NSAlert? = nil
    
    /// Update progress
    var lastUpdateAt : UInt64 = 0
    public func updateProgress(_ progress : Float) {
        guard let alert = self.alert else { return }
        guard progress.isNormal else { return }
        
        let t : UInt64 = CVGetCurrentHostTime()
        guard (t - lastUpdateAt) > 100000000 else { return }
        lastUpdateAt = t
        
        DispatchQueue.main.async {
            alert.informativeText = String("Please hold on minute(s)... : \(Int(progress * 100)) %")
        }
    }
    
    /// Show busy modalSheet
    private func showBusySheet(_ message : String?, _ info : String?) {
        DispatchQueue.main.async {
            guard let window = self.window else { return }
            
            let alert : NSAlert = NSAlert()
            alert.messageText = message ?? "Processing...(message)"
            alert.informativeText = info ?? "Hold on seconds...(informative)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "") // No button on sheet
            let handler : (NSApplication.ModalResponse) -> Void = {(response) in
                //if response == .stop {/* hideBusySheet() called */}
            }
            
            alert.beginSheetModal(for: window, completionHandler: handler)
            self.alert = alert
        }
    }
    
    /// Hide busy modalSheet
    private func hideBusySheet() {
        DispatchQueue.main.async {
            guard let window = self.window else { return }
            guard let alert = self.alert else { return }
            
            window.endSheet(alert.window)
            self.alert = nil
        }
    }
    
    /// Cleanup for close document
    private func cleanup() {
        //
        self.removeMutationObserver()
        self.useUpdateTimer(false)
        self.removePlayerObserver()
        
        //
        self.viewController?.cleanup()
        
        // dealloc AVPlayer
        self.player?.pause()
        self.playerView?.player = nil
        
        // dealloc mutator
        self.movieMutator = nil
    }
    
    /// Get AVFileType from specified URL
    private func fileTypeForURL(_ url : URL) -> AVFileType? {
        let pathExt : String = url.pathExtension.lowercased()
        let dict : [String:AVFileType] = [
            "mov" : AVFileType.mov,
            "mp4" : AVFileType.mp4,
            "m4v" : AVFileType.m4v,
            "m4a" : AVFileType.m4a
        ]
        if let fileType = dict[pathExt] {
            return fileType
        }
        return nil
    }
    
    private func modifier(_ mask : NSEvent.ModifierFlags) -> Bool {
        guard let current = NSApp.currentEvent?.modifierFlags else { return false }
        
        return current.contains(mask)
    }
    
    /// Update Timeline view, seek, and refresh AVPlayerItem if required
    private func updateGUI(_ time : CMTime, _ timeRange : CMTimeRange, _ reload : Bool) {
        // Swift.print(#function, #line)
        
        // update GUI
        self.updateTimeline(time, range: timeRange)
        if reload {
            self.updatePlayer()
        } else {
            guard let player = self.player else { return }
            self.resumeAfterSeek(to: time, with: player.rate)
        }
    }
    
    /// Seek and Play
    private func resumeAfterSeek(to time : CMTime, with rate : Float) {
        guard let player = self.player else { return }
        guard let mutator = self.movieMutator else { return }
        
        do {
            let t = time
            Swift.print("resumeAfterSeek",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }

        player.pause()
        let handler : (Bool) -> Void = {[unowned player] (finished) in
            guard let mutator = self.movieMutator else { return }
            player.rate = rate
            self.updateTimeline(time, range: mutator.selectedTimeRange)
        }
        player.seek(to: time, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero, completionHandler: handler)
    }
    
    /// Update marker position in Timeline view
    private func updateTimeline(_ time : CMTime, range : CMTimeRange) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        
        // Update marker position
        mutator.insertionTime = time
        mutator.selectedTimeRange = range
        
        // Prepare userInfo
        var userInfo : [AnyHashable:Any] = [:]
        userInfo["time"] = NSValue(time: time)
        userInfo["range"] = NSValue(timeRange: range)
        userInfo["curPosition"] = NSNumber(value: positionOfTime(time))
        userInfo["startPosition"] = NSNumber(value: positionOfTime(range.start))
        userInfo["endPosition"] = NSNumber(value: positionOfTime(range.end))
        userInfo["string"] = mutator.shortTimeString(time, withDecimals: true)
        userInfo["duration"] = NSNumber(value: CMTimeGetSeconds(mutator.movieDuration()))
        
        // Post notification (.timelineUpdateReq)
        let notification = Notification(name: .timelineUpdateReq,
                                        object: self,
                                        userInfo: userInfo)
        let center = NotificationCenter.default
        center.post(notification)
    }
    
    /// Refresh AVPlayerItem and seek as is
    private func updatePlayer() {
        //Swift.print(#function, #line)
        guard let mutator = movieMutator, let pv = playerView else { return }
        
        if let player = pv.player {
            // Apply modified source movie
            let playerItem = mutator.makePlayerItem()
            player.replaceCurrentItem(with: playerItem)
            
            // seek
            let handler : (Bool) -> Void = {[unowned pv] (finished) in
                pv.needsDisplay = true
            }
            playerItem.seek(to: mutator.insertionTime, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero,
                            completionHandler: handler)
        } else {
            // Initial setup
            let playerItem = mutator.makePlayerItem()
            let player : AVPlayer = AVPlayer(playerItem: playerItem)
            pv.player = player
            
            // AddObserver to AVPlayer
            self.addPlayerObserver()
            
            // Start polling timer
            self.useUpdateTimer(true)
        }
    }
    
    /// Add AVPlayer properties observer
    private func addPlayerObserver() {
        //Swift.print(#function, #line)
        guard let player = self.player else { return }
        
        player.addObserver(self,
                           forKeyPath: #keyPath(AVPlayer.status),
                           options: [.old, .new],
                           context: &(self.kvoContext))
        player.addObserver(self,
                           forKeyPath: #keyPath(AVPlayer.rate),
                           options: [.old, .new],
                           context: &(self.kvoContext))
    }
    
    /// Remove AVPlayer properties observer
    private func removePlayerObserver() {
        //Swift.print(#function, #line)
        guard let player = self.player else { return }
        
        player.removeObserver(self,
                              forKeyPath: #keyPath(AVPlayer.status),
                              context: &(self.kvoContext))
        player.removeObserver(self,
                              forKeyPath: #keyPath(AVPlayer.rate),
                              context: &(self.kvoContext))
    }
    
    // NSKeyValueObserving protocol - observeValue(forKeyPath:of:change:context:)
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        //Swift.print(#function, #line)
        guard context == &(self.kvoContext) else { return }
        guard let object = object as? AVPlayer else { return }
        guard let keyPath = keyPath, let change = change else { return }
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        
        if object == player && keyPath == #keyPath(AVPlayer.status) {
            // Swift.print(#function, #line, "#keyPath(AVPlayer.status)")
            
            // Force redraw when AVPlayer.status is updated
            let newStatus = change[.newKey] as! NSNumber
            if newStatus.intValue == AVPlayerStatus.readyToPlay.rawValue {
                // Seek and refresh View
                let time = mutator.insertionTime
                let range = mutator.selectedTimeRange
                self.updateGUI(time, range, false)
            } else if newStatus.intValue == AVPlayerStatus.failed.rawValue {
                //
                Swift.print("ERROR: AVPlayerStatus.failed detected.")
            }
            return
        } else if object == player && keyPath == #keyPath(AVPlayer.rate) {
            //Swift.print(#function, #line, "#keyPath(AVPlayer.rate)")
            
            // Check special case : movie play reached at end of movie
            let oldRate = change[.oldKey] as! NSNumber
            let newRate = change[.newKey] as! NSNumber
            if oldRate.floatValue > 0.0 && newRate.floatValue == 0.0 {
                // TODO: refine here
                let current = player.currentTime()
                let duration = mutator.movieDuration()
                let selection = mutator.selectedTimeRange
                if current == duration {
                    // now Stopped at end of movie - force update GUI to end of movie
                    updateTimeline(current, range: selection)
                }
            } else {
                // ignore
            }
            return
        } else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
        }
    }
    
    /// Register observer for movie mutation
    private func addMutationObserver() {
        //Swift.print(#function, #line)
        let handler : (Notification) -> Void = {[unowned self] (notification) in
            Swift.print("========================== Received : .movieWasMutated ==========================")
            
            // extract CMTime/CMTimeRange from userInfo
            guard let userInfo = notification.userInfo else { return }
            guard let timeValue = userInfo["timeValue"] as? NSValue else { return }
            guard let timeRangeValue = userInfo["timeRangeValue"] as? NSValue else { return }
            
            let time : CMTime = timeValue.timeValue
            let timeRange : CMTimeRange = timeRangeValue.timeRangeValue
            self.updateGUI(time, timeRange, true)
        }
        let center = NotificationCenter.default
        center.addObserver(forName: .movieWasMutated,
                           object: movieMutator,
                           queue: OperationQueue.main,
                           using: handler)
    }
    
    /// Unregister observer for movie mutation
    private func removeMutationObserver() {
        //Swift.print(#function, #line)
        let center = NotificationCenter.default
        center.removeObserver(self,
                              name: .movieWasMutated,
                              object: movieMutator)
    }
    
    /// Move either start/end marker at current marker (nearest marker do sync)
    private func syncSelection(_ current: CMTime) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let selection : CMTimeRange = mutator.selectedTimeRange
        let start : CMTime = selection.start
        let end : CMTime = selection.end
        
        let halfDuration : CMTime = CMTimeMultiplyByRatio(selection.duration, 1, 2)
        let centerOfRange : CMTime = start + halfDuration
        let t1 : CMTime = (current < centerOfRange) ? current : start
        let t2 : CMTime = (current > centerOfRange) ? current : end
        let newSelection : CMTimeRange = CMTimeRangeFromTimeToTime(t1, t2)
        mutator.selectedTimeRange = newSelection
    }
    
    /// Move either Or both start/end marker to current marker
    private func resetSelection(_ newTime : CMTime, _ resetStart : Bool, _ resetEnd : Bool) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let selection : CMTimeRange = mutator.selectedTimeRange
        let start : CMTime = selection.start
        let end : CMTime = selection.end
        
        let sFlag : Bool = (resetEnd && newTime < start) ? true : resetStart
        let eFlag : Bool = (resetStart && newTime > end) ? true : resetEnd
        if sFlag || eFlag {
            let t1 : CMTime = sFlag ? newTime : start
            let t2 : CMTime = eFlag ? newTime : end
            let newSelection : CMTimeRange = CMTimeRangeFromTimeToTime(t1, t2)
            mutator.selectedTimeRange = newSelection
        }
    }
    
    /// Setup polling timer - queryPosition()
    private func useUpdateTimer(_ enable : Bool) {
        //Swift.print(#function, #line, (enable ? "on" : "off"))
        
        if enable {
            if self.timer == nil {
                self.timer = Timer.scheduledTimer(timeInterval: self.pollingInterval,
                                                  target: self,
                                                  selector: #selector(queryPosition),
                                                  userInfo: nil,
                                                  repeats: true)
            }
        } else {
            if let timer = self.timer {
                timer.invalidate()
                self.timer = nil
            }
        }
    }
    
    /// Check if it is head of movie
    private func checkHeadOfMovie() -> Bool {
        //Swift.print(#function, #line)
        guard let player = self.player else { return false }
        
        // NOTE: Return false if player is not paused.
        if player.rate != 0.0 { return false }
        
        let current = player.currentTime()
        if current == kCMTimeZero {
            return true
        }
        return false
    }
    
    //
    private var cachedTime = kCMTimeInvalid
    private var cachedWithinLastSampleRange : Bool = false
    private var cachedLastSampleRange : CMTimeRange? = nil
    
    /// Check if it is tail of movie
    private func checkTailOfMovie() -> Bool {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return false }
        guard let player = self.player else { return false }
        
        // NOTE: Return false if player is not paused.
        if player.rate != 0.0 { return false }
        
        let current = player.currentTime()
        let duration : CMTime = mutator.movieDuration()
        
        // validate cached range value
        if cachedTime == current {
            // use cached result
            return cachedWithinLastSampleRange
        } else {
            // reset cache
            cachedTime = current
            cachedWithinLastSampleRange = false
            cachedLastSampleRange = kCMTimeRangeInvalid
            
            if let info = mutator.presentationInfoAtTime(current) {
                let endOfRange : Bool = info.timeRange.end == duration
                if endOfRange {
                    cachedTime = current
                    cachedWithinLastSampleRange = true
                    cachedLastSampleRange = info.timeRange
                }
            }
            return cachedWithinLastSampleRange
        }
    }
    
    /// Snap to grid - Adjust Timeline resolution
    private func quantize(_ position : Float64) -> CMTime {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return kCMTimeZero }
        let position : Float64 = min(max(position, 0.0), 1.0)
        if let info = mutator.presentationInfoAtPosition(position) {
            let ratio : Float64 = (position - info.startPosition) / (info.endPosition - info.startPosition)
            return (ratio < 0.5) ? info.timeRange.start : info.timeRange.end
        } else {
            return CMTimeMultiplyByFloat64(mutator.movieDuration(), position)
        }
    }
    
    /* ============================================ */
    // MARK: - public method - utilities
    /* ============================================ */
    
    /// Poll AVPlayer/AVPlayerItem status and refresh Timeline
    @objc func queryPosition() {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        guard let playerItem = self.playerItem else { return }
        
        let notReady : Bool = (player.status != .readyToPlay)
        let empty : Bool = playerItem.isPlaybackBufferEmpty
        if notReady || empty { return }
        
        let current = player.currentTime()
        if mutator.insertionTime != current {
            let range = mutator.selectedTimeRange
            
            if checkTailOfMovie() {
                // ignore
            } else {
                updateTimeline(current, range: range)
            }
        }
    }
    
    /* ============================================ */
    // MARK: - ViewControllerDelegate Protocol
    /* ============================================ */
    
    public func hasSelection() -> Bool {
        guard let mutator = self.movieMutator else { return false }
        return (mutator.selectedTimeRange.duration > kCMTimeZero) ? true : false
    }
    
    public func hasDuration() -> Bool {
        guard let mutator = self.movieMutator else { return false }
        return (mutator.movieDuration() > kCMTimeZero) ? true : false
    }
    
    public func hasClipOnPBoard() -> Bool {
        guard let mutator = self.movieMutator else { return false }
        return (mutator.validateClipFromPBoard()) ? true : false
    }
    
    public func debugInfo() {
        guard let mutator = self.movieMutator else { return }
        let player = self.player!
        Swift.print("##### ", mutator.ts(), " #####")
        #if false
        do {
            let t = mutator.movieDuration()
            Swift.print(" movie duration",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            let t = mutator.insertionTime
            Swift.print("movie insertion",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            let t = mutator.selectedTimeRange.start
            Swift.print("      sel start",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            let t = mutator.selectedTimeRange.end
            Swift.print("        sel end",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            let t = player.currentTime()
            Swift.print("  movie current",
                        mutator.shortTimeString(t, withDecimals: true),
                        mutator.rawTimeString(t))
        }
        do {
            guard let info = mutator.presentationInfoAtTime(mutator.insertionTime) else {
                Swift.print("presentationInfo", "not available!!!")
                return
            }
            let s = info.timeRange.start
            let e = info.timeRange.end
            Swift.print("   sample start",
                        mutator.shortTimeString(s, withDecimals: true),
                        mutator.rawTimeString(s))
            Swift.print("     sample end",
                        mutator.shortTimeString(e, withDecimals: true),
                        mutator.rawTimeString(e))
        }
        
        //
        guard modifier(.option) else { return }
        do {
            if let info = mutator.presentationInfoAtTime(mutator.insertionTime) {
                if let prev = mutator.previousInfo(of: info.timeRange) {
                    let s = prev.timeRange.start
                    let e = prev.timeRange.end
                    Swift.print(" p sample start",
                                mutator.shortTimeString(s, withDecimals: true),
                                mutator.rawTimeString(s))
                    Swift.print(" prv sample end",
                                mutator.shortTimeString(e, withDecimals: true),
                                mutator.rawTimeString(e))
                } else {
                    Swift.print("prev presentationInfo", "not available!!!")
                }
            } else {
                Swift.print("presentationInfo", "not available!!!")
            }
        }
        do {
            if let info = mutator.presentationInfoAtTime(mutator.insertionTime) {
                if let next = mutator.nextInfo(of: info.timeRange) {
                    let s = next.timeRange.start
                    let e = next.timeRange.end
                    Swift.print(" n sample start",
                                mutator.shortTimeString(s, withDecimals: true),
                                mutator.rawTimeString(s))
                    Swift.print(" nxt sample end",
                                mutator.shortTimeString(e, withDecimals: true),
                                mutator.rawTimeString(e))
                } else {
                    Swift.print("next presentationInfo", "not available!!!")
                }
            } else {
                Swift.print("presentationInfo", "not available!!!")
            }
        }
        #endif
        Swift.print(mutator.clappaspDictionary() as Any)
    }
    
    public func timeOfPosition(_ position : Float64) -> CMTime {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return kCMTimeZero }
        return mutator.timeOfPosition(position)
    }
    
    public func positionOfTime(_ time : CMTime) -> Float64 {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return 0.0 }
        return mutator.positionOfTime(time)
    }
    
    public func doCut() throws {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        mutator.cutSelection(using: self.undoManager!)
    }
    
    public func doCopy() throws {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        mutator.copySelection()
    }
    
    public func doPaste() throws {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        mutator.pasteAtInsertionTime(using: self.undoManager!)
    }
    
    /// Delete selection range
    public func doDelete() throws {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        mutator.deleteSelection(using: self.undoManager!)
    }
    
    /// Select all range of movie
    public func selectAll() {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let time = mutator.insertionTime
        let range : CMTimeRange = mutator.movieRange()
        self.updateGUI(time, range, false)
    }
    
    /// offset current marker by specified step
    public func doStepByCount(_ count : Int64, _ resetStart : Bool, _ resetEnd : Bool) {
        var target : CMTime? = nil
        doStepByCount(count, resetStart, resetEnd, &target)
    }
    
    /// offset current marker by specified step (private)
    private func doStepByCount(_ count : Int64, _ resetStart : Bool, _ resetEnd : Bool, _ target : inout CMTime?) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        guard let player = player, let item = playerItem else { return }
        
        // pause first
        let rate = player.rate
        player.rate = 0.0
        
        //
        let nowTime = mutator.insertionTime
        if checkTailOfMovie(), let lastRange = cachedLastSampleRange {
            // Player is at final sample. Special handling required.
            if count > 0 && mutator.insertionTime < lastRange.end {
                resetSelection(lastRange.end, resetStart, resetEnd)
                updateTimeline(lastRange.end, range: mutator.selectedTimeRange)
                cachedTime = lastRange.start
                target = lastRange.start
                return
            }
            if count < 0 && mutator.insertionTime > lastRange.start {
                resetSelection(lastRange.start, resetStart, resetEnd)
                updateTimeline(lastRange.start, range: mutator.selectedTimeRange)
                cachedTime = lastRange.start
                target = lastRange.start
                return
            }
        }
        
        // step and resume
        let duration = mutator.movieDuration()
        let okForward = (count > 0 && item.canStepForward && nowTime < duration)
        let okBackward = (count < 0 && item.canStepBackward && kCMTimeZero < nowTime)
        if okForward {
            guard let info = mutator.presentationInfoAtTime(nowTime) else { return }
            let newTime = CMTimeClampToRange(info.timeRange.end, mutator.movieRange())
            resetSelection(newTime, resetStart, resetEnd)
            resumeAfterSeek(to: newTime, with: rate)
            target = newTime
        } else if okBackward {
            guard let info = mutator.presentationInfoAtTime(nowTime) else { return }
            guard let prev = mutator.previousInfo(of: info.timeRange) else { return }
            let newTime = CMTimeClampToRange(prev.timeRange.start, mutator.movieRange())
            resetSelection(newTime, resetStart, resetEnd)
            resumeAfterSeek(to: newTime, with: rate)
            target = newTime
        } else {
            self.updateGUI(nowTime, mutator.selectedTimeRange, false)
            target = nowTime
        }
    }
    
    /// offset current marker by specified seconds
    public func doStepBySecond(_ offset : Float64, _ resetStart : Bool, _ resetEnd : Bool) {
        var target : CMTime? = nil
        doStepBySecond(offset, resetStart, resetEnd, &target)
    }
    
    /// offset current marker by specified seconds (private)
    private func doStepBySecond(_ offset: Float64, _ resetStart : Bool, _ resetEnd : Bool, _ target : inout CMTime?) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        guard let player = self.player else { return }
        let movieRange : CMTimeRange = mutator.movieRange()
        
        // pause first
        var rate = player.rate
        player.rate = 0.0
        
        // calc target time
        var adjust : Bool = true
        let nowTime = mutator.insertionTime
        let offsetTime = CMTimeMakeWithSeconds(offset, nowTime.timescale)
        var newTime = nowTime + offsetTime
        if newTime < movieRange.start {
            newTime = movieRange.start; adjust = false
        } else if newTime > movieRange.end {
            newTime = movieRange.end; adjust = false
        }
        
        // adjust time (snap to grid)
        if adjust, let info = mutator.presentationInfoAtTime(newTime) {
            let beforeCenter : Bool = (info.timeRange.end - newTime) > (newTime - info.timeRange.start)
            newTime = beforeCenter ? info.timeRange.start : info.timeRange.end
        }
        
        // implicit pause
        if newTime == movieRange.end {
            rate = 0.0
        }
        
        // seek and resume
        resetSelection(newTime, resetStart, resetEnd)
        resumeAfterSeek(to: newTime, with: rate)
        target = newTime
    }
    
    /// offset current volume by specified percent
    public func doVolumeOffset(_ percent: Int) {
        //Swift.print(#function, #line)
        guard let player = self.player else { return }
        
        // Mute/Unmute handling
        player.isMuted = (percent < -100) ? true : false
        
        // Update AVPlayer.volume
        if percent >= -100 && percent <= +100 {
            var volume : Float = player.volume
            volume += Float(percent) / 100.0
            volume = min(max(volume, 0.0), 1.0)
            player.volume = volume
        }
    }
    
    /// move left current marker by key combination
    public func doMoveLeft(_ optionKey : Bool, _ shiftKey : Bool, _ resetStart : Bool, _ resetEnd : Bool) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        var target : CMTime? = nil
        if optionKey {
            var current : CMTime = mutator.insertionTime
            let selection : CMTimeRange = mutator.selectedTimeRange
            let start : CMTime = selection.start
            let end : CMTime = selection.end
            let limit : CMTime = kCMTimeZero
            current = (
                (end < current) ? end :
                    (start < current) ? start : limit
            )
            updateGUI(current, selection, false)
            target = current
        } else {
            doStepByCount(-1, resetStart, resetEnd, &target)
        }
        if shiftKey, let target = target {
            syncSelection(target)
            updateGUI(target, mutator.selectedTimeRange, false)
        }
    }
    
    /// move right current marker by key combination
    public func doMoveRight(_ optionKey : Bool, _ shiftKey : Bool, _ resetStart : Bool, _ resetEnd : Bool) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        var target : CMTime? = nil
        if optionKey {
            var current : CMTime = mutator.insertionTime
            let selection : CMTimeRange = mutator.selectedTimeRange
            let start : CMTime = selection.start
            let end : CMTime = selection.end
            let limit : CMTime = mutator.movieDuration()
            current = (
                (current < start) ? start :
                    (current < end) ? end : limit
            )
            updateGUI(current, selection, false)
            target = current
        } else {
            doStepByCount(+1, resetStart, resetEnd, &target)
        }
        if shiftKey, let target = target {
            syncSelection(target)
            updateGUI(target, mutator.selectedTimeRange, false)
        }
    }
    
    /// Set playback rate
    public func doSetRate(_ offset : Int) {
        //Swift.print(#function, #line)
        guard let player = self.player else { return }
        guard let item = self.playerItem else { return }
        var currentRate : Float = player.rate
        let okForward : Bool = (item.status == .readyToPlay)
        let okReverse : Bool = item.canPlayReverse
        let okFastForward : Bool = item.canPlayFastForward
        let okFastReverse : Bool = item.canPlayFastReverse
        
        // Fine acceleration control on fastforward/fastreverse
        let resolution : Float = 3.0 // 1.0, 1.33, 1.66, 2.00, 2.33, ...
        if currentRate > 0.0 {
            currentRate = (currentRate - 1.0) * resolution + 1.0
        } else if currentRate < 0.0 {
            currentRate = (currentRate + 1.0) * resolution - 1.0
        }
        var newRate : Float = (offset == 0) ? 0.0 : (currentRate + Float(offset))
        if newRate > 0.0 {
            newRate = (newRate - 1.0) / resolution + 1.0
        } else if newRate < 0.0 {
            newRate = (newRate + 1.0) / resolution - 1.0
        }
        
        //
        if newRate == 0.0 {
            player.pause()
            return
        }
        if newRate > 0.0 && okForward {
            if newRate == 1.0 || (newRate > 1.0 && okFastForward) {
                if checkTailOfMovie() { // Restart from head of movie
                    self.resumeAfterSeek(to: kCMTimeZero, with: newRate)
                } else { // Start play
                    player.rate = newRate
                }
                return
            }
        }
        if newRate < 0.0 && okReverse {
            if newRate == -1.0 || (newRate < -1.0 && okFastReverse) {
                if checkHeadOfMovie() { // Restart from tail of the movie
                    self.resumeAfterSeek(to: item.duration, with: newRate)
                } else { // Start play
                    player.rate = newRate
                }
                return
            }
        }
        //
        NSSound.beep()
    }
    
    /// Toggle play
    public func doTogglePlay() {
        //Swift.print(#function, #line)
        guard let player = self.player else { return }
        let currentRate : Float = player.rate
        if currentRate != 0.0 { // play => pause
            doSetRate(0)
        } else { // pause => play
            if checkTailOfMovie() { // Restart play from head of the movie
                self.resumeAfterSeek(to: kCMTimeZero, with: 1.0)
            } else { // Start play
                doSetRate(+1)
            }
        }
    }
    
    /* ============================================ */
    // MARK: - TimelineUpdateDelegate Protocol
    /* ============================================ */
    
    /// called on mouse down/drag event
    public func didUpdateCursor(to position : Float64) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let time : CMTime = quantize(position)
        updateGUI(time, mutator.selectedTimeRange, false)
    }
    
    /// called on mouse down/drag event
    public func didUpdateStart(to position : Float64) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let fromTime : CMTime = quantize(position)
        let toTime : CMTime = mutator.selectedTimeRange.end
        let newRange = CMTimeRangeFromTimeToTime(fromTime, toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// called on mouse down/drag event
    public func didUpdateEnd(to position : Float64) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let fromTime : CMTime = mutator.selectedTimeRange.start
        let toTime : CMTime = quantize(position)
        let newRange = CMTimeRangeFromTimeToTime(fromTime, toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// called on mouse down/drag event
    public func didUpdateSelection(from fromPos : Float64, to toPos : Float64) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let fromTime : CMTime = quantize(fromPos)
        let toTime : CMTime = quantize(toPos)
        let newRange = CMTimeRangeFromTimeToTime(fromTime, toTime)
        updateGUI(mutator.insertionTime, newRange, false)
    }
    
    /// get PresentationInfo at specified position
    public func presentationInfo(at position: Float64) -> PresentationInfo? {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return nil }
        return mutator.presentationInfoAtPosition(position)
    }
    
    /// get PresentationInfo at prior to specified range
    public func previousInfo(of range: CMTimeRange) -> PresentationInfo? {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return nil }
        return mutator.previousInfo(of: range)
    }
    
    /// get PresentationInfo at next to specified range
    public func nextInfo(of range: CMTimeRange) -> PresentationInfo? {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return nil }
        return mutator.nextInfo(of: range)
    }
    
    /// Move current marker to specified anchor point
    public func doSetCurrent(to anchor : anchor) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let current : CMTime = mutator.insertionTime
        let start : CMTime = mutator.selectedTimeRange.start
        let end : CMTime = mutator.selectedTimeRange.end
        let duration : CMTime = mutator.movieDuration()
        
        switch anchor {
        case .head :
            mutator.insertionTime = kCMTimeZero
        case .start :
            mutator.insertionTime = start
        case .end :
            mutator.insertionTime = end
        case .tail :
            mutator.insertionTime = duration
        case .startOrHead :
            if mutator.insertionTime != start {
                mutator.insertionTime = start
            } else {
                mutator.insertionTime = kCMTimeZero
            }
        case .endOrTail :
            if mutator.insertionTime != end {
                mutator.insertionTime = end
            } else {
                mutator.insertionTime = duration
            }
        case .forward :
            if current < start {
                mutator.insertionTime = start
            } else if current < end {
                mutator.insertionTime = end
            } else {
                mutator.insertionTime = duration
            }
        case .backward :
            if end < current {
                mutator.insertionTime = end
            } else if start < current {
                mutator.insertionTime = start
            } else {
                mutator.insertionTime = kCMTimeZero
            }
        default:
            NSSound.beep()
            return
        }
        
        let newCurrent : CMTime = mutator.insertionTime
        let newRange : CMTimeRange = mutator.selectedTimeRange
        self.updateGUI(newCurrent, newRange, false)
    }
    
    /// Move selection start marker to specified anchor point
    public func doSetStart(to anchor : anchor) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let current : CMTime = mutator.insertionTime
        let start : CMTime = mutator.selectedTimeRange.start
        let end : CMTime = mutator.selectedTimeRange.end
        let duration : CMTime = mutator.movieDuration()
        var newRange : CMTimeRange = mutator.selectedTimeRange
        
        switch anchor {
        case .headOrCurrent :
            if start != kCMTimeZero {
                newRange = CMTimeRangeFromTimeToTime(kCMTimeZero, end)
            } else {
                fallthrough
            }
        case .current :
            if current < end {
                newRange = CMTimeRangeFromTimeToTime(current, end)
            } else {
                newRange = CMTimeRangeFromTimeToTime(current, current)
            }
        case .head :
            newRange = CMTimeRangeFromTimeToTime(kCMTimeZero, end)
        case .end :
            newRange = CMTimeRangeFromTimeToTime(end, end)
        case .tail :
            newRange = CMTimeRangeFromTimeToTime(duration, duration)
        default:
            NSSound.beep()
            return
        }
        
        updateTimeline(current, range: newRange)
    }
    
    /// Move selection end marker to specified anchor point
    public func doSetEnd(to anchor : anchor) {
        //Swift.print(#function, #line)
        guard let mutator = self.movieMutator else { return }
        let current : CMTime = mutator.insertionTime
        let start : CMTime = mutator.selectedTimeRange.start
        let end : CMTime = mutator.selectedTimeRange.end
        let duration : CMTime = mutator.movieDuration()
        var newRange : CMTimeRange = mutator.selectedTimeRange
        
        switch anchor {
        case .tailOrCurrent :
            if end != duration {
                newRange = CMTimeRangeFromTimeToTime(start, duration)
            } else {
                fallthrough
            }
        case .current :
            if start < current {
                newRange = CMTimeRangeFromTimeToTime(start, current)
            } else {
                newRange = CMTimeRangeFromTimeToTime(current, current)
            }
        case .head :
            newRange = CMTimeRangeFromTimeToTime(kCMTimeZero, kCMTimeZero)
        case .start :
            newRange = CMTimeRangeFromTimeToTime(start, start)
        case .tail:
            newRange = CMTimeRangeFromTimeToTime(start, duration)
        default:
            NSSound.beep()
            return
        }
        
        updateTimeline(current, range: newRange)
    }
    
}
