//
//  MovieWriter+CustomExport.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import VideoToolbox
import os.log

/* ============================================ */
// MARK: - exportCustomMovie methods
/* ============================================ */

extension MovieWriter {
    
    private typealias LayoutPtr = UnsafePointer<AudioChannelLayout>
    private typealias ASBDPtr = UnsafePointer<AudioStreamBasicDescription>
    
    private func prepareCopyChannels(_ movie: AVMutableMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter, _ mediaType: AVMediaType) {
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
    
    private func prepareOtherMediaChannels(_ movie: AVMutableMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) {
        let numCopyOtherMedia = customParam[kCopyOtherMediaKey] as? NSNumber
        let copyOtherMedia: Bool = numCopyOtherMedia?.boolValue ?? false
        guard copyOtherMedia else { return }
        
        // Copy non-av media type (excludes muxed media)
        prepareCopyChannels(movie, ar, aw, .text)
        prepareCopyChannels(movie, ar, aw, .closedCaption)
        prepareCopyChannels(movie, ar, aw, .subtitle)
        prepareCopyChannels(movie, ar, aw, .timecode)
        prepareCopyChannels(movie, ar, aw, .metadata)
        prepareCopyChannels(movie, ar, aw, .depthData)
    }
    
    private func prepareAudioChannels(_ movie: AVMutableMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) throws {
        let numAudioEncode = customParam[kAudioEncodeKey] as? NSNumber
        let audioEncode: Bool = numAudioEncode?.boolValue ?? true
        if audioEncode == false {
            prepareCopyChannels(movie, ar, aw, .audio)
            return
        }
        
        guard let fourcc = customParam[kAudioCodecKey] as? NSString else {
            preconditionFailure("kAudioCodecKey not set in customParam")
        }
        
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
                guard descArray.count > 0 else { continue }
                let desc: CMFormatDescription = descArray[0] as! CMFormatDescription // CF typealias
                
                let asbdPtr: ASBDPtr? = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
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
                    let aclPtr: LayoutPtr? = CMAudioFormatDescriptionGetChannelLayout(desc, sizeOut: &layoutSize)
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
                        data1.withUnsafeBytes {(p: UnsafeRawBufferPointer) in
                            guard let baseAddress: UnsafeRawPointer = p.baseAddress else { preconditionFailure("ERROR: Invalid AudioChannelLayoutData") }
                            let ptr: LayoutPtr = baseAddress.bindMemory(to: AudioChannelLayout.self, capacity: 1)
                            avacSrcLayout = AVAudioChannelLayout(layout: ptr)
                        }
                        data2.withUnsafeBytes {(p: UnsafeRawBufferPointer) in
                            guard let baseAddress: UnsafeRawPointer = p.baseAddress else { preconditionFailure("ERROR: Invalid AudioChannelLayoutData") }
                            let ptr: LayoutPtr = baseAddress.bindMemory(to: AudioChannelLayout.self, capacity: 1)
                            avacDstLayout = AVAudioChannelLayout(layout: ptr)
                            numChannel = Int(avacDstLayout.channelCount)
                        }
                    } else {
                        preconditionFailure("ERROR: Failed to convert layout")
                    }
                }
                
