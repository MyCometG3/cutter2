//
//  MovieWriter.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/08.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

class MovieWriter: NSObject {
    
    private var internalMovie : AVMovie
    
    /// callback for NSDocument.unblockUserInteraction()
    public var unblockUserInteraction : (() -> Void)? = nil
    
    init(_ movie : AVMovie) {
        internalMovie = movie
    }
    
    /* ============================================ */
    // MARK: - public method - exportSession methods
    /* ============================================ */
    
    /// Flag if exportSession is running
    public private(set) var exportSessionBusy : Bool = false
    
    /// ExportSession
    private var exportSession : AVAssetExportSession? = nil
    
    /// Date when last exportSession had started
    private var exportSessionStart : Date? = nil
    
    /// Date when last exportSession had finished
    private var exportSessionEnd : Date? = nil
    
    /// Progress of last exportSession (update after finished)
    private var exportSessionProgress : Float = 0.0
    
    /// Status of last exportSession (update after finished)
    private var exportSessionStatus : AVAssetExportSessionStatus = .unknown
    
    /// Status string representation
    ///
    /// - Parameter status: AVAssetExportSessionStatus
    /// - Returns: String representation of status
    private func statusString(of status : AVAssetExportSessionStatus) -> String {
        let statusStrArray : [String] =
            ["unknown(0)","waiting(1)","exporting(2)","completed(3)","failed(4)","cancelled(5)"]
        
        let statusRaw : Int = status.rawValue
        let statusStr : String = statusStrArray[statusRaw]
        return statusStr
    }
    
