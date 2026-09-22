//
//  MovieWriter.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/08.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import VideoToolbox
import os.log

/* ============================================ */
// MARK: - MovieWriterError
/* ============================================ */

enum MovieWriterError: Error, NSErrorConvertible {
    case compatibilityError
    case assetReaderWriterUnavailable
    case anotherExportSessionRunning
    case movieWriterFailed
    case assetReaderWriterFailed
    case operationCancelled
    case unknown
    
    static let errorDomain = "MovieWriterError"
    
    var nsError: NSError {
        let domain = MovieWriterError.errorDomain
        switch self {
        case .compatibilityError:
            let message = NSLocalizedString("error.writer.compatibility",
                                            comment: "Error when file type or preset is not compatible")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: 1, userInfo: info)
        case .assetReaderWriterUnavailable:
            let message = NSLocalizedString("error.writer.reader_writer_unavailable",
                                            comment: "Error when AVAssetReader or AVAssetWriter cannot be created")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: 2, userInfo: info)
        case .anotherExportSessionRunning:
            let message = NSLocalizedString("error.writer.export_in_progress",
                                            comment: "Error when trying to start export while another is running")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: 3, userInfo: info)
        case .movieWriterFailed:
            let message = NSLocalizedString("error.writer.write_failed",
                                            comment: "Error when movie writer encounters an error")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: 4, userInfo: info)
        case .assetReaderWriterFailed:
            let message = NSLocalizedString("error.writer.reader_writer_failed",
                                            comment: "Error when asset reader or writer encounters an error")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: 5, userInfo: info)
        case .operationCancelled:
            // Note: This uses the custom domain internally. Document.write() converts it
            // to NSCocoaErrorDomain before rethrowing to conform to system conventions.
            let message = NSLocalizedString("error.writer.operation_cancelled",
                                            comment: "Error when user cancels an operation")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: NSUserCancelledError, userInfo: info)
        case .unknown:
            let message = NSLocalizedString("error.writer.unknown",
                                            comment: "Unknown error message")
            let info = [NSLocalizedDescriptionKey: message]
            return NSError(domain: domain, code: -1, userInfo: info)
        }
    }
}

extension MovieWriter {
    /// Throw an error with a specific reason. This method updates the internal state of the writer and throws the error.
    /// - Parameters:
    ///   - error: The `MovieWriterError` to throw
    ///   - reason: Optional reason for the error
    /// - Returns: Never
    func throwError(_ error: MovieWriterError, reason: String? = nil) throws -> Never {
        do {
            try ErrorUtilities.throwError(error, reason: reason)
        } catch let nsError as NSError {
            self.writeError = nsError
            self.writeSuccess = false
            throw nsError
        }
    }
}

/* ============================================ */
// MARK: - common write phases
/* ============================================ */

extension MovieWriter {
    /// Begin a write/export phase with mutual exclusion and shared state reset.
    ///
    /// - Throws `anotherExportSessionRunning` when a write/export is already running.
    /// - Resets the shared write state (`writeInProgress`, `writeSuccess`, `writeError`,
    ///   `writeCancelled`, `writeStart`, `writeEnd`, `writeProgress`).
    ///
    /// The caller must keep `defer { writeInProgress = false }` at its own scope.
    /// Moving the defer into this method would release the flag as soon as this
    /// method returns (see S-15 plan §2.5).
    ///
    /// - Returns: The operation start date (also stored into `writeStart`).
    /// - Throws: `MovieWriterError.anotherExportSessionRunning` when busy.
    func beginWrite() throws -> Date {
        guard !writeInProgress else {
            let reason = "Please wait until the current export session finishes."
            try throwError(.anotherExportSessionRunning, reason: reason)
        }
        
        // Update Properties
        self.writeInProgress = true
        self.writeSuccess = false
        self.writeError = nil
        self.writeCancelled = false
        
        let dateStart: Date = Date()
        self.writeStart = dateStart
        self.writeEnd = nil
        self.writeProgress = 0.0
        
        return dateStart
    }

    /// Post the start-phase notification with the standard userInfo keys.
    ///
    /// - Parameters:
    ///   - name: Entry-specific notification name (`movieWill*`).
    ///   - url: The destination file URL (`urlInfoKey`).
    ///   - dateStart: The operation start date (`startInfoKey`).
    func issueStartNotification(_ name: Notification.Name, url: URL, dateStart: Date) {
        let userInfoStart: [AnyHashable:Any] = [urlInfoKey:url,
                                              startInfoKey:dateStart]
        let notificationStart = Notification(name: name, object: self, userInfo: userInfoStart)
        NotificationCenter.default.post(notificationStart)
    }

