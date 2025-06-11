//
//  ViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Actor isolation
/* ============================================ */

extension ViewController {
    
    /// Runs a throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A closure isolated to the main actor that may throw an error.
    /// - Returns: The result of the closure's operation.
    /// - Throws: Any error thrown by the closure.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try block()
            }
        } else {
            return try DispatchQueue.main.sync {
                return try MainActor.assumeIsolated {
                    try block()
                }
            }
        }
    }
    
    /// Runs a non-throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A non-throwing closure isolated to the main actor.
    /// - Returns: The result of the closure's operation.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                block()
            }
        } else {
            return DispatchQueue.main.sync {
                return MainActor.assumeIsolated {
                    block()
                }
            }
        }
    }
}

/* ============================================ */

extension Notification.Name {
    static let timelineUpdateReq = Notification.Name("timelineUpdateReq")
}

@MainActor
protocol ViewControllerDelegate: TimelineUpdateDelegate, Sendable {
    func hasSelection() -> Bool
    func hasDuration() -> Bool
    func hasClipOnPBoard() -> Bool
    //
    func debugInfo()
    func timeOfPosition(_ percentage: Float64) -> CMTime
    func positionOfTime(_ time: CMTime) -> Float64
    //
    func doCut() throws
    func doCopy() throws
    func doPaste() throws
    func doDelete() throws
    func selectAll()
    //
    func doStepByCount(_ count: Int64, _ resetStart: Bool, _ resetEnd: Bool)
    func doStepBySecond(_ offset: Float64, _ resetStart: Bool, _ resetEnd: Bool)
    func doVolumeOffset(_ percent: Int)
    //
    func doMoveLeft(_ optFlag: Bool, _ shiftFlag: Bool, _ resetStart: Bool, _ resetEnd: Bool)
    func doMoveRight(_ optFlag: Bool, _ shiftFlag: Bool, _ resetStart: Bool, _ resetEnd: Bool)
    //
    func doSetSlow(_ ratio: Float)
    func doSetRate(_ offset: Int)
    func doTogglePlay()
}

@MainActor
class ViewController: NSViewController, TimelineUpdateDelegate {
    
    /* ============================================ */
    // MARK: - private properties/constants
    /* ============================================ */
    
    // Observer key
    private let keyPathStepMode: String = "useStepMode" // "values.useStepMode" is NG
    
    // To mimic legacy QT7PlayerPro JKL key tracking
    private var keyDownJ: Bool = false
    private var keyDownK: Bool = false
    private var keyDownL: Bool = false
    private var acceptAuto: Bool = false
    
    // Notification Observer
    private var resizeObserver: NSObjectProtocol? = nil
    private var updateObserver: NSObjectProtocol? = nil
    
    /* ============================================ */
    // MARK: - public properties
    /* ============================================ */
    
    // Step offset resolution in sec
    public var offsetS: Float64 = 1.0
    public var offsetM: Float64 = 5.0
    public var offsetL: Float64 = 15.0
    
    // To mimic legacy QT7PlayerPro JKL combination
    @objc public var mimicJKLcombination: Bool = true
    
    // To mimic legacy QT7PlayerPro left/right combination
    public var ignoreOptionWhenShift: Bool = false
    
    // To mimic legacy QT7PlayerPro selectionMarker move sync w/ current
    public var followSelectionMove: Bool = true
    
    /// delegate to Document (NSDocument subclass)
    public weak var delegate: ViewControllerDelegate? = nil
    
    /// MyPlayerView as AVPlayerView subclass
    @IBOutlet weak var playerView: MyPlayerView!
    @IBOutlet weak var timelineView: TimelineView!
    @IBOutlet weak var controllerBox: NSBox!
    
    /* ============================================ */
    // MARK: - public var/func for ViewController
    /* ============================================ */
    
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
    
    override func viewWillAppear() {
        guard let window = self.view.window else { return }
        if window.makeFirstResponder(timelineView) != true {
            Swift.print("ERROR: Failed to update initial first responder.")
        }
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
        removeWindowResizeObserver()
        //
        removeUserDefaultsObserver()
    }
    
    public func updateTimeline(current curPosition: Float64,
                               from startPosition: Float64,
                               to endPosition: Float64,
                               label string: String,
                               isValid valid: Bool) {
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
    
    public func showController(_ flag: Bool) {
        controllerBox.isHidden = !flag
    }
    
    /* ============================================ */
    // MARK: - Observer utilities
    /* ============================================ */
    
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
    
    override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey:Any]?,
                                           context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else { return }
        guard let change: [NSKeyValueChangeKey:Any] = change else { return }
        guard let newAny = change[.newKey] else { return }
        
