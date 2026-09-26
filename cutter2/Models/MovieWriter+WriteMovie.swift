//
//  MovieWriter+WriteMovie.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: - writeMovie methods
/* ============================================ */

extension MovieWriter {
    
    /// Flatten mode
    ///
    /// - writeSelfContained: Flatten in SelfContained Movie
    /// - writeReferenceMovie: Flatten in Reference Movie
    /// - refreshMovieHeader: Refresh Movie Header (keep data box)
    private enum FlattenMode {
        case writeSelfContained
        case writeReferenceMovie
        case refreshMovieHeader
    }
    
    /// Writes the internal movie as a self-contained or reference movie.
    ///
    /// MOV output uses movie flattening. Other file types use the export-session path.
    ///
    /// - Parameters:
    ///   - url: The destination file URL.
    ///   - type: The destination AVFoundation file type.
    ///   - selfContained: Whether MOV output should include the referenced sample data.
    /// - Throws: A writer error produced while writing or exporting the movie.
    public func writeMovie(to url: URL, fileType type: AVFileType, copySampleData selfContained: Bool) async throws {
        //     selfContained ? "selfContained movie" : "reference movie")
        
        if type == .mov {
            if selfContained {
                try await flattenMovie(to: url, with: .writeSelfContained)
            } else {
                try await flattenMovie(to: url, with: .writeReferenceMovie)
            }
        } else {
            try await exportMovie(to: url, fileType: type, presetName: nil)
        }
    }
    
    /// Flatten internal movie to destination url
    ///
    /// - Parameters:
    ///   - url: destination to write
    ///   - mode: FlattenMode
    private func flattenMovie(to url: URL, with mode: FlattenMode) async throws {
        
        let dateStart: Date = try beginWrite()
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent).\(UUID().uuidString).mov")
        var after: Notification.Name = .movieDidWriteHeaderOnly
        defer {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            if self.writeEnd == nil {
                self.writeEnd = Date()
            }
            writeInProgress = false
            issueEndNotification(after, url: url, dateStart: dateStart)
        }
        
        /* ============================================ */
        
        //
        self.unblockUserInteraction?()
        
        // Prepare
        var selfContained: Bool = false
        var option: AVMovieWritingOptions = .truncateDestinationToMovieHeaderOnly
        var before: Notification.Name = .movieWillWriteHeaderOnly
        
        switch mode {
        case .writeSelfContained:
            selfContained = true
            option = .addMovieHeaderToDestination
            before = .movieWillWriteWithData
            after = .movieDidWriteWithData
        case .writeReferenceMovie:
            selfContained = false
            option = .truncateDestinationToMovieHeaderOnly
            before = .movieWillWriteHeaderOnly
            after = .movieDidWriteHeaderOnly
        case .refreshMovieHeader:
            selfContained = false
            option = .addMovieHeaderToDestination
            before = .movieWillRefreshHeader
            after = .movieDidRefreshHeader
        }
        
        // Issue start notification
        issueStartNotification(before, url: url, dateStart: dateStart)
        
        /* ============================================ */
        
        // Prepare empty movie to save
        let movie: AVMutableMovie = internalMovie
        let range: CMTimeRange = movie.range
        guard let newMovie: AVMutableMovie = try? AVMutableMovie(settingsFrom: movie, options: nil) else {
            let reason = "Failed to create proxy movie for flattening."
            try throwError(.movieWriterFailed, reason: reason)
        }
        newMovie.timescale = movie.timescale // workaround
        newMovie.defaultMediaDataStorage = selfContained ? AVMediaDataStorage(url: temporaryURL, options: nil) : nil
        
        /* ============================================ */
        
        // Start flatten movie with security-scoped access bracket for reference media
        let referenceURLs: [URL] = internalMovie.findReferenceURLs() ?? []
        try await bracketSecurityScopedAccess(for: referenceURLs) {
            do {
                var success: Bool = false
                let cancel: Bool = self.writeCancelled
                var error: Error? = nil
                
                // Insert sampleData to destination first
                try newMovie.insertTimeRange(range,
                                             of: movie,
                                             at: CMTime.zero,
                                             copySampleData: selfContained)
                
                // Write movieHeader to a same-directory temporary file. The
                // destination is finalized only after the complete movie is valid.
                try newMovie.writeHeader(to: temporaryURL, fileType: AVFileType.mov, options: option)
                try finalizeTemporaryMovie(at: temporaryURL, to: url)
                
                //
                success = true
                error = nil
                
                //
                let progress: Float = 1.0
                let dateEnd: Date = Date()
                let interval: TimeInterval = dateEnd.timeIntervalSince(dateStart)
                
                // Update Properties
                self.writeSuccess = success
                self.writeError = error
                self.writeCancelled = cancel
                self.writeStart = dateStart
                self.writeEnd = dateEnd
                self.writeProgress = 1.0
                
                //
                let status = "completed" // (success ? "completed" : (cancel ? "cancelled" : "failed"))
                let progressStr = String(format:"%.2f",progress * 100)
                let intervalStr = String(format:"%.2f",interval)
                if let error = self.writeError {
                    LoggingSystem.export.error("Result: \(status), progress: \(progressStr), elapsed: \(intervalStr), error: \(error)")
                } else {
                    LoggingSystem.export.notice("Result: \(status), progress: \(progressStr), elapsed: \(intervalStr)")
                }
            } catch {
                self.writeEnd = Date()
                self.writeError = error
                self.writeSuccess = false
                throw error
            }
        }
    }

    func finalizeTemporaryMovie(at temporaryURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        if destinationExists {
            _ = try fileManager.replaceItemAt(destinationURL,
                                              withItemAt: temporaryURL,
                                              backupItemName: nil,
                                              options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }
}
