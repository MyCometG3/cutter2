//
//  MovieMutator.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: -
/* ============================================ */

extension NSPasteboard.PasteboardType {
    static let movieMutator = NSPasteboard.PasteboardType("com.mycometg3.cutter.MovieMutator")
}

/* ============================================ */
// MARK: - Actor isolation
/* ============================================ */

@MainActor
final class UndoManagerWrapper {
    private let undoManager: UndoManager
    
    init(_ undoManager: UndoManager) {
        self.undoManager = undoManager
    }
    
    func registerUndo<T: AnyObject>(
        withTarget target: T,
        handler: @Sendable @escaping (T) -> Void
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

extension MovieMutator {
    
    /// Runs a throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A closure isolated to the main actor that may throw an error.
    /// - Returns: The result of the closure's operation.
    /// - Throws: Any error thrown by the closure.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try block()
            }
        } else {
            return try DispatchQueue.main.sync {
                return try MainActor.assumeIsolated {
                    try block()
                }
            }
        }
    }
    
    /// Runs a non-throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A non-throwing closure isolated to the main actor.
    /// - Returns: The result of the closure's operation.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                block()
            }
        } else {
            return DispatchQueue.main.sync {
                return MainActor.assumeIsolated {
                    block()
                }
            }
        }
    }
}

/* ============================================ */
// MARK: -
/* ============================================ */

/// Wrapper of AVMutableMovie as model object of movie editor
@MainActor
class MovieMutator: MovieMutatorBase {
    
    /* ============================================ */
    // MARK: - private method - get movie clip
    /* ============================================ */
    
