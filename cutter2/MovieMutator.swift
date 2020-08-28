//
//  MovieMutator.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2019年 MyCometG3. All rights reserved.
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
// MARK: -
/* ============================================ */

/// Wrapper of AVMutableMovie as model object of movie editor
class MovieMutator: MovieMutatorBase {
    
    /* ============================================ */
    // MARK: - private method - get movie clip
    /* ============================================ */
    
    /// Create movie clip from specified CMTimeRange
    ///
    /// - Parameter range: clip range
    /// - Returns: clip as AVMutableMovie
    private func movieClip(_ range: CMTimeRange) -> AVMutableMovie? {
        assert(validateRange(range, true), #function)
        
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
                assert(false, #function)
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
            assert(false, #function) //
            return nil
        }
        
        assert(validateClip(clip), #function)
        return clip
    }
    
    /* ============================================ */
    // MARK: - private method - work w/ PasteBoard
    /* ============================================ */
    
    /// Read movie clip data from PasteBoard
    ///
    /// - Returns: AVMutableMovie
    private func readClipFromPBoard() -> AVMutableMovie? {
        let pBoard: NSPasteboard = NSPasteboard.general
        
        // extract movie header data from PBoard
        let data: Data? = pBoard.data(forType: .movieMutator)
        
        if let data = data {
            // create movie from movieHeader data
            // Swift.print(ts(), #function, #line, #file)
            let clip: AVMutableMovie? = AVMutableMovie(data: data, options: nil)
            // Swift.print(ts(), #function, #line, #file)
            
            if let clip = clip, validateClip(clip) {
                return clip
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    /// Write movie clip data to PasteBoard
    ///
    /// - Parameter clip: AVMutableMovie
    /// - Returns: true if success
    private func writeClipToPBoard(_ clip: AVMutableMovie) -> Bool {
        assert(validateClip(clip), #function) //
        
        // create movieHeader data from movie
        if let data = clip.movHeader {
            // register data to PBoard
            let pBoard: NSPasteboard = NSPasteboard.general
            pBoard.clearContents()
            pBoard.setData(data, forType: .movieMutator)
            
            return true
        } else {
            return false
        }
    }
    
    /// Write movie clip data to PasteBoard
    ///
    /// - Parameter range: CMTimeRange of clip
    /// - Returns: AVMutableMovie of clip
    private func writeRangeToPBoard(_ range: CMTimeRange) -> AVMutableMovie? {
        guard let clip = self.movieClip(range) else { return nil }
        guard self.writeClipToPBoard(clip) else { return nil }
        return clip
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
        assert(validateRange(range, true), #function)
        
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
    ///   - clip: removed clip - unused
    private func undoRemove(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip: AVMutableMovie) {
        assert(validateClip(clip), #function)
        
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        assert(reloadDone, #function)
    }
    
    /// Insert clip at insertionTime. Adjust insertionTime/selection.
    ///
    /// - Parameters:
    ///   - clip: insertionTime
    ///   - time: selection
    private func doInsert(_ clip: AVMutableMovie, _ time: CMTime) {
        assert(validateClip(clip), #function)
        assert(validateTime(time), #function)
        
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
            assert(false, #function) //
        }
    }
    
    /// Undo insert clip. Restore movie, insertionTime and selection.
    ///
    /// - Parameters:
    ///   - data: movieHeader data to be restored.
    ///   - range: original selection
    ///   - time: original insertionTime
    ///   - clip: inserted clip
    private func undoInsert(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip: AVMutableMovie) {
        assert(validateClip(clip), #function)
        
        // populate PBoard with original clip
        let pbDone: Bool = writeClipToPBoard(clip)
        assert(pbDone, #function)
        
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        assert(reloadDone, #function)
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
        assert(pbDone, #function)
    }
    
    /// Cut selection of internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func cutSelection(using undoManager: UndoManager) {
        // Swift.print(ts(), #function, #line, #file)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, true) else { NSSound.beep(); return; }
        guard let clip = writeRangeToPBoard(range) else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo record
        let undoCutHandler: (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in // @escaping
            // register redo record
            let redoCutHandler: (MovieMutator) -> Void = {[unowned undoManager] (me2) in // @escaping
                me2.resetMarker(time, range, false)
                me2.cutSelection(using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoCutHandler)
            undoManager.setActionName("Cut selection")
            
            // perform undo cut
            me1.undoRemove(data, range, time, clip)
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
    public func pasteAtInsertionTime(using undoManager: UndoManager) {
        // Swift.print(ts(), #function, #line, #file)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, false) else { NSSound.beep(); return; }
        guard let clip = readClipFromPBoard() else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo record
        let undoPasteHandler: (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in // @escaping
            // register redo record
            let redoPasteHandler: (MovieMutator) -> Void = {[unowned undoManager] (me2) in // @escaping
                me2.pasteAtInsertionTime(using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoPasteHandler)
            undoManager.setActionName("Paste at marker")
            
            // perform undo paste
            me1.undoInsert(data, range, time, clip)
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
    public func deleteSelection(using undoManager: UndoManager) {
        // Swift.print(ts(), #function, #line, #file)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, true) else { NSSound.beep(); return; }
        guard let clip = movieClip(range) else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo redord
        let undoDeleteHandler: (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in // @escaping
            // register redo record
            let redoDeleteHandler: (MovieMutator) -> Void = {[unowned undoManager] (me2) in // @escaping
                me2.resetMarker(time, range, false)
                me2.deleteSelection(using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoDeleteHandler)
            undoManager.setActionName("Delete selection")
            
            // perform undo delete
            me1.undoRemove(data, range, time, clip)
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
    private func doReplace(_ movie: AVMutableMovie, _ range: CMTimeRange, _ time: CMTime) {
        assert(validateRange(range, false), #function)
        
        // perform replacement
        do {
            // Swift.print(ts(), #function, #line, #file)
            internalMovie = movie
            // Swift.print(ts(), #function, #line, #file)
            
            // Update Marker
            let newTime: CMTime = (time < movie.range.end) ? time : movie.range.end
            let newRange: CMTimeRange = CMTimeRangeGetIntersection(range, otherRange: movie.range)
            resetMarker(newTime, newRange, true)
        }
    }
    
    //
    private func undoReplace(_ data: Data, _ range: CMTimeRange, _ time: CMTime) {
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        assert(reloadDone, #function)
    }
    
    //
    private func updateFormat(_ movie: AVMutableMovie, using undoManager: UndoManager) {
        // Swift.print(ts(), #function, #line, #file)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, false) else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo record
        let undoPasteHandler: (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in // @escaping
            // register redo replace
            let redoPasteHandler: (MovieMutator) -> Void = {[unowned undoManager] (me2) in // @escaping
                me2.updateFormat(movie, using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoPasteHandler)
            undoManager.setActionName("Update format")
            
            // perform undo replace
            me1.undoReplace(data, range, time)
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
        
        let vTracks: [AVMovieTrack] = internalMovie.tracks(withMediaType: .video)
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
    public func applyClapPasp(_ dict: [AnyHashable:Any], using undoManager: UndoManager) -> Bool {
        guard #available(OSX 10.13, *) else { return false }
        
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
        
        if count > 0 {
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
