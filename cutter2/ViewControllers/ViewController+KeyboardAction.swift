//
//  ViewController+KeyboardAction.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Keyboard Action handling
/* ============================================ */

extension ViewController {
    
    override func deleteBackward(_ sender: Any?) {
        guard let document = delegate else { return }
        do {
            try document.doDelete()
        } catch {
            NSSound.beep()
        }
    }
    
    override func selectAll(_ sender: Any?) {
        guard let document = delegate else { return }
        document.selectAll()
    }
    
    override func insertNewline(_ sender: Any?) {
        // enter
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return }
        document.doTogglePlay()
    }
    
    override func insertTab(_ sender: Any?) {
        // tab
        // Swift.print(#function, #line, #file)
        guard let window = timelineView.window else { return }
        window.selectNextKeyView(self)
    }
    
    override func insertBacktab(_ sender: Any?) {
        // Shift + tab
        // Swift.print(#function, #line, #file)
        guard let window = timelineView.window else { return }
        window.selectPreviousKeyView(self)
    }
    
    override func moveUp(_ sender: Any?) {
        // up arrow
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return }
        let offset: Int = modifier(.option) ? 100 : 10
        document.doVolumeOffset(offset)
    }
    
    override func moveDown(_ sender: Any?) {
        // down arrow
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return }
        let offset: Int = modifier(.option) ? -100 : -10
        document.doVolumeOffset(offset)
    }
    
    override func moveLeft(_ sender: Any?) {
        // left arrow
        // Swift.print(#function, #line, #file)
        doMoveLeft(modifier(.option), modifier(.shift))
    }
    
    override func moveRight(_ sender: Any?) {
        // right arrow
        // Swift.print(#function, #line, #file)
        doMoveRight(modifier(.option), modifier(.shift))
    }
    
    override func moveWordLeft(_ sender: Any?) {
        // Option + left
        // Swift.print(#function, #line, #file)
        doMoveLeft(modifier(.option), modifier(.shift))
    }
    
    override func moveWordRight(_ sender: Any?) {
        // Option + right
        // Swift.print(#function, #line, #file)
        doMoveRight(modifier(.option), modifier(.shift))
    }
    
    override func moveLeftAndModifySelection(_ sender: Any?) {
        // Shift + left
        // Swift.print(#function, #line, #file)
        doMoveLeft(modifier(.option), modifier(.shift))
    }
    
    override func moveRightAndModifySelection(_ sender: Any?) {
        // Shift + right
        // Swift.print(#function, #line, #file)
        doMoveRight(modifier(.option), modifier(.shift))
    }
    
    override func moveWordLeftAndModifySelection(_ sender: Any?) {
        // Shift + Option + left
        // Swift.print(#function, #line, #file)
        let option: Bool = ignoreOptionWhenShift ? false : true
        let shift: Bool = true
        doMoveLeft(option, shift)
    }
    
    override func moveWordRightAndModifySelection(_ sender: Any?) {
        // Shift + Option + right
        // Swift.print(#function, #line, #file)
        let option: Bool = ignoreOptionWhenShift ? false : true
        let shift: Bool = true
        doMoveRight(option, shift)
    }
    
    override func moveToLeftEndOfLine(_ sender: Any?) {
        // Command + left
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return }
        document.doSetRate(-1)
    }
    
    override func moveToRightEndOfLine(_ sender: Any?) {
        // Command + right
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return }
        document.doSetRate(+1)
    }
    
    override func insertText(_ insertString: Any) {
        // Any character input
        // Swift.print(#function, #line, #file)
        
        guard let document = delegate else { return }
        document.debugInfo()
    }
}
