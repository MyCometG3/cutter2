//
//  Document+Export.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/13.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - Export/Transcode Operations
/* ============================================ */

extension Document {
    
    /* ============================================ */
    // MARK: - Export/Transcode
    /* ============================================ */
    
    @IBAction func transcode(_ sender: Any?) {
        
        // Prepare Transcode SheetController
        let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
        let sid: NSStoryboard.SceneIdentifier = "TranscodeSheet Controller"
        guard let transcodeWC = storyboard.instantiateController(withIdentifier: sid) as? NSWindowController else {
            preconditionFailure("Failed to instantiate TranscodeSheet Controller")
        }
        // transcodeWC.loadWindow()
        
        // Prepare Transcode ViewController
        guard let contVC = transcodeWC.contentViewController else { preconditionFailure("Unexpected nil contentViewController detected.") }
        guard let transcodeVC = contVC as? TranscodeViewController else { preconditionFailure("Unexpected nil TranscodeViewController detected.") }
        
        // Show Transcode Sheet
        transcodeVC.beginSheetModal(for: self.window!) { @Sendable @MainActor [weak self] (response) in // @escaping
            self?.afterSheetContinue(response) { document in
                document.transcoding = true
                document.saveTo(document)
                document.transcoding = false
            }
        }
    }
    
    /// Run an async operation with NSProgress, busy sheet, and progress stream monitoring.
    ///
    /// This helper encapsulates the common preamble shared by `writeAsync`, `export`,
    /// and `exportCustom`. It sets up:
    /// - Cancellable `NSProgress` assigned to `saveProgress`
    /// - Busy sheet UI
    /// - `unblockUserInteraction` callback on the mutator
    /// - Progress stream monitoring task
    ///
    /// Cleanup (`progressTask.cancel()`, `hideBusySheet()`, `saveProgress = nil`)
    /// runs in the same order as the original inline defers.
    ///
    /// - Parameters:
    ///   - title: Busy sheet title.
    ///   - message: Busy sheet message.
    ///   - operationName: Name used in progress-monitoring log messages.
    ///   - operation: Async closure that performs the actual write/export work.
    /// - Returns: The value produced by `operation`.
    /// - Throws: `CocoaError(.fileWriteUnknown)` if `movieMutator` is nil, or any
    ///   error thrown by `operation`.
    func withBusyProgress<T: Sendable>(
        title: String,
        message: String,
        operationName: String,
        operation: (MovieMutator) async throws -> T
    ) async throws -> T {
        guard let mutator = self.movieMutator else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        // Create NSProgress with proper lifecycle management
        let progress = Progress(totalUnitCount: 100)
        progress.isCancellable = true
        progress.cancellationHandler = { [weak mutator] in
            Task { @MainActor [weak mutator] in
                await mutator?.cancel()
            }
        }
        self.saveProgress = progress
        defer {
            if self.saveProgress === progress {
                self.saveProgress = nil
            }
        }
        
        // Show busy sheet
        showBusySheet(title, message)
        mutator.unblockUserInteraction = { @Sendable [weak self] in
            self?.unblockUserInteraction()
        }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }
        
        // Create progress stream and start monitoring BEFORE operation begins
        let stream = mutator.progressStream()
        let progressTask = Task { @MainActor [weak self, weak progress] in
            for await progressValue in stream {
                guard let self else {
                    LoggingSystem.document.warning("Progress monitoring stopped: Document was deallocated during \(operationName)")
                    break
                }
                guard let progress else {
                    LoggingSystem.document.warning("Progress monitoring stopped: NSProgress was deallocated during \(operationName)")
                    break
                }
                updateProgress(progressValue)
                progress.completedUnitCount = Int64(progressValue * 100)
            }
        }
        defer {
            progressTask.cancel()
        }
        
        return try await operation(mutator)
    }
    
    internal func export(to url: URL, ofType typeName: String, preset: String) async throws {
        let title = NSLocalizedString("progress.exporting.title", comment: "Title for export progress dialog")
        let message = NSLocalizedString("progress.exporting.message", comment: "Message for export progress dialog")
        try await withBusyProgress(title: title, message: message, operationName: "export") { mutator in
            let fileType: AVFileType = AVFileType.init(rawValue: typeName)
            try await mutator.exportMovie(to: url, fileType: fileType, presetName: preset)
        }
    }
    
    internal func exportCustom(to url: URL, ofType typeName: String) async throws {
        let title = NSLocalizedString("progress.exporting.title", comment: "Title for export progress dialog")
        let message = NSLocalizedString("progress.exporting.message", comment: "Message for export progress dialog")
        try await withBusyProgress(title: title, message: message, operationName: "custom export") { mutator in
            let fileType: AVFileType = AVFileType.init(rawValue: typeName)
            let videoID: [String] = ["avc1","hvc1","apcn","apcs","apco"]
            let audioID: [String] = ["aac ","lpcm","lpcm","lpcm"]
            let lpcmBPC: [Int] = [0, 16, 24, 32]
            
            let defaults = UserDefaults.standard
            let audioRate = defaults.integer(forKey: kAudioKbpsKey)
            let videoRate = defaults.integer(forKey: kVideoKbpsKey)
            let copyField = defaults.bool(forKey: kCopyFieldKey)
            let copyNCLC = defaults.bool(forKey: kCopyNCLCKey)
            let copyOtherMedia = defaults.bool(forKey: kCopyOtherMediaKey)
            let videoEncode = defaults.bool(forKey: kVideoEncodeKey)
            let audioEncode = defaults.bool(forKey: kAudioEncodeKey)
            let videoCodecIndex = min(max(defaults.integer(forKey: kVideoCodecKey), 0), videoID.count - 1)
            let audioCodecIndex = min(max(defaults.integer(forKey: kAudioCodecKey), 0), audioID.count - 1)
            let lpcmDepthIndex = min(max(defaults.integer(forKey: kLPCMDepthKey), 0), lpcmBPC.count - 1)
            let videoCodec = videoID[videoCodecIndex]
            let audioCodec = audioID[audioCodecIndex]
            let lpcmDepth = lpcmBPC[lpcmDepthIndex]
            
            var param: [String: any Sendable] = [:]
            param[kAudioKbpsKey] = audioRate
            param[kVideoKbpsKey] = videoRate
            param[kCopyFieldKey] = copyField
            param[kCopyNCLCKey] = copyNCLC
            param[kCopyOtherMediaKey] = copyOtherMedia
            param[kVideoEncodeKey] = videoEncode
            param[kAudioEncodeKey] = audioEncode
            param[kVideoCodecKey] = videoCodec
            param[kAudioCodecKey] = audioCodec
            param[kLPCMDepthKey] = lpcmDepth
            
            try await mutator.exportCustomMovie(to: url, fileType: fileType, settings: param)
        }
    }
}
