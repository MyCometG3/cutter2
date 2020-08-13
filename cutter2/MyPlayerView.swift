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
    
    // NSResponder
    override var acceptsFirstResponder: Bool {
        return false
    }
    
    // NSResponder
    override func becomeFirstResponder() -> Bool {
        return false
    }
    
    // NSView(NSKeyboardUI)
    override var canBecomeKeyView: Bool {
        return false
    }
}
