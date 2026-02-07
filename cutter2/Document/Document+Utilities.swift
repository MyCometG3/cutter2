//
//  Document+Utilities.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/16.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - Misc utilities
/* ============================================ */

extension Document {
    public func inspectorDictionary() -> [String:Any] {
        
        var dict: [String:Any] = [:]
        guard let mutator = self.movieMutator else { return dict }
        
        dict[titleInspectKey] = self.displayName
        dict[pathInspectKey] = mutator.mediaDataPaths()?.joined(separator: "\n")
        dict[videoFormatInspectKey] = mutator.videoFormats()?.joined(separator: "\n")
        dict[videoFPSInspectKey] = mutator.videoFPSs()?.joined(separator: "\n")
        dict[audioFormatInspectKey] = mutator.audioFormats()?.joined(separator: "\n")
        dict[videoDataSizeInspectKey] = mutator.videoDataSizes()?.joined(separator: "\n")
        dict[audioDataSizeInspectKey] = mutator.audioDataSizes()?.joined(separator: "\n")
        dict[currentTimeInspectKey] = mutator.shortTimeString(mutator.insertionTime, withDecimals: true)
        dict[movieDurationInspectKey] = mutator.shortTimeString(mutator.movieDuration(), withDecimals: true)
        
        let range: CMTimeRange = mutator.selectedTimeRange
        dict[selectionStartInspectKey] = mutator.shortTimeString(range.start, withDecimals: true)
        dict[selectionEndInspectKey] = mutator.shortTimeString(range.end, withDecimals: true)
        dict[selectionDurationInspectKey] = mutator.shortTimeString(range.duration, withDecimals: true)
        
        return dict
    }
    
    /// used in debugInfo()
    public func modifier(_ mask: NSEvent.ModifierFlags) -> Bool {
        
        guard let current = NSApp.currentEvent?.modifierFlags else { return false }
        
        return current.contains(mask)
    }
    
    /// Cleanup for close document
    public func cleanup() {
        
        //
        self.removeMutationObserver()
        self.removeAllUndoRecords()
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
}
