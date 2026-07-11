//
//  MovieMutator+Edit.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Edit Operations
/* ============================================ */

extension MovieMutator {
    
    /* ============================================ */
    // MARK: - private method - get movie clip
    /* ============================================ */
    
    /// Create movie clip from specified CMTimeRange
    ///
    /// - Parameter range: clip range
    /// - Returns: clip as AVMutableMovie
    internal func movieClip(_ range: CMTimeRange) -> AVMutableMovie? {
        guard validateRange(range, true) else {
            LoggingSystem.video.error("\(self.ts()) Invalid range \(CMTimeGetSeconds(range.start))...\(CMTimeGetSeconds(range.end))")
            return nil
        }
        
        // Prepare clip
        guard let aClip = internalMovie.mutableCopy() as? AVMutableMovie else {
            preconditionFailure("mutableCopy() of AVMutableMovie returned non-AVMutableMovie")
        }
        var clip = aClip
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
                try clip.insertTimeRange(movieRange, of: internalMovie, at: CMTime.zero, copySampleData: false)
            } catch {
                LoggingSystem.video.error("\(self.ts()) \(error)")
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
        
        guard range.duration == clip.range.duration else {
            LoggingSystem.video.error("\(self.ts()) invalid clip duration mismatch")
            return nil
        }
        
        precondition(validateClip(clip), "ERROR: invalid clip")
        return clip
    }
    
    /* ============================================ */
    // MARK: - private method - remove/insert clip
    /* ============================================ */
    
    /// Remove range. Adjust insertionTime.
    ///
    /// - Parameters:
    ///   - range: Range to remove
    ///   - time: insertionTime
    /// - Returns: true if the removal succeeded
    private func doRemove(_ range: CMTimeRange, _ time: CMTime) -> Bool {
        guard validateRange(range, true) else {
            LoggingSystem.video.error("\(self.ts()) Invalid range \(CMTimeGetSeconds(range.start))...\(CMTimeGetSeconds(range.end))")
            return false
        }
        
        // perform delete selection
        do {
            internalMovie.removeTimeRange(range)
            
            // Update Marker
            let newTime: CMTime = (time <= range.start ? time
                                   : (range.start < time && time <= range.end) ? range.start
                                   : time - range.duration)
            let newRange: CMTimeRange = CMTimeRangeMake(start: range.start, duration: CMTime.zero)
            resetMarker(newTime, newRange, true)
            return true
        }
    }
    
    /// Undo remove range. Restore movie, insertionTime and selection.
    ///
    /// - Parameters:
    ///   - data: movieHeader data to be restored.
    ///   - range: original selection
    ///   - time: original insertionTime
    ///   - clip: removed clip data
    private func undoRemove(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip: Data) {
        guard validateClipData(clip) else {
            LoggingSystem.video.error("\(self.ts()) Invalid clip data for undo remove")
            return
        }
        
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        guard reloadDone else {
            LoggingSystem.video.error("\(self.ts()) Failed to reload movie for undo remove")
            return
        }
    }
    
    /// Insert clip at insertionTime. Adjust insertionTime/selection.
    ///
    /// - Parameters:
    ///   - clip: clip data to insert
    ///   - time: insertionTime
    /// - Returns: true if the insertion succeeded
    private func doInsert(_ clip: Data, _ time: CMTime) -> Bool {
        let clip = AVMutableMovie(data: clip, options: nil)
        guard validateClip(clip), validateTime(time) else {
            LoggingSystem.video.error("\(self.ts()) Invalid insert request")
            return false
        }
        
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
            
            try internalMovie.insertTimeRange(clipRange,
                                              of: clip,
                                              at: time,
                                              copySampleData: false)
            
            // Update Marker
            let afterDuration = self.movieDuration()
            let actualDelta = afterDuration - beforeDuration
            let newTime: CMTime = time + actualDelta
            let newRange: CMTimeRange = CMTimeRangeMake(start: time, duration: actualDelta)
            resetMarker(newTime, newRange, true)
            return true
        } catch {
            LoggingSystem.video.error("Failed to insert clip: \(error.localizedDescription)")
            return false
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
        guard validateClipData(clip) else {
            LoggingSystem.video.error("\(self.ts()) Invalid clip data for undo insert")
            return
        }
        
        // populate PBoard with original clip
        let pbDone: Bool = writeClipToPBoard(clip)
        guard pbDone else {
            LoggingSystem.video.error("\(self.ts()) Failed to populate PBoard for undo insert")
            return
        }
        
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        guard reloadDone else {
            LoggingSystem.video.error("\(self.ts()) Failed to reload movie for undo insert")
            return
        }
    }
    
    /* ============================================ */
    // MARK: - public method - edit action
    /* ============================================ */
    
    /// Copy selection of internalMovie
    public func copySelection() {
        
        // perform copy selection
        let range = self.selectedTimeRange
        guard validateRange(range, true) else { NSSound.beep(); return; }
        
        let pbDone = (writeRangeToPBoard(range) != nil)
        guard pbDone else {
            NSSound.beep()
            return
        }
    }
    
    /// Cut selection of internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func cutSelection(using undoManager: UndoManagerWrapper) {
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, true) else { NSSound.beep(); return; }
        guard let clip = writeRangeToPBoard(range) else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // perform cut first
        guard self.doRemove(range, time) else {
            NSSound.beep()
            return
        }
        refreshMovie()
        
        // register undo record (only after successful mutation)
        let undoCutHandler: @MainActor (MovieMutator) -> Void = {[data, clip, range, time, unowned undoManager] (me1) in // @escaping
            let redoCutHandler: @MainActor (MovieMutator) -> Void = {[range, time, unowned undoManager] (me2) in // @escaping
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
    }
    
    /// Paste clip into internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func pasteAtInsertionTime(using undoManager: UndoManagerWrapper) {
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, false) else { NSSound.beep(); return; }
        guard let clip = readClipFromPBoard() else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // perform paste first
        guard self.doInsert(clip, time) else {
            NSSound.beep()
            return
        }
        refreshMovie()
        
        // register undo record (only after successful mutation)
        let undoPasteHandler: @MainActor (MovieMutator) -> Void = {[data, clip, range, time, unowned undoManager] (me1) in // @escaping
            let redoPasteHandler: @MainActor (MovieMutator) -> Void = {[unowned undoManager] (me2) in // @escaping
                me2.pasteAtInsertionTime(using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoPasteHandler)
            undoManager.setActionName("Paste at marker")
            
            // perform undo paste
            me1.undoInsert(data, range, time, clip)
        }
        undoManager.registerUndo(withTarget: self, handler: undoPasteHandler)
        undoManager.setActionName("Paste at marker")
    }
    
    /// Delete selection of internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func deleteSelection(using undoManager: UndoManagerWrapper) {
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, true) else { NSSound.beep(); return; }
        guard let clip = movieClip(range)?.movHeader else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // perform delete first
        guard self.doRemove(range, time) else {
            NSSound.beep()
            return
        }
        refreshMovie()
        
        // register undo record (only after successful mutation)
        let undoDeleteHandler: @MainActor (MovieMutator) -> Void = {[data, clip, range, time, unowned undoManager] (me1) in // @escaping
            let redoDeleteHandler: @MainActor (MovieMutator) -> Void = {[range, time, unowned undoManager] (me2) in // @escaping
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
    }
}