                //
                aclData = LayoutConverter().dataFor(layoutBytes: avacDstLayout.layout)
            }
            
            // destination
            var awInputSetting: [String:Any] = [:]
            awInputSetting[AVFormatIDKey] = stringToOSType(fourcc as String)
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
                guard let outFormat = AVAudioFormat(settings: awInputSetting),
                      let converter = AVAudioConverter(from: inFormat, to: outFormat),
                      let bitrates = converter.applicableEncodeBitRates
                else {
                    try throwError(.movieWriterFailed, reason: "Invalid audio format/converter settings")
                }
                let bitrateArray = bitrates.map { $0.intValue }
                if bitrateArray.contains(targetBitRate) == false {
                    // bitrate adjustment
                    var prev = bitrateArray.first!
                    for item in bitrateArray {
                        if item > targetBitRate { break }
                        prev = item
                    }
                    awInputSetting[AVEncoderBitRateKey] = prev
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
    
    private func hasFieldModeSupport(of track: AVMutableMovieTrack) -> Bool {
        let descArray: [Any] = track.formatDescriptions
        guard descArray.count > 0 else { return false }
        let desc: CMFormatDescription = descArray[0] as! CMFormatDescription // CF typealias
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
            guard status == noErr, let session = decompSession else { return false }

            defer { VTDecompressionSessionInvalidate(session) }

            status = VTSessionCopySupportedPropertyDictionary(session,
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
    
    private func addDecompressionProperties(_ track: AVMutableMovieTrack, _ copyField: Bool, _ arOutputSetting: inout [String:Any]) {
        if hasFieldModeSupport(of: track) {
            var decompressionProperties: NSDictionary? = nil
            if copyField {
                // Keep both fields
                let dict: NSMutableDictionary = NSMutableDictionary()
                dict[kVTDecompressionPropertyKey_FieldMode] = kVTDecompressionProperty_FieldMode_BothFields
                decompressionProperties = (dict.copy() as! NSDictionary) // NSMutableDictionary copy to NSDictionary
            } else {
                // Allow deinterlace - only DV decoder works...?
                let dict: NSMutableDictionary = NSMutableDictionary()
                dict[kVTDecompressionPropertyKey_FieldMode] = kVTDecompressionProperty_FieldMode_DeinterlaceFields
                dict[kVTDecompressionPropertyKey_DeinterlaceMode] = kVTDecompressionProperty_DeinterlaceMode_VerticalFilter
                decompressionProperties = (dict.copy() as! NSDictionary) // NSMutableDictionary copy to NSDictionary
            }
            
            arOutputSetting[AVVideoDecompressionPropertiesKey] = decompressionProperties
        }
    }
    
    private func prepareVideoChannels(_ movie: AVMutableMovie, _ ar: AVAssetReader, _ aw: AVAssetWriter) {
        let numVideoEncode = customParam[kVideoEncodeKey] as? NSNumber
        let videoEncode: Bool = numVideoEncode?.boolValue ?? true
        if videoEncode == false {
            prepareCopyChannels(movie, ar, aw, .video)
            return
        }
        
        guard let fourcc = customParam[kVideoCodecKey] as? NSString else {
            preconditionFailure("kVideoCodecKey not set in customParam")
        }
        
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
                let desc: CMFormatDescription = descArray[0] as! CMFormatDescription // CF typealias
                trackDimensions = CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                                    usePixelAspectRatio: false,
                                                                                    useCleanAperture: false)
                
                var fieldCount: NSNumber? = nil
                var fieldDetail: NSString? = nil
                
                let extCA: CFPropertyList? =
                    CMFormatDescriptionGetExtension(desc,
                                                    extensionKey: kCMFormatDescriptionExtension_CleanAperture)
                if let extCA = extCA,
                   let width = extCA[kCMFormatDescriptionKey_CleanApertureWidth] as? NSNumber,
                   let height = extCA[kCMFormatDescriptionKey_CleanApertureHeight] as? NSNumber,
                   let wOffset = extCA[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] as? NSNumber,
                   let hOffset = extCA[kCMFormatDescriptionKey_CleanApertureVerticalOffset] as? NSNumber {
                    
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
                if let extPA = extPA,
                   let hSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as? NSNumber,
                   let vSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as? NSNumber {
                    
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
                        if let colorPrimaries = extCP as? NSString,
                            let transferFunction = extTF as? NSString,
                            let ycbcrMatrix = extMX as? NSString {
                        
                        let dict: NSMutableDictionary = NSMutableDictionary()
                        dict[AVVideoColorPrimariesKey] = colorPrimaries
                        dict[AVVideoTransferFunctionKey] = transferFunction
                        dict[AVVideoYCbCrMatrixKey] = ycbcrMatrix
                        
                        nclc = dict
                        }
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
                        fieldCount = (extFC as? NSNumber)
                        fieldDetail = (extFD as? NSString)
                    }
                }
                
                if fieldCount != nil || fieldDetail != nil {
                    let dict: NSMutableDictionary = NSMutableDictionary()
                    
                    if copyField, let fieldCount = fieldCount, let fieldDetail = fieldDetail {
                        dict[kVTCompressionPropertyKey_FieldCount] = fieldCount
                        dict[kVTCompressionPropertyKey_FieldDetail] = fieldDetail
                    }
                    
                    if let compressionProperties = compressionProperties {
                        if let props = compressionProperties as? [AnyHashable:Any] {
                            dict.addEntries(from: props)
                        }
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
    
    private func exportCustomMovieCore(ar: AVAssetReader, aw: AVAssetWriter,
                                       startTime: CMTime, endTime: CMTime,
                                       dateStart: Date) async {
        // Start the writing session on the asset writer.
        aw.startSession(atSourceTime: startTime)
        
        // Process sample buffer channels concurrently
        await withTaskGroup(of: Void.self) { group in
            for sbc in customSampleBufferChannels {
                group.addTask { @Sendable in
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        sbc.start(with: self) {
                            continuation.resume()
                        }
                    }
                }
            }
            for await _ in group { }
        }
        
        // Check for cancellation.
        let cancel = self.writeCancelled
        if cancel {
            ar.cancelReading()
            aw.cancelWriting()
            // Note: After cancelWriting(), the writer is in .cancelled state and
            // no further methods (endSession, finishWriting) should be called.
            // cancelWriting() already performs cleanup.
        } else {
            // Normal completion flow
            aw.endSession(atSourceTime: endTime)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                aw.finishWriting { @Sendable in
                    continuation.resume()
                }
            }
        }
        
        // Evaluate success or failure.
        var success = false
        var error: Error? = nil
        if ar.status == .completed && aw.status == .completed {
            success = true
        } else {
            if ar.status == .failed {
                error = ar.error
            } else if aw.status == .failed {
                error = aw.error
            }
            success = false
        }
        
        // Calculate final progress and elapsed time.
        let progress: Float = 1.0
        let dateEnd: Date = Date()
        let interval: TimeInterval = dateEnd.timeIntervalSince(dateStart)
        
        // Update export properties.
        self.writeSuccess  = success
        self.writeError    = error
        self.writeCancelled = cancel
        self.writeStart    = dateStart
        self.writeEnd      = dateEnd
        self.writeProgress = progress
        
        // Log the result for debugging.
        let statusStr = success ? "completed" : (cancel ? "cancelled" : "failed")
        let progressStr = String(format: "%.2f", progress * 100)
        let intervalStr = String(format: "%.2f", interval)
        if let error = self.writeError {
            LoggingSystem.export.error("Result: \(statusStr), progress: \(progressStr), elapsed: \(intervalStr), error: \(error)")
        } else {
            LoggingSystem.export.notice("Result: \(statusStr), progress: \(progressStr), elapsed: \(intervalStr)")
        }
    }
    
    public func exportCustomMovie(to url: URL, fileType type: AVFileType, settings param: [String: any Sendable]) async throws {
        
        // Check that no export is already running.
        guard writeInProgress == false else {
            let reason = "Please wait until the current export session finishes."
            try throwError(.anotherExportSessionRunning, reason: reason)
        }
        defer {
            writeInProgress = false
        }
        
        /* ============================================ */
        
        // Set up initial export state.
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
        
        // Unblock user interaction.
        self.unblockUserInteraction?()
        
        // Notify that export is starting.
        let userInfoStart: [AnyHashable:Any] = [urlInfoKey:url,
                                                startInfoKey:dateStart]
        let notificationStart = Notification(name: .movieWillExportCustom,
                                             object: self, userInfo: userInfoStart)
        NotificationCenter.default.post(notificationStart)
        
        /* ============================================ */
        
        // Initialize asset reader and writer.
        let movie: AVMutableMovie = internalMovie
        let startTime: CMTime = movie.range.start
        let endTime: CMTime = movie.range.end
        var ar: AVAssetReader
        var aw: AVAssetWriter
        do {
            ar = try AVAssetReader(asset: movie)
            aw = try AVAssetWriter(url: url, fileType: type)
        } catch {
            try throwError(.assetReaderWriterUnavailable, reason: "Failed to create AVAssetReader or AVAssetWriter.")
        }
        
        // Configure asset reader and writer.
        do {
            // Set writer parameters.
            aw.movieTimeScale = movie.timescale
            aw.movieFragmentInterval = CMTime.invalid
            aw.shouldOptimizeForNetworkUse = true
            
            // Prepare media channels.
            try prepareAudioChannels(movie, ar, aw)
            prepareVideoChannels(movie, ar, aw)
            prepareOtherMediaChannels(movie, ar, aw)
            
            // Begin reading and writing.
            let readyReader: Bool = ar.startReading()
            let readyWriter: Bool = aw.startWriting()
            guard readyReader && readyWriter else {
                let error = (readyReader == false) ? ar.error : aw.error
                ar.cancelReading()
                aw.cancelWriting()
                try throwError(.assetReaderWriterFailed, reason: error.debugDescription)
            }
        }
        
        /* ============================================ */
        
        // Export using the async method.
        await exportCustomMovieCore(ar: ar, aw: aw, startTime: startTime, endTime: endTime, dateStart: dateStart)

        // If export failed, throw the error.
        if writeSuccess == false {
            if writeCancelled {
                try throwError(.operationCancelled, reason: "Export was cancelled by the user.")
            } else if let error = writeError {
                throw error
            } else {
                try throwError(.movieWriterFailed, reason: "Export failed without an error.")
            }
        }
        
        /* ============================================ */
        
        // Notify that export has finished.
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
    
    /// Cancel ongoing custom export operation
    ///
    /// This method cancels a custom export operation if one is in progress.
    /// It is safe to call even if no custom export is active (customQueue will be nil).
    ///
    /// Design Notes:
    /// - writeCancelled is set BEFORE dispatching channel cancellations for two
    ///   reasons:
    ///     1. It suppresses duplicate dispatches: the `if writeCancelled == false`
    ///        check inside cancelCustomMovie() short-circuits repeated Cancel
    ///        button presses, so the SampleBufferChannel queue only sees one
    ///        cancel pass.
    ///     2. After the export's withTaskGroup completes, the value of
    ///        writeCancelled (read from the actor) selects between the cancel
    ///        path (ar.cancelReading() + aw.cancelWriting()) and the normal
    ///        completion path (aw.endSession + aw.finishWriting).
    /// - The async dispatch is intentionally retained (not sync) because sbc.cancel()
    ///   dispatches to SampleBufferChannel's own queue; sync would risk deadlock.
    ///
    public func cancelCustomMovie() {
        // Only proceed if a custom export is actually in progress
        guard let customQueue = customQueue else { return }
        if writeCancelled == false {
            writeCancelled = true
            let params = cancelParams(channels: customSampleBufferChannels)
            customQueue.async { @Sendable in // @escaping
                for sbc in params.channels {
                    sbc.cancel()
                }
            }
        }
    }
    
    private struct cancelParams: @unchecked Sendable {
        let channels: [SampleBufferChannel]
    }
    
    // SampleBufferChannelDelegate
    nonisolated public func didRead(from channel: SampleBufferChannel, buffer: CMSampleBuffer) {
        let params = didReadParams(channel: channel, buffer: buffer)
        Task { @Sendable in
            await self.didReadCore(params)
        }
    }
    
    private func didReadCore(_ params: didReadParams) {
        let buffer = params.buffer
        let progress: Float = Float(calcProgress(of: buffer))
        
        // Send progress to AsyncStream
        progressContinuation?.yield(progress)
        
        //if let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(buffer) {
        //    if let pixelBuffer: CVPixelBuffer = imageBuffer as? CVPixelBuffer {
        //        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        //        // Pixel processing?
        //        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        //    }
        //}
        //
        //Task { @Sendable [weak self] in // @escaping
        //    // Any GUI related processing - update GUI etc. here
        //}
    }
    
    private struct didReadParams: @unchecked Sendable {
        let channel: SampleBufferChannel
        let buffer: CMSampleBuffer
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
    
    // subs for UTGetOSTypeFromString()
    private func stringToOSType(_ type:String) -> OSType {
        guard type.count == 4 else { return 0 }
        let code:[UInt8] = type.map{ $0.asciiValue ?? UInt8(0) }
        let v0 = UInt32(code[0])
        let v1 = UInt32(code[1])
        let v2 = UInt32(code[2])
        let v3 = UInt32(code[3])
        return (v0 << 24) | (v1 << 16) | (v2 << 8) | v3
    }
}
