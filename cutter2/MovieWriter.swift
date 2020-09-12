//
//  MovieWriter.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/08.
//  Copyright © 2018-2020年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import VideoToolbox

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

class MovieWriter: NSObject, SampleBufferChannelDelegate {
    
    public init(_ movie: AVMovie) {
        internalMovie = movie.mutableCopy() as! AVMutableMovie
    }
    
    /* ============================================ */
    // MARK: - common properties
    /* ============================================ */
    
    private var internalMovie: AVMutableMovie
    
    /// callback for NSDocument.unblockUserInteraction()
    public var unblockUserInteraction: (() -> Void)? = nil
    
    /// Progress update block
    public var updateProgress: ((Float) -> Void)? = nil
    
    /// Flag if writer is running
    public private(set) var writeInProgress: Bool = false
    
    /// Flag if writer finished successfully
    public private(set) var writeSuccess: Bool = false
    
    /// Flag if cancelled while writing
    public private(set) var writeCancelled: Bool = false
    
    /// Error result while writing
    public private(set) var writeError: Error? = nil
    
    /// Date when save/export operation start
    public private(set) var writeStart: Date? = nil
    
    /// Date when save/export operation finish
    public private(set) var writeEnd: Date? = nil
    
    /// Progress ratio of save/export operation
    public private(set) var writeProgress: Float = 0.0
    
    /* ============================================ */
    // MARK: - exportSession properties
    /* ============================================ */
    
    /// Status polling timer interval
    private let exportSessionTimerRefreshInterval: TimeInterval = 1.0/10
    
    /// ExportSession
    private var exportSession: AVAssetExportSession? = nil
    
    /// Status of last exportSession (update after finished)
    private var exportSessionStatus: AVAssetExportSession.Status = .unknown
    
    /// Status polling timer
    private var exportSessionTimer: Timer? = nil
    
    /* ============================================ */
    // MARK: - exportCustomMovie properties
    /* ============================================ */
    
    /// DispatchGroupQueue for SampleBufferChannels
    private var customQueue: DispatchQueue? = nil
    
    /// SampleBufferChannels array
    private var customSampleBufferChannels: [SampleBufferChannel] = []
    
    /// Parameter dictionary for custom exporting
    private var customParam: [String:Any] = [:]
}

/* ============================================ */
// MARK: - exportSession methods
/* ============================================ */

extension MovieWriter {
    
    /// Status update timer
    ///
    /// - Parameter timer: Timer object
    @objc dynamic func timerFireMethod(_ timer: Timer) {
        guard let session = self.exportSession, session.status == .exporting else { return }
        guard let updateProgress = updateProgress else { return }
        
        let progress: Float = session.progress
        updateProgress(progress)
        // Swift.print("#####", "Progress:", progress)
    }
    
    /// Install status polling timer on main thread
    private func exportSessionStartTimer() {
        DispatchQueue.main.sync {
            let timer = Timer.scheduledTimer(timeInterval: exportSessionTimerRefreshInterval,
                                             target: self, selector: #selector(timerFireMethod),
                                             userInfo: nil, repeats: true)
            self.exportSessionTimer = timer
        }
    }
    
    /// Uninstall status polling timer
    private func exportSessionStopTimer() {
        DispatchQueue.main.sync {
            self.exportSessionTimer?.invalidate()
            self.exportSessionTimer = nil
        }
    }
    
    /// Status string representation
    ///
    /// - Parameter status: AVAssetExportSessionStatus
    /// - Returns: String representation of status
    private func statusString(of status: AVAssetExportSession.Status) -> String {
        let statusStrArray: [String] =
            ["unknown(0)","waiting(1)","exporting(2)","completed(3)","failed(4)","cancelled(5)"]
        
        let statusRaw: Int = status.rawValue
        let statusStr: String = statusStrArray[statusRaw]
        return statusStr
    }
    
