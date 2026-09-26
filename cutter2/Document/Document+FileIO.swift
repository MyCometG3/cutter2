//
//  Document+FileIO.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/13.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
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

@MainActor
extension Document {
    
    /* ============================================ */
    // MARK: - Revert
    /* ============================================ */

    /// Returns whether an error represents user cancellation from MovieWriter or AppKit.
    ///
    /// MovieWriter cancellation is converted to the Cocoa domain by `write(to:)`; both
    /// representations must bypass `showErrorSheet` in the outer save path.
    nonisolated static func isUserCancellationError(_ error: NSError) -> Bool {
        let isKnownDomain = error.domain == MovieWriterError.errorDomain ||
            error.domain == NSCocoaErrorDomain
        return isKnownDomain && error.code == NSUserCancelledError
    }
    
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        LoggingSystem.document.debug("\(#function) called for \(url.lastPathComponent)")
        
        try super.revert(toContentsOf: url, ofType: typeName)
        
        // reset GUI when revert
        self.resetPositionCache()
        self.updateGUI(CMTime.zero, CMTimeRange.zero, true)
        self.doVolumeOffset(100)
    }
    
    /* ============================================ */
    // MARK: - File type validation
    /* ============================================ */
    
    /// Validate that the given UTI is a supported movie type.
    ///
    /// Shared by `readAsync(from:openPreparation:)` and `read(from:ofType:)` so the
    /// UTI check has a single source of truth (and is directly testable).
    /// - Parameter typeName: The UTI to validate.
    /// - Throws: An `NSError` produced by `ErrorUtilities.throwError` for
    ///   `DocumentError.incompatibleFileType` (domain `NSOSStatusErrorDomain`, code
    ///   `unimpErr`) when the UTI is not a movie type. Note the thrown value is the
    ///   NSError form, not the `DocumentError` case itself.
    nonisolated static func validateMovieType(_ typeName: String) throws {
        let fileType = AVFileType.init(rawValue: typeName)
        guard AVMovie.movieTypes().contains(fileType) else {
            let reason = "(UTI: \(typeName))"
            LoggingSystem.fileIO.error("Incompatible file type: \(typeName)")
            try ErrorUtilities.throwError(DocumentError.incompatibleFileType, reason: reason)
        }
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
        try Self.validateMovieType(openPreparation.typeName)
        
        if let header = openPreparation.movHeader {
            // File opened successfully
            // Initialize movieMutator
            let movie = AVMutableMovie(data: header)
            guard MovieHeaderValidator.isValid(movie) else {
                let reason = "Invalid movie header for \(url.lastPathComponent)"
                LoggingSystem.fileIO.error("Failed to validate movie header: \(url.lastPathComponent)")
                try throwError(.unableToOpenFile, reason: reason)
            }
            self.applyOpenedMovie(movie)
            
            LoggingSystem.fileIO.notice("Document opened successfully: \(url.lastPathComponent)")
        } else {
            let reason = url.lastPathComponent + " at " + url.deletingLastPathComponent().path
            LoggingSystem.fileIO.error("Failed to open file: \(url.lastPathComponent)")
            try throwError(.unableToOpenFile, reason: reason)
        }
    }

    private func applyOpenedMovie(_ movie: AVMutableMovie) {
        removeMutationObserver()
        removeAllUndoRecords()
        movieMutator = MovieMutator(with: movie)
        resetPositionCache()
        addMutationObserver()
    }
    
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        // Synchronous revert/reload path:
        // 1) validate the AppKit-provided file type
        // 2) load file metadata and movie header via AsyncBridge
        // 3) apply the new mutator on the MainActor
        
        // Stage 0: Validate the AppKit-provided UTI before doing any I/O.
        try Self.validateMovieType(typeName)
        
        // Stage 1: File I/O is performed on a background task and bridged back
        // through AsyncBridge.
        let preparation: OpenPreparation
        do {
            // allowMainThread: true — the bridged async block performs only file I/O
            // and AVMovie header parsing, deliberately staying MainActor-free so no
            // deadlock can occur even if NSDocument invokes read() on the main thread.
            preparation = try AsyncBridge.perform(timeout: 30, allowMainThread: true) { @Sendable in
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let modificationDate = attrs[.modificationDate] as? Date
                let movie = AVMutableMovie(url: url, options: nil)
                if let error = MovieHeaderValidator.validate(movie) {
                    try self.throwError(.unableToOpenFile, reason: error.localizedDescription)
                }
                return OpenPreparation(
                    typeName: typeName,
                    modificationDate: modificationDate,
                    movHeader: movie.movHeader
                )
            }
        } catch {
            LoggingSystem.document.fault("Revert prepare failed: \(error)")
            throw error
        }
        
        // Stage 2: Rebuild the mutator on the MainActor.
        do {
            try ActorUtilities.performSyncOnMainActor {
                if let header = preparation.movHeader {
                    let movie = AVMutableMovie(data: header)
                    guard MovieHeaderValidator.isValid(movie) else {
                        let reason = "Invalid movie header for \(url.lastPathComponent)"
                        LoggingSystem.fileIO.error("Failed to validate movie header: \(url.lastPathComponent)")
                        try self.throwError(.unableToOpenFile, reason: reason)
                    }
                    self.applyOpenedMovie(movie)
                    self.fileType = preparation.typeName
                    self.fileModificationDate = preparation.modificationDate
                    LoggingSystem.fileIO.notice("Document opened successfully: \(url.lastPathComponent)")
                } else {
                    let reason = url.lastPathComponent + " at " + url.deletingLastPathComponent().path
                    LoggingSystem.fileIO.error("Failed to open file: \(url.lastPathComponent)")
                    try self.throwError(.unableToOpenFile, reason: reason)
                }
            }
        } catch {
            LoggingSystem.document.fault("Revert Stage 2 failed: \(error)")
            throw error
        }
    }
    
    /// Allows AppKit to perform document reads concurrently.
    ///
    /// This method returns `true` unconditionally. The custom `DocumentController` open
    /// and reopen paths are required: using AppKit's default document-opening path can
    /// invoke the `@MainActor` document creation method off the main actor and crash.
    /// The custom paths prepare file metadata off the main actor and apply the result
    /// through `readAsync(from:openPreparation:)`.
    ///
    /// - Parameter typeName: The document type being opened.
    /// - Returns: Always `true`.
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        return true
    }
    
    /* ============================================ */
    // MARK: - Write
    /* ============================================ */
    
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) async throws {
        LoggingSystem.document.info("Saving document to \(url.lastPathComponent)")
        
        //
        guard let mutator = self.movieMutator else { throw CocoaError(.fileWriteUnknown) }
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
            // Self-contained status describes the source movie, not the Save As target.
            let selfContained = self.fileURL.map {
                validateIfSelfContained(for: $0)
            } ?? false
            
            // Check if current document URL = write target URL
            let overwrite = self.fileURL == url
            
            // Check if accessory view is presented in SavePanel
            let useAccessory = saveOperation == .saveAsOperation || saveOperation == .saveToOperation
            
            // Check if user requested to save as ReferenceMovie
            let copyData: Bool
            if useAccessory {
                copyData = self.accessoryVCselfContained
            } else {
                copyData = selfContained
            }
            self.saveMode = SaveMode(
                selfContained: selfContained,
                overwrite: overwrite,
                useAccessory: useAccessory,
                copyData: copyData
            )
            
            #if DEBUG
            LoggingSystem.fileIO.debug("Save operation - source: \(self.displayName ?? "n/a", privacy: .public), target: \(url.lastPathComponent)")
            LoggingSystem.fileIO.debug("Save flags - selfContained: \(self.saveMode.selfContained), overwrite: \(self.saveMode.overwrite), useAccessory: \(self.saveMode.useAccessory), copyData: \(self.saveMode.copyData)")
            #endif
        }
        
        // Verify if user is attemping to overwrite sourceMovieFile with ReferenceMovieFile
        let fileType: AVFileType = AVFileType.init(rawValue: typeName)
        if fileType == .mov {
            if saveMode.overwrite && saveMode.selfContained && !saveMode.copyData {
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
                guard let self else { return }
                let fileType: AVFileType = AVFileType.init(rawValue: typeName)
                guard fileType == .mov else { return }
                
                guard let accessoryVC = self.accessoryVC else { return }
                let saveAsRefMov: Bool = (accessoryVC.selfContained == false)
                guard saveAsRefMov else { return }
                
                // SaveAs reference movie - Need to keep readonly access to original
                guard let app = NSApp.delegate as? AppDelegate else { return }
                app.addBookmark(for: srcURL)
            }
        }
    }
    
    override nonisolated func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        
        // Unblock main thread first to work w/ MainActor
        self.unblockUserInteraction()
        let originalFileURL = self.fileURL
        
        do {
            // Prepare to save
            try ActorUtilities.performSyncOnMainActor {
                try preparation(to: url, ofType: typeName, for: saveOperation)
            }
            
            // Trigger actual write operation (saveTo, save/saveAs)
            try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        } catch {
            if !Self.isUserCancellationError(error as NSError) {
                ActorUtilities.performSyncOnMainActor {
                    showErrorSheet(error)
                }
            }
            throw error // rethrow to abort write operation
        }
        
        // Refresh internal movie (to sync selfcontained <> referece movie change)
        if saveOperation == .saveAsOperation {
            let refreshed = ActorUtilities.performSyncOnMainActor {
                refreshMutator(from: url)
            }
            if !refreshed {
                ActorUtilities.performSyncOnMainActor {
                    self.fileURL = originalFileURL
                }
                let reason = "The saved movie was written, but the document could not refresh its in-memory movie."
                let error = NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: reason]
                )
                ActorUtilities.performSyncOnMainActor {
                    showErrorSheet(error)
                }
                throw error
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
    override nonisolated func write(to url: URL, ofType typeName: String,
                                    for saveOperation: NSDocument.SaveOperationType,
                                    originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        
        // Trigger long running task via global dispatch queue
        do {
            try performAsync { @Sendable [weak self] in
                guard let self else { throw CocoaError(.fileWriteUnknown) }
                
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
            if Self.isUserCancellationError(error) {
                // Rethrow as standard user cancellation error
                // This prevents error sheet and maintains document dirty flag
                if error.domain == MovieWriterError.errorDomain {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: error.userInfo)
                }
            }
            throw error
        }
    }
    
    private func writeAsync(to url: URL, ofType typeName: String) async throws {
        try await withBusyProgress(title: "Writing...",
                                   message: "Please hold on second(s)...",
                                   operationName: "write") { mutator in
            let fileType: AVFileType = AVFileType.init(rawValue: typeName)
            if fileType == .mov {
                try await mutator.writeMovie(to: url, fileType: fileType, copySampleData: self.saveMode.copyData)
            } else {
                try await mutator.exportMovie(to: url, fileType: fileType, presetName: nil)
            }
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
    
    private func refreshMutator(from url: URL) -> Bool {
        
        // SaveAs triggers internal movie refresh (to sync selfcontained <> referece movie change)
        let newMovie = AVMutableMovie(url: url, options: nil)
        guard let mutator = self.movieMutator else {
            LoggingSystem.fileIO.error("Failed to refresh mutator after SaveAs: movie mutator is unavailable")
            return false
        }
        guard let movieHeader = newMovie.movHeader else {
            LoggingSystem.fileIO.error("Failed to refresh mutator after SaveAs: movie header is unavailable")
            return false
        }
        let time: CMTime = mutator.insertionTime
        let range: CMTimeRange = mutator.selectedTimeRange
        
        let newMovieRange: CMTimeRange = newMovie.range
        var newTime: CMTime = CMTimeClampToRange(time, range: newMovieRange)
        let newRange: CMTimeRange = CMTimeRangeGetIntersection(range, otherRange: newMovieRange)
        newTime = CMTIME_IS_VALID(newTime) ? newTime : CMTime.zero
        
        guard mutator.reloadAndNotify(from: movieHeader, range: newRange, time: newTime) else {
            LoggingSystem.fileIO.error("Failed to refresh mutator after SaveAs")
            return false
        }
        resetPositionCache()
        return true
    }
}
