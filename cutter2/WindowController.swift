//
//  WindowController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/02/17.
//  Copyright © 2018-2022年 MyCometG3. All rights reserved.
//

import Cocoa

class WindowController: NSWindowController, NSWindowDelegate {
    
    /* ============================================ */
    // MARK: - NSWindowController
    /* ============================================ */
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        self.shouldCascadeWindows = true
    }
    
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        // Update window title with scale ratio
        let doc = self.document as! Document
        let ratio = doc.displayRatio(nil) * 100
        let titleStr = String(format: "%@ (%.0f%%)", displayName, ratio)
        return titleStr
    }
    
    /* ============================================ */
    // MARK: - NSWindowDelegate protocol
    /* ============================================ */
    
    public func windowDidResize(_ notification: Notification) {
        // Update window title with scale ratio
        synchronizeWindowTitleWithDocumentName()
    }
    
    public func windowWillEnterFullScreen(_ notification: Notification) {
        // Hide controllerBox
        let vc = self.contentViewController as! ViewController
        vc.showController(false)
    }
    
    public func windowWillExitFullScreen(_ notification: Notification) {
        // Reveal controllerBox
        let vc = self.contentViewController as! ViewController
        vc.showController(true)
    }
    
    public func windowDidEnterFullScreen(_ notification: Notification) {
        // Reset keyView/makeFirstResponder on Fullscreen mode
        self.window!.selectNextKeyView(self)
    }
    
    public func windowDidExitFullScreen(_ notification: Notification) {
        // Reset keyView/makeFirstResponder on Non-Fullscreen mode
        self.window!.selectNextKeyView(self)
    }
}
