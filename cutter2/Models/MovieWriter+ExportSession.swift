//
//  MovieWriter+ExportSession.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation
import AVFoundation

/* ============================================ */
// MARK: - exportSession methods
/* ============================================ */

extension MovieWriter {
    
    /// Get current progress if exportSession is exporting.
    ///
    /// On macOS 15+, progress is mirrored into `writeProgress` from the
    /// `states(updateInterval:)` stream so we do not depend on deprecated
    /// `AVAssetExportSession.progress/status` polling. On macOS 14, the legacy
    /// session polling path remains in use.
    private func currentProgressIfExporting() -> Float? {
        if #available(macOS 15, *) {
            guard exportSessionStatus == .exporting else { return nil }
            return writeProgress
        } else {
            guard let session = exportSession, session.status == .exporting else { return nil }
            return session.progress
        }
    }
    
    @available(macOS 15, *)
    private func updateExportState(_ state: AVAssetExportSession.State) {
        switch state {
        case .pending:
            writeProgress = 0.0
            exportSessionStatus = .unknown
        case .waiting:
            exportSessionStatus = .waiting
        case .exporting(let progress):
            let progressValue = Float(progress.fractionCompleted)
            writeProgress = progressValue
            exportSessionStatus = .exporting
            progressContinuation?.yield(progressValue)
        @unknown default:
            exportSessionStatus = .unknown
        }
    }
    
    @available(macOS 15, *)
    private func monitorExportSessionStates() async {
        guard let session = exportSession else { return }
        let updateInterval = exportSessionTimerRefreshInterval
        
        for await state in session.states(updateInterval: updateInterval) {
            if Task.isCancelled {
                break
            }
            updateExportState(state)
        }
    }
    
    private func finalizeExport(
        startedAt dateStart: Date,
        endedAt dateEnd: Date,
        progress: Float,
        status: AVAssetExportSession.Status,
        error: Error?
    ) {
        self.writeSuccess = (status == .completed)
        self.writeError = error
        self.writeCancelled = (status == .cancelled)
        self.writeStart = dateStart
        self.writeEnd = dateEnd
        self.writeProgress = progress
        self.exportSession = nil
        self.exportSessionStatus = status
        
        let statusStr = self.statusString(of: status)
        let progressStr = String(format: "%.2f", progress * 100)
        let intervalStr = String(format: "%.2f", dateEnd.timeIntervalSince(dateStart))
        if let error {
            LoggingSystem.export.error("Export result: \(statusStr), progress: \(progressStr), elapsed: \(intervalStr), error: \(error)")
        } else {
            LoggingSystem.export.notice("Export result: \(statusStr), progress: \(progressStr), elapsed: \(intervalStr)")
        }
    }
    
    /// Install progress/status monitoring for the current export session.
    ///
    /// On macOS 15+, this method consumes `AVAssetExportSession.states(updateInterval:)`
    /// and mirrors the state stream into `writeProgress` / `exportSessionStatus`.
    /// On macOS 14, it uses adaptive polling to reduce CPU usage when progress
    /// is stagnant while maintaining responsive updates when progress changes.
    ///
    /// Features:
    /// - macOS 15+: state-stream driven progress updates
    /// - macOS 14: Base interval 100ms with adaptive slowdown up to 500ms
    /// - Automatic cancellation when export completes or monitoring is cancelled
    public func exportSessionPollingStart() {
        exportSessionPollingStop()
        
        if #available(macOS 15, *) {
            exportSessionPollingTask = Task<Void, Never> { @Sendable [weak self] in
                guard let self else { return }
                await self.monitorExportSessionStates()
            }
            return
        }
        
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
                    interval = (stagnantCount >= 10
                                ? self.exportSessionTimerMaxInterval
                                : self.exportSessionTimerRefreshInterval)
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
    
    /// Uninstall progress/status monitoring task.
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
    
    /// Status string representation.
    ///
    /// - Parameter status: `AVAssetExportSession.Status`
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
    
    /// Export as specified file type using AVAssetExportSessionPreset.
    ///
    /// - Parameters:
    ///   - url: target url
    ///   - type: AVFileType
    ///   - preset: AVAssetExportSessionPreset. Specify nil for pass-through
    /// - Throws: Raised by compatibility failures, cancellation, or AVFoundation
    ///   export errors surfaced by the active platform path.
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
        
        // Configure exportSession. On macOS 15+, output URL / type are supplied
        // to the async export API call below. On macOS 14, the legacy
        // exportAsynchronously path still uses the session properties.
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
        
        // Start ExportSession with security-scoped access bracket for reference media
        let referenceURLs: [URL] = internalMovie.findReferenceURLs() ?? []
        try await bracketSecurityScopedAccess(for: referenceURLs) {
            if #available(macOS 15, *) {
                do {
                    try await exportSession.export(to: url, as: type, isolation: #isolation)
                    let dateEnd = Date()
                    finalizeExport(startedAt: dateStart,
                                   endedAt: dateEnd,
                                   progress: 1.0,
                                   status: .completed,
                                   error: nil)
                } catch {
                    let dateEnd = Date()
                    let nsError = error as NSError
                    let cancelled = writeCancelled || nsError.code == NSUserCancelledError
                    let status: AVAssetExportSession.Status = (cancelled ? .cancelled : .failed)
                    finalizeExport(startedAt: dateStart,
                                   endedAt: dateEnd,
                                   progress: self.writeProgress,
                                   status: status,
                                   error: cancelled ? nil : error)
                }
            } else {
                exportSession.outputFileType = type
                exportSession.outputURL = url
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    exportSession.exportAsynchronously { @Sendable in
                        continuation.resume()
                    }
                }
                
                let progress: Float = exportSession.progress
                let dateEnd: Date = Date()
                let result: AVAssetExportSession.Status = exportSession.status
                let error: Error? = (result == .cancelled ? nil : exportSession.error)
                finalizeExport(startedAt: dateStart,
                               endedAt: dateEnd,
                               progress: progress,
                               status: result,
                               error: error)
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
    
    /// Check compatibility of preset + asset + output file type.
    ///
    /// - Parameters:
    ///   - type: target AVFileType
    ///   - preset: one of AVAssetExportSession.exportPresets()
    /// - Returns: True if the exact combination can export.
    ///
    /// This uses the async compatibility API on macOS 15+ and falls back to a
    /// continuation bridge over `determineCompatibility(...)` on macOS 14.
    public func validateExportSession(fileType type: AVFileType, presetName preset: String?) async -> Bool {
        let preset: String = (preset ?? AVAssetExportPresetPassthrough)
        guard let movie = internalMovie.copy() as? AVAsset else {
            preconditionFailure("copy() of AVMutableMovie returned non-AVAsset")
        }
        
        let compatible: Bool
        if #available(macOS 15, *) {
            compatible = await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: movie,
                outputFileType: type
            )
        } else {
            compatible = await withCheckedContinuation { continuation in
                AVAssetExportSession.determineCompatibility(
                    ofExportPreset: preset,
                    with: movie,
                    outputFileType: type
                ) { compatible in
                    continuation.resume(returning: compatible)
                }
            }
        }
        guard compatible else {
            LoggingSystem.export.error("Incompatible export combination detected (preset: \(preset), type: \(type.rawValue))")
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
                let progress: Float
                let status: AVAssetExportSession.Status
                if #available(macOS 15, *) {
                    progress = self.writeProgress
                    status = self.exportSessionStatus
                } else {
                    progress = session.progress
                    status = session.status
                }
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