    /// Create movie clip from specified CMTimeRange
    ///
    /// - Parameter range: clip range
    /// - Returns: clip as AVMutableMovie
    private func movieClip(_ range: CMTimeRange) -> AVMutableMovie? {
        precondition(validateRange(range, true), "ERROR: Invalid range \(range)")
        
        // Prepare clip
        var clip: AVMutableMovie = internalMovie.mutableCopy() as! AVMutableMovie
        if clip.timescale != range.duration.timescale {
            // Create new Movie with exact timescale; it should match before operation
            clip = AVMutableMovie()
            let scale = range.duration.timescale
            clip.timescale = scale
            clip.preferredRate = 1.0
            clip.preferredVolume = 1.0
            clip.interleavingPeriod = CMTimeMakeWithSeconds(0.5, preferredTimescale: scale)
            clip.preferredTransform = CGAffineTransform.identity
            clip.isModified = false
            // convert all into different timescale
            do {
                let movieRange: CMTimeRange = self.movieRange()
                // Swift.print(ts(), #function, #line, #file)
                try clip.insertTimeRange(movieRange, of: internalMovie, at: CMTime.zero, copySampleData: false)
                // Swift.print(ts(), #function, #line, #file)
            } catch {
                Swift.print(ts(), error)
                preconditionFailure("ERROR: invalid clip")
            }
        }
        
        // Trim clip
        let rangeAfter: CMTimeRange = CMTimeRangeMake(start: range.end, duration: clip.range.duration - range.end)
        if rangeAfter.duration > CMTime.zero {
            clip.removeTimeRange(rangeAfter)
        }
        let rangeBefore: CMTimeRange = CMTimeRangeMake(start: CMTime.zero, duration: range.start)
        if rangeBefore.duration > CMTime.zero {
            clip.removeTimeRange(rangeBefore)
        }
        
        if range.duration != clip.range.duration {
            Swift.print(ts(), "diff", CMTimeGetSeconds(range.duration),
                        CMTimeGetSeconds(clip.range.duration), "at", #function, #line)
            Swift.print(ts(), range.duration)
            Swift.print(ts(), clip.range.duration)
            preconditionFailure("ERROR: invalid clip")
        }
        
        precondition(validateClip(clip), "ERROR: invalid clip")
        return clip
    }
    
    /* ============================================ */
    // MARK: - private method - work w/ PasteBoard
    /* ============================================ */
    
    /// Read movie clip data from PasteBoard
    ///
    /// - Returns: Data of movie header
    private func readClipFromPBoard() -> Data? {
        let pBoard: NSPasteboard = NSPasteboard.general
        
        // extract movie header data from PBoard
        let data: Data? = pBoard.data(forType: .movieMutator)
        return data
    }
    
    /// Write movie header data to PasteBoard
    ///
    /// - Parameter data: Data of movie header
    /// - Returns: true if success
    private func writeClipToPBoard(_ data: Data) -> Bool {
        // register data to PBoard
        let pBoard: NSPasteboard = NSPasteboard.general
        pBoard.clearContents()
        let result = pBoard.setData(data, forType: .movieMutator)
        return result
    }
    
    /// Write movie clip data to PasteBoard
    ///
    /// - Parameter range: CMTimeRange of clip
    /// - Returns: Data of movie header
    private func writeRangeToPBoard(_ range: CMTimeRange) -> Data? {
        guard let clip = self.movieClip(range) else { return nil }
        guard let data = clip.movHeader else { return nil }
        guard self.writeClipToPBoard(data) else { return nil }
        return data
    }
    
    /* ============================================ */
    // MARK: - public method - work w/ PasteBoard
    /* ============================================ */
    
    /// Check if pasteboard has valid movie clip
    ///
    /// - Returns: true if available
    public func validateClipFromPBoard() -> Bool {
        let pBoard: NSPasteboard = NSPasteboard.general
        
        if let _ = pBoard.data(forType: .movieMutator) {
            return true
        } else {
            return false
        }
    }
    
    /* ============================================ */
    // MARK: - private method - remove/insert clip
    /* ============================================ */
    
    /// Remove range. Adjust insertionTime.
    ///
    /// - Parameters:
    ///   - range: Range to remove
    ///   - time: insertionTime
    private func doRemove(_ range: CMTimeRange, _ time: CMTime) {
        precondition(validateRange(range, true), "ERROR: Invalid range \(range)")
        
        // perform delete selection
        do {
            // Swift.print(ts(), #function, #line, #file)
            internalMovie.removeTimeRange(range)
            // Swift.print(ts(), #function, #line, #file)
            
            // Update Marker
            let newTime: CMTime = (time <= range.start ? time
                : (range.start < time && time <= range.end) ? range.start
                : time - range.duration)
            let newRange: CMTimeRange = CMTimeRangeMake(start: range.start, duration: CMTime.zero)
            resetMarker(newTime, newRange, true)
        }
    }
    
    /// Undo remove range. Restore movie, insertionTime and selection.
    ///
    /// - Parameters:
    ///   - data: movieHeader data to be restored.
    ///   - range: original selection
    ///   - time: original intertionTime
    ///   - clip: removed clip data
    private func undoRemove(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip: Data) {
        precondition(validateClipData(clip), "ERROR: Invalid clip data")
        
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        precondition(reloadDone, "ERROR: Failed to reload movie")
    }
    
    /// Insert clip at insertionTime. Adjust insertionTime/selection.
    ///
    /// - Parameters:
    ///   - clip: clip data to insert
    ///   - time: insertionTime
    private func doInsert(_ clip: Data, _ time: CMTime) {
        let clip = AVMutableMovie(data: clip, options: nil)
        precondition(validateClip(clip), "ERROR: Invalid clip data")
        precondition(validateTime(time), "ERROR: Invalid insertion time")
        
        // perform insert clip at marker
        do {
            var clipRange: CMTimeRange = CMTimeRange(start: CMTime.zero,
                                                     duration: clip.range.duration)
            if clip.timescale != internalMovie.timescale {
                // Shorten if fraction is not zero
                let duration: CMTime = CMTimeConvertScale(clip.range.duration,
                                                          timescale: internalMovie.timescale,
                                                          method: .roundTowardZero)
                clipRange = CMTimeRange(start: CMTime.zero,
                                        duration: duration)
            }
            let beforeDuration = self.movieDuration()
            
            // Swift.print(ts(), #function, #line, #file)
            try internalMovie.insertTimeRange(clipRange,
                                              of: clip,
                                              at: time,
                                              copySampleData: false)
            // Swift.print(ts(), #function, #line, #file)
            
            // Update Marker
            let afterDuration = self.movieDuration()
            let actualDelta = afterDuration - beforeDuration
            let newTime: CMTime = time + actualDelta
            let newRange: CMTimeRange = CMTimeRangeMake(start: time, duration: actualDelta)
            resetMarker(newTime, newRange, true)
        } catch {
            Swift.print("ERROR:", error)
            preconditionFailure("ERROR: failed to insert clip")
        }
    }
    
    /// Undo insert clip. Restore movie, insertionTime and selection.
    ///
    /// - Parameters:
    ///   - data: movieHeader data to be restored.
    ///   - range: original selection
    ///   - time: original insertionTime
    ///   - clip: inserted clip data
    private func undoInsert(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip: Data) {
        precondition(validateClipData(clip), "ERROR: invalid clip data")
        
        // populate PBoard with original clip
        let pbDone: Bool = writeClipToPBoard(clip)
        precondition(pbDone, "ERROR: failed to populate PBoard")
        
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        precondition(reloadDone, "ERROR: failed to reload movie")
    }
    
    /* ============================================ */
    // MARK: - public method - edit action
    /* ============================================ */
    
    /// Copy selection of internalMovie
    public func copySelection() {
        // Swift.print(ts(), #function, #line, #file)
        
        // perform copy selection
        let range = self.selectedTimeRange
        guard validateRange(range, true) else { NSSound.beep(); return; }
        
        let pbDone = (writeRangeToPBoard(range) != nil)
        precondition(pbDone, "ERROR: failed to copy selection")
    }
    
    /// Cut selection of internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func cutSelection(using undoManager: UndoManagerWrapper) {
        // Swift.print(ts(), #function, #line, #file)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, true) else { NSSound.beep(); return; }
        guard let clip = writeRangeToPBoard(range) else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo record
        let undoCutHandler: @Sendable (MovieMutator) -> Void = {[data, clip, range, time, unowned undoManager, unowned self] (me1) in // @escaping
            // register redo record
            performSyncOnMainActor {
                let redoCutHandler: @Sendable (MovieMutator) -> Void = {[range, time, unowned undoManager, unowned self] (me2) in // @escaping
                    performSyncOnMainActor {
                        me2.resetMarker(time, range, false)
                        me2.cutSelection(using: undoManager)
                    }
                }
                undoManager.registerUndo(withTarget: me1, handler: redoCutHandler)
                undoManager.setActionName("Cut selection")
                
                // perform undo cut
                me1.undoRemove(data, range, time, clip)
            }
        }
        undoManager.registerUndo(withTarget: self, handler: undoCutHandler)
        undoManager.setActionName("Cut selection")
        
        // perform cut
        self.doRemove(range, time)
        refreshMovie()
    }
    
