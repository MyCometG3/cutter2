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
        return try ActorUtilities.performSyncOnMainActor(block)
    }
    
    /// Runs a non-throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A non-throwing closure isolated to the main actor.
    /// - Returns: The result of the closure's operation.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () -> T) -> T {
        return ActorUtilities.performSyncOnMainActor(block)
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
    internal let keyPathStepMode: String = "useStepMode" // "values.useStepMode" is NG
    
    // To mimic legacy QT7PlayerPro JKL key tracking
    internal var keyDownJ: Bool = false
    internal var keyDownK: Bool = false
    internal var keyDownL: Bool = false
    internal var acceptAuto: Bool = false
    
    // Notification Observer
    internal var resizeObserver: NSObjectProtocol? = nil
    internal var updateObserver: NSObjectProtocol? = nil
    
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
