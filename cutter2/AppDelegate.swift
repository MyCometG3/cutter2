//
//  AppDelegate.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    /// Select next document
    ///
    /// - Parameter sender: Any
    @IBAction func nextDocument(_ sender: Any) {
        let docList : [Document]? = NSApp.orderedDocuments as? [Document]
        if let docList = docList, docList.count > 1 {
            if let doc = docList.last, let window = doc.window {
                window.makeKeyAndOrderFront(self)
            }
        }
    }
}

