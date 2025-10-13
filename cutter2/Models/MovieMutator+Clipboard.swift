//
//  MovieMutator+Clipboard.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Clipboard Operations
/* ============================================ */

extension MovieMutator {
    
    /* ============================================ */
    // MARK: - private method - work w/ PasteBoard
    /* ============================================ */
    
    /// Read movie clip data from PasteBoard
    ///
    /// - Returns: Data of movie header
    internal func readClipFromPBoard() -> Data? {
        let pBoard: NSPasteboard = NSPasteboard.general
        
        // extract movie header data from PBoard
        let data: Data? = pBoard.data(forType: .movieMutator)
        return data
    }
    
    /// Write movie header data to PasteBoard
    ///
    /// - Parameter data: Data of movie header
    /// - Returns: true if success
    internal func writeClipToPBoard(_ data: Data) -> Bool {
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
    internal func writeRangeToPBoard(_ range: CMTimeRange) -> Data? {
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
}
