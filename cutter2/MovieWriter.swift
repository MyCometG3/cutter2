//
//  MovieWriter.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/08.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import VideoToolbox

class MovieWriter: NSObject, SampleBufferChannelDelegate {
    private var internalMovie : AVMutableMovie
    
    /// callback for NSDocument.unblockUserInteraction()
    public var unblockUserInteraction : (() -> Void)? = nil
    
    /// Flag if writer is running
    public private(set) var writerIsBusy : Bool = false
    
    init(_ movie : AVMovie) {
        internalMovie = movie.mutableCopy() as! AVMutableMovie
    }
    
    /* ============================================ */
    // MARK: - exportSession methods
    /* ============================================ */
    
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
        
        guard writerIsBusy == false else {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Another exportSession is running."
            info[NSLocalizedFailureReasonErrorKey] = "Try after export session is completed."
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        writerIsBusy = true
        defer {
            writerIsBusy = false
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
    // MARK: - exportCustomMovie methods
    /* ============================================ */
    
    public private(set) var finalSuccess : Bool = true
    public private(set) var finalError : Error? = nil
    public var updateProgress : ((Float) -> Void)? = nil
    
    private var queue : DispatchQueue? = nil
    private var sampleBufferChannels : [SampleBufferChannel] = []
    private var cancelled : Bool = false
    private var param : [String:Any] = [:]
    
    fileprivate func prepareCopyChannels(_ movie: AVMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter, _ mediaType : AVMediaType) {
        for track in movie.tracks(withMediaType: mediaType) {
            // source
            let arOutputSetting : [String:Any]? = nil
            let arOutput : AVAssetReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: arOutputSetting)
            ar.add(arOutput)
            
            // destination
            let awInputSetting : [String:Any]? = nil
            let awInput : AVAssetWriterInput = AVAssetWriterInput(mediaType: mediaType, outputSettings: awInputSetting)
            if mediaType != .audio {
                awInput.mediaTimeScale = track.naturalTimeScale
            }
            aw.add(awInput)
            
            // channel
            let copySBC : SampleBufferChannel = SampleBufferChannel(readerOutput: arOutput,
                                                                     writerInput: awInput,
                                                                     trackID: track.trackID)
            sampleBufferChannels += [copySBC]
        }
    }
    
    fileprivate func prepareOtherMediaChannels(_ movie: AVMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) {
        let numCopyOtherMedia = param[kCopyOtherMediaKey] as? NSNumber
        let copyOtherMedia : Bool = numCopyOtherMedia?.boolValue ?? false
        guard copyOtherMedia else { return }
        
        // Copy non-av media type (excludes muxed media)
        prepareCopyChannels(movie, ar, aw, .text)
        prepareCopyChannels(movie, ar, aw, .closedCaption)
        prepareCopyChannels(movie, ar, aw, .subtitle)
        prepareCopyChannels(movie, ar, aw, .timecode)
        prepareCopyChannels(movie, ar, aw, .metadata)
        if #available(OSX 10.13, *) {
            prepareCopyChannels(movie, ar, aw, .depthData)
        }
    }
    
    fileprivate func prepareAudioChannels(_ movie: AVMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) {
        let numAudioEncode = param[kAudioEncodeKey] as? NSNumber
        let audioEncode : Bool = numAudioEncode?.boolValue ?? true
        if audioEncode == false {
            prepareCopyChannels(movie, ar, aw, .audio)
            return
        }
        
        let fourcc = param[kAudioCodecKey] as! NSString
        
        let numAudioKbps = param[kAudioKbpsKey] as? NSNumber
        let targetKbps : Float = numAudioKbps?.floatValue ?? 128
        let targetBitRate : Int = Int(targetKbps * 1000)
        
        let numLPCMDepth = param[kLPCMDepthKey] as? NSNumber
        let lpcmDepth : Int = numLPCMDepth?.intValue ?? 16
        
        for track in movie.tracks(withMediaType: .audio) {
            // source
            var arOutputSetting : [String:Any] = [:]
            arOutputSetting[AVFormatIDKey] = kAudioFormatLinearPCM
            let arOutput : AVAssetReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: arOutputSetting)
            ar.add(arOutput)
            
            // preseve original sampleRate, numChannel, and audioChannelLayout
            var sampleRate = 48000
            var numChannel = 2
            var avacLayout : AVAudioChannelLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)!
            
