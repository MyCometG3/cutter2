//
//  WindowController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/02/17.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa

@MainActor
class WindowController: NSWindowController, NSWindowDelegate {
    
    /* ============================================ */
    // MARK: - NSWindowController
    /* ============================================ */
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        self.shouldCascadeWindows = true
        self.window?.isMovableByWindowBackground = true
    }
    
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        // Update window title with scale ratio
        guard let doc = self.document as? Document else { return displayName }
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
        guard let vc = self.contentViewController as? ViewController else { return }
        vc.showController(false)
    }
    
    public func windowWillExitFullScreen(_ notification: Notification) {
        // Reveal controllerBox
        guard let vc = self.contentViewController as? ViewController else { return }
        vc.showController(true)
    }
    
    public func windowDidEnterFullScreen(_ notification: Notification) {
        // Reset keyView/makeFirstResponder on Fullscreen mode
        guard let window = self.window else { return }
        window.selectNextKeyView(self)
    }
    
    public func windowDidExitFullScreen(_ notification: Notification) {
        // Reset keyView/makeFirstResponder on Non-Fullscreen mode
        guard let window = self.window else { return }
        window.selectNextKeyView(self)
    }
    
    @IBAction public func dumpResponderChain(_ sender: Any) {
        #if DEBUG
        guard let window = self.window else { return }
        var responder = window.firstResponder
        LoggingSystem.ui.debug("=== Responder Chain ===")
        while let r = responder {
            LoggingSystem.ui.debug("  \(String(describing: r))")
            responder = r.nextResponder
        }
        let vc = self.contentViewController as? ViewController
        LoggingSystem.ui.debug("vc.delegate: \(String(describing: vc?.delegate))")
        LoggingSystem.ui.debug("window.nextResponder: \(String(describing: window.nextResponder))")
        LoggingSystem.ui.debug("windowController.nextResponder: \(String(describing: self.nextResponder))")
        #endif
    }
}