    /// Paste clip into internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func pasteAtInsertionTime(using undoManager: UndoManagerWrapper) {
        // Swift.print(ts(), #function, #line, #file)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, false) else { NSSound.beep(); return; }
        guard let clip = readClipFromPBoard() else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo record
        let undoPasteHandler: @Sendable (MovieMutator) -> Void = {[data, clip, range, time, unowned undoManager, unowned self] (me1) in // @escaping
            // register redo record
            performSyncOnMainActor {
                let redoPasteHandler: @Sendable (MovieMutator) -> Void = {[unowned undoManager, unowned self] (me2) in // @escaping
                    performSyncOnMainActor {
                        me2.pasteAtInsertionTime(using: undoManager)
                    }
                }
                undoManager.registerUndo(withTarget: me1, handler: redoPasteHandler)
                undoManager.setActionName("Paste at marker")
                
                // perform undo paste
                me1.undoInsert(data, range, time, clip)
            }
        }
        undoManager.registerUndo(withTarget: self, handler: undoPasteHandler)
        undoManager.setActionName("Paste at marker")
        
        // perform paste
        self.doInsert(clip, time)
        refreshMovie()
    }
    
    /// Delete selection of internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func deleteSelection(using undoManager: UndoManagerWrapper) {
        // Swift.print(ts(), #function, #line, #file)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, true) else { NSSound.beep(); return; }
        guard let clip = movieClip(range)?.movHeader else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo redord
        let undoDeleteHandler: @Sendable (MovieMutator) -> Void = {[data, clip, range, time, unowned undoManager, unowned self] (me1) in // @escaping
            // register redo record
            performSyncOnMainActor {
                let redoDeleteHandler: @Sendable (MovieMutator) -> Void = {[range, time, unowned undoManager, unowned self] (me2) in // @escaping
                    performSyncOnMainActor {
                        me2.resetMarker(time, range, false)
                        me2.deleteSelection(using: undoManager)
                    }
                }
                undoManager.registerUndo(withTarget: me1, handler: redoDeleteHandler)
                undoManager.setActionName("Delete selection")
                
                // perform undo delete
                me1.undoRemove(data, range, time, clip)
            }
        }
        undoManager.registerUndo(withTarget: self, handler: undoDeleteHandler)
        undoManager.setActionName("Delete selection")
        
        // perform delete
        self.doRemove(range, time)
        refreshMovie()
    }
    
    /* ============================================ */
    // MARK: - private method - clap/pasp
    /* ============================================ */
    
    //
    private func doReplace(_ movie: Data, _ range: CMTimeRange, _ time: CMTime) {
        precondition(validateRange(range, false), "ERROR: invalid range")
        
        // perform replacement
        do {
            // Swift.print(ts(), #function, #line, #file)
            precondition(reloadMovie(from: movie), "ERROR: reloadMovie failed")
            // Swift.print(ts(), #function, #line, #file)
            
            // Update Marker
            let movie = internalMovie
            let newTime: CMTime = (time < movie.range.end) ? time : movie.range.end
            let newRange: CMTimeRange = CMTimeRangeGetIntersection(range, otherRange: movie.range)
            resetMarker(newTime, newRange, true)
        }
    }
    
    //
    private func undoReplace(_ data: Data, _ range: CMTimeRange, _ time: CMTime) {
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        precondition(reloadDone, "ERROR: reloadAndNotify failed")
    }
    
    //
    private func updateFormat(_ movie: Data, using undoManager: UndoManagerWrapper) {
        // Swift.print(ts(), #function, #line, #file)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, false) else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo record
        let undoPasteHandler: @Sendable (MovieMutator) -> Void = {[data, range, time, movie, unowned undoManager, unowned self] (me1) in // @escaping
            // register redo replace
            performSyncOnMainActor {
                let redoPasteHandler: @Sendable (MovieMutator) -> Void = {[movie, unowned undoManager, unowned self] (me2) in // @escaping
                    performSyncOnMainActor {
                        me2.updateFormat(movie, using: undoManager)
                    }
                }
                undoManager.registerUndo(withTarget: me1, handler: redoPasteHandler)
                undoManager.setActionName("Update format")
                
                // perform undo replace
                me1.undoReplace(data, range, time)
            }
        }
        undoManager.registerUndo(withTarget: self, handler: undoPasteHandler)
        undoManager.setActionName("Update format")
        
        // perform replacement
        self.doReplace(movie, range, time)
        refreshMovie()
    }
    
    /* ============================================ */
    // MARK: - public method - clap/pasp
    /* ============================================ */
    
    //
    public func clappaspDictionary() -> [AnyHashable: Any]? {
        var dict: [AnyHashable:Any] = [:]
        
        let vTracks: [AVMutableMovieTrack] = internalMovie.tracks(withMediaType: .video)
        guard vTracks.count > 0 else { NSSound.beep(); return nil }
        
        let formats: [Any] = (vTracks[0]).formatDescriptions
        let format: CMVideoFormatDescription? = (formats[0] as! CMVideoFormatDescription)
        guard let desc = format else { NSSound.beep(); return nil }
        
        dict[dimensionsKey] =
            CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                              usePixelAspectRatio: false,
                                                              useCleanAperture: false)
        
        let extCA: CFPropertyList? =
            CMFormatDescriptionGetExtension(desc,
                                            extensionKey: kCMFormatDescriptionExtension_CleanAperture)
        if let extCA = extCA {
            let width = extCA[kCMFormatDescriptionKey_CleanApertureWidth] as! NSNumber
            let height = extCA[kCMFormatDescriptionKey_CleanApertureHeight] as! NSNumber
            let wOffset = extCA[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] as! NSNumber
            let hOffset = extCA[kCMFormatDescriptionKey_CleanApertureVerticalOffset] as! NSNumber
            
            dict[clapSizeKey] = NSSize(width: width.intValue, height: height.intValue)
            dict[clapOffsetKey] = NSPoint(x: wOffset.intValue, y: hOffset.intValue)
        } else {
            dict[clapSizeKey] = dict[dimensionsKey]
            dict[clapOffsetKey] = NSZeroPoint
        }
        
        let extPA: CFPropertyList? =
            CMFormatDescriptionGetExtension(desc,
                                            extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio)
        if let extPA = extPA {
            let hSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as! NSNumber
            let vSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as! NSNumber
            
            dict[paspRatioKey] = NSSize(width: hSpacing.doubleValue, height: vSpacing.doubleValue)
        } else {
            dict[paspRatioKey] = NSSize(width: 1.0, height: 1.0)
        }
        
        return dict
    }
    
    //
    public func applyClapPasp(_ dict: [AnyHashable:Any], using undoManager: UndoManagerWrapper) -> Bool {
        guard let clapSize = dict[clapSizeKey] as? NSSize else { return false }
        guard let clapOffset = dict[clapOffsetKey] as? NSPoint else { return false }
        guard let paspRatio = dict[paspRatioKey] as? NSSize else { return false }
        guard let dimensions = dict[dimensionsKey] as? NSSize else { return false }
        
        var count: Int = 0
        
        let movie: AVMutableMovie = internalMovie.mutableCopy() as! AVMutableMovie
        
        let vTracks: [AVMutableMovieTrack] = movie.tracks(withMediaType: .video)
        for track in vTracks {
            let formats = track.formatDescriptions as! [CMFormatDescription]
            
            // Verify if track.encodedDimension is equal to target dimensions
            var valid: Bool = false
            for format in formats {
                let rawSize: CGSize =
                    CMVideoFormatDescriptionGetPresentationDimensions(format,
                                                                      usePixelAspectRatio: false,
                                                                      useCleanAperture: false)
                if dimensions == rawSize {
                    valid = true
                    break
                }
            }
            guard valid else {
                Swift.print("     encodedPixelsDimensions:", track.encodedPixelsDimensions)
                Swift.print("productionApertureDimensions:", track.productionApertureDimensions)
                Swift.print("     cleanApertureDimensions:", track.cleanApertureDimensions)
                Swift.print("           track naturalSize:", track.naturalSize)
                Swift.print("         required dimension :", dimensions)
                Swift.print(ts(), "Different dimension:", track.trackID, track.naturalSize)
                continue
            }
            
            do {
                let ratio = paspRatio.width / paspRatio.height
                let newCAD = NSSize(width: clapSize.width * ratio, height: clapSize.height)
                let newPAD = NSSize(width: dimensions.width * ratio, height: dimensions.height)
                track.encodedPixelsDimensions = dimensions
                track.cleanApertureDimensions = newCAD
                track.productionApertureDimensions = newPAD
            }
            
            for format in formats {
                // Prepare new extensionDictionary
                guard let cfDict = CMFormatDescriptionGetExtensions(format) else { continue }
                let dict: NSMutableDictionary = NSMutableDictionary(dictionary: cfDict)
                dict[kCMFormatDescriptionExtension_VerbatimSampleDescription] = nil
                dict[kCMFormatDescriptionExtension_VerbatimISOSampleEntry] = nil
                
                // Replace CleanAperture if available
                if !validSize(clapSize) || !validPoint(clapOffset) {
                    dict[kCMFormatDescriptionExtension_CleanAperture] = nil
                } else {
                    let clap: NSMutableDictionary = [:]
                    clap[kCMFormatDescriptionKey_CleanApertureWidth] = clapSize.width
                    clap[kCMFormatDescriptionKey_CleanApertureHeight] = clapSize.height
                    clap[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] = clapOffset.x
                    clap[kCMFormatDescriptionKey_CleanApertureVerticalOffset] = clapOffset.y
                    dict[kCMFormatDescriptionExtension_CleanAperture] = clap
                }
                
                // Replace PixelAspectRatio if available
                if !validSize(paspRatio) {
                    dict[kCMFormatDescriptionExtension_PixelAspectRatio] = nil
                } else {
                    let pasp: NSMutableDictionary = [:]
                    pasp[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] = paspRatio.width
                    pasp[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] = paspRatio.height
                    dict[kCMFormatDescriptionExtension_PixelAspectRatio] = pasp
                }
                
                // Create New formatDescription as replacement
                var newFormat: CMVideoFormatDescription? = nil
                let codecType = CMFormatDescriptionGetMediaSubType(format) as CMVideoCodecType
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                let result = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                            codecType: codecType,
                                                            width: dimensions.width,
                                                            height: dimensions.height,
                                                            extensions: dict,
                                                            formatDescriptionOut: &newFormat)
                if result == noErr, let newFormat = newFormat {
                    track.replaceFormatDescription(format, with: newFormat)
                    count += 1
                } else {
                    //
                }
            }
        }
        
        if count > 0, let movie = movie.movHeader {
            // Replace movie object with undo record
            self.updateFormat(movie, using: undoManager)
            // Swift.print(ts(), self.clappaspDictionary()! as! [String:Any])
            return true
        } else {
            Swift.print(ts(), "ERROR: Failed to modify CAPAR extensions.")
            return false
        }
    }
}

