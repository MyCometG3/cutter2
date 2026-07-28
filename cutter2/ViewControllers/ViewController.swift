//
//  ViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

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
    internal var stepModeObservation: NSKeyValueObservation? = nil
    
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
            LoggingSystem.ui.error("Failed to set timeline view as first responder")
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
}
