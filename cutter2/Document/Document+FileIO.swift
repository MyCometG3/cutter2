//
//  Document+FileIO.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/13.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/// Prepared data for async document opening.
///
/// This separates background I/O from MainActor state application. `DocumentController.prepareOpen`
/// collects:
/// - `typeName`: Document type resolved on MainActor.
/// - `modificationDate`: File modification date for metadata updates.
/// - `movHeader`: Movie header used to initialize MovieMutator without extra I/O.
/// The preparation is passed into `Document.readAsync(from:openPreparation:)` during open/reopen.
struct OpenPreparation: Sendable {
    let typeName: String
    let modificationDate: Date?
    let movHeader: Data?
}

/* ============================================ */
// MARK: - File I/O Operations
/* ============================================ */

extension Document {
    
    /* ============================================ */
    // MARK: - Revert
    /* ============================================ */
    
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        LoggingSystem.document.debug("\(#function) called for \(url.lastPathComponent)")
        
        try super.revert(toContentsOf: url, ofType: typeName)
        
        // reset GUI when revert
        self.updateGUI(CMTime.zero, CMTimeRange.zero, true)
        self.doVolumeOffset(100)
    }
    
    /* ============================================ */
    // MARK: - Read
    /* ============================================ */
    
    /// Custom read(from:ofType:) throws w/ async
    /// - Parameters:
    ///   - url: The location from which the document contents are read.
    ///   - openPreparation: Precomputed open metadata for the URL.
    func readAsync(from url: URL, openPreparation: OpenPreparation) async throws {
        LoggingSystem.fileIO.info("Reading document from \(url.lastPathComponent, privacy: .public)")
        
        // Check UTI for AVMovie fileType
        let typeName = openPreparation.typeName
        let fileType = AVFileType.init(rawValue: typeName)
        if AVMovie.movieTypes().contains(fileType) == false {
            let reason = "(UTI: \(typeName))"
            LoggingSystem.fileIO.error("Incompatible file type: \(typeName)")
            try throwError(.incompatibleFileType, reason: reason)
        }
        
        if let header = openPreparation.movHeader {
            // File opened successfully
            // Initialize movieMutator
            let movie = AVMutableMovie(data: header)
            self.removeMutationObserver()
            self.removeAllUndoRecords()
            self.movieMutator = MovieMutator(with: movie)
            self.addMutationObserver()
            
            LoggingSystem.fileIO.notice("Document opened successfully: \(url.lastPathComponent)")
        } else {
            let reason = url.lastPathComponent + " at " + url.deletingLastPathComponent().path
            LoggingSystem.fileIO.error("Failed to open file: \(url.lastPathComponent)")
            try throwError(.unableToOpenFile, reason: reason)
        }
    }
    
    override func read(from url: URL, ofType typeName: String) throws {
        let reason = "read(from:ofType:) should never be called"
        LoggingSystem.document.fault("Unexpected read(from:ofType:) called - internal error")
        try throwError(.internalError, reason: reason)
    }
    
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        /*
         NOTE: This feature seems to be incompatible with Swift Concurrency and will cause a crash.
         Returning `true` causes `makeDocument(withContentsOf:ofType:)` to be called off the main thread,
         but that method is marked with `@MainActor`, so invoking it on a background thread crashes immediately.
         
         Instead, we override `NSDocumentController`'s `openDocument()` and `reopenDocument()` methods
         and use custom `OpenPreparation` + `readAsync()` implementations to support Swift Concurrency properly.
         */
        return true
    }
    
    /* ============================================ */
    // MARK: - Write
    /* ============================================ */
    
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) async throws {
        LoggingSystem.document.info("Saving document to \(url.lastPathComponent)")
        
        //
        guard let mutator = self.movieMutator else { preconditionFailure("Unexpected nil mutator detected.") }
        guard mutator.movieDuration() > CMTime.zero else {
            let reason = NSLocalizedString("error.reason.zero_duration_movie",
                                         comment: "Error reason when movie has zero duration")
            LoggingSystem.document.error("Cannot save: movie has zero duration")
            try throwError(.emptyMovie, reason: reason)
        }
        
        try await super.save(to: url, ofType: typeName, for: saveOperation)
    }
    
    private func preparation(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        
        do {
            // Check if current AVMovie reference URL = write target URL
            selfcontainedFlag = validateIfSelfContained(for: url)
            
            // Check if current document URL = write target URL
            if let original = self.fileURL, original == url {
                overwriteFlag = true
            } else {
                overwriteFlag = false
            }
            
            // Check if accessory view is presented in SavePanel
            if saveOperation == .saveAsOperation || saveOperation == .saveToOperation {
                useAccessory = true
            } else {
                useAccessory = false
            }
            
            // Check if user requested to save as ReferenceMovie
            if useAccessory {
                copyData = accessoryVCselfContained
            } else {
                copyData = selfcontainedFlag
            }
            
            #if DEBUG
            LoggingSystem.fileIO.debug("Save operation - source: \(self.displayName ?? "n/a", privacy: .public), target: \(url.lastPathComponent)")
            LoggingSystem.fileIO.debug("Save flags - selfContained: \(self.selfcontainedFlag), overwrite: \(self.overwriteFlag), useAccessory: \(self.useAccessory), copyData: \(self.copyData)")
            #endif
        }
        
        // Verify if user is attemping to overwrite sourceMovieFile with ReferenceMovieFile
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        if fileType == .mov {
            if overwriteFlag && selfcontainedFlag && copyData == false {
                // Reset cached accessoryVCselfContained to avoid unexpected behavior
                self.accessoryVCselfContained = true
                
                let reason = "You cannot overwrite self-contained movie with reference movie."
                try throwError(.overwriteSelfContainedWithReference, reason: reason)
            }
        }
        
        // Verify UTI compatibility with AVFileType
        if AVMovie.movieTypes().contains(fileType) == false {
            let reason = "(UTI:" + typeName + ")"
            try throwError(.incompatibleFileType, reason: reason)
        }
        
        // Sandbox support - keep source document security scope bookmark
        if saveOperation == .saveAsOperation, let srcURL = self.fileURL {
            Task { @Sendable @MainActor [typeName, srcURL, weak self] in // @escaping
                
                guard let self else { preconditionFailure("Unexpected nil self detected.") }
                let fileType: AVFileType = AVFileType.init(rawValue: typeName)
                guard fileType == .mov else { return }
                
                guard let accessoryVC = self.accessoryVC else { preconditionFailure("Unexpected nil accessoryVC detected.") }
                let saveAsRefMov: Bool = (accessoryVC.selfContained == false)
                guard saveAsRefMov else { return }
                
                // SaveAs reference movie - Need to keep readonly access to original
                let app: AppDelegate = NSApp.delegate as! AppDelegate
                app.addBookmark(for: srcURL)
            }
        }
    }
    
    override nonisolated func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        
        // Unblock main thread first to work w/ MainActor
        self.unblockUserInteraction()
        
        do {
            // Prepare to save
            try performSyncOnMainActor {
                try preparation(to: url, ofType: typeName, for: saveOperation)
            }
            
            // Trigger actual write operation (saveTo, save/saveAs)
            try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        } catch {
            performSyncOnMainActor {
                showErrorSheet(error)
            }
            throw error // rethrow to abort write operation
        }
        
        // Refresh internal movie (to sync selfcontained <> referece movie change)
        if saveOperation == .saveAsOperation {
            performSyncOnMainActor {
                refreshMutator()
            }
        }
    }
    
    /// Override of NSDocument's write method to support async save/export operations.
    ///
    /// This method is called by AppKit on a background queue (due to `canAsynchronouslyWrite` returning true).
    /// It bridges the synchronous AppKit document save API to our async/await implementation.
    ///
    /// The method uses `performAsync` to:
    /// - Execute async operations (writeAsync, export, exportCustom) in a detached Task
    /// - Block until the operation completes
    /// - Return results or throw errors synchronously back to AppKit
    ///
    /// This approach enables:
    /// - Swift Concurrency in save/export operations
    /// - Progress reporting via NSProgress
    /// - Proper resource cleanup with defer blocks
    /// - Integration with AppKit's document save machinery
    ///
    /// - SeeAlso: `canAsynchronouslyWrite(to:ofType:for:)` - enables background execution
    /// - SeeAlso: `performAsync(_:)` - async-to-sync bridge implementation
    override nonisolated func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        
        // Trigger long running task via global dispatch queue
        do {
            try performAsync { @Sendable [weak self] in
                guard let self else { preconditionFailure("Unexpected nil self detected.") }
                
                switch saveOperation {
                case .saveToOperation:
                    // Export...
                    let transcodePreset: String? = UserDefaults.standard.string(forKey: kTranscodePresetKey)
                    let preset = transcodePreset ?? kTranscodePresetCustom
                    if preset == kTranscodePresetCustom {
                        try await exportCustom(to: url, ofType: typeName)
                    } else {
                        try await export(to: url, ofType: typeName, preset: preset)
                    }
                case .saveOperation, .saveAsOperation:
                    // Save.../Save as...
                    try await writeAsync(to: url, ofType: typeName)
                default:
                    let reason = "No autoSave feature is implemented yet."
                    try throwError(.unsupportedSaveOperation, reason: reason)
                }
            }
        } catch let error as NSError {
            // Handle cancellation specially - don't show error sheet
            if error.domain == MovieWriterError.errorDomain && error.code == NSUserCancelledError {
                // Rethrow as standard user cancellation error
                // This prevents error sheet and maintains document dirty flag
                throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: error.userInfo)
            }
            throw error
        }
    }
    
    private func writeAsync(to url: URL, ofType typeName: String) async throws {
        
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
        showBusySheet("Writing...", "Please hold on second(s)...")
        mutator.unblockUserInteraction = { @Sendable [weak self] in
            self?.unblockUserInteraction()
        }
        defer {
            mutator.unblockUserInteraction = nil
            hideBusySheet()
        }
        
        // Create progress stream and start monitoring BEFORE write/export begins
        // This ensures progressContinuation is set before MovieWriter tries to use it
        let stream = mutator.progressStream()
        let progressTask = Task { @MainActor [weak self, weak progress] in
            for await progressValue in stream {
                // Separate guards for better debuggability
                guard let self else {
                    LoggingSystem.document.warning("Progress monitoring stopped: Document was deallocated during write")
                    break
                }
                guard let progress else {
                    LoggingSystem.document.warning("Progress monitoring stopped: NSProgress was deallocated during write")
                    break
                }
                updateProgress(progressValue)
                // Update NSProgress (thread-safe with weak capture)
                progress.completedUnitCount = Int64(progressValue * 100)
            }
        }
        defer {
            progressTask.cancel()
        }
        
        
        // Check fileType (mov or other)
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        if fileType == .mov {
            // Write mov file as either self-contained movie or reference movie
            try await mutator.writeMovie(to: url, fileType: fileType, copySampleData: self.copyData)
        } else {
            // Export as specified file type with AVAssetExportPresetPassthrough
            try await mutator.exportMovie(to: url, fileType: fileType, presetName: nil)
        }
        
    }
    
    /// Indicates that this document can perform write operations asynchronously.
    ///
    /// By returning true, we inform AppKit that `write(to:ofType:for:originalContentsURL:)` can be
    /// safely called on a background queue. This is essential for our async/await bridge pattern:
    ///
    /// - AppKit executes `write()` on a background queue (not main thread)
    /// - Our `write()` method uses `performAsync` to run async operations
    /// - The background thread blocks (via semaphore) until async operation completes
    /// - Main thread remains responsive during long save/export operations
    ///
    /// This pattern works because:
    /// - We never block the main thread (write is called on background queue)
    /// - Progress updates are dispatched to main thread via `performSyncOnMainActor`
    /// - User can interact with UI via the Busy Sheet during operations
    ///
    /// - Returns: Always returns `true` to enable background write operations
    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String,
                                         for saveOperation: NSDocument.SaveOperationType) -> Bool {
        return true
    }
    
    private func refreshMutator() {
        
        // SaveAs triggers internal movie refresh (to sync selfcontained <> referece movie change)
        Task { @MainActor [weak self] in
            
            guard let self else { preconditionFailure("Unexpected nil self detected.") }
            guard let url: URL = self.fileURL else { preconditionFailure("Unexpected nil fileURL detected.") }
            let newMovie: AVMutableMovie? = AVMutableMovie(url: url, options: nil)
            if let newMovie = newMovie {
                guard let mutator = self.movieMutator else { preconditionFailure("Unexpected nil mutator detected.") }
                let time: CMTime = mutator.insertionTime
                let range: CMTimeRange = mutator.selectedTimeRange
                
                let newMovieRange: CMTimeRange = newMovie.range
                var newTime: CMTime = CMTimeClampToRange(time, range: newMovieRange)
                let newRange: CMTimeRange = CMTimeRangeGetIntersection(range, otherRange: newMovieRange)
                newTime = CMTIME_IS_VALID(newTime) ? newTime : CMTime.zero
                
                self.removeMutationObserver()
                self.removeAllUndoRecords()
                self.movieMutator = MovieMutator(with: newMovie)
                self.movieMutator?.resetMarker(newTime, newRange, true)
                self.addMutationObserver()
            }
        }
    }
}