    /// Export as specified file type using AVAssetExportSessionPreset
    ///
    /// - Parameters:
    ///   - url: target url
    ///   - type: AVFileType
    ///   - preset: AVAssetExportSessionPreset. Specify nil for pass-through
    /// - Throws: Raised by any internal error
    public func exportMovie(to url: URL, fileType type: AVFileType, presetName preset: String?) throws {
        // Swift.print(#function, #line, #file)
        
        guard writeInProgress == false else {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Another exportSession is running."
            info[NSLocalizedFailureReasonErrorKey] = "Try after export session is completed."
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
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
        let valid: Bool = validateExportSession(fileType: type, presetName: preset)
        guard valid, let exportSession = AVAssetExportSession(asset: movie, presetName: preset) else {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Incompatible b/w UTI/preset is detected."
            info[NSLocalizedFailureReasonErrorKey] = "(type:" + type.rawValue + ", preset:" + preset + ") is incompatible."
            self.writeError = NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
            self.writeSuccess = false
            throw self.writeError ?? NSError()
        }
        
        // Configure exportSession
        exportSession.outputFileType = type
        exportSession.outputURL = url
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.canPerformMultiplePassesOverSourceMediaData = true
        exportSession.timeRange = movie.range
        
        //
        self.exportSession = exportSession
        
        // Start progress timer
        exportSessionStartTimer()
        defer {
            exportSessionStopTimer()
        }
        
        /* ============================================ */
        
        // Start ExportSession
        let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        let handler: () -> Void = {[semaphore, unowned self] in // @escaping
            guard let exportSession = self.exportSession else { return }
            
            // Check results
            let progress: Float = exportSession.progress
            let dateEnd: Date = Date()
            let interval: TimeInterval = dateEnd.timeIntervalSince(dateStart)
            let result: AVAssetExportSession.Status = exportSession.status
            
            // Update Properties
            self.writeSuccess = (result == .completed)
            self.writeError = exportSession.error
            self.writeCancelled = (result == .cancelled)
            self.writeStart = dateStart
            self.writeEnd = dateEnd
            self.writeProgress = progress
            self.exportSession = nil
            self.exportSessionStatus = result
            
            //
            let statusStr = self.statusString(of: result)
            let progressStr = String(format:"%.2f",progress * 100)
            let intervalStr = String(format:"%.2f",interval)
            if let error = self.writeError {
                Swift.print("#####", "result:", statusStr, "progress:", progressStr, "elapsed:", intervalStr, "error", error)
            } else {
                Swift.print("#####", "result:", statusStr, "progress:", progressStr, "elapsed:", intervalStr)
            }
            
            //
            semaphore.signal()
        }
        exportSession.exportAsynchronously(completionHandler: handler)
        semaphore.wait()
        
        //
        if writeSuccess == false, let error = writeError {
            throw error
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
    
    /// Check compatibility b/w exportSession and presetName
    ///
    /// - Parameters:
    ///   - type: target AVFileType
    ///   - preset: one of AVAssetExportSession.exportPresets()
    /// - Returns: True if compatible
    public func validateExportSession(fileType type: AVFileType, presetName preset: String?) -> Bool {
        let preset: String = (preset ?? AVAssetExportPresetPassthrough)
        let movie: AVAsset = internalMovie
        
        var compatiblePresets: [String] = AVAssetExportSession.exportPresets(compatibleWith: movie)
        compatiblePresets = compatiblePresets + [AVAssetExportPresetPassthrough]
        guard compatiblePresets.contains(preset) else {
            Swift.print("ERROR: Incompatible presetName detected.")
            return false
        }
        
        guard let exportSession: AVAssetExportSession = AVAssetExportSession(asset: movie, presetName: preset) else {
            Swift.print("ERROR: Failed to create AVAssetExportSession.")
            return false
        }
        
        let compatibleFileTypes: [AVFileType] = exportSession.supportedFileTypes
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
        var result: [String:Any] = [:]
        
        if let dateStart = self.writeStart {
            if let session = self.exportSession {
                // exportSession is running
                let progress: Float = session.progress
                let status: AVAssetExportSession.Status = session.status
                result[progressInfoKey] = progress // 0.0 - 1.0: Float
                result[statusInfoKey] = statusString(of: status)
                
                let dateNow: Date = Date()
                let interval: TimeInterval = dateNow.timeIntervalSince(dateStart)
                result[elapsedInfoKey] = interval // seconds: Double
                
                let estimatedTotal: TimeInterval = interval / Double(progress)
                let estimatedRemaining: TimeInterval = estimatedTotal * Double(1.0 - progress)
                result[estimatedRemainingInfoKey] = estimatedRemaining // seconds: Double
                result[estimatedTotalInfoKey] = estimatedTotal // seconds: Double
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

/* ============================================ */
// MARK: - exportCustomMovie methods
/* ============================================ */

extension MovieWriter {
    
    private func prepareCopyChannels(_ movie: AVMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter, _ mediaType: AVMediaType) {
        for track in movie.tracks(withMediaType: mediaType) {
            // source
            let arOutputSetting: [String:Any]? = nil
            let arOutput: AVAssetReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: arOutputSetting)
            ar.add(arOutput)
            
            // destination
            let awInputSetting: [String:Any]? = nil
            let awInput: AVAssetWriterInput = AVAssetWriterInput(mediaType: mediaType, outputSettings: awInputSetting)
            if mediaType != .audio {
                awInput.mediaTimeScale = track.naturalTimeScale
            }
            aw.add(awInput)
            
            // channel
            let copySBC: SampleBufferChannel = SampleBufferChannel(readerOutput: arOutput,
                                                                   writerInput: awInput,
                                                                   trackID: track.trackID)
            customSampleBufferChannels += [copySBC]
        }
    }
    
    private func prepareOtherMediaChannels(_ movie: AVMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) {
        let numCopyOtherMedia = customParam[kCopyOtherMediaKey] as? NSNumber
        let copyOtherMedia: Bool = numCopyOtherMedia?.boolValue ?? false
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
    
    private func prepareAudioChannels(_ movie: AVMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) {
        let numAudioEncode = customParam[kAudioEncodeKey] as? NSNumber
        let audioEncode: Bool = numAudioEncode?.boolValue ?? true
        if audioEncode == false {
            prepareCopyChannels(movie, ar, aw, .audio)
            return
        }
        
        let fourcc = customParam[kAudioCodecKey] as! NSString
        
        let numAudioKbps = customParam[kAudioKbpsKey] as? NSNumber
        let targetKbps: Float = numAudioKbps?.floatValue ?? 128
        let targetBitRate: Int = Int(targetKbps * 1000)
        
        let numLPCMDepth = customParam[kLPCMDepthKey] as? NSNumber
        let lpcmDepth: Int = numLPCMDepth?.intValue ?? 16
        
        for track in movie.tracks(withMediaType: .audio) {
            // source
            var arOutputSetting: [String:Any] = [:]
            arOutputSetting[AVFormatIDKey] = kAudioFormatLinearPCM
            let arOutput: AVAssetReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: arOutputSetting)
            ar.add(arOutput)
            
            // preseve original sampleRate, numChannel, and audioChannelLayout(best effort)
            var sampleRate = 48000
            var numChannel = 2
            var avacSrcLayout: AVAudioChannelLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)!
            var avacDstLayout: AVAudioChannelLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)!
            var aclData: Data? = nil
            
            do {
                let descArray: [Any] = track.formatDescriptions
                let desc: CMFormatDescription = descArray[0] as! CMFormatDescription
                
                let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                if let asbd = asbdPtr?.pointee {
                    sampleRate = Int(asbd.mSampleRate)
                    numChannel = Int(asbd.mChannelsPerFrame)
                }
                
                if numChannel == 1 {
                    avacSrcLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono)!
                    avacDstLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono)!
                } else if numChannel == 2 {
                    avacSrcLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)!
                    avacDstLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)!
                } else {
                    // Multi channel (surround audio) requires AudioChannelLayout
                    let conv: LayoutConverter = LayoutConverter()
                    var dataSrc: AudioChannelLayoutData? = nil
                    var dataDst: AudioChannelLayoutData? = nil
                    
                    var layoutSize: Int = 0
                    let aclPtr: UnsafePointer<AudioChannelLayout>? =
                        CMAudioFormatDescriptionGetChannelLayout(desc, sizeOut: &layoutSize)
                    if let aclPtr = aclPtr {
                        avacDstLayout = AVAudioChannelLayout(layout: aclPtr)
                        dataSrc = conv.dataFor(layoutBytes: aclPtr, size: layoutSize)
                    }
                    if let dataSrc = dataSrc {
                        // Try to translate layout as predefined tag
                        if fourcc == "lpcm" {
                            dataDst = conv.convertAsPCMTag(from: dataSrc)
                            if dataDst == nil {
                                dataDst = conv.convertAsBitmap(from: dataSrc)
                            }
                            if dataDst == nil {
                                dataDst = conv.convertAsDescriptions(from: dataSrc)
                            }
                        }
                        if fourcc == "aac " {
                            dataDst = conv.convertAsAACTag(from: dataSrc)
                        }
                    }
                    if let data1 = dataSrc, let data2 = dataDst {
                        let count1: Int = data1.count
                        data1.withUnsafeBytes {(p: UnsafeRawBufferPointer) in
                            let ptr: UnsafePointer<AudioChannelLayout> =
                                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count1)
                            avacSrcLayout = AVAudioChannelLayout(layout: ptr)
                        }
                        let count2: Int = data2.count
                        data2.withUnsafeBytes {(p: UnsafeRawBufferPointer) in
                            let ptr: UnsafePointer<AudioChannelLayout> =
                                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count2)
                            avacDstLayout = AVAudioChannelLayout(layout: ptr)
                        }
                    } else {
                        assert(false, "ERROR: Failed to convert layout")
                    }
                }
                
                //
                let acDescCount: UInt32 = avacDstLayout.layout.pointee.mNumberChannelDescriptions
                let acDescSize: Int = MemoryLayout<AudioChannelDescription>.size
                let acLayoutSize: Int = MemoryLayout<AudioChannelLayout>.size + (Int(acDescCount) - 1) * acDescSize
                aclData = Data.init(bytes: avacDstLayout.layout, count: acLayoutSize)
            }
            
