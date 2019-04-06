//
//  MyPlayerView.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2019年 MyCometG3. All rights reserved.
//

import Cocoa
import AVKit

class MyPlayerView: AVPlayerView {

    /* ============================================ */
    // MARK: - Keybaord Event handling
    /* ============================================ */
    
    override var acceptsFirstResponder: Bool {
        return false
    }
    
    override func becomeFirstResponder() -> Bool {
        return false
    }
    
    override var canBecomeKeyView: Bool {
        return false
    }
    
    override func keyDown(with event: NSEvent) {
        self.interpretKeyEvents([event])
    }
    
    override func insertTab(_ sender: Any?) {
        if let window = self.window, window.firstResponder == self {
            window.selectNextKeyView(self)
        }
    }
    
    override func insertBacktab(_ sender: Any?) {
        if let window = self.window, window.firstResponder == self {
            window.selectPreviousKeyView(self)
        }
    }
    
    override func insertText(_ insertString: Any) {
        super.insertText(insertString)
    }
}
