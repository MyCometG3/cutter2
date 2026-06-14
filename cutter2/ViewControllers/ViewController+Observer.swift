//
//  ViewController+Observer.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Observer utilities
/* ============================================ */

extension ViewController {
    
    /* ============================================ */
    // MARK: UserDefaults Observer
    /* ============================================ */
    
    internal func addUserDefaultObserver() {
        let defaults = UserDefaults.standard
        defaults.addObserver(self,
                             forKeyPath: keyPathStepMode,
                             options: [.initial, .old,.new],
                             context: nil)
    }
    
    internal func removeUserDefaultsObserver() {
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
    
    /* ============================================ */
    // MARK: Window Resize Observer
    /* ============================================ */
    
    internal func addWindowResizeObserver() {
        let handler: @Sendable (Notification) -> Void = {[weak self] (notification) in // @escaping
            
            guard let self else { return }
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
    
    internal func removeWindowResizeObserver() {
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
    
    /* ============================================ */
    // MARK: Update Request Observer
    /* ============================================ */
    
    internal func addUpdateReqObserver() {
        let handler: @Sendable (Notification) -> Void = { [weak self] (notification) in // @escaping
            
            guard let self else { return }
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
    
    internal func removeUpdateReqObserver() {
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
    
    /* ============================================ */
    // MARK: Mode Application
    /* ============================================ */
    
    internal func applyMode() {
        self.timelineView.jklMode = mimicJKLcombination
        self.timelineView.needsLayout = true
    }
}
