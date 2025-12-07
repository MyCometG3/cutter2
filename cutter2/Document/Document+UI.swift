//
//  Document+UI.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/13.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - UI Operations
/* ============================================ */

extension Document {
    
    /* ============================================ */
    // MARK: - Resize window
    /* ============================================ */
    
    public func displayRatio(_ baseSize: CGSize?) -> CGFloat {
        
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
        
        guard let mutator = self.movieMutator else { NSSound.beep(); return }
        guard let dict: [AnyHashable:Any] = mutator.clappaspDictionary() else { NSSound.beep(); return }
        
        // Prepare CAPAR SheetController
        let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
        let sid: NSStoryboard.SceneIdentifier = "CAPARSheet Controller"
        let caparWC = storyboard.instantiateController(withIdentifier: sid) as! NSWindowController
        // caparWC.loadWindow()
        
        // Prepare CAPAR ViewController
        guard let contVC = caparWC.contentViewController else { preconditionFailure("Unexpected nil contentViewController detected.") }
        guard let caparVC = contVC as? CAPARViewController else { preconditionFailure("Unexpected nil CAPARViewController detected.") }
        guard caparVC.applySource(dict) else { return }
        
        // Show CAPAR Sheet
        caparVC.beginSheetModal(for: self.window!) {[caparVC, mutator, weak self] (response) in // @escaping
            
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            guard response == .continue else { return }
            
            // Update Clap/Pasp settings
            let result: [AnyHashable:Any] = caparVC.resultContent
            let done: Bool = mutator.applyClapPasp(result, using: self.undoManagerWrapper)
            if !done {
                var info: [String:Any] = [:]
                info[NSLocalizedDescriptionKey] = "Failed to modify CAPAR extensions."
                info[NSLocalizedFailureReasonErrorKey] = "Check if video track has same dimensions."
                let err = NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: info)
                
                self.showErrorSheet(err)
            }
        }
    }
    
    /* ============================================ */
    // MARK: - Track Offset
    /* ============================================ */
    
    @IBAction func showTrackOffsetPanel(_ sender: Any?) {
        
        guard let mutator = self.movieMutator else { NSSound.beep(); return }
        
        // Prepare Track Offset SheetController
        let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
        let sid: NSStoryboard.SceneIdentifier = "TrackOffsetSheet Controller"
        let trackOffsetWC = storyboard.instantiateController(withIdentifier: sid) as! NSWindowController
        
        // Prepare Track Offset ViewController
        guard let contVC = trackOffsetWC.contentViewController else { 
            preconditionFailure("Unexpected nil contentViewController detected.") 
        }
        guard let trackOffsetVC = contVC as? TrackOffsetViewController else { 
            preconditionFailure("Unexpected nil TrackOffsetViewController detected.") 
        }
        
        // Show Track Offset Sheet
        trackOffsetVC.beginSheetModal(for: self.window!, document: self) { [weak self] (response) in
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            guard response == .continue else { return }
            
            // Offsets applied successfully - refresh UI is handled by notification
        }
    }
}