    /// Export as specified file type using AVAssetExportSessionPreset
    ///
    /// - Parameters:
    ///   - url: target url
    ///   - type: AVFileType
    ///   - preset: AVAssetExportSessionPreset. Specify nil for pass-through
    /// - Throws: Raised by any internal error
    public func exportMovie(to url : URL, fileType type : AVFileType, presetName preset : String?) throws {
        // Swift.print(#function, #line, url.path, type)
        
        guard exportSessionBusy == false else {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Another exportSession is running."
            info[NSLocalizedFailureReasonErrorKey] = "Try after export session is completed."
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        // Prepare exportSession
        let preset : String = (preset ?? AVAssetExportPresetPassthrough)
        let srcMovie : AVMovie = internalMovie.copy() as! AVMovie
        let valid : Bool = validateExportSession(fileType: type, presetName: preset)
        guard valid, let exportSession = AVAssetExportSession(asset: srcMovie, presetName: preset) else {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Incompatible b/w UTI/preset is detected."
            info[NSLocalizedFailureReasonErrorKey] = "(type:" + type.rawValue + ", preset:" + preset + ") is incompatible."
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        // Configure exportSession
        exportSession.outputFileType = type
        exportSession.outputURL = url
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.canPerformMultiplePassesOverSourceMediaData = true
        exportSession.timeRange = srcMovie.range
        
        //
        self.unblockUserInteraction?()
        
        // Issue start notification
        let dateStart : Date = Date()
        let userInfoStart : [AnyHashable:Any] = ["url":url,
                                                 "start":dateStart]
        let notificationStart = Notification(name: .movieWillExportSession,
                                             object: self, userInfo: userInfoStart)
        NotificationCenter.default.post(notificationStart)
        
        // Start ExportSession
        self.exportSession = exportSession
        self.exportSessionBusy = true
        self.exportSessionStart = dateStart
        self.exportSessionEnd = nil
        self.exportSessionProgress = 0.0
        self.exportSessionStatus = .unknown
        let semaphore : DispatchSemaphore = DispatchSemaphore(value: 0)
        let handler : () -> Void = {[unowned self] in
            guard let exportSession = self.exportSession else { return }
            
            // Check results
            var completed : Bool = false
            let result : AVAssetExportSessionStatus = exportSession.status
            let progress : Float = exportSession.progress
            let dateEnd : Date = Date()
            let interval : TimeInterval = dateEnd.timeIntervalSince(dateStart)
            if result == .completed {
                completed = true
                Swift.print("result:", "completed", "progress:", progress, "elapsed:", interval)
            } else {
                let error : Error? = exportSession.error
                Swift.print("result:", result, "progress:", progress, "elapsed:", interval, "error", (error ?? "n/a"))
            }
            
            // Issue end notification
            let userInfoEnd : [AnyHashable:Any] = ["completed":completed,
                                                   "url":url,
                                                   "end":dateEnd,
                                                   "interval":interval]
            let notificationEnd = Notification(name: .movieDidExportSession,
                                               object: self, userInfo: userInfoEnd)
            NotificationCenter.default.post(notificationEnd)
            
            // cleanup
            self.exportSession = nil
            self.exportSessionBusy = false
            self.exportSessionStart = dateStart
            self.exportSessionEnd = dateEnd
            self.exportSessionProgress = progress
            self.exportSessionStatus = result
            
            //
            semaphore.signal()
        }
        exportSession.exportAsynchronously(completionHandler: handler)
        semaphore.wait()
    }
    
    /// Check compatibility b/w exportSession and presetName
    ///
    /// - Parameters:
    ///   - type: target AVFileType
    ///   - preset: one of AVAssetExportSession.exportPresets()
    /// - Returns: True if compatible
    public func validateExportSession(fileType type : AVFileType, presetName preset : String?) -> Bool {
        let preset : String = (preset ?? AVAssetExportPresetPassthrough)
        let srcMovie : AVAsset = internalMovie.copy() as! AVAsset
        
        var compatiblePresets : [String] = AVAssetExportSession.exportPresets(compatibleWith: srcMovie)
        compatiblePresets = compatiblePresets + [AVAssetExportPresetPassthrough]
        guard compatiblePresets.contains(preset) else {
            Swift.print("ERROR: Incompatible presetName detected.")
            return false
        }
        
        guard let exportSession : AVAssetExportSession = AVAssetExportSession(asset: srcMovie, presetName: preset) else {
            Swift.print("ERROR: Failed to create AVAssetExportSession.")
            return false
        }
        
        let compatibleFileTypes : [AVFileType] = exportSession.supportedFileTypes
        guard compatibleFileTypes.contains(type) else {
            Swift.print("ERROR: Incompatible AVFileType detected.")
            return false
        }
        
        return true
    }
    
    /// Get progress info of current exportSession
    ///
    /// - Returns: Dictionary of progress info
    public func exportSessionProgressInfo() -> [String: Any] {
        var result : [String:Any] = [:]
        //guard exportSessionBusy == true else { return result }
        
        if let dateStart = self.exportSessionStart {
            if let session = self.exportSession {
                // exportSession is running
                let progress : Float = session.progress
                let status : AVAssetExportSessionStatus = session.status
                result["progress"] = progress // 0.0 - 1.0 : Float
                result["status"] = statusString(of: status)
                
                let dateNow : Date = Date()
                let interval : TimeInterval = dateNow.timeIntervalSince(dateStart)
                result["elapsed"] = interval // seconds : Double
                
                let estimatedTotal : TimeInterval = interval / Double(progress)
                let estimatedRemaining : TimeInterval = estimatedTotal * Double(1.0 - progress)
                result["estimatedRemaining"] = estimatedRemaining // seconds : Double
                result["estimatedTotal"] = estimatedTotal // seconds : Double
            } else {
                // exportSession is not running
                let progress : Float = self.exportSessionProgress
                let status : AVAssetExportSessionStatus = self.exportSessionStatus
                result["progress"] = progress // 0.0 - 1.0 : Float
                result["status"] = statusString(of: status)
                
                if let dateEnd = self.exportSessionEnd {
                    let interval : TimeInterval = dateEnd.timeIntervalSince(dateStart)
                    result["elapsed"] = interval // seconds : Double
                }
            }
        }
        
        return result
    }
    
    /* ============================================ */
    // MARK: - public/private method - write action/methods
    /* ============================================ */
    
    /// Write internalMovie to destination url (as self-contained or reference movie)
    ///
    /// - Parameters:
    ///   - url: destination to write
    ///   - type: AVFileType. If it is not .mov, exportSession will be triggered.
    ///   - selfContained: Other than AVFileType.mov should be true.
    /// - Throws: Misc Error while exporting AVMovie
    public func writeMovie(to url : URL, fileType type : AVFileType, copySampleData selfContained : Bool) throws {
        // Swift.print(#function, #line, url.lastPathComponent, type.rawValue, selfContained ? "selfContained movie" : "reference movie")
        
        if type == .mov {
            if selfContained {
                try flattenMovie(to: url, with: .writeSelfContaind)
            } else {
                try flattenMovie(to: url, with: .writeReferenceMovie)
            }
        } else {
            try exportMovie(to: url, fileType: type, presetName: nil)
        }
    }
    
    /// Flatten mode
    ///
    /// - writeSelfContaind: Flatten in SelfContained Movie
    /// - writeReferenceMovie: Flatten in Reference Movie
    /// - refreshMovieHeader: Refresh Movie Header (keep data box)
    public enum FlattenMode {
        case writeSelfContaind
        case writeReferenceMovie
        case refreshMovieHeader
    }
    
    /// Flatten internal movie to destination url
    ///
    /// - Parameters:
    ///   - url: destination to write
    ///   - mode: FlattenMode
    public func flattenMovie(to url : URL, with mode : FlattenMode) throws {
        // Swift.print(#function, #line, mode.hashValue, url.path)
        
        var selfContained : Bool = false
        var option : AVMovieWritingOptions = .truncateDestinationToMovieHeaderOnly
        var before : Notification.Name = .movieWillWriteHeaderOnly
        var after : Notification.Name = .movieWillWriteHeaderOnly
        
        switch mode {
        case .writeSelfContaind:
            selfContained = true
            option = .addMovieHeaderToDestination
            before = .movieWillWriteWithData
            after = .movieWillWriteWithData
        case .writeReferenceMovie:
            selfContained = false
            option = .truncateDestinationToMovieHeaderOnly
            before = .movieWillWriteHeaderOnly
            after = .movieWillWriteHeaderOnly
        case .refreshMovieHeader:
            selfContained = false
            option = .addMovieHeaderToDestination
            before = .movieWillRefreshHeader
            after = .movieDidRefreshHeader
        }
        
        do {
            //
            let srcMovie : AVMutableMovie = internalMovie.mutableCopy() as! AVMutableMovie
            let range : CMTimeRange = srcMovie.range
            let tmp : AVMutableMovie? = try AVMutableMovie(settingsFrom: srcMovie, options: nil)
            guard let newMovie : AVMutableMovie = tmp else {
                Swift.print("ERROR: Failed to create proxy object.")
                assert(false, #function);
                return
            }
            newMovie.timescale = srcMovie.timescale
            newMovie.defaultMediaDataStorage = selfContained ? AVMediaDataStorage(url: url, options: nil) : nil
            
            //
            self.unblockUserInteraction?()
            
            //
            let dateStart : Date = Date()
            let userInfoStart : [AnyHashable:Any] = ["url":url]
            let notificationStart = Notification(name: before, object: self, userInfo: userInfoStart)
            NotificationCenter.default.post(notificationStart)
            
            //
            var completed : Bool = false
            try newMovie.insertTimeRange(range, of: srcMovie, at: kCMTimeZero, copySampleData: selfContained)
            try newMovie.writeHeader(to: url, fileType: AVFileType.mov, options: option)
            completed = true
            
            //
            let dateEnd : Date = Date()
            let interval : TimeInterval = dateEnd.timeIntervalSince(dateStart)
            let userInfoEnd : [AnyHashable:Any] = ["completed":completed, "url":url, "interval":interval]
            let notificationEnd = Notification(name: after, object: self, userInfo: userInfoEnd)
            NotificationCenter.default.post(notificationEnd)
        }
    }

}