/* ============================================ */
// MARK: - Inspector utilities
/* ============================================ */

extension MovieMutatorBase {
    
    /// Inspector - mediaDataURLs
    ///
    /// - Returns: all referenced file URLs by every track samples
    public func mediaDataPaths() -> [String]? {
        if let cache = cachedMediaDataPaths {
            return cache
        }
        
        var urlStrings: [String] = []
        let urls: [URL]? = internalMovie.findReferenceURLs()
        if let urls = urls {
            urlStrings = urls.map { $0.path }
        }
        cachedMediaDataPaths = (urlStrings.count > 0 ? urlStrings : ["-"])
        return cachedMediaDataPaths
    }
    
    
    /// Inspector - VideoFPS Description
    ///
    /// - Returns: human readable description
    public func videoFPSs() -> [String]? {
        if let cache = cachedVideoFPSs {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            let trackID: Int = Int(track.trackID)
            let fps: Float = track.nominalFrameRate
            let trackString: String = String(format:"%d: %.2f fps", trackID, fps)
            trackStrings.append(trackString)
        }
        cachedVideoFPSs = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedVideoFPSs
    }
    
    /// Inspector - VideoDataSize/Rate Description
    ///
    /// - Returns: human readable description
    public func videoDataSizes() -> [String]? {
        if let cache = cachedVideoDataSizes {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            let trackID: Int = Int(track.trackID)
            let size: Int64 = track.totalSampleDataLength
            let rate: Float = track.estimatedDataRate
            let trackString: String = String(format:"%d: %.2f MB, %.3f Mbps", trackID,
                                             Float(size)/1000000.0,
                                             rate/1000000.0)
            trackStrings.append(trackString)
        }
        cachedVideoDataSizes = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedVideoDataSizes
    }
    
