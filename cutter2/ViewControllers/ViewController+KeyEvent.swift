//
//  ViewController+KeyEvent.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Key Event utilities
/* ============================================ */

extension ViewController {
    
    /* ============================================ */
    // MARK: Helper methods
    /* ============================================ */
    
    internal func doMoveLeft(_ optFlag: Bool, _ shiftFlag: Bool) {
        guard let document = delegate else { return }
        
        switch timelineView.marker() {
        case .start:
            document.doMoveLeft(optFlag, shiftFlag, true, false)
        case .end:
            document.doMoveLeft(optFlag, shiftFlag, false, true)
        default:
            document.doMoveLeft(optFlag, shiftFlag, false, false)
        }
    }
    
    internal func doMoveRight(_ optFlag: Bool, _ shiftFlag: Bool) {
        guard let document = delegate else { return }
        
        switch timelineView.marker() {
        case .start:
            document.doMoveRight(optFlag, shiftFlag, true, false)
        case .end:
            document.doMoveRight(optFlag, shiftFlag, false, true)
        default:
            document.doMoveRight(optFlag, shiftFlag, false, false)
        }
    }
    
    internal func modifier(_ mask: NSEvent.ModifierFlags) -> Bool {
        guard let current = NSApp.currentEvent?.modifierFlags else { return false }
        
        return current.contains(mask)
    }
    
    /* ============================================ */
    // MARK: JKL Mode Key Handling
    /* ============================================ */
    
    private func keyMimic(with event: NSEvent) -> Bool {
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return false }
        
        let code: UInt = UInt(event.keyCode)
        let option: Bool = event.modifierFlags.contains(.option)
        let shift: Bool = event.modifierFlags.contains(.shift)
        let autoKey: Bool = event.isARepeat
        
