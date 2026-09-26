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
    
    /// The short keyboard-step offset in seconds.
    public var offsetS: Float64 = 1.0
    /// The medium keyboard-step offset in seconds.
    public var offsetM: Float64 = 5.0
    /// The long keyboard-step offset in seconds.
    public var offsetL: Float64 = 15.0
    
    /// Whether to mimic the legacy QuickTime Player Pro JKL key combination behavior.
    @objc public var mimicJKLcombination: Bool = true
    
    /// Whether Shift+Option movement should ignore the Option modifier's boundary behavior.
    public var ignoreOptionWhenShift: Bool = false
    
    /// Whether moving a selection marker also moves the current marker.
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
    
    /// Connects the timeline and installs the view controller's notification observers.
    public func setup() {
        self.timelineView.delegate = self
        
        //
        addUpdateReqObserver()
        //
        addWindowResizeObserver()
        //
        addUserDefaultObserver()
    }
    
    /// Removes notification observers installed by `setup()`.
    public func cleanup() {
        //
        removeUpdateReqObserver()
        //
        removeWindowResizeObserver()
        //
        removeUserDefaultsObserver()
    }
    
    /// Updates timeline markers and the time label, requesting layout only when state changes.
    ///
    /// - Parameters:
    ///   - curPosition: The current marker position from 0.0 to 1.0.
    ///   - startPosition: The selection start position from 0.0 to 1.0.
    ///   - endPosition: The selection end position from 0.0 to 1.0.
    ///   - string: The time label text.
    ///   - valid: Whether the supplied timeline state is valid.
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
    
    /// Shows or hides the controller box.
    ///
    /// - Parameter flag: `true` to show the controller box; `false` to hide it.
    public func showController(_ flag: Bool) {
        controllerBox.isHidden = !flag
    }
}