    /// Inspector - AudioDataSize/Rate Description
    ///
    /// - Returns: human readable description
    public func audioDataSizes() -> [String]? {
        if let cache = cachedAudioDataSizes {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .audio) {
            let trackID: Int = Int(track.trackID)
            let size: Int64 = track.totalSampleDataLength
            let rate: Float = track.estimatedDataRate
            let trackString: String = String(format:"%d: %.2f MB, %.3f Mbps", trackID,
                                             Float(size)/1000000.0,
                                             rate/1000000.0)
            trackStrings.append(trackString)
        }
        cachedAudioDataSizes = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedAudioDataSizes
    }
    
    /// Inspector - VideoFormats Description
    ///
    /// - Returns: human readable description
    public func videoFormats() -> [String]? {
        if let cache = cachedVideoFormats {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            var trackString: [String] = []
            let trackID: Int = Int(track.trackID)
            let reference: Bool = !(track.isSelfContained)
            for desc in track.formatDescriptions as! [CMVideoFormatDescription] {
                var name: String = ""
                do {
                    let ext: CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc,
                                                        extensionKey: kCMFormatDescriptionExtension_FormatName)
                    if let ext = ext {
                        let nameStr = ext as! NSString
                        name = String(nameStr)
                    } else {
                        let fcc: FourCharCode = CMFormatDescriptionGetMediaSubType(desc)
                        let fccString: NSString = osTypeToString(fcc) as NSString
                        name = "\'\(fccString)\'"
                    }
                }
                var dimension: String = ""
                do {
                    let encoded: CGSize =
                        CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                          usePixelAspectRatio: false,
                                                                          useCleanAperture: false)
                    let prod: CGSize =
                        CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                          usePixelAspectRatio: true,
                                                                          useCleanAperture: false)
                    let clean: CGSize =
                        CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                          usePixelAspectRatio: true,
                                                                          useCleanAperture: true)
                    if encoded != prod || encoded != clean {
                        dimension = (prod == clean) ?
                            stringForTwo(encoded, prod) :
                            stringForThree(encoded, prod, clean)
                    } else {
                        dimension = stringForOne(encoded)
                    }
                }
                if reference {
                    trackString.append("\(trackID): \(name), \(dimension), Reference")
                } else {
                    trackString.append("\(trackID): \(name), \(dimension)")
                }
            }
            trackStrings.append(contentsOf: trackString)
        }
        cachedVideoFormats = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedVideoFormats
    }
    
    /// Inspector - AudioFormats Description
    ///
    /// - Returns: human readable description
    public func audioFormats() -> [String]? {
        if let cache = cachedAudioFormats {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .audio) {
            var trackString: [String] = []
            let trackID: Int = Int(track.trackID)
            let reference: Bool = !(track.isSelfContained)
            for desc in track.formatDescriptions as! [CMAudioFormatDescription] {
                var rateString: String = ""
                do {
                    let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                    if let ptr = basic {
                        let rate: Float64 = ptr.pointee.mSampleRate
                        rateString = String(format:"%.3f kHz", rate/1000.0)
                    }
                }
                var formatString: String = ""
                do {
                    // get AudioStreamBasicDescription ptr
                    let asbdSize: UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                    let asbdPtr: UnsafePointer<AudioStreamBasicDescription>? =
                        CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                    if asbdPtr != nil {
                        var formatSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
                        var format: CFString = String() as CFString
                        withUnsafeMutablePointer(to: &format) { formatPtr -> Void in
                            let err: OSStatus = AudioFormatGetProperty(kAudioFormatProperty_FormatName,
                                                                       asbdSize, asbdPtr, &formatSize, formatPtr)
                            if err == noErr {
                                formatString = formatPtr.pointee as String
                            }
                        }
                    }
                }
                var layoutString: String = ""
                do {
                    let tagSize: UInt32 = UInt32(MemoryLayout<AudioChannelLayoutTag>.size)
                    var tag: AudioChannelLayoutTag = kAudioChannelLayoutTag_Unknown
                    var dataSize: UInt32 = 0
                    var data: Data? = nil
                    var err: OSStatus = noErr;
                    let item: UnsafePointer<AudioFormatListItem>? =
                        CMAudioFormatDescriptionGetMostCompatibleFormat(desc)
                    if let item = item {
                        tag = item.pointee.mChannelLayoutTag // kAudioChannelLayoutTag_Stereo //
                        err = AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForTag,
                                                         tagSize, &tag, &dataSize)
                        if err == noErr && dataSize > 0 {
                            data = Data(count: Int(dataSize))
                        }
                    }
                    data?.withUnsafeMutableBytes { (dataPtr) -> Void in
                        var aclSize: UInt32 = dataSize
                        let aclPtr: UnsafeMutableRawPointer? = dataPtr.baseAddress
                        err = AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag,
                                                     tagSize, &tag, &aclSize, aclPtr)
                        if err == noErr {
                            var nameSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
                            var name: CFString = String() as CFString
                            withUnsafeMutablePointer(to: &name) { namePtr -> Void in
                                err = AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutName,
                                                             aclSize, aclPtr, &nameSize, namePtr)
                                if err == noErr {
                                    layoutString = namePtr.pointee as String
                                }
                            }
                        }
                    }
                }
                do {
                    var err: OSStatus = noErr;
                    var aclSize: Int = 0
                    let aclPtr: UnsafePointer<AudioChannelLayout>? =
                        CMAudioFormatDescriptionGetChannelLayout(desc, sizeOut: &aclSize)
                    if aclSize > 0, let aclPtr = aclPtr {
                        var nameSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
                        var name: CFString = String() as CFString
                        withUnsafeMutablePointer(to: &name) { namePtr -> Void in
                            err = AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutName,
                                                         UInt32(aclSize), aclPtr, &nameSize, namePtr)
                            if err == noErr {
                                layoutString = namePtr.pointee as String
                            }
                        }
                    }
                }
                if reference {
                    trackString.append("\(trackID): \(formatString), \(layoutString), \(rateString), Reference")
                } else {
                    trackString.append("\(trackID): \(formatString), \(layoutString), \(rateString)")
                }
            }
            trackStrings.append(contentsOf: trackString)
        }
        cachedAudioFormats = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedAudioFormats
    }
    
    // subs for UTCreateStringForOSType()
    private func osTypeToString(_ code:OSType) -> String {
        let s0 = UInt8(code >> 24 & 255)
        let s1 = UInt8(code >> 16 & 255)
        let s2 = UInt8(code >> 8  & 255)
        let s3 = UInt8(code       & 255)
        return [s0, s1, s2, s3].map{ String(UnicodeScalar($0)) }.joined()
    }
}

