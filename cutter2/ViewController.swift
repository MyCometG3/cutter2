//
//  ViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2019年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

extension Notification.Name {
    static let timelineUpdateReq = Notification.Name("timelineUpdateReq")
}

protocol ViewControllerDelegate : TimelineUpdateDelegate {
    func hasSelection() -> Bool
    func hasDuration() -> Bool
    func hasClipOnPBoard() -> Bool
    //
    func debugInfo()
    func timeOfPosition(_ percentage : Float64) -> CMTime
    func positionOfTime(_ time : CMTime) -> Float64
    //
    func doCut() throws
    func doCopy() throws
    func doPaste() throws
    func doDelete() throws
    func selectAll()
    //
    func doStepByCount(_ count : Int64, _ resetStart : Bool, _ resetEnd : Bool)
    func doStepBySecond(_ offset : Float64, _ resetStart : Bool, _ resetEnd : Bool)
    func doVolumeOffset(_ percent : Int)
    //
    func doMoveLeft(_ optFlag : Bool, _ shiftFlag : Bool, _ resetStart : Bool, _ resetEnd : Bool)
    func doMoveRight(_ optFlag : Bool, _ shiftFlag : Bool, _ resetStart : Bool, _ resetEnd : Bool)
    //
    func doSetSlow(_ ratio : Float)
    func doSetRate(_ offset : Int)
    func doTogglePlay()
}

class ViewController: NSViewController, TimelineUpdateDelegate {
    /* ============================================ */
    // MARK: - public var/func for ViewController
    /* ============================================ */
    
    // Step Mode : step offset resolution in sec
    public var offsetS : Float64 = 1.0
    public var offsetM : Float64 = 5.0
    public var offsetL : Float64 = 15.0
    
    // To mimic legacy QT7PlayerPro left/right combination set this true
    public var ignoreOptionWhenShift : Bool = false
    
    // To mimic legacy QT7PlayerPro JKL combinationset this true
    @objc public var mimicJKLcombination : Bool = true
    
    // To mimic legacy QT7PlayerPro selectionMarker move sync w/ current
    public var followSelectionMove : Bool = true
    
    //
    public var keyDownJ : Bool = false
    public var keyDownK : Bool = false
    public var keyDownL : Bool = false
    public var acceptAuto : Bool = false
    
    /// delegate to Document (NSDocument subclass)
    public weak var delegate : ViewControllerDelegate? = nil
    
