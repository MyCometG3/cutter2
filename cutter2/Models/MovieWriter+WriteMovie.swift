//
//  MovieWriter+WriteMovie.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
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
    /// - writeSelfContaind: Flatten in SelfContained Movie
    /// - writeReferenceMovie: Flatten in Reference Movie
    /// - refreshMovieHeader: Refresh Movie Header (keep data box)
    private enum FlattenMode {
        case writeSelfContaind
        case writeReferenceMovie
        case refreshMovieHeader
    }
    
    /// Write internalMovie to destination url (as self-contained or reference movie)
    ///
    /// - Parameters:
    ///   - url: destination to write
    ///   - type: AVFileType. If it is not .mov, exportSession will be triggered.
    ///   - selfContained: Other than AVFileType.mov should be true.
    /// - Throws: Misc Error while exporting AVMovie
    public func writeMovie(to url: URL, fileType type: AVFileType, copySampleData selfContained: Bool) async throws {
        //     selfContained ? "selfContained movie" : "reference movie")
        
        if type == .mov {
            if selfContained {
                try await flattenMovie(to: url, with: .writeSelfContaind)
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
        
        //
        self.unblockUserInteraction?()
        
        // Prepare
        var selfContained: Bool = false
        var option: AVMovieWritingOptions = .truncateDestinationToMovieHeaderOnly
        var before: Notification.Name = .movieWillWriteHeaderOnly
        var after: Notification.Name = .movieDidWriteHeaderOnly
        
        switch mode {
        case .writeSelfContaind:
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
        let userInfoStart: [AnyHashable:Any] = [urlInfoKey:url,
                                                startInfoKey:dateStart]
        let notificationStart = Notification(name: before, object: self, userInfo: userInfoStart)
        NotificationCenter.default.post(notificationStart)
        
        /* ============================================ */
        
        // Prepare empty movie to save
        let movie: AVMutableMovie = internalMovie
        let range: CMTimeRange = movie.range
        guard let newMovie: AVMutableMovie = try? AVMutableMovie(settingsFrom: movie, options: nil) else {
            preconditionFailure("ERROR: Failed to create proxy object.")
        }
        newMovie.timescale = movie.timescale // workaround
        newMovie.defaultMediaDataStorage = selfContained ? AVMediaDataStorage(url: url, options: nil) : nil
        
        /* ============================================ */
        
        // Start flatten movie
        do {
            var success: Bool = false
            let cancel: Bool = self.writeCancelled
            var error: Error? = nil
            
            // Insert sampleData to destination first
            try newMovie.insertTimeRange(range,
                                         of: movie,
                                         at: CMTime.zero,
                                         copySampleData: selfContained)
            
            // Write movieHeader to destination
            try newMovie.writeHeader(to: url, fileType: AVFileType.mov, options: option)
            
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
            let reason = "Failed to write movie: \(option)."
            try throwError(.movieWriterFailed, reason: reason)
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
        let notificationEnd = Notification(name: after, object: self, userInfo: userInfoEnd)
        NotificationCenter.default.post(notificationEnd)
    }
}