            let descArray : [Any] = track.formatDescriptions
            if descArray.count > 0 {
                let desc : CMFormatDescription = descArray[0] as! CMFormatDescription
                
                let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                if let asbd = asbdPtr?.pointee {
                    sampleRate = Int(asbd.mSampleRate)
                    numChannel = Int(asbd.mChannelsPerFrame)
                }
                
                var layoutSize : Int = 0
                let aclPtr = CMAudioFormatDescriptionGetChannelLayout(desc, &layoutSize)
                if let acl = aclPtr?.pointee {
                    var audioChannelLayout : AudioChannelLayout = acl
                    avacLayout = AVAudioChannelLayout(layout: &audioChannelLayout)
                }
            }
            
            //
            let acDescCount : UInt32 = avacLayout.layout.pointee.mNumberChannelDescriptions
            let acDescSize : Int = MemoryLayout<AudioChannelDescription>.size
            let acLayoutSize : Int = MemoryLayout<AudioChannelLayout>.size + (Int(acDescCount) - 1) * acDescSize
            var acl : AudioChannelLayout = avacLayout.layout.pointee
            let aclData : Data = Data.init(bytes: &acl, count: acLayoutSize)
            
            // destination
            var awInputSetting : [String:Any] = [:]
            awInputSetting[AVFormatIDKey] = UTGetOSTypeFromString(fourcc)
            if fourcc == "lpcm" {
                awInputSetting[AVLinearPCMIsBigEndianKey] = false
                awInputSetting[AVLinearPCMIsFloatKey] = false
                awInputSetting[AVLinearPCMBitDepthKey] = lpcmDepth
                awInputSetting[AVLinearPCMIsNonInterleaved] = false
            } else {
                awInputSetting[AVEncoderBitRateKey] = targetBitRate
            }
            awInputSetting[AVSampleRateKey] = sampleRate
            awInputSetting[AVNumberOfChannelsKey] = numChannel
            awInputSetting[AVChannelLayoutKey] = aclData
            
