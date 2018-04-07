//
//  WindowController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/02/17.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa

class WindowController: NSWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()
        
        self.shouldCascadeWindows = true
    }
}