    /// MyPlayerView as AVPlayerView subclass
    @IBOutlet weak var playerView: MyPlayerView!
    @IBOutlet weak var timelineView : TimelineView!
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
            self.timelineView.needsLayout = true
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        applyMode()
    }
    
    public func setup() {
        self.timelineView.delegate = self
        
        //
        addUpdateReqObserver()
        //
        addWindowResizeObserver()
        //
        addUserDefaultObserver()
    }
    
    public func cleanup() {
        //
        removeUpdateReqObserver()
        //
        removeWindowResieObserver()
        //
        removeUserDefaultsObserver()
    }
    
    public func updateTimeline(current curPosition : Float64,
                               from startPosition : Float64,
                               to endPosition : Float64,
                               label string : String,
                               isValid valid : Bool) {
        //
        let result = self.timelineView.updateTimeline(current: curPosition,
                                                      from: startPosition,
                                                      to: endPosition,
                                                      isValid: valid)
        if result {
            self.timelineView.updateTimeLabel(to: string)
            self.timelineView.needsLayout = true
        }
    }
    
    @IBOutlet weak var controllerBox: NSBox!
    
    public func showController(_ flag : Bool) {
        controllerBox.isHidden = !flag
    }
    
    /* ============================================ */
    // MARK: - Observer utilities
    /* ============================================ */
    
    private let keyPathStepMode : String = "useStepMode" // "values.useStepMode" is NG
    
    private func addUserDefaultObserver() {
        let defaults = UserDefaults.standard
        defaults.addObserver(self,
                             forKeyPath: keyPathStepMode,
                             options: [.initial, .old,.new],
                             context: nil)
    }
    
    private func removeUserDefaultsObserver() {
        let defaults = UserDefaults.standard
        defaults.removeObserver(self,
                                forKeyPath: keyPathStepMode)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else { return }
        guard let change : [NSKeyValueChangeKey : Any] = change else { return }
        guard let newAny = change[.newKey] else { return }
        
        if keyPath == keyPathStepMode, let newNumber = newAny as? NSNumber {
            let new : Bool = !newNumber.boolValue
            if mimicJKLcombination != new {
                mimicJKLcombination = new
                
                applyMode()
            }
        }
    }
    
    private func addWindowResizeObserver() {
        guard let window = view.window else { return }
        let center = NotificationCenter.default
        let handler : (Notification) -> Void = {[unowned self] (notification) in // @escaping
            let object = notification.object as AnyObject
            if object !== window {
                return
            }
            
            // After Live resize we needs tracking area update
            self.timelineView.needsUpdateTrackingArea = true
            self.timelineView.needsLayout = true
        }
        center.addObserver(forName: NSWindow.didEndLiveResizeNotification,
                           object: window,
                           queue: OperationQueue.main,
                           using: handler)
    }
    
    private func removeWindowResieObserver() {
        guard let window = view.window else { return }
        let center = NotificationCenter.default
        center.removeObserver(self,
                              name: NSWindow.didEndLiveResizeNotification,
                              object: window)
    }
    
    private func addUpdateReqObserver() {
        let center = NotificationCenter.default
        let handler : (Notification) -> Void = {[unowned self] (notification) in // @escaping
            let object = notification.object as AnyObject
            if object !== self.delegate {
                return
            }
            
            if let userInfo = notification.userInfo {
                let curPosition = Float64((userInfo[curPositionInfoKey] as! NSNumber).doubleValue)
                let startPosition = Float64((userInfo[startPositionInfoKey] as! NSNumber).doubleValue)
                let endPosition = Float64((userInfo[endPositionInfoKey] as! NSNumber).doubleValue)
                let string = (userInfo[stringInfoKey] as! String)
                let valid = (userInfo[durationInfoKey] as! NSNumber).doubleValue > 0.0
                self.updateTimeline(current: curPosition,
                                    from: startPosition,
                                    to: endPosition,
                                    label: string,
                                    isValid: valid)
            }
        }
        center.addObserver(forName: .timelineUpdateReq,
                           object: delegate,
                           queue: OperationQueue.main,
                           using: handler)
    }
    
    private func removeUpdateReqObserver() {
        let center = NotificationCenter.default
        center.removeObserver(self,
                              name: .timelineUpdateReq,
                              object: delegate)
    }
    
    private func applyMode() {
        self.timelineView.jklMode = mimicJKLcombination
        self.timelineView.needsLayout = true
    }
    
    /* ============================================ */
    // MARK: - Validate menu
    /* ============================================ */
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let document = delegate else { return false }
        if menuItem.action == #selector(ViewController.cut(_:)) {
            return document.hasSelection()
        }
        if menuItem.action == #selector(ViewController.copy(_:)) {
            return document.hasSelection()
        }
        if menuItem.action == #selector(ViewController.paste(_:)) {
            return document.hasClipOnPBoard()
        }
        if menuItem.action == #selector(ViewController.delete(_:)) {
            return document.hasSelection()
        }
        if menuItem.action == #selector(ViewController.selectAll(_:)) {
            return document.hasDuration()
        }
        return false
    }
    
    /* ============================================ */
    // MARK: - Key Event utilities
    /* ============================================ */
    
    private func doMoveLeft(_ optFlag : Bool, _ shiftFlag : Bool) {
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
    private func doMoveRight(_ optFlag : Bool, _ shiftFlag : Bool) {
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
    
    private func modifier(_ mask : NSEvent.ModifierFlags) -> Bool {
        guard let current = NSApp.currentEvent?.modifierFlags else { return false }
        
        return current.contains(mask)
    }
    
    private func keyMimic(with event: NSEvent) -> Bool {
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return false }
        
        let code : UInt = UInt(event.keyCode)
        let option : Bool = event.modifierFlags.contains(.option)
        let shift : Bool = event.modifierFlags.contains(.shift)
        let autoKey : Bool = event.isARepeat
        
        switch code {
        case 0x26: // J key
            keyDownJ = true
            if keyDownJ && keyDownL {
                if !autoKey {
                    // Swift.print("#####", "L=>J : pause")
                    document.doSetRate(0)
                }
                return true
            }
            if keyDownJ && !keyDownK {
                if !autoKey {
                    // Swift.print("#####", "J : backward play / accelarate")
                    document.doSetRate(-1)
                }
            }
            if keyDownJ && keyDownK {
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
        case 0x28 : // K key
            keyDownK = true
            if keyDownJ && keyDownL {
                if !autoKey {
                    // Swift.print("#####", "J/L=>K : pause")
                    document.doSetRate(0)
                }
            }
            if keyDownJ {
                if !autoKey {
                    // Swift.print("#####", "J=>K : pause")
                    document.doSetRate(0)
                    acceptAuto = true
                } else {
                    if acceptAuto {
                        // Swift.print("#####", "K=>J+ : backward play / slowmotion")
                        document.doSetSlow(-0.5)
                        acceptAuto = false
                    }
                }
            } else if keyDownL {
                if !autoKey {
                    // Swift.print("#####", "L=>K : pause")
                    document.doSetRate(0)
                    acceptAuto = true
                } else {
                    if acceptAuto {
                        // Swift.print("#####", "K=>L+ : forward play / slowmotion")
                        document.doSetSlow(+0.5)
                        acceptAuto = false
                    }
                }
            } else {
                if !autoKey {
                    // Swift.print("#####", "K : pause")
                    document.doSetRate(0)
                }
            }
            return true
        case 0x25 : // L key
            keyDownL = true
            if keyDownJ && keyDownL {
                if !autoKey {
                    // Swift.print("#####", "J=>L : pause")
                    document.doSetRate(0)
                }
                return true
            }
            if !keyDownK && keyDownL {
                if !autoKey {
                    // Swift.print("#####", "L : forward play / accelarate")
                    document.doSetRate(+1)
                }
            }
            if keyDownK && keyDownL {
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
        case 0x22 : // I key
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
        case 0x1f : // O key
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
        case 0x31 : // space bar
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
        
        let code : UInt = UInt(event.keyCode)
        
        switch code {
        case 0x26: // J key
            keyDownJ = false
            if keyDownK {
                // Swift.print("#####", "-J=>K : pause")
                document.doSetRate(0)
            }
            return true
        case 0x28 : // K key
            keyDownK = false
            if keyDownJ {
                // Swift.print("#####", "-K=>J : backward play")
                document.doSetRate(-1)
            } else if keyDownL {
                // Swift.print("#####", "-K=>L : forward play")
                document.doSetRate(+1)
            }
            return true
        case 0x25 : // L key
            keyDownL = false
            if keyDownK {
                // Swift.print("#####", "-L=>K : pause")
                document.doSetRate(0)
            }
            return true
        default:
            break
        }
        return false
    }
    
    private func keyStep(with event: NSEvent) -> Bool {
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return false }
        
        let code : UInt = UInt(event.keyCode)
        let option : Bool = event.modifierFlags.contains(.option)
        let shift : Bool = event.modifierFlags.contains(.shift)
        
        switch code {
        case 0x26 : // J key
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
        case 0x28 : // K key
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
        case 0x25 : // L key
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
        case 0x29 : // ; key (depends on keymapping)
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
        case 0x22 : // I key
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
        case 0x1f : // O key
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
        case 0x31 : // space bar
            // Swift.print("#####", "space : toggle play/pause")
            document.doTogglePlay()
            return true
        default:
            break
        }
        return false
    }
    
    override func keyDown(with event: NSEvent) {
        // Swift.print(#function, #line, #file)
        
        let code : UInt = UInt(event.keyCode)
        let mod : UInt = event.modifierFlags.rawValue
        let noMod = (mod & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue) == 0
        
        #if false
        Swift.print("#####", "code:", code,
                    "/ mod:", mod,
                    "/ noMod:", (noMod ? "true" : "false"))
        #endif
        #if false
        let char = event.charactersIgnoringModifiers
        let option : Bool = event.modifierFlags.contains(.option)
        let shift : Bool = event.modifierFlags.contains(.shift)
        let control : Bool = event.modifierFlags.contains(.control)
        let command : Bool = event.modifierFlags.contains(.command)
        let string : String = String(format:"%qu(%@) %@ %@ %@ %@",
                                     code,
                                     char ?? "_",
                                     option ? "opt" : "---",
                                     shift ? "shi" : "---",
                                     control ? "ctr" : "---",
                                     command ? "cmd" : "---")
        Swift.print("#####", "keyDown =", string)
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
        
        // use interpretKeyEvents: for other key events
        self.interpretKeyEvents([event])
    }
    
    override func keyUp(with event: NSEvent) {
        if mimicJKLcombination {
            if keyMimicUp(with: event) {
                return
            }
        }
        return
    }
    
    /* ============================================ */
    // MARK: - cut/copy/paste/delete IBAction
    /* ============================================ */
    
    @IBAction func cut(_ sender : Any) {
        guard let document = delegate else { return }
        do {
            try document.doCut()
        } catch {
            NSSound.beep()
        }
    }
    @IBAction func copy(_ sender : Any) {
        guard let document = delegate else { return }
        do {
            try document.doCopy()
        } catch {
            NSSound.beep()
        }
    }
    @IBAction func paste(_ sender : Any) {
        guard let document = delegate else { return }
        do {
            try document.doPaste()
        } catch {
            NSSound.beep()
        }
    }
    
    @IBAction func delete(_ sender: Any?) {
        deleteBackward(sender)
    }
    
    /* ============================================ */
    // MARK: - Keybaord Action handling
    /* ============================================ */
    
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
        let offset : Int = modifier(.option) ? 100 : 10
        document.doVolumeOffset(offset)
    }
    
    override func moveDown(_ sender: Any?) {
        // down arrow
        // Swift.print(#function, #line, #file)
        guard let document = delegate else { return }
        let offset : Int = modifier(.option) ? -100 : -10
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
        let option : Bool = ignoreOptionWhenShift ? false : true
        let shift : Bool = true
        doMoveLeft(option, shift)
    }
    
    override func moveWordRightAndModifySelection(_ sender: Any?) {
        // Shift + Option + right
        // Swift.print(#function, #line, #file)
        let option : Bool = ignoreOptionWhenShift ? false : true
        let shift : Bool = true
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
        // Swift.print(#function, #line, #file)
        // Swift.print("#####", "insertText: ", insertString as! String)
        //NSSound.beep()
        
        guard let document = delegate else { return }
        document.debugInfo()
    }
    
    /* ============================================ */
    // MARK: - TimelineUpdateDelegate
    /* ============================================ */
    
    public func didUpdateCursor(to position : Float64) {
        guard let document = delegate else { return }
        document.didUpdateCursor(to: position)
    }
    
    public func didUpdateStart(to position : Float64) {
        guard let document = delegate else { return }
        if followSelectionMove {
            document.didUpdateCursor(to: position)
            document.didUpdateStart(to: position)
        } else {
            document.didUpdateStart(to: position)
        }
    }
    
    public func didUpdateEnd(to position : Float64) {
        guard let document = delegate else { return }
        if followSelectionMove {
            document.didUpdateCursor(to: position)
            document.didUpdateEnd(to: position)
        } else {
            document.didUpdateEnd(to: position)
        }
    }
    
    public func didUpdateSelection(from fromPos : Float64, to toPos : Float64) {
        guard let document = delegate else { return }
        if fromPos == toPos && followSelectionMove {
            document.didUpdateCursor(to: fromPos)
            document.didUpdateSelection(from: fromPos, to: toPos)
        } else {
            document.didUpdateSelection(from: fromPos, to: toPos)
        }
    }
    
    public func presentationInfo(at position: Float64) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.presentationInfo(at: position)
    }
    
    public func previousInfo(of range: CMTimeRange) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.previousInfo(of: range)
    }
    
    public func nextInfo(of range: CMTimeRange) -> PresentationInfo? {
        guard let document = delegate else { return nil }
        return document.nextInfo(of: range)
    }
    
    public func doSetCurrent(to goTo : anchor) {
        guard let document = delegate else { return }
        document.doSetCurrent(to: goTo)
    }
    
    public func doSetStart(to goTo : anchor) {
        guard let document = delegate else { return }
        document.doSetStart(to: goTo)
    }
    
    public func doSetEnd(to goTo : anchor) {
        guard let document = delegate else { return }
        document.doSetEnd(to: goTo)
    }
    
}
