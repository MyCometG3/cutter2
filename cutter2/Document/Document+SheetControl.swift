//
//  Document+SheetControl.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - Sheet control
/* ============================================ */

extension Document {
    
    /// Update progress with smooth animation
    ///
    /// This function implements exponential smoothing for smoother progress bar animation.
    /// It also throttles UI updates to every 100ms to reduce unnecessary redraws.
    ///
    /// - Parameter progress: The raw progress value (0.0 to 1.0)
    public func updateProgress(_ progress: Float) {
        
        // Use Low frequency update (throttle to 100ms)
        let unit = NSEC_PER_MSEC * 100 // 100ms
        let t: UInt64 = clock_gettime_nsec_np(CLOCK_REALTIME)
        if lastUpdateAt == 0 {
            // First call: initialize timestamp and progress
            lastUpdateAt = t
            lastReportedProgress = 0.0
        } else {
            if t > lastUpdateAt {
                // Normal case: time moved forward
                if (t - lastUpdateAt) > unit {
                    // Sufficient time passed: update timestamp
                    lastUpdateAt += unit
                } else {
                    // Too soon: skip this update
                    return
                }
            } else {
                // Edge case: clock went backwards, reset
                lastUpdateAt = t
            }
        }
        
        // Apply exponential smoothing for smoother animation
        // Formula: smoothed = α * new + (1 - α) * old
        // α = 0.3 provides good balance between responsiveness and smoothness
        let smoothingFactor: Float = 0.3
        let smoothedProgress = lastReportedProgress + smoothingFactor * (progress - lastReportedProgress)
        lastReportedProgress = smoothedProgress
        
        // Update UI in main queue
        Task { @MainActor in
            
            guard let alert = self.alert else { return }
            guard smoothedProgress.isNormal else { return }
            
            // Update progress indicator (visual feedback)
            if let indicator = self.progressIndicator {
                indicator.doubleValue = Double(smoothedProgress * 100.0)
            }
            
            // Update text (percentage)
            let format = NSLocalizedString("progress.format.percent", comment: "Progress percentage format")
            alert.informativeText = String(format: format, Int(smoothedProgress * 100))
        }
    }
    
    /// Show busy modalSheet
    ///
    /// Displays a modal sheet with progress information, a visual progress indicator,
    /// and an optional Cancel button.
    /// When the user clicks Cancel, the operation is cancelled via NSProgress and MovieMutator.
    ///
    /// - Parameters:
    ///   - message: The main message to display (defaults to "Processing...")
    ///   - info: Additional information text (defaults to "Hold on seconds...")
    public func showBusySheet(_ message: String?, _ info: String?) {
        
        // Reset progress state for new operation
        lastUpdateAt = 0
        lastReportedProgress = 0.0
        
        Task { @MainActor in
            
            guard let window = self.window else { return }
            
            // Create progress indicator for visual feedback
            let progressIndicator = NSProgressIndicator()
            progressIndicator.style = .bar
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0.0
            progressIndicator.maxValue = 100.0
            progressIndicator.doubleValue = 0.0
            progressIndicator.controlSize = .regular
            
            // Set frame for progress indicator (width: 300pt, height: 20pt)
            progressIndicator.frame = NSRect(x: 0, y: 0, width: 300, height: 20)
            
            // Store reference for updates
            self.progressIndicator = progressIndicator
            
            // Create alert
            let alert: NSAlert = NSAlert()
            let defaultTitle = NSLocalizedString("progress.default.title", comment: "Default title for progress dialog")
            let defaultMessage = NSLocalizedString("progress.default.message", comment: "Default message for progress dialog")
            alert.messageText = message ?? defaultTitle
            alert.informativeText = info ?? defaultMessage
            alert.alertStyle = .informational
            
            // Add progress indicator as accessory view
            alert.accessoryView = progressIndicator
            
            alert.addButton(withTitle: NSLocalizedString("ui.button.cancel", comment: "Cancel button for canceling operations"))
            let handler: (NSApplication.ModalResponse) -> Void = { @Sendable [weak self] (response) in // @escaping
                guard let self else { return }
                if response == .alertFirstButtonReturn {
                    // User clicked Cancel - the cancellationHandler will call mutator.cancel()
                    ActorUtilities.performSyncOnMainActor {
                        self.saveProgress?.cancel()
                    }
                }
            }
            alert.beginSheetModal(for: window, completionHandler: handler)
            
            // Keep NSAlert object for later update
            self.alert = alert
        }
    }
    
    /// Hide busy modalSheet
    public func hideBusySheet() {
        
        Task { @MainActor in
            
            guard let window = self.window else { return }
            guard let alert = self.alert else { return }
            
            window.endSheet(alert.window)
            
            // Release NSAlert and progress indicator
            self.alert = nil
            self.progressIndicator = nil
        }
    }
    
    /// Present ErrorSheet asynchronously
    public func showErrorSheet(_ error: Error) {
        
        // Don't use NSDocument default error handling
        Task { @MainActor in
            
            guard let window = self.window else { NSSound.beep(); return }
            
            let alert = NSAlert(error: error)
            let err :NSError = error as NSError
            var text :String? = nil
            let userInfo: [String:Any] = err.userInfo // Can be empty dictionary
            if userInfo.count > 0 {
                let keys = userInfo.keys
                if keys.contains(NSUnderlyingErrorKey) || keys.contains(NSDebugDescriptionErrorKey) {
                    text = err.description
                } else if keys.contains(NSLocalizedFailureErrorKey) {
                    text = userInfo[NSLocalizedFailureErrorKey] as? String
                } else if keys.contains(NSLocalizedDescriptionKey) {
                    text = userInfo[NSLocalizedDescriptionKey] as? String
                } else if keys.contains(NSLocalizedFailureReasonErrorKey) {
                    text = userInfo[NSLocalizedFailureReasonErrorKey] as? String
                }
            }
            if let text = text {
                alert.informativeText = text
            }
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }
}
