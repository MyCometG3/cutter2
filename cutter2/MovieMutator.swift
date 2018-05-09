//
//  MovieMutator.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVKit
import AVFoundation

/// Wrapper of AVMutableMovie as model object of movie editor
class MovieMutator: MovieMutatorBase {
    /* ============================================ */
    // MARK: - private method - get movie clip
    /* ============================================ */
    
    /// Create movie clip from specified CMTimeRange
    ///
    /// - Parameter range: clip range
    /// - Returns: clip as AVMutableMovie
    private func movieClip(_ range : CMTimeRange) -> AVMutableMovie? {
        guard validateRange(range, true) else {
            assert(false, #function) //
            return nil
        }
        
        // Prepare clip
        var clip : AVMutableMovie = internalMovie.mutableCopy() as! AVMutableMovie
        if clip.timescale != range.duration.timescale {
            // Create new Movie with exact timescale; it should match before operation
            clip = AVMutableMovie()
            let scale = range.duration.timescale
            clip.timescale = scale
            clip.preferredRate = 1.0
            clip.preferredVolume = 1.0
            clip.interleavingPeriod = CMTimeMakeWithSeconds(0.5, scale)
            clip.preferredTransform = CGAffineTransform.identity
            clip.isModified = false
            // convert all into different timescale
            do {
                let movieRange : CMTimeRange = self.movieRange()
                Swift.print(ts(), #function, #line)
                try clip.insertTimeRange(movieRange, of: internalMovie, at: kCMTimeZero, copySampleData: false)
                Swift.print(ts(), #function, #line)
            } catch {
                Swift.print(error)
                assert(false, #function)
            }
        }
        
        // Trim clip
        let rangeAfter : CMTimeRange = CMTimeRangeMake(range.end, clip.range.duration - range.end)
        if rangeAfter.duration > kCMTimeZero {
            clip.removeTimeRange(rangeAfter)
        }
        let rangeBefore : CMTimeRange = CMTimeRangeMake(kCMTimeZero, range.start)
        if rangeBefore.duration > kCMTimeZero {
            clip.removeTimeRange(rangeBefore)
        }
        
        if range.duration != clip.range.duration {
            Swift.print(ts(), "NOTICE: diff", CMTimeGetSeconds(range.duration),
                        CMTimeGetSeconds(clip.range.duration), "at", #function, #line)
            Swift.print(ts(), range.duration)
            Swift.print(ts(), clip.range.duration)
            assert(false, #function) //
            return nil
        }
        
        if validateClip(clip) {
            return clip
        } else {
            assert(false, #function) //
            return nil
        }
    }
    
    /* ============================================ */
    // MARK: - private method - work w/ PasteBoard
    /* ============================================ */
    
    /// Read movie clip data from PasteBoard
    ///
    /// - Returns: AVMutableMovie
    private func readClipFromPBoard() -> AVMutableMovie? {
        let pBoard : NSPasteboard = NSPasteboard.general
        
        // extract movie header data from PBoard
        let data : Data? = pBoard.data(forType: clipPBoardType)
        
        if let data = data {
            // create movie from movieHeader data
            //Swift.print(ts(), #function, #line)
            let clip : AVMutableMovie? = AVMutableMovie(data: data, options: nil)
            //Swift.print(ts(), #function, #line)
            
            if let clip = clip, validateClip(clip) {
                return clip
            } else {
                assert(false, #function) //
                return nil
            }
        } else {
            // assert(false, #function) //
            return nil
        }
    }
    
    /// Write movie clip data to PasteBoard
    ///
    /// - Parameter clip: AVMutableMovie
    /// - Returns: true if success
    private func writeClipToPBoard(_ clip : AVMutableMovie) -> Bool {
        assert( validateClip(clip), #function ) //
        
        // create movieHeader data from movie
        do {
            //Swift.print(ts(), #function, #line)
            let data : Data? = try clip.makeMovieHeader(fileType: AVFileType.mov)
            //Swift.print(ts(), #function, #line)
            
            if let data = data {
                // register data to PBoard
                let pBoard : NSPasteboard = NSPasteboard.general
                pBoard.clearContents()
                pBoard.setData(data, forType: clipPBoardType)
                
                return true
            } else {
                assert(false, #function) //
                return false
            }
        } catch {
            Swift.print(error)
            assert(false, #function)
        }
        return false
    }
    
    /// Write movie clip data to PasteBoard
    ///
    /// - Parameter range: CMTimeRange of clip
    /// - Returns: AVMutableMovie of clip
    private func writeRangeToPBoard(_ range : CMTimeRange) -> AVMutableMovie? {
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
        let pBoard : NSPasteboard = NSPasteboard.general
        
        if let _ = pBoard.data(forType: clipPBoardType) {
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
        assert( validateRange(range, true), #function )
        
        // perform delete selection
        do {
            //Swift.print(ts(), #function, #line)
            internalMovie.removeTimeRange(range)
            //Swift.print(ts(), #function, #line)
            
            // Update Marker
            insertionTime = (time < range.start ? time
                : (CMTimeRangeContainsTime(range, time) ? range.start : time - range.duration))
            selectedTimeRange = CMTimeRangeMake(range.start, kCMTimeZero)
            internalMovieDidChange(insertionTime, selectedTimeRange)
        }
    }
    
    /// Undo remove range. Restore movie, insertionTime and selection.
    ///
    /// - Parameters:
    ///   - data: movieHeader data to be restored.
    ///   - range: original selection
    ///   - time: original intertionTime
    ///   - clip: removed clip - unused
    private func undoRemove(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip : AVMutableMovie) {
        assert( validateClip(clip), #function )
        
        guard reloadAndNotify(from: data, range: range, time: time) else {
            assert(false, #function) //
            NSSound.beep(); return
        }
    }
    
    /// Insert clip at insertionTime. Adjust insertionTime/selection.
    ///
    /// - Parameters:
    ///   - clip: insertionTime
    ///   - time: selection
    private func doInsert(_ clip: AVMutableMovie, _ time: CMTime) {
        assert( validateClip(clip), #function )
        assert( validateTime(time), #function )
        
        // perform insert clip at marker
        do {
            var clipRange : CMTimeRange = CMTimeRange(start: kCMTimeZero,
                                                      duration: clip.range.duration)
            if clip.timescale != internalMovie.timescale {
                // Shorten if fraction is not zero
                let duration : CMTime = CMTimeConvertScale(clip.range.duration,
                                                           internalMovie.timescale,
                                                           .roundTowardZero)
                clipRange = CMTimeRange(start: kCMTimeZero,
                                        duration: duration)
            }
            let beforeDuration = self.movieDuration()
            
            Swift.print(ts(), #function, #line)
            try internalMovie.insertTimeRange(clipRange,
                                              of: clip,
                                              at: time,
                                              copySampleData: false)
            Swift.print(ts(), #function, #line)
            
            // Update Marker
            let afterDuration = self.movieDuration()
            let actualDelta = afterDuration - beforeDuration
            insertionTime = time + actualDelta
            selectedTimeRange = CMTimeRangeMake(time, actualDelta)
            
            internalMovieDidChange(insertionTime, selectedTimeRange)
        } catch {
            Swift.print(error)
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
    private func undoInsert(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip : AVMutableMovie) {
        assert( validateClip(clip), #function )
        
        // populate PBoard with original clip
        guard writeClipToPBoard(clip) else {
            assert(false, #function) //
            NSSound.beep(); return
        }
        
        guard reloadAndNotify(from: data, range: range, time: time) else {
            assert(false, #function) //
            NSSound.beep(); return
        }
    }
    
    /* ============================================ */
    // MARK: - public method - edit action
    /* ============================================ */
    
    /// Copy selection of internalMovie
    public func copySelection() {
        // Swift.print(#function, #line)
        
        // perform copy selection
        let range = self.selectedTimeRange
        if !validateRange(range, true) { NSSound.beep(); return; }
        
        guard let _ = writeRangeToPBoard(range) else {
            assert(false, #function) //
            NSSound.beep(); return;
        }
    }
    
    /// Cut selection of internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func cutSelection(using undoManager : UndoManager) {
        // Swift.print(#function, #line)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        if !validateRange(range, true) { NSSound.beep(); return; }
        
        guard let clip = writeRangeToPBoard(range) else { NSSound.beep(); return; }
        guard let data = movieData() else { NSSound.beep(); return; }
        
        // register undo record
        let undoCutHandler : (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in
            // register redo record
            let redoCutHandler : (MovieMutator) -> Void = {[unowned undoManager] (me2) in
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
    public func pasteAtInsertionTime(using undoManager : UndoManager) {
        // Swift.print(#function, #line)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        if !validateRange(range, false) { NSSound.beep(); return; }
        
        guard let clip = readClipFromPBoard() else { NSSound.beep(); return; }
        guard let data = movieData() else { NSSound.beep(); return; }

        // register undo record
        let undoPasteHandler : (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in
            // register redo record
            let redoPasteHandler : (MovieMutator) -> Void = {[unowned undoManager] (me2) in
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
    public func deleteSelection(using undoManager : UndoManager) {
        // Swift.print(#function, #line)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        if !validateRange(range, true) { NSSound.beep(); return; }
        
        guard let clip = movieClip(range) else {
            assert(false, #function) //
            NSSound.beep(); return;
        }
        guard let data = movieData() else { NSSound.beep(); return; }

        // register undo redord
        let undoDeleteHandler : (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in
            // register redo record
            let redoDeleteHandler : (MovieMutator) -> Void = {[unowned undoManager] (me2) in
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
        assert( validateRange(range, false), #function )
        
        // perform replacement
        do {
            //Swift.print(ts(), #function, #line)
            internalMovie = movie
            //Swift.print(ts(), #function, #line)
            
            // Update Marker
            insertionTime = (time < movie.range.end) ? time : movie.range.end
            selectedTimeRange = CMTimeRangeGetIntersection(range, movie.range)
            internalMovieDidChange(insertionTime, selectedTimeRange)
        }
    }
    
    //
    private func undoReplace(_ data: Data, _ range: CMTimeRange, _ time: CMTime) {
        guard reloadAndNotify(from: data, range: range, time: time) else {
            assert(false, #function) //
            NSSound.beep(); return
        }
    }
    
    //
    private func updateFormat(_ movie: AVMutableMovie, using undoManager : UndoManager) {
        // Swift.print(#function, #line)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        if !validateRange(range, false) { NSSound.beep(); return; }
        
        guard let data = movieData() else { NSSound.beep(); return; }
        
        // register undo record
        let undoPasteHandler : (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in
            // register redo replace
            let redoPasteHandler : (MovieMutator) -> Void = {[unowned undoManager] (me2) in
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
    public func applyClapPasp(_ dict : [AnyHashable:Any], using undoManager : UndoManager) -> Bool {
        guard #available(OSX 10.13, *) else { return false }
        
        guard let clapSize = dict[clapSizeKey] as? NSSize else { return false }
        guard let clapOffset = dict[clapOffsetKey] as? NSPoint else { return false }
        guard let paspRatio = dict[paspRatioKey] as? NSSize else { return false }
        guard let dimensions = dict[dimensionsKey] as? NSSize else { return false }
        
        var count : Int = 0
        
        let movie : AVMutableMovie = internalMovie.mutableCopy() as! AVMutableMovie
        
        let vTracks : [AVMutableMovieTrack] = movie.tracks(withMediaType: .video)
        for track in vTracks {
            if track.naturalSize != dimensions {
                Swift.print(#function, #line, track.trackID, track.naturalSize)
                continue
            }
            
            do {
                let ratio = paspRatio.width / paspRatio.height
                let newCAD = NSSize(width: clapSize.width * ratio, height: clapSize.height)
                let newPAD = NSSize(width: dimensions.width * ratio, height: dimensions.height)
                track.encodedPixelsDimensions = track.naturalSize
                track.cleanApertureDimensions = newCAD
                track.productionApertureDimensions = newPAD
            }
            
            let formats = track.formatDescriptions as! [CMFormatDescription]
            for format in formats {
                // Prepare new extensionDictionary
                guard let cfDict = CMFormatDescriptionGetExtensions(format) else { continue }
                let dict : NSMutableDictionary = NSMutableDictionary(dictionary: cfDict)
                dict[kCMFormatDescriptionExtension_VerbatimSampleDescription] = nil
                dict[kCMFormatDescriptionExtension_VerbatimISOSampleEntry] = nil

                // Replace CleanAperture if available
                if !validSize(clapSize) || !validPoint(clapOffset) {
                    dict[kCMFormatDescriptionExtension_CleanAperture] = nil
                } else {
                    let clap : NSMutableDictionary = [:]
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
                    let pasp : NSMutableDictionary = [:]
                    pasp[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] = paspRatio.width
                    pasp[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] = paspRatio.height
                    dict[kCMFormatDescriptionExtension_PixelAspectRatio] = pasp
                }
                
                // Create New formatDescription as replacement
                var newFormat : CMVideoFormatDescription? = nil
                let codecType = CMFormatDescriptionGetMediaSubType(format) as CMVideoCodecType
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                let result = CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                                               codecType,
                                                               dimensions.width,
                                                               dimensions.height,
                                                               dict,
                                                               &newFormat)
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
            //Swift.print(self.clappaspDictionary()! as! [String:Any])
            return true
        } else {
            Swift.print(ts(), "ERROR: Failed to modify CAPAR extensions.")
            return false
        }
    }
    
}
