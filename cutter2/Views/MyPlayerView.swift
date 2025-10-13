//
//  MyPlayerView.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVKit

@MainActor
class MyPlayerView: AVPlayerView {
    
    /* ============================================ */
    // MARK: - Keyboard Event handling
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