        switch code {
        case 0x26: // J key
            keyDownJ = true
            if  keyDownJ              &&  keyDownL { // J_L, JKL
                if !autoKey {
                    // Swift.print("#####", "L=>J : pause")
                    document.doSetRate(0)
                }
            }
            if  keyDownJ && !keyDownK && !keyDownL { // J__
                if !autoKey {
                    // Swift.print("#####", "J : backward play / accelarate")
                    document.doSetRate(-1)
                }
            }
            if  keyDownJ &&  keyDownK && !keyDownL { // JK_
                if option && shift {
                    document.doStepBySecond(-offsetM, false, false)
                } else if shift {
                    document.doStepBySecond(-offsetL, false, false)
                } else if option {
                    document.doStepBySecond(-offsetS, false, false)
                } else {
                    if !autoKey {
                        // Swift.print("#####", "K=>J : step backward")
                        document.doStepByCount(-1, false, false)
                        acceptAuto = true
                    }
                    if autoKey && acceptAuto {
                        // Swift.print("#####", "K=>J+ : backward play / slowmotion")
                        document.doSetSlow(-0.5)
                        acceptAuto = false
                    }
                }
            }
            return true
        case 0x28: // K key
            keyDownK = true
            if  keyDownJ &&  keyDownK &&  keyDownL { // JKL
                if !autoKey {
                    // Swift.print("#####", "J/L=>K : pause")
                    document.doSetRate(0)
                }
            }
            if  keyDownJ &&  keyDownK && !keyDownL { // JK_
                if option && shift {
                    document.doStepBySecond(-offsetM, false, false)
                } else if shift {
                    document.doStepBySecond(-offsetL, false, false)
                } else if option {
                    document.doStepBySecond(-offsetS, false, false)
                } else {
                    if !autoKey {
                        // Swift.print("#####", "J=>K+ : backward play / slowmotion")
                        document.doSetSlow(-0.5)
                    }
                }
            }
            if !keyDownJ &&  keyDownK &&  keyDownL { // _KL
                if option && shift {
                    document.doStepBySecond(+offsetM, false, false)
                } else if shift {
                    document.doStepBySecond(+offsetL, false, false)
                } else if option {
                    document.doStepBySecond(+offsetS, false, false)
                } else {
                    if !autoKey {
                        // Swift.print("#####", "L=>K+ : forward play / slowmotion")
                        document.doSetSlow(+0.5)
                    }
                }
            }
            if !keyDownJ &&  keyDownK && !keyDownL { // _K_
                if !autoKey {
                    // Swift.print("#####", "K : pause")
                    document.doSetRate(0)
                }
            }
            return true
        case 0x25: // L key
            keyDownL = true
            if  keyDownJ              &&  keyDownL { // J_L, JKL
                if !autoKey {
                    // Swift.print("#####", "J=>L : pause")
                    document.doSetRate(0)
                }
            }
            if !keyDownJ && !keyDownK &&  keyDownL { // __L
                if !autoKey {
                    // Swift.print("#####", "L : forward play / accelarate")
                    document.doSetRate(+1)
                }
            }
            if !keyDownJ &&  keyDownK &&  keyDownL { // _KL
                if option && shift {
                    document.doStepBySecond(+offsetM, false, false)
                } else if shift {
                    document.doStepBySecond(+offsetL, false, false)
                } else if option {
                    document.doStepBySecond(+offsetS, false, false)
                } else {
                    if !autoKey {
                        // Swift.print("#####", "K=>L : step forward")
                        document.doStepByCount(+1, false, false)
                        acceptAuto = true
                    }
                    if autoKey && acceptAuto {
                        // Swift.print("#####", "K=>L+ : forward play / slowmotion")
                        document.doSetSlow(+0.5)
                        acceptAuto = false
                    }
                }
            }
            return true
        case 0x22: // I key
            // Swift.print("#####", "I : set selection start")
            if option && shift {
                break
            } else if shift {
                break
            } else if option {
                doSetStart(to: .headOrCurrent)
            } else {
                doSetStart(to: .current)
            }
            return true
        case 0x1f: // O key
            // Swift.print("#####", "O : set selection end")
            if option && shift {
                break
            } else if shift {
                break
            } else if option {
                doSetEnd(to: .tailOrCurrent)
            } else {
                doSetEnd(to: .current)
            }
            return true
        case 0x31: // space bar
            if !autoKey {
                // Swift.print("#####", "space : toggle play/pause")
                document.doTogglePlay()
            }
            return true
        default:
            break
        }
        return false
    }
    
    private func keyMimicUp(with event: NSEvent) -> Bool {
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return false }
        
        let code: UInt = UInt(event.keyCode)
        
        switch code {
        case 0x26: // J key
            keyDownJ = false
            acceptAuto = false
            if !keyDownJ &&  keyDownK &&  keyDownL { // _KL
                // Swift.print("#####", "-J=>K/L : forward play / slowmotion")
                document.doSetSlow(+0.5)
            }
            if !keyDownJ &&  keyDownK && !keyDownL { // _K_
                // Swift.print("#####", "-J=>K : pause")
                document.doSetRate(0)
            }
            if !keyDownJ && !keyDownK &&  keyDownL { // __L
                // Swift.print("#####", "-J=>L : forward play")
                document.doSetRate(+1)
            }
            return true
        case 0x28: // K key
            keyDownK = false
            acceptAuto = false
            if  keyDownJ && !keyDownK &&  keyDownL { // J_L
                // Swift.print("#####", "-K=>J/L : pause")
                document.doSetRate(0)
            }
            if  keyDownJ && !keyDownK && !keyDownL { // J__
                // Swift.print("#####", "-K=>J : backward play")
                document.doSetRate(-1)
            }
            if !keyDownJ && !keyDownK &&  keyDownL { // __L
                // Swift.print("#####", "-K=>L : forward play")
                document.doSetRate(+1)
            }
            return true
        case 0x25: // L key
            keyDownL = false
            acceptAuto = false
            if  keyDownJ &&  keyDownK && !keyDownL { // JK_
                // Swift.print("#####", "-L=>J/K : backward play / slowmotion")
                document.doSetSlow(-0.5)
            }
            if !keyDownJ &&  keyDownK && !keyDownL { // _K_
                // Swift.print("#####", "-L=>K : pause")
                document.doSetRate(0)
            }
            if  keyDownJ && !keyDownK && !keyDownL { // J__
                // Swift.print("#####", "-L=>J : backward play")
                document.doSetRate(-1)
            }
            return true
        default:
            break
        }
        return false
    }
    
    /* ============================================ */
    // MARK: Step Mode Key Handling
    /* ============================================ */
    
    private func keyStep(with event: NSEvent) -> Bool {
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return false }
        
        let code: UInt = UInt(event.keyCode)
        let option: Bool = event.modifierFlags.contains(.option)
        let shift: Bool = event.modifierFlags.contains(.shift)
        
        switch code {
        case 0x26: // J key
            // Swift.print("#####", "J : toggle marker-backward")
            if option && shift {
                break
            } else if shift {
                break
            } else if option {
                doSetCurrent(to: .startOrHead)
            } else {
                document.doStepBySecond(-offsetL, false, false)
            }
            return true
        case 0x28: // K key
            // Swift.print("#####", "K : step backward")
            if option && shift {
                break
            } else if shift {
                document.doStepBySecond(-offsetM, false, false)
            } else if option {
                document.doStepByCount(-1, false, false)
            } else {
                document.doStepBySecond(-offsetS, false, false)
            }
            return true
        case 0x25: // L key
            // Swift.print("#####", "L : step forward")
            if option && shift {
                break
            } else if shift {
                document.doStepBySecond(+offsetM, false, false)
            } else if option {
                document.doStepByCount(+1, false, false)
            } else {
                document.doStepBySecond(+offsetS, false, false)
            }
            return true
        case 0x29: // ; key (depends on keymapping)
            // Swift.print("#####", "; : toggle marker-forward")
            if option && shift {
                break
            } else if shift {
                break
            } else if option {
                doSetCurrent(to: .endOrTail)
            } else {
                document.doStepBySecond(+offsetL, false, false)
            }
            return true
        case 0x22: // I key
            // Swift.print("#####", "I : set selection start")
            if option && shift {
                break
            } else if shift {
                break
            } else if option {
                doSetStart(to: .headOrCurrent)
            } else {
                doSetStart(to: .current)
            }
            return true
        case 0x1f: // O key
            // Swift.print("#####", "O : set selection end")
            if option && shift {
                break
            } else if shift {
                break
            } else if option {
                doSetEnd(to: .tailOrCurrent)
            } else {
                doSetEnd(to: .current)
            }
            return true
        case 0x31: // space bar
            // Swift.print("#####", "space : toggle play/pause")
            document.doTogglePlay()
            return true
        default:
            break
        }
        return false
    }
    
    /* ============================================ */
    // MARK: Key Event Overrides
    /* ============================================ */
    
    override func keyDown(with event: NSEvent) {
        // Swift.print(#function, #line, #file)
        
        #if false
        keyDump(with: event)
        #endif
        
        if mimicJKLcombination {
            if keyMimic(with: event) {
                return
            }
        } else {
            if keyStep(with: event) {
                return
            }
        }
        
        // use interpretKeyEvents(_:) for other key events
        self.interpretKeyEvents([event])
    }
    
    override func keyUp(with event: NSEvent) {
        // Swift.print(#function, #line, #file)
        
        if mimicJKLcombination {
            if keyMimicUp(with: event) {
                return
            }
        }
    }
    
    /* ============================================ */
    // MARK: Debug Utilities
    /* ============================================ */
    
    private func keyDump(with event: NSEvent) {
        // Swift.print(#function, #line, #file)
        
        let code: UInt = UInt(event.keyCode)
        let char = event.charactersIgnoringModifiers
        let option: Bool = event.modifierFlags.contains(.option)
        let shift: Bool = event.modifierFlags.contains(.shift)
        let control: Bool = event.modifierFlags.contains(.control)
        let command: Bool = event.modifierFlags.contains(.command)
        let mod: UInt = event.modifierFlags.rawValue
        let string: String = String(format:"%qu(%@) %@ %@ %@ %@ %8lx",
                                    code,
                                    char ?? "_",
                                    option ? "opt" : "---",
                                    shift ? "shi" : "---",
                                    control ? "ctr" : "---",
                                    command ? "cmd" : "---",
                                    mod)
        Swift.print("#####", "keyDown =", string)
    }
}