    /// Post the end-phase notification with the standard userInfo keys.
    ///
    /// `endInfoKey` / `intervalInfoKey` are appended only when `writeEnd` is set.
    ///
    /// - Parameters:
    ///   - name: Entry-specific notification name (`movieDid*`).
    ///   - url: The destination file URL (`urlInfoKey`).
    ///   - dateStart: The operation start date (`startInfoKey`).
    func issueEndNotification(_ name: Notification.Name, url: URL, dateStart: Date) {
        var userInfoEnd: [AnyHashable:Any] = [urlInfoKey:url,
                                            startInfoKey:dateStart,
                                        completedInfoKey:self.writeSuccess]
        if let dateEnd = self.writeEnd, let dateStart = self.writeStart {
            userInfoEnd[endInfoKey] = dateEnd
            userInfoEnd[intervalInfoKey] = dateEnd.timeIntervalSince(dateStart)
        }
        let notificationEnd = Notification(name: name, object: self, userInfo: userInfoEnd)
        NotificationCenter.default.post(notificationEnd)
    }
}

/* ============================================ */
// MARK: -
/* ============================================ */

extension Notification.Name {
    static let movieWillExportSession = Notification.Name("movieWillExportSession")
    static let movieDidExportSession = Notification.Name("movieDidExportSession")
    static let movieWillExportCustom = Notification.Name("movieWillExportCustom")
    static let movieDidExportCustom = Notification.Name("movieDidExportCustom")
    static let movieWillWriteHeaderOnly = Notification.Name("movieWillWriteHeaderOnly")
    static let movieDidWriteHeaderOnly = Notification.Name("movieDidWriteHeaderOnly")
    static let movieWillWriteWithData = Notification.Name("movieWillWriteWithData")
    static let movieDidWriteWithData = Notification.Name("movieDidWriteWithData")
    static let movieWillRefreshHeader = Notification.Name("movieWillRefreshHeader")
    static let movieDidRefreshHeader = Notification.Name("movieDidRefreshHeader")
}

/* ============================================ */
// MARK: -
/* ============================================ */

/// `@unchecked Sendable` rationale:
/// `MovieWriterParams` is created by `prepareMovieWriterParams()` and
/// immediately moved into the `MovieWriter` actor (effectively move-only).
/// `progressContinuation` and `unblockUserInteraction` are accessed only
/// within the `MovieWriter` actor. `movie` (`AVMutableMovie`) is mutated
/// only under actor isolation.
struct MovieWriterParams: @unchecked Sendable {
    let movie: AVMutableMovie
    let unblockUserInteraction: (@Sendable () -> Void)?
    let progressContinuation: AsyncStream<Float>.Continuation?
}

/* ============================================ */
// MARK: -
/* ============================================ */

actor MovieWriter: SampleBufferChannelDelegate {
    
    /// Creates a writer actor for the supplied movie and progress callbacks.
    ///
    /// - Parameter params: The movie and callbacks used by the writer.
    public init(params: MovieWriterParams) {
        self.internalMovie = params.movie
        self.unblockUserInteraction = params.unblockUserInteraction
        self.progressContinuation = params.progressContinuation
    }
    
    /* ============================================ */
    // MARK: - common properties
    /* ============================================ */
    
    private(set) var internalMovie: AVMutableMovie
    
    /// callback for NSDocument.unblockUserInteraction()
    private(set) var unblockUserInteraction: (@Sendable () -> Void)? = nil
    
    /// Progress stream continuation
    private(set) var progressContinuation: AsyncStream<Float>.Continuation?
    
    /// Whether a save or export operation is currently running.
    public internal(set) var writeInProgress: Bool = false
    
    /// Whether the most recent save or export operation completed successfully.
    public internal(set) var writeSuccess: Bool = false
    
    /// Whether the current save or export operation was cancelled.
    public internal(set) var writeCancelled: Bool = false
    
    /// The error produced by the current or most recent save/export operation.
    public internal(set) var writeError: Error? = nil
    
    /// The start date of the current or most recent save/export operation.
    public internal(set) var writeStart: Date? = nil
    
    /// The completion date of the current or most recent save/export operation.
    public internal(set) var writeEnd: Date? = nil
    
    /// The current save/export progress as a value from 0.0 to 1.0.
    public internal(set) var writeProgress: Float = 0.0
    /* ============================================ */
    // MARK: - exportSession properties
    /* ============================================ */
    
    /// Status polling timer interval (100ms for responsive updates)
    /// This provides 10x more frequent updates compared to the original 1-second polling,
    /// resulting in smoother progress bar animation and better user experience.
    let exportSessionTimerRefreshInterval: TimeInterval = 1.0/10
    
    /// Maximum polling interval when progress is stagnant (adaptive polling)
    let exportSessionTimerMaxInterval: TimeInterval = 0.5
    
    /// ExportSession
    var exportSession: AVAssetExportSession? = nil
    
    /// Status of last exportSession (update after finished)
    var exportSessionStatus: AVAssetExportSession.Status = .unknown
    
    /// Status polling task
    var exportSessionPollingTask: Task<Void, Never>?
    
    /* ============================================ */
    // MARK: - exportCustomMovie properties
    /* ============================================ */
    
    /// DispatchGroupQueue for SampleBufferChannels
    var customQueue: DispatchQueue? = nil
    
    /// SampleBufferChannels array
    var customSampleBufferChannels: [SampleBufferChannel] = []
    
    /// Parameter dictionary for custom exporting
    var customParam: [String: any Sendable] = [:]
}