            let awInput : AVAssetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: awInputSetting)
            // awInput.mediaTimeScale = track.naturalTimeScale // Audio track is unable to change
            aw.add(awInput)
            
            // channel
            let audioSBC : SampleBufferChannel = SampleBufferChannel(readerOutput: arOutput,
                                                                     writerInput: awInput,
                                                                     trackID: track.trackID)
            sampleBufferChannels += [audioSBC]
        } // for track in movie.tracks(withMediaType: .audio)
    }
    
    fileprivate func prepareVideoChannels(_ movie: AVMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) {
        let numVideoEncode = param[kVideoEncodeKey] as? NSNumber
        let videoEncode : Bool = numVideoEncode?.boolValue ?? true
        if videoEncode == false {
            prepareCopyChannels(movie, ar, aw, .video)
            return
        }
        
        let fourcc = param[kVideoCodecKey] as! NSString
        
        let numVideoKbps = param[kVideoKbpsKey] as? NSNumber
        let targetKbps : Float = numVideoKbps?.floatValue ?? 2500
        let targetBitRate : Int = Int(targetKbps*1000)
        
        let numCopyField = param[kCopyFieldKey] as? NSNumber
        let copyField : Bool = numCopyField?.boolValue ?? false
        
        let numCopyNCLC = param[kCopyNCLCKey] as? NSNumber
        let copyNCLC : Bool = numCopyNCLC?.boolValue ?? false
        
        for track in movie.tracks(withMediaType: .video) {
            // source
            var arOutputSetting : [String:Any] = [:]
            arOutputSetting[String(kCVPixelBufferPixelFormatTypeKey)] = kCVPixelFormatType_422YpCbCr8_yuvs
            let arOutput : AVAssetReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: arOutputSetting)
            ar.add(arOutput)
            
            //
            var compressionProperties : NSDictionary? = nil
            if ["ap4h","apch","apcn","apcs","apco"].contains(fourcc) {
                // ProRes family
            } else {
                compressionProperties = [AVVideoAverageBitRateKey:targetBitRate]
            }
            
            var cleanAperture : NSDictionary? = nil
            var pixelAspectRatio : NSDictionary? = nil
            var nclc : NSDictionary? = nil
            
            var trackDimensions = track.naturalSize
            let descArray : [Any] = track.formatDescriptions
            if descArray.count > 0 {
                let desc : CMFormatDescription = descArray[0] as! CMFormatDescription
                trackDimensions = CMVideoFormatDescriptionGetPresentationDimensions(desc, false, false)
                
                var fieldCount : NSNumber? = nil
                var fieldDetail : NSString? = nil
                
                let extCA : CFPropertyList? =
                    CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_CleanAperture)
                if let extCA = extCA {
                    let width = extCA[kCMFormatDescriptionKey_CleanApertureWidth] as! NSNumber
                    let height = extCA[kCMFormatDescriptionKey_CleanApertureHeight] as! NSNumber
                    let wOffset = extCA[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] as! NSNumber
                    let hOffset = extCA[kCMFormatDescriptionKey_CleanApertureVerticalOffset] as! NSNumber
                    
                    let dict : NSMutableDictionary = NSMutableDictionary()
                    dict[AVVideoCleanApertureWidthKey] = width
                    dict[AVVideoCleanApertureHeightKey] = height
                    dict[AVVideoCleanApertureHorizontalOffsetKey] = wOffset
                    dict[AVVideoCleanApertureVerticalOffsetKey] = hOffset
                    
                    cleanAperture = dict
                }
                
                let extPA : CFPropertyList? =
                    CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_PixelAspectRatio)
                if let extPA = extPA {
                    let hSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as! NSNumber
                    let vSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as! NSNumber
                    
                    let dict : NSMutableDictionary = NSMutableDictionary()
                    dict[AVVideoPixelAspectRatioHorizontalSpacingKey] = hSpacing
                    dict[AVVideoPixelAspectRatioVerticalSpacingKey] = vSpacing
                    
                    pixelAspectRatio = dict
                }
                
                if copyNCLC {
                    let extCP : CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_ColorPrimaries)
                    let extTF : CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_TransferFunction)
                    let extMX : CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_YCbCrMatrix)
                    if let extCP  = extCP, let extTF = extTF, let extMX = extMX {
                        let colorPrimaries = extCP as! NSString
                        let transferFunction = extTF as! NSString
                        let ycbcrMatrix = extMX as! NSString
                        
                        let dict : NSMutableDictionary = NSMutableDictionary()
                        dict[AVVideoColorPrimariesKey] = colorPrimaries
                        dict[AVVideoTransferFunctionKey] = transferFunction
                        dict[AVVideoYCbCrMatrixKey] = ycbcrMatrix
                        
                        nclc = dict
                    }
                }
                
                if copyField {
                    let extFC : CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldCount)
                    let extFD : CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldDetail)
                    if let extFC = extFC, let extFD = extFD {
                        fieldCount = (extFC as! NSNumber)
                        fieldDetail = (extFD as! NSString)
                    }
                }
                
                if fieldCount != nil || fieldDetail != nil {
                    let dict : NSMutableDictionary = NSMutableDictionary()
                    
                    if copyField, let fieldCount = fieldCount, let fieldDetail = fieldDetail {
                        dict[kVTCompressionPropertyKey_FieldCount] = fieldCount
                        dict[kVTCompressionPropertyKey_FieldDetail] = fieldDetail
                    }
                    
                    if let compressionProperties = compressionProperties {
                        dict.addEntries(from: compressionProperties as! [AnyHashable:Any])
                    }
                    compressionProperties = dict
                }
            }
            
            // destination
            var awInputSetting : [String:Any] = [:]
            awInputSetting[AVVideoCodecKey] = fourcc
            awInputSetting[AVVideoWidthKey] = trackDimensions.width
            awInputSetting[AVVideoHeightKey] = trackDimensions.height
            if let compressionProperties = compressionProperties {
                awInputSetting[AVVideoCompressionPropertiesKey] = compressionProperties
            }
            
            if let cleanAperture = cleanAperture {
                awInputSetting[AVVideoCleanApertureKey] = cleanAperture
            }
            if let pixelAspectRatio = pixelAspectRatio {
                awInputSetting[AVVideoPixelAspectRatioKey] = pixelAspectRatio
            }
            if copyNCLC, let nclc = nclc {
                awInputSetting[AVVideoColorPropertiesKey] = nclc
            }
            
            let awInput : AVAssetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: awInputSetting)
            awInput.mediaTimeScale = track.naturalTimeScale
            aw.add(awInput)
            
            // channel
            let videoSBC : SampleBufferChannel = SampleBufferChannel(readerOutput: arOutput,
                                                                     writerInput: awInput,
                                                                     trackID: track.trackID)
            sampleBufferChannels += [videoSBC]
        } // for track in movie.tracks(withMediaType: .video)
    }
    
    public func exportCustomMovie(to url : URL, fileType type : AVFileType, settings param : [String:Any]) throws {
        // Swift.print(#function, #line, url.path, type)

        guard writerIsBusy == false else {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Another exportSession is running."
            info[NSLocalizedFailureReasonErrorKey] = "Try after export session is completed."
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        writerIsBusy = true
        defer {
            writerIsBusy = false
        }
        
        //
        self.param = param
        self.queue = DispatchQueue(label: "exportCustomMovie")
        self.sampleBufferChannels = []
        self.cancelled = false
        guard let queue = self.queue else { return }

        //
        let movie : AVMutableMovie = internalMovie
        var assetReader : AVAssetReader? = nil
        var assetWriter : AVAssetWriter? = nil
        do {
            assetReader = try AVAssetReader(asset: movie)
            assetWriter = try AVAssetWriter(url: url, fileType: type)
        } catch {
            self.finalSuccess = false
            self.finalError = error
            return
        }
        guard let ar = assetReader, let aw = assetWriter else {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Internal error"
            info[NSLocalizedFailureReasonErrorKey] = "Either AVAssetReader or AVAssetWriter is not available."
            self.finalError = NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
            self.finalSuccess = false
            return
        }

        // setup aw parameters here
        aw.movieTimeScale = movie.timescale
        aw.movieFragmentInterval = kCMTimeInvalid
        aw.shouldOptimizeForNetworkUse = true
        
        //
        prepareAudioChannels(movie, ar, aw)
        prepareVideoChannels(movie, ar, aw)
        prepareOtherMediaChannels(movie, ar, aw)
        
        //
        let readyReader : Bool = ar.startReading()
        let readyWriter : Bool = aw.startWriting()
        guard readyReader && readyWriter else {
            let error = (readyReader == false) ? ar.error : aw.error
            ar.cancelReading()
            aw.cancelWriting()
            self.rwDidFinish(result: false, error: error)
            self.finalSuccess = false
            self.finalError = error
            return
        }

        // Start writing session
        let startTime : CMTime = movie.range.start
        let endTime : CMTime = movie.range.end
        aw.startSession(atSourceTime: startTime)
        
        // Allow sheet to show
        self.unblockUserInteraction?()

        //
        let dg : DispatchGroup = DispatchGroup()
        for sbc in sampleBufferChannels {
            dg.enter()
            let handler : () -> Void = { dg.leave() }
            sbc.start(with: self, completionHandler: handler)
        }
        
        let waitSem  = DispatchSemaphore(value: 0)
        dg.notify(queue: queue, execute: {[unowned self, ar, aw] in
            if self.cancelled == false { // either completed or failed
                let arFailed = (ar.status == .failed)
                if arFailed {
                    self.finalSuccess = false
                    self.finalError = ar.error
                } else {
                    // Finish writing session
                    aw.endSession(atSourceTime: endTime)
                    
                    let sem = DispatchSemaphore(value: 0)
                    aw.finishWriting(completionHandler: {
                        let awFailed = (aw.status == .failed)
                        if awFailed {
                            self.finalSuccess = false
                            self.finalError = aw.error
                        }
                        sem.signal()
                    })
                    sem.wait() // await completion
                }
            }
            
            ar.cancelReading()
            aw.cancelWriting()
            self.rwDidFinish(result: self.finalSuccess, error: self.finalError)
            waitSem.signal()
        })
        waitSem.wait()
    }
    
    public func cancelCustomMovie(_ sender : Any) {
        queue?.async {
            for sbc in self.sampleBufferChannels {
                sbc.cancel()
            }
            self.cancelled = true
        }
    }
    
    private func rwDidFinish(result success : Bool, error : Error?) {
        // run some ui related tasks in main queue
        DispatchQueue.main.async {
            // do something for gui
        }
    }
    
    internal func didRead(from channel: SampleBufferChannel, buffer: CMSampleBuffer) {
        if let updateProgress = updateProgress {
            //Swift.print("Progress:", progress)
            let progress : Float = Float(calcProgress(of: buffer))
            updateProgress(progress)
        }
        
        //if let imageBuffer : CVImageBuffer = CMSampleBufferGetImageBuffer(buffer) {
        //    if let pixelBuffer : CVPixelBuffer = imageBuffer as? CVPixelBuffer {
        //        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        //        // Pixel processing?
        //        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        //    }
        //}
        //
        //DispatchQueue.main.async {
        //    // Any GUI related processing - update GUI etc. here
        //}
    }
    
    private func calcProgress(of sampleBuffer : CMSampleBuffer) -> Float64 {
        var pts : CMTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dur : CMTime = CMSampleBufferGetDuration(sampleBuffer)
        if CMTIME_IS_NUMERIC(dur) {
            pts = pts + dur
        }
        let ptsSec : Float64 = CMTimeGetSeconds(pts)
        let lenSec : Float64 = CMTimeGetSeconds(internalMovie.range.duration)
        return (lenSec != 0.0) ? (ptsSec/lenSec) : 0.0
    }
    
    /* ============================================ */
    // MARK: - writeMovie methods
    /* ============================================ */
    
    /// Write internalMovie to destination url (as self-contained or reference movie)
    ///
    /// - Parameters:
    ///   - url: destination to write
    ///   - type: AVFileType. If it is not .mov, exportSession will be triggered.
    ///   - selfContained: Other than AVFileType.mov should be true.
    /// - Throws: Misc Error while exporting AVMovie
    public func writeMovie(to url : URL, fileType type : AVFileType, copySampleData selfContained : Bool) throws {
        // Swift.print(#function, #line, url.lastPathComponent, type.rawValue,
        //     selfContained ? "selfContained movie" : "reference movie")
        
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
    private enum FlattenMode {
        case writeSelfContaind
        case writeReferenceMovie
        case refreshMovieHeader
    }
    
    /// Flatten internal movie to destination url
    ///
    /// - Parameters:
    ///   - url: destination to write
    ///   - mode: FlattenMode
    private func flattenMovie(to url : URL, with mode : FlattenMode) throws {
        // Swift.print(#function, #line, mode.hashValue, url.path)
        
        guard writerIsBusy == false else {
            var info : [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Another exportSession is running."
            info[NSLocalizedFailureReasonErrorKey] = "Try after export session is completed."
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
        }
        
        var completed : Bool = false
        writerIsBusy = true
        defer {
            writerIsBusy = false
            Swift.print(#function, completed ? "completed" : "failed")
        }

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