        if keyPath == keyPathStepMode, let newNumber = newAny as? NSNumber {
            let new: Bool = !newNumber.boolValue
            performSyncOnMainActor {
                if mimicJKLcombination != new {
                    mimicJKLcombination = new
                    
                    applyMode()
                }
            }
        }
    }
    
    private func addWindowResizeObserver() {
        let handler: @Sendable (Notification) -> Void = {[weak self] (notification) in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            guard
                let vcWindow = performSyncOnMainActor({ self.view.window }),
                let object = notification.object as? NSWindow,
                vcWindow == object
            else {
                return
            }
            
            // After Live resize we needs tracking area update
            performSyncOnMainActor{
                self.timelineView.needsUpdateTrackingArea = true
                self.timelineView.needsLayout = true
            }
        }
        do {
            guard let window = self.view.window else { return }
            let center = NotificationCenter.default
            var observer: NSObjectProtocol? = nil
            observer = center.addObserver(forName: NSWindow.didEndLiveResizeNotification,
                                          object: window,
                                          queue: OperationQueue.main,
                                          using: handler)
            self.resizeObserver = observer
        }
    }
    
    private func removeWindowResizeObserver() {
        do {
            guard let observer = self.resizeObserver else { return }
            guard let window = self.view.window else { return }
            let center = NotificationCenter.default
            center.removeObserver(observer,
                                  name: NSWindow.didEndLiveResizeNotification,
                                  object: window)
            self.resizeObserver = nil
        }
    }
    
    private func addUpdateReqObserver() {
        let handler: @Sendable (Notification) -> Void = { [weak self] (notification) in // @escaping
            // Swift.print(#function, #line, #file)
            
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            guard
                let delegate = performSyncOnMainActor({ self.delegate }),
                let object = notification.object as? ViewControllerDelegate,
                object === delegate // ViewControllerDelegate is not Equatable
            else { return }
            
            guard
                let userInfo = notification.userInfo,
                let curPosition = (userInfo[curPositionInfoKey] as? NSNumber)?.doubleValue,
                let startPosition = (userInfo[startPositionInfoKey] as? NSNumber)?.doubleValue,
                let endPosition = (userInfo[endPositionInfoKey] as? NSNumber)?.doubleValue,
                let string = userInfo[stringInfoKey] as? String,
                let duration = (userInfo[durationInfoKey] as? NSNumber)?.doubleValue
            else { return }
            let valid = duration > 0.0
            performSyncOnMainActor {
                updateTimeline(current: Float64(curPosition),
                               from: Float64(startPosition),
                               to: Float64(endPosition),
                               label: string,
                               isValid: valid)
            }
        }
        do {
            guard let delegate = self.delegate else { return }
            let center = NotificationCenter.default
            var observer: NSObjectProtocol? = nil
            observer = center.addObserver(forName: .timelineUpdateReq,
                                          object: delegate,
                                          queue: OperationQueue.main,
                                          using: handler)
            self.updateObserver = observer
        }
    }
    
    private func removeUpdateReqObserver() {
        do {
            guard let observer = self.updateObserver else { return }
            guard let delegate = self.delegate else { return }
            let center = NotificationCenter.default
            center.removeObserver(observer,
                                  name: .timelineUpdateReq,
                                  object: delegate)
            self.updateObserver = nil
        }
    }
    
    private func applyMode() {
        self.timelineView.jklMode = mimicJKLcombination
        self.timelineView.needsLayout = true
    }
    
    /* ============================================ */
    // MARK: - Validate menu
    /* ============================================ */
    
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
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
    
    private func doMoveLeft(_ optFlag: Bool, _ shiftFlag: Bool) {
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
    private func doMoveRight(_ optFlag: Bool, _ shiftFlag: Bool) {
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
    
    private func modifier(_ mask: NSEvent.ModifierFlags) -> Bool {
        guard let current = NSApp.currentEvent?.modifierFlags else { return false }
        
        return current.contains(mask)
    }
    
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
    
    /* ============================================ */
    // MARK: - cut/copy/paste/delete IBAction
    /* ============================================ */
    
    @IBAction func cut(_ sender: Any) {
        guard let document = delegate else { return }
        do {
            try document.doCut()
        } catch {
            NSSound.beep()
        }
    }
    @IBAction func copy(_ sender: Any) {
        guard let document = delegate else { return }
        do {
            try document.doCopy()
        } catch {
            NSSound.beep()
        }
    }
    @IBAction func paste(_ sender: Any) {
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
    
    /* ============================================ */
    // MARK: - TimelineUpdateDelegate
    /* ============================================ */
    
    public func didUpdateCursor(to position: Float64) {
        guard let document = delegate else { return }
        document.didUpdateCursor(to: position)
    }
    
    public func didUpdateStart(to position: Float64) {
        guard let document = delegate else { return }
        if followSelectionMove {
            document.didUpdateCursor(to: position)
            document.didUpdateStart(to: position)
        } else {
            document.didUpdateStart(to: position)
        }
    }
    
    public func didUpdateEnd(to position: Float64) {
        guard let document = delegate else { return }
        if followSelectionMove {
            document.didUpdateCursor(to: position)
            document.didUpdateEnd(to: position)
        } else {
            document.didUpdateEnd(to: position)
        }
    }
    
    public func didUpdateSelection(from fromPos: Float64, to toPos: Float64) {
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
    
    public func doSetCurrent(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetCurrent(to: goTo)
    }
    
    public func doSetStart(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetStart(to: goTo)
    }
    
    public func doSetEnd(to goTo: anchor) {
        guard let document = delegate else { return }
        document.doSetEnd(to: goTo)
    }
}
