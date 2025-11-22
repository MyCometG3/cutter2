//
//  Document+Export.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/13.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
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
        let transcodeWC = storyboard.instantiateController(withIdentifier: sid) as! NSWindowController
        // transcodeWC.loadWindow()
        
        // Prepare Transcode ViewController
        guard let contVC = transcodeWC.contentViewController else { preconditionFailure("Unexpected nil contentViewController detected.") }
        guard let transcodeVC = contVC as? TranscodeViewController else { preconditionFailure("Unexpected nil TranscodeViewController detected.") }
        
        // Show Transcode Sheet
        transcodeVC.beginSheetModal(for: self.window!) { @Sendable @MainActor [weak self] (response) in // @escaping
            
            guard response == NSApplication.ModalResponse.continue else { return }
            
            Task { @MainActor in
                guard let self else { preconditionFailure("Unexpected nil self detected.") }
                self.transcoding = true
                self.saveTo(self)
                self.transcoding = false
            }
        }
    }
    
    internal func export(to url: URL, ofType typeName: String, preset: String) async throws {
        
        guard let mutator = self.movieMutator else { preconditionFailure("Unexpected nil mutator detected.") }
        
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
            self.saveProgress = nil
        }
        
        // Show busy sheet
        let title = NSLocalizedString("progress.exporting.title", comment: "Title for export progress dialog")
        let message = NSLocalizedString("progress.exporting.message", comment: "Message for export progress dialog")
        showBusySheet(title, message)
        mutator.unblockUserInteraction = { @Sendable [weak self] in
            self?.unblockUserInteraction()
        }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }
        
        // Create progress stream and start monitoring BEFORE export begins
        // This ensures progressContinuation is set before MovieWriter tries to use it
        let stream = mutator.progressStream()
        let progressTask = Task { @MainActor [weak self, weak progress] in
            for await progressValue in stream {
                guard let self, let progress else { break }
                updateProgress(progressValue)
                // Update NSProgress (thread-safe with weak capture)
                progress.completedUnitCount = Int64(progressValue * 100)
            }
        }
        defer {
            progressTask.cancel()
        }
        
        
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        do {
            // Export as specified file type with AVAssetExportPresetPassthrough
            try await mutator.exportMovie(to: url, fileType: fileType, presetName: preset)
        }
        
    }
    
    internal func exportCustom(to url: URL, ofType typeName: String) async throws {
        
        guard let mutator = self.movieMutator else { preconditionFailure("Unexpected nil mutator detected.") }
        
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
            self.saveProgress = nil
        }
        
        // Show busy sheet
        let title = NSLocalizedString("progress.exporting.title", comment: "Title for export progress dialog")
        let message = NSLocalizedString("progress.exporting.message", comment: "Message for export progress dialog")
        showBusySheet(title, message)
        mutator.unblockUserInteraction = { @Sendable [weak self] in
            self?.unblockUserInteraction()
        }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }
        
        // Create progress stream and start monitoring BEFORE export begins
        // This ensures progressContinuation is set before MovieWriter tries to use it
        let stream = mutator.progressStream()
        let progressTask = Task { @MainActor [weak self, weak progress] in
            for await progressValue in stream {
                guard let self, let progress else { break }
                updateProgress(progressValue)
                // Update NSProgress (thread-safe with weak capture)
                progress.completedUnitCount = Int64(progressValue * 100)
            }
        }
        defer {
            progressTask.cancel()
        }
        
        
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        do {
            let videoID: [String] = ["avc1","hvc1","apcn","apcs","apco"]
            let audioID: [String] = ["aac ","lpcm","lpcm","lpcm"]
            let lpcmBPC: [Int] = [0, 16, 24, 32]
            
            // Export as specified file type using custom setting params
            let defaults = UserDefaults.standard
            let audioRate = defaults.integer(forKey: kAudioKbpsKey)
            let videoRate = defaults.integer(forKey: kVideoKbpsKey)
            let copyField = defaults.bool(forKey: kCopyFieldKey)
            let copyNCLC = defaults.bool(forKey: kCopyNCLCKey)
            let copyOtherMedia = defaults.bool(forKey: kCopyOtherMediaKey)
            let videoEncode = defaults.bool(forKey: kVideoEncodeKey)
            let audioEncode = defaults.bool(forKey: kAudioEncodeKey)
            let videoCodec = videoID[defaults.integer(forKey: kVideoCodecKey)]
            let audioCodec = audioID[defaults.integer(forKey: kAudioCodecKey)]
            let lpcmDepth = lpcmBPC[defaults.integer(forKey: kAudioCodecKey)]
            
            var param: [String:Sendable] = [:]
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