/* ============================================ */
// MARK: - AVPlayer support
/* ============================================ */

extension MovieMutator {
    
    /// Make new AVPlayerItem for internalMovie
    ///
    /// - Returns: AVPlayerItem
    public func makePlayerItem() -> AVPlayerItem {
        let asset: AVAsset = internalMovie.copy() as! AVAsset
        let playerItem: AVPlayerItem = AVPlayerItem(asset: asset)
        if let comp = makeVideoComposition() {
            playerItem.videoComposition = comp
        }
        return playerItem
    }
    
    /* ============================================ */
    // MARK: private method
    /* ============================================ */
    
    /// Make new AVVideoComposition for internalMovie
    ///
    /// - Returns: AVVideoComposition
    private func makeVideoComposition() -> AVVideoComposition? {
        let vCount = internalMovie.tracks(withMediaType: .video).count
        if vCount > 1 {
            let comp: AVVideoComposition = AVVideoComposition(propertiesOf: internalMovie)
            return comp
        }
        return nil
    }
}

/* ============================================ */
// MARK: - export/write support
/* ============================================ */

extension MovieMutator {
    private func prepareMovieWriterParams() -> MovieWriterParams {
        return MovieWriterParams(movie: self.internalMovie,
                                 unblockUserInteraction: self.unblockUserInteraction,
                                 updateProgress: self.updateProgress)
    }
    
    public func exportMovie(to url: URL, fileType type: AVFileType, presetName preset: String?) async throws {
        let movieWriterParams = prepareMovieWriterParams()
        try await Task { @MainActor in
            let movieWriter = MovieWriter(params: movieWriterParams)
            try await movieWriter.exportMovie(to: url, fileType: type, presetName: preset)
        }.value
    }
    
    public func exportCustomMovie(to url: URL, fileType type: AVFileType, settings param: [String:Sendable]) async throws {
        let movieWriterParams = prepareMovieWriterParams()
        try await Task { @MainActor in
            let movieWriter = MovieWriter(params: movieWriterParams)
            try await movieWriter.exportCustomMovie(to: url, fileType: type, settings: param)
        }.value
    }
    
    public func writeMovie(to url: URL, fileType type: AVFileType, copySampleData selfContained: Bool) async throws {
        let movieWriterParams = prepareMovieWriterParams()
        try await Task { @MainActor in
            let movieWriter = MovieWriter(params: movieWriterParams)
            try await movieWriter.writeMovie(to: url, fileType: type, copySampleData: selfContained)
        }.value
    }
}