            // destination
            var awInputSetting: [String:Any] = [:]
            awInputSetting[AVFormatIDKey] = UTGetOSTypeFromString(fourcc)
            awInputSetting[AVSampleRateKey] = sampleRate
            awInputSetting[AVNumberOfChannelsKey] = numChannel
            awInputSetting[AVChannelLayoutKey] = aclData
            awInputSetting[AVSampleRateConverterAlgorithmKey] = AVSampleRateConverterAlgorithm_Normal
            //awInputSetting[AVSampleRateConverterAudioQualityKey] = AVAudioQuality.medium
            
            if fourcc == "lpcm" {
                awInputSetting[AVLinearPCMIsBigEndianKey] = false
                awInputSetting[AVLinearPCMIsFloatKey] = false
                awInputSetting[AVLinearPCMBitDepthKey] = lpcmDepth
                awInputSetting[AVLinearPCMIsNonInterleaved] = false
            } else {
                awInputSetting[AVEncoderBitRateKey] = targetBitRate
                awInputSetting[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_LongTermAverage
                //awInputSetting[AVEncoderAudioQualityKey] = AVAudioQuality.medium
            }
            
            // Validate bitrate
            if let _ = awInputSetting[AVEncoderBitRateKey] {
                let inFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate),
                                             channelLayout: avacSrcLayout)
                let outFormat = AVAudioFormat(settings: awInputSetting)!
                let converter = AVAudioConverter(from: inFormat, to: outFormat)!
                let bitrateArray = converter.applicableEncodeBitRates!.map{($0).intValue}
                if bitrateArray.contains(targetBitRate) == false {
                    // bitrate adjustment
                    var prev = bitrateArray.first!
                    for item in bitrateArray {
                        if item > targetBitRate { break }
                        prev = item
                    }
                    awInputSetting[AVEncoderBitRateKey] = prev
                    // Swift.print("#####", "Bitrate adjustment to", prev, "from", targetBitRate)
                }
            }
            
            let awInput: AVAssetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: awInputSetting)
            // awInput.mediaTimeScale = track.naturalTimeScale // Audio track is unable to change
            aw.add(awInput)
            
            // channel
            let audioSBC: SampleBufferChannel = SampleBufferChannel(readerOutput: arOutput,
                                                                    writerInput: awInput,
                                                                    trackID: track.trackID)
            customSampleBufferChannels += [audioSBC]
        } // for track in movie.tracks(withMediaType: .audio)
    }
    
    private func hasFieldModeSupport(of track: AVMovieTrack) -> Bool {
        let descArray: [Any] = track.formatDescriptions
        guard descArray.count > 0 else { return false }
        
        let desc: CMFormatDescription = descArray[0] as! CMFormatDescription
        var dict: CFDictionary? = nil
        do {
            var status: OSStatus = noErr
            let spec: NSMutableDictionary? = nil
            //var spec: NSMutableDictionary? = nil
            //spec = NSMutableDictionary()
            //spec![kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder] = false
            var decompSession: VTDecompressionSession? = nil
            status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                  formatDescription: desc,
                                                  decoderSpecification: spec,
                                                  imageBufferAttributes: nil,
                                                  outputCallback: nil,
                                                  decompressionSessionOut: &decompSession)
            guard status == noErr else { return false }
            
            defer { VTDecompressionSessionInvalidate(decompSession!) }
            
            status = VTSessionCopySupportedPropertyDictionary(decompSession!,
                                                              supportedPropertyDictionaryOut: &dict)
            guard status == noErr else { return false }
        }
        
        if let dict = dict as? [NSString:Any] {
            if let propFieldMode = dict[kVTDecompressionPropertyKey_FieldMode] as? [NSString:Any] {
                if let propList = propFieldMode[kVTPropertySupportedValueListKey] as? [NSString] {
                    let hasDF = propList.contains(kVTDecompressionProperty_FieldMode_DeinterlaceFields)
                    let hasBF = propList.contains(kVTDecompressionProperty_FieldMode_BothFields)
                    return (hasDF && hasBF)
                }
            }
        }
        return false
    }
    
    private func addDecompressionProperties(_ track: AVMovieTrack, _ copyField: Bool, _ arOutputSetting: inout [String:Any]) {
        if #available(OSX 10.13, *), hasFieldModeSupport(of: track) {
            var decompressionProperties: NSDictionary? = nil
            if copyField {
                // Keep both fields
                // Swift.print("#####", "Decoder: FieldMode_BothFields")
                let dict: NSMutableDictionary = NSMutableDictionary()
                dict[kVTDecompressionPropertyKey_FieldMode] = kVTDecompressionProperty_FieldMode_BothFields
                decompressionProperties = (dict.copy() as! NSDictionary)
            } else {
                // Allow deinterlace - only DV decoder works...?
                // Swift.print("#####", "Decoder: FieldMode_DeinterlaceFields")
                let dict: NSMutableDictionary = NSMutableDictionary()
                dict[kVTDecompressionPropertyKey_FieldMode] = kVTDecompressionProperty_FieldMode_DeinterlaceFields
                dict[kVTDecompressionPropertyKey_DeinterlaceMode] = kVTDecompressionProperty_DeinterlaceMode_VerticalFilter
                decompressionProperties = (dict.copy() as! NSDictionary)
            }
            
            arOutputSetting[AVVideoDecompressionPropertiesKey] = decompressionProperties
        }
    }
    
    private func prepareVideoChannels(_ movie: AVMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) {
        let numVideoEncode = customParam[kVideoEncodeKey] as? NSNumber
        let videoEncode: Bool = numVideoEncode?.boolValue ?? true
        if videoEncode == false {
            prepareCopyChannels(movie, ar, aw, .video)
            return
        }
        
        let fourcc = customParam[kVideoCodecKey] as! NSString
        
        let numVideoKbps = customParam[kVideoKbpsKey] as? NSNumber
        let targetKbps: Float = numVideoKbps?.floatValue ?? 2500
        let targetBitRate: Int = Int(targetKbps*1000)
        
        let numCopyField = customParam[kCopyFieldKey] as? NSNumber
        let copyField: Bool = numCopyField?.boolValue ?? false
        
        let numCopyNCLC = customParam[kCopyNCLCKey] as? NSNumber
        let copyNCLC: Bool = numCopyNCLC?.boolValue ?? false
        
        for track in movie.tracks(withMediaType: .video) {
            // source
            var arOutputSetting: [String:Any] = [:]
            addDecompressionProperties(track, copyField, &arOutputSetting)
            arOutputSetting[String(kCVPixelBufferPixelFormatTypeKey)] = kCVPixelFormatType_422YpCbCr8
            let arOutput: AVAssetReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: arOutputSetting)
            ar.add(arOutput)
            
            //
            var compressionProperties: NSDictionary? = nil
            if ["ap4h","apch","apcn","apcs","apco"].contains(fourcc) {
                // ProRes family
            } else {
                compressionProperties = [AVVideoAverageBitRateKey:targetBitRate]
            }
            
            var cleanAperture: NSDictionary? = nil
            var pixelAspectRatio: NSDictionary? = nil
            var nclc: NSDictionary? = nil
            
            var trackDimensions = track.naturalSize
            let descArray: [Any] = track.formatDescriptions
            if descArray.count > 0 {
                let desc: CMFormatDescription = descArray[0] as! CMFormatDescription
                trackDimensions = CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                                    usePixelAspectRatio: false,
                                                                                    useCleanAperture: false)
                
                var fieldCount: NSNumber? = nil
                var fieldDetail: NSString? = nil
                
                let extCA: CFPropertyList? =
                    CMFormatDescriptionGetExtension(desc,
                                                    extensionKey: kCMFormatDescriptionExtension_CleanAperture)
                if let extCA = extCA {
                    let width = extCA[kCMFormatDescriptionKey_CleanApertureWidth] as! NSNumber
                    let height = extCA[kCMFormatDescriptionKey_CleanApertureHeight] as! NSNumber
                    let wOffset = extCA[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] as! NSNumber
                    let hOffset = extCA[kCMFormatDescriptionKey_CleanApertureVerticalOffset] as! NSNumber
                    
                    let dict: NSMutableDictionary = NSMutableDictionary()
                    dict[AVVideoCleanApertureWidthKey] = width
                    dict[AVVideoCleanApertureHeightKey] = height
                    dict[AVVideoCleanApertureHorizontalOffsetKey] = wOffset
                    dict[AVVideoCleanApertureVerticalOffsetKey] = hOffset
                    
                    cleanAperture = dict
                }
                
                let extPA: CFPropertyList? =
                    CMFormatDescriptionGetExtension(desc,
                                                    extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio)
                if let extPA = extPA {
                    let hSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as! NSNumber
                    let vSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as! NSNumber
                    
                    let dict: NSMutableDictionary = NSMutableDictionary()
                    dict[AVVideoPixelAspectRatioHorizontalSpacingKey] = hSpacing
                    dict[AVVideoPixelAspectRatioVerticalSpacingKey] = vSpacing
                    
                    pixelAspectRatio = dict
                }
                
                if copyNCLC {
                    let extCP: CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc,
                                                        extensionKey: kCMFormatDescriptionExtension_ColorPrimaries)
                    let extTF: CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc,
                                                        extensionKey: kCMFormatDescriptionExtension_TransferFunction)
                    let extMX: CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc,
                                                        extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix)
                    if let extCP  = extCP, let extTF = extTF, let extMX = extMX {
                        let colorPrimaries = extCP as! NSString
                        let transferFunction = extTF as! NSString
                        let ycbcrMatrix = extMX as! NSString
                        
                        let dict: NSMutableDictionary = NSMutableDictionary()
                        dict[AVVideoColorPrimariesKey] = colorPrimaries
                        dict[AVVideoTransferFunctionKey] = transferFunction
                        dict[AVVideoYCbCrMatrixKey] = ycbcrMatrix
                        
                        nclc = dict
                    }
                }
                
                if copyField {
                    let extFC: CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc,
                                                        extensionKey: kCMFormatDescriptionExtension_FieldCount)
                    let extFD: CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc,
                                                        extensionKey: kCMFormatDescriptionExtension_FieldDetail)
                    if let extFC = extFC, let extFD = extFD {
                        fieldCount = (extFC as! NSNumber)
                        fieldDetail = (extFD as! NSString)
                    }
                }
                
                if fieldCount != nil || fieldDetail != nil {
                    let dict: NSMutableDictionary = NSMutableDictionary()
                    
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
            var awInputSetting: [String:Any] = [:]
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
            
            let awInput: AVAssetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: awInputSetting)
            awInput.mediaTimeScale = track.naturalTimeScale
            aw.add(awInput)
            
            // channel
            let videoSBC: SampleBufferChannel = SampleBufferChannel(readerOutput: arOutput,
                                                                    writerInput: awInput,
                                                                    trackID: track.trackID)
            customSampleBufferChannels += [videoSBC]
        } // for track in movie.tracks(withMediaType: .video)
    }
    
    public func exportCustomMovie(to url: URL, fileType type: AVFileType, settings param: [String:Any]) throws {
        // Swift.print(#function, #line, #file)
        
        guard writeInProgress == false else {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Another exportSession is running."
            info[NSLocalizedFailureReasonErrorKey] = "Try after export session is completed."
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
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
        
        let dgQueue: DispatchQueue = DispatchQueue(label: "exportCustomMovie")
        self.customParam = param
        self.customQueue = dgQueue
        self.customSampleBufferChannels = []
        
        //
        self.unblockUserInteraction?()
        
        // Issue start notification
        let userInfoStart: [AnyHashable:Any] = [urlInfoKey:url,
                                                startInfoKey:dateStart]
        let notificationStart = Notification(name: .movieWillExportCustom,
                                             object: self, userInfo: userInfoStart)
        NotificationCenter.default.post(notificationStart)
        
        /* ============================================ */
        
        // Prepare assetReader/assetWriter
        let movie: AVMutableMovie = internalMovie
        let startTime: CMTime = movie.range.start
        let endTime: CMTime = movie.range.end
        var ar: AVAssetReader
        var aw: AVAssetWriter
        do {
            let assetReader: AVAssetReader? = try AVAssetReader(asset: movie)
            let assetWriter: AVAssetWriter? = try AVAssetWriter(url: url, fileType: type)
            if let assetReader = assetReader, let assetWriter = assetWriter {
                ar = assetReader
                aw = assetWriter
            } else {
                var info: [String:Any] = [:]
                info[NSLocalizedDescriptionKey] = "Internal error"
                info[NSLocalizedFailureReasonErrorKey] = "Either AVAssetReader or AVAssetWriter is not available."
                self.writeError = NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
                self.writeSuccess = false
                throw self.writeError ?? NSError()
            }
        } catch {
            self.writeError = error
            self.writeSuccess = false
            throw self.writeError ?? NSError()
        }
        
        // Configure assetReader/assetWriter
        do {
            // setup aw parameters here
            aw.movieTimeScale = movie.timescale
            aw.movieFragmentInterval = CMTime.invalid
            aw.shouldOptimizeForNetworkUse = true
            
            // setup sampleBufferChannels for each track
            prepareAudioChannels(movie, ar, aw)
            prepareVideoChannels(movie, ar, aw)
            prepareOtherMediaChannels(movie, ar, aw)
            
            // setup assetReader/assetWriter
            let readyReader: Bool = ar.startReading()
            let readyWriter: Bool = aw.startWriting()
            guard readyReader && readyWriter else {
                let error = (readyReader == false) ? ar.error : aw.error
                ar.cancelReading()
                aw.cancelWriting()
                self.writeError = error
                self.writeSuccess = false
                throw error ?? NSError()
            }
        }
        
        /* ============================================ */
        
        // Start actual writing session
        aw.startSession(atSourceTime: startTime)
        
        // Start sampleBufferChannel as DispatchGroup
        let dg: DispatchGroup = DispatchGroup()
        for sbc in customSampleBufferChannels {
            dg.enter()
            let handler: () -> Void = { [dg] in dg.leave() } // @escaping
            sbc.start(with: self, completionHandler: handler)
        }
        
        // Wait the completion of DispatchGroup
        let semaphore  = DispatchSemaphore(value: 0)
        dg.notify(queue: dgQueue) {[semaphore, ar, aw, unowned self] in // @escaping
            var success: Bool = false
            let cancel: Bool = self.writeCancelled
            var error: Error? = nil
            
            // Cancel assetReader/Writer if required
            if cancel {
                ar.cancelReading()
                aw.cancelWriting()
            }
            
            // Finish writing session - blocking
            let sem = DispatchSemaphore(value: 0)
            aw.endSession(atSourceTime: endTime)
            aw.finishWriting { [sem] in // @escaping
                sem.signal()
            }
            sem.wait() // await completion
            
            // Verify status from assetReader/Writer
            if (ar.status == .completed && aw.status == .completed) {
                success = true
            } else {
                if (ar.status == .failed) {
                    success = false
                    error = ar.error
                } else if (aw.status == .failed) {
                    success = false
                    error = aw.error
                } else {
                    success = false
                }
            }
            
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
            self.writeProgress = progress
            
            //
            let status = (success ? "completed" : (cancel ? "cancelled" : "failed"))
            let progressStr = String(format:"%.2f",progress * 100)
            let intervalStr = String(format:"%.2f",interval)
            if let error = self.writeError {
                Swift.print("#####", "result:", status, "progress:", progressStr, "elapsed:", intervalStr, "error", error)
            } else {
                Swift.print("#####", "result:", status, "progress:", progressStr, "elapsed:", intervalStr)
            }
            
            //
            semaphore.signal()
        }
        semaphore.wait()
        
        //
        if writeSuccess == false, let error = writeError {
            throw error
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
        let notificationEnd = Notification(name: .movieDidExportCustom,
                                           object: self, userInfo: userInfoEnd)
        NotificationCenter.default.post(notificationEnd)
    }
    
    public func cancelCustomMovie(_ sender: Any) {
        customQueue?.async { [unowned self] in // @escaping
            for sbc in self.customSampleBufferChannels {
                sbc.cancel()
            }
            self.writeCancelled = true
        }
    }
    
    // SampleBufferChannelDelegate
    public func didRead(from channel: SampleBufferChannel, buffer: CMSampleBuffer) {
        if let updateProgress = updateProgress {
            let progress: Float = Float(calcProgress(of: buffer))
            updateProgress(progress)
            // Swift.print("#####", "Progress:", progress)
        }
        
        //if let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(buffer) {
        //    if let pixelBuffer: CVPixelBuffer = imageBuffer as? CVPixelBuffer {
        //        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        //        // Pixel processing?
        //        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        //    }
        //}
        //
        //DispatchQueue.main.async { [unowned self] in // @escaping
        //    // Any GUI related processing - update GUI etc. here
        //}
    }
    
    private func calcProgress(of sampleBuffer: CMSampleBuffer) -> Float64 {
        var pts: CMTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dur: CMTime = CMSampleBufferGetDuration(sampleBuffer)
        if CMTIME_IS_NUMERIC(dur) {
            pts = pts + dur
        }
        let ptsSec: Float64 = CMTimeGetSeconds(pts)
        let lenSec: Float64 = CMTimeGetSeconds(internalMovie.range.duration)
        return (lenSec != 0.0) ? (ptsSec/lenSec) : 0.0
    }
}

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
    public func writeMovie(to url: URL, fileType type: AVFileType, copySampleData selfContained: Bool) throws {
        // Swift.print(#function, #line, #file, url.lastPathComponent, type.rawValue,
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
    
    /// Flatten internal movie to destination url
    ///
    /// - Parameters:
    ///   - url: destination to write
    ///   - mode: FlattenMode
    private func flattenMovie(to url: URL, with mode: FlattenMode) throws {
        // Swift.print(#function, #line, #file)
        
        guard writeInProgress == false else {
            var info: [String:Any] = [:]
            info[NSLocalizedDescriptionKey] = "Another exportSession is running."
            info[NSLocalizedFailureReasonErrorKey] = "Try after export session is completed."
            throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: info)
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
            Swift.print("ERROR: Failed to create proxy object.")
            assert(false, #function);
            return
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
                Swift.print("#####", "result:", status, "progress:", progressStr, "elapsed:", intervalStr, "error", error)
            } else {
                Swift.print("#####", "result:", status, "progress:", progressStr, "elapsed:", intervalStr)
            }
        } catch {
            self.writeError = error
            self.writeSuccess = false
            throw self.writeError ?? NSError()
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
