//
//  Document+Observers.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - Observer
/* ============================================ */

extension Document {
    
    /// Add AVPlayer properties observer
    func addPlayerObserver() {
        
        guard let player = self.player else { return }
        
        player.addObserver(self,
                           forKeyPath: #keyPath(AVPlayer.status),
                           options: [.old, .new],
                           context: &(self.kvoContext))
        player.addObserver(self,
                           forKeyPath: #keyPath(AVPlayer.rate),
                           options: [.old, .new],
                           context: &(self.kvoContext))
    }
    
    /// Remove AVPlayer properties observer
    func removePlayerObserver() {
        
        guard let player = self.player else { return }
        
        player.removeObserver(self,
                              forKeyPath: #keyPath(AVPlayer.status),
                              context: &(self.kvoContext))
        player.removeObserver(self,
                              forKeyPath: #keyPath(AVPlayer.rate),
                              context: &(self.kvoContext))
    }
    
    /// compare KVO context address as UInt
    @MainActor func checkKVOContext(_ contextAddress: UInt) -> Bool {
        return withUnsafePointer(to: &self.kvoContext) { kvoPointer in
            let kvoAddress = UInt(bitPattern: kvoPointer)
            return (contextAddress == kvoAddress)
        }
    }
    
    // NSKeyValueObserving protocol - observeValue(forKeyPath:of:change:context:)
    override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey:Any]?,
                                           context: UnsafeMutableRawPointer?) {
        
        guard
            let context = context, let object = object as? AVPlayer, let keyPath = keyPath, let change = change
        else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
            return
        }
        
        let contextAddress = UInt(bitPattern: context) // Cast UnsafeMutableRawPointer to UInt for actor isolation
        let (objectIsPlayer, keyPathIsAVPlayerStatus, keyPathIsAVPlayerRate) = ActorUtilities.performSyncOnMainActor {
            let contextMatch: Bool = checkKVOContext(contextAddress)
            let objectIsPlayer: Bool = (object === self.player)
            let keyPathIsAVPlayerStatus: Bool = (keyPath == #keyPath(AVPlayer.status))
            let keyPathIsAVPlayerRate: Bool = (keyPath == #keyPath(AVPlayer.rate))
            return (contextMatch && objectIsPlayer, keyPathIsAVPlayerStatus, keyPathIsAVPlayerRate)
        }
        
        if objectIsPlayer && keyPathIsAVPlayerStatus {
            
            // Force redraw when AVPlayer.status is updated
            guard let newStatus = change[.newKey] as? NSNumber else { return }
            if newStatus.intValue == AVPlayer.Status.readyToPlay.rawValue {
                // Seek and refresh View
                ActorUtilities.performSyncOnMainActor {
                    guard let mutator = self.movieMutator else { return }
                    let time = mutator.insertionTime
                    let range = mutator.selectedTimeRange
                    updateGUI(time, range, false)
                }
            } else if newStatus.intValue == AVPlayer.Status.failed.rawValue {
                //
                LoggingSystem.ui.error("AVPlayerStatus.failed detected")
            }
            return
        } else if objectIsPlayer && keyPathIsAVPlayerRate {
            
            // Check special case: movie play reached at end of movie
            guard let oldRate = change[.oldKey] as? NSNumber else { return }
            guard let newRate = change[.newKey] as? NSNumber else { return }
            if oldRate.floatValue > 0.0 && newRate.floatValue == 0.0 {
                // Movie stopped
                ActorUtilities.performSyncOnMainActor {
                    guard let player = self.player else { return }
                    guard let mutator = self.movieMutator else { return }
                    
                    // Check if it is tail of movie
                    let current = player.currentTime()
                    let duration = mutator.movieDuration()
                    let selection = mutator.selectedTimeRange
                    if current == duration {
                        // Force-refresh GUI at the end of movie
                        updateTimeline(current, range: selection)
                    }
                }
                LoggingSystem.ui.debug("Movie playback stopped")
            }
            if oldRate.floatValue == 0.0 && newRate.floatValue > 0.0 {
                LoggingSystem.ui.debug("Movie playback started (forward)")
            }
            if oldRate.floatValue == 0.0 && newRate.floatValue < 0.0 {
                LoggingSystem.ui.debug("Movie playback started (backward)")
            }
            if oldRate.floatValue == newRate.floatValue {
                LoggingSystem.ui.notice("No rate change detected - needs investigation")
            }
            return
        } else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
        }
    }
    
    /// Register observer for movie mutation
    public func addMutationObserver() {
        
        let handler: @Sendable (Notification) -> Void = {[weak self] (notification) in // @escaping
            
            guard let self else { return }
            guard
                let mutator = ActorUtilities.performSyncOnMainActor({ self.movieMutator }),
                let object = notification.object as? MovieMutator,
                mutator == object
            else { return }
            
            #if DEBUG
            let displayName = ActorUtilities.performSyncOnMainActor({ self.displayName ?? "unknown" })
            LoggingSystem.document.debug("Received .movieWasMutated notification: \(displayName)")
            #endif
            
            // extract CMTime/CMTimeRange from userInfo
            guard
                let userInfo = notification.userInfo,
                let timeValue = userInfo[timeValueInfoKey] as? NSValue,
                let timeRangeValue = userInfo[timeRangeValueInfoKey] as? NSValue
            else { return }
            
            let time: CMTime = timeValue.timeValue
            let timeRange: CMTimeRange = timeRangeValue.timeRangeValue
            ActorUtilities.performSyncOnMainActor {
                updateGUI(time, timeRange, true)
            }
        }
        do {
            guard let mutator = self.movieMutator else { return }
            let center = NotificationCenter.default
            var observer: NSObjectProtocol? = nil
            observer = center.addObserver(forName: .movieWasMutated,
                                          object: mutator,
                                          queue: OperationQueue.main,
                                          using: handler)
            self.mutationObserver = observer
        }
    }
    
    /// Unregister observer for movie mutation
    public func removeMutationObserver() {
        
        do {
            guard let mutator = self.movieMutator else { return }
            guard let observer = self.mutationObserver else { return }
            let center = NotificationCenter.default
            center.removeObserver(observer,
                                  name: .movieWasMutated,
                                  object: mutator)
            self.mutationObserver = nil
        }
    }
    
    /// Unregister all undo record for current MovieMutator object
    public func removeAllUndoRecords() {
        
        guard let mutator = self.movieMutator else { return }
        self.undoManagerWrapper.removeAllActions(withTarget: mutator)
    }
}
