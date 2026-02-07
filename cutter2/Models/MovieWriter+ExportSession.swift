//
//  MovieWriter+ExportSession.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Foundation
import AVFoundation

/* ============================================ */
// MARK: - exportSession methods
/* ============================================ */

extension MovieWriter {
    
    /// Get current progress if exportSession is exporting
    private func currentProgressIfExporting() -> Float? {
        guard let session = exportSession, session.status == .exporting else { return nil }
        return session.progress
    }
    
    /// Install status polling task with adaptive polling and smooth progress updates
    ///
    /// This implementation uses adaptive polling to reduce CPU usage when progress is stagnant,
    /// while maintaining responsive updates (100ms) when progress is actively changing.
    ///
    /// Features:
    /// - Base interval: 100ms (10x faster than original 1s polling)
    /// - Adaptive slowdown: Up to 500ms when progress stagnates
    /// - Automatic cancellation when export completes
    public func exportSessionPollingStart() {
        exportSessionPollingStop()
        
        exportSessionPollingTask = Task<Void, Never> { @Sendable [weak self] in
            guard let self else { return }
            
            var lastProgress: Float = -1.0
            var stagnantCount = 0
            
            while let progress = await self.currentProgressIfExporting() {
                if Task.isCancelled {
                    break
                }
                await self.progressContinuation?.yield(progress)
                
                // Adaptive polling: slow down if no progress change
                let interval: TimeInterval
                if abs(progress - lastProgress) < 0.001 {
                    stagnantCount += 1
                    // After 10 stagnant updates (1 second), slow down to 500ms
                    interval = stagnantCount >= 10
                        ? self.exportSessionTimerMaxInterval 
                        : self.exportSessionTimerRefreshInterval
                } else {
                    // Progress is changing, use fast interval
                    stagnantCount = 0
                    interval = self.exportSessionTimerRefreshInterval
                }
                
                lastProgress = progress
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }
    
    /// Uninstall status polling task
    public func exportSessionPollingStop() {
        guard let currentTask = self.exportSessionPollingTask else { return }
        currentTask.cancel()
        self.exportSessionPollingTask = nil
    }
    
    /// Cancel ongoing export operation
    ///
    /// This method sets the `writeCancelled` flag and cancels the export session if one is active.
    /// For custom exports, the cancellation is handled via `cancelCustomMovie`.
    ///
    /// The method is safe to call at any time:
    /// - If no export is in progress, it has no effect
    /// - If an export is in progress, it attempts to cancel it gracefully
    /// - The export session's status will be set to `.cancelled`
    public func cancelExport() {
        writeCancelled = true
        exportSession?.cancelExport()
        // Note: For custom exports, cancelCustomMovie must be called separately
    }
    
    /// Status string representation
    ///
    /// - Parameter status: AVAssetExportSessionStatus
    /// - Returns: String representation of status
    private func statusString(of status: AVAssetExportSession.Status) -> String {
        switch status {
        case .unknown:
            return "unknown(0)"
        case .waiting:
            return "waiting(1)"
        case .exporting:
            return "exporting(2)"
        case .completed:
            return "completed(3)"
        case .failed:
            return "failed(4)"
        case .cancelled:
            return "cancelled(5)"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }
    
    /// Export as specified file type using AVAssetExportSessionPreset
    ///
    /// - Parameters:
    ///   - url: target url
    ///   - type: AVFileType
    ///   - preset: AVAssetExportSessionPreset. Specify nil for pass-through
    /// - Throws: Raised by any internal error
    public func exportMovie(to url: URL, fileType type: AVFileType, presetName preset: String?) async throws {
        
        guard writeInProgress == false else {
            let reason = "Please wait until the current export session finishes."
            try throwError(.anotherExportSessionRunning, reason: reason)
        }
        defer {
            writeInProgress = false
        }
        
        /* ============================================ */
        
        // Update Properties
        self.writeInProgress = true
        self.writeSuccess = false
        self.writeError = nil
        self.writeCancelled = false
        
        let dateStart: Date = Date()
        self.writeStart = dateStart
        self.writeEnd = nil
        self.writeProgress = 0.0
        
        self.exportSession = nil
        self.exportSessionStatus = .unknown
        
        //
        self.unblockUserInteraction?()
        
        // Issue start notification
        let userInfoStart: [AnyHashable:Any] = [urlInfoKey:url,
                                                startInfoKey:dateStart]
        let notificationStart = Notification(name: .movieWillExportSession,
                                             object: self, userInfo: userInfoStart)
        NotificationCenter.default.post(notificationStart)
        
        /* ============================================ */
        
        // Prepare exportSession
        let preset: String = (preset ?? AVAssetExportPresetPassthrough)
        let movie: AVMutableMovie = internalMovie
        let valid: Bool = await validateExportSession(fileType: type, presetName: preset)
        guard valid, let exportSession = AVAssetExportSession(asset: movie, presetName: preset) else {
            let reason: String = "(type:" + type.rawValue + ", preset:" + preset + ") is incompatible."
            try throwError(.compatibilityError, reason: reason)
        }
        
        // Configure exportSession
        exportSession.outputFileType = type
        exportSession.outputURL = url
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.canPerformMultiplePassesOverSourceMediaData = true
        exportSession.timeRange = movie.range
        
        //
        self.exportSession = exportSession
        
        // Start progress timer
        exportSessionPollingStart()
        defer {
            exportSessionPollingStop()
        }
        
        /* ============================================ */
        
        // Start ExportSession
        do {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exportSession.exportAsynchronously { @Sendable in
                    continuation.resume()
                }
            }
            
            // Check results
            let progress: Float = exportSession.progress
            let dateEnd: Date = Date()
            let interval: TimeInterval = dateEnd.timeIntervalSince(dateStart)
            let result: AVAssetExportSession.Status = exportSession.status
            
            // Update Properties
            self.writeSuccess = (result == .completed)
            self.writeError = exportSession.error
            self.writeCancelled = (result == .cancelled)
            self.writeStart = dateStart
            self.writeEnd = dateEnd
            self.writeProgress = progress
            self.exportSession = nil
            self.exportSessionStatus = result
            
            //
            let statusStr = self.statusString(of: result)
            let progressStr = String(format:"%.2f",progress * 100)
            let intervalStr = String(format:"%.2f",interval)
            if let error = self.writeError {
                LoggingSystem.export.error("Export result: \(statusStr), progress: \(progressStr), elapsed: \(intervalStr), error: \(error)")
            } else {
                LoggingSystem.export.notice("Export result: \(statusStr), progress: \(progressStr), elapsed: \(intervalStr)")
            }
        }
        
        //
        if writeSuccess == false {
            if writeCancelled {
                try throwError(.operationCancelled, reason: "Export was cancelled by the user.")
            } else if let error = writeError {
                throw error
            } else {
                try throwError(.movieWriterFailed, reason: "Export session failed with unknown error.")
            }
        }
        
        /* ============================================ */
        
        // Issue end notification
        var userInfoEnd: [AnyHashable:Any] = [urlInfoKey:url,
                                              startInfoKey:dateStart,
                                              completedInfoKey:self.writeSuccess]
        if let dateEnd = self.writeEnd, let dateStart = self.writeStart {
            userInfoEnd[endInfoKey] = dateEnd
            userInfoEnd[intervalInfoKey] = dateEnd.timeIntervalSince(dateStart)
        }
        let notificationEnd = Notification(name: .movieDidExportSession,
                                           object: self, userInfo: userInfoEnd)
        NotificationCenter.default.post(notificationEnd)
    }
    
    /// Check compatibility b/w exportSession and presetName
    ///
    /// - Parameters:
    ///   - type: target AVFileType
    ///   - preset: one of AVAssetExportSession.exportPresets()
    /// - Returns: True if compatible
    public func validateExportSession(fileType type: AVFileType, presetName preset: String?) async -> Bool {
        let preset: String = (preset ?? AVAssetExportPresetPassthrough)
        let movie: AVAsset = internalMovie.copy() as! AVAsset
        
        let compatible = await withCheckedContinuation { continuation in
            AVAssetExportSession.determineCompatibility(ofExportPreset: preset, with: movie, outputFileType: type) { compatible in
                continuation.resume(returning: compatible)
            }
        }
        guard compatible else {
            LoggingSystem.export.error("Incompatible preset '\(preset)' detected with AVAsset")
            return false
        }
        
        guard let exportSession: AVAssetExportSession = AVAssetExportSession(asset: movie, presetName: preset) else {
            LoggingSystem.export.error("Failed to create AVAssetExportSession with preset '\(preset)'")
            return false
        }
        
        let compatibleFileTypes: [AVFileType] = exportSession.supportedFileTypes
        guard compatibleFileTypes.contains(type) else {
            LoggingSystem.export.error("Incompatible AVFileType '\(type.rawValue)' for current export session")
            return false
        }
        
        return true
    }
    
    /// Get progress info of current exportSession
    ///
    /// - Returns: Dictionary of progress info
    public func exportSessionProgressInfo() -> [String: Any] {
        var result: [String:Any] = [:]
        
        if let dateStart = self.writeStart {
            if let session = self.exportSession {
                // exportSession is running
                let progress: Float = session.progress
                let status: AVAssetExportSession.Status = session.status
                result[progressInfoKey] = progress // 0.0 - 1.0: Float
                result[statusInfoKey] = statusString(of: status)
                
                let dateNow: Date = Date()
                let interval: TimeInterval = dateNow.timeIntervalSince(dateStart)
                result[elapsedInfoKey] = interval // seconds: Double
                
                if progress > 0.0 {
                    let estimatedTotal: TimeInterval = interval / Double(progress)
                    let estimatedRemaining: TimeInterval = estimatedTotal * Double(1.0 - progress)
                    result[estimatedRemainingInfoKey] = estimatedRemaining // seconds: Double
                    result[estimatedTotalInfoKey] = estimatedTotal // seconds: Double
                }
            } else {
                // exportSession is not running
                let progress: Float = self.writeProgress
                let status: AVAssetExportSession.Status = self.exportSessionStatus
                result[progressInfoKey] = progress // 0.0 - 1.0: Float
                result[statusInfoKey] = statusString(of: status)
                
                if let dateEnd = self.writeEnd {
                    let interval: TimeInterval = dateEnd.timeIntervalSince(dateStart)
                    result[elapsedInfoKey] = interval // seconds: Double
                }
            }
        }
        
        return result
    }
}
