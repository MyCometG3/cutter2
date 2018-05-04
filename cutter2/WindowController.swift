//
//  WindowController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/02/17.
//  Copyright © 2018年 MyCometG3. All rights reserved.
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
}
