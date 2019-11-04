//
//  WindowController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/02/17.
//  Copyright © 2018-2019年 MyCometG3. All rights reserved.
//

import Cocoa

class WindowController: NSWindowController, NSWindowDelegate {
    override func windowDidLoad() {
        super.windowDidLoad()
        
        self.shouldCascadeWindows = true
    }
    
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        let doc = self.document as! Document
        let ratio = doc.displayRatio(nil) * 100
        let titleStr = String(format: "%@ (%.0f%%)", displayName, ratio)
        return titleStr
    }
    
    // NSWindowDelegate
    func windowDidResize(_ notification: Notification) {
        synchronizeWindowTitleWithDocumentName()
    }
    
    func windowWillEnterFullScreen(_ notification: Notification) {
        let vc = self.contentViewController as! ViewController
        vc.showController(false)
    }
    
    func windowWillExitFullScreen(_ notification: Notification) {
        let vc = self.contentViewController as! ViewController
        vc.showController(true)
    }
    
    func windowDidEnterFullScreen(_ notification: Notification) {
        self.window!.selectNextKeyView(self)
    }
    
    func windowDidExitFullScreen(_ notification: Notification) {
        self.window!.selectNextKeyView(self)
    }
}
