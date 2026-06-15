//
//  MovieMutator+Inspector.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Inspector utilities
/* ============================================ */

extension MovieMutatorBase {
    
    /// Inspector - mediaDataURLs
    ///
    /// - Returns: all referenced file URLs by every track samples
    public func mediaDataPaths() -> [String]? {
        if let cache = cachedMediaDataPaths {
            return cache
        }
        
        var urlStrings: [String] = []
        let urls: [URL]? = internalMovie.findReferenceURLs()
        if let urls = urls {
            urlStrings = urls.map { $0.path }
        }
        cachedMediaDataPaths = (urlStrings.count > 0 ? urlStrings : ["-"])
        return cachedMediaDataPaths
    }
    
    
    /// Inspector - VideoFPS Description
    ///
    /// - Returns: human readable description
    public func videoFPSs() -> [String]? {
        if let cache = cachedVideoFPSs {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            let trackID: Int = Int(track.trackID)
            let fps: Float = track.nominalFrameRate
            let trackString: String = String(format:"%d: %.2f fps", trackID, fps)
            trackStrings.append(trackString)
        }
        cachedVideoFPSs = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedVideoFPSs
    }
    
    /// Inspector - VideoDataSize/Rate Description
    ///
    /// - Returns: human readable description
    public func videoDataSizes() -> [String]? {
        if let cache = cachedVideoDataSizes {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            let trackID: Int = Int(track.trackID)
            let size: Int64 = track.totalSampleDataLength
            let rate: Float = track.estimatedDataRate
            let trackString: String = String(format:"%d: %.2f MB, %.3f Mbps", trackID,
                                             Float(size)/1000000.0,
                                             rate/1000000.0)
            trackStrings.append(trackString)
        }
        cachedVideoDataSizes = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedVideoDataSizes
    }
    
    /// Inspector - AudioDataSize/Rate Description
    ///
    /// - Returns: human readable description
    public func audioDataSizes() -> [String]? {
        if let cache = cachedAudioDataSizes {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .audio) {
            let trackID: Int = Int(track.trackID)
            let size: Int64 = track.totalSampleDataLength
            let rate: Float = track.estimatedDataRate
            let trackString: String = String(format:"%d: %.2f MB, %.3f Mbps", trackID,
                                             Float(size)/1000000.0,
                                             rate/1000000.0)
            trackStrings.append(trackString)
        }
        cachedAudioDataSizes = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedAudioDataSizes
    }
    
    /// Inspector - VideoFormats Description
    ///
    /// - Returns: human readable description
    public func videoFormats() -> [String]? {
        if let cache = cachedVideoFormats {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            var trackString: [String] = []
            let trackID: Int = Int(track.trackID)
            let reference: Bool = !(track.isSelfContained)
            for desc in track.formatDescriptions as! [CMVideoFormatDescription] { // CF typealias of CMFormatDescription
                var name: String = ""
                do {
                    let ext: CFPropertyList? =
                        CMFormatDescriptionGetExtension(desc,
                                                        extensionKey: kCMFormatDescriptionExtension_FormatName)
                    if let nameStr = ext as? NSString {
                        name = String(nameStr)
                    } else {
                        let fcc: FourCharCode = CMFormatDescriptionGetMediaSubType(desc)
                        let fccString: NSString = osTypeToString(fcc) as NSString
                        name = "\'\(fccString)\'"
                    }
                }
                var dimension: String = ""
                do {
                    let encoded: CGSize =
                        CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                          usePixelAspectRatio: false,
                                                                          useCleanAperture: false)
                    let prod: CGSize =
                        CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                          usePixelAspectRatio: true,
                                                                          useCleanAperture: false)
                    let clean: CGSize =
                        CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                          usePixelAspectRatio: true,
                                                                          useCleanAperture: true)
                    if encoded != prod || encoded != clean {
                        dimension = (prod == clean) ?
                            stringForTwo(encoded, prod) :
                            stringForThree(encoded, prod, clean)
                    } else {
                        dimension = stringForOne(encoded)
                    }
                }
                if reference {
                    trackString.append("\(trackID): \(name), \(dimension), Reference")
                } else {
                    trackString.append("\(trackID): \(name), \(dimension)")
                }
            }
            trackStrings.append(contentsOf: trackString)
        }
        cachedVideoFormats = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedVideoFormats
    }
    
    /// Inspector - AudioFormats Description
    ///
    /// - Returns: human readable description
    public func audioFormats() -> [String]? {
        if let cache = cachedAudioFormats {
            return cache
        }
        
        var trackStrings: [String] = []
        for track in internalMovie.tracks(withMediaType: .audio) {
            var trackString: [String] = []
            let trackID: Int = Int(track.trackID)
            let reference: Bool = !(track.isSelfContained)
            for desc in track.formatDescriptions as! [CMAudioFormatDescription] { // CF typealias of CMFormatDescription
                var rateString: String = ""
                do {
                    let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                    if let ptr = basic {
                        let rate: Float64 = ptr.pointee.mSampleRate
                        rateString = String(format:"%.3f kHz", rate/1000.0)
                    }
                }
                var formatString: String = ""
                do {
                    // get AudioStreamBasicDescription ptr
                    let asbdSize: UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                    let asbdPtr: UnsafePointer<AudioStreamBasicDescription>? =
                        CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                    if asbdPtr != nil {
                        var formatSize: UInt32 = UInt32(MemoryLayout<CFString?>.size)
                        var format: Unmanaged<CFString>? = nil
                        let err: OSStatus = withUnsafeMutablePointer(to: &format) { formatPtr in
                            AudioFormatGetProperty(kAudioFormatProperty_FormatName,
                                                   asbdSize, asbdPtr, &formatSize, formatPtr)
                        }
                        if err == noErr, let format = format {
                            formatString = format.takeUnretainedValue() as String
                        }
                    }
                }
                var layoutString: String = ""
                do {
                    let tagSize: UInt32 = UInt32(MemoryLayout<AudioChannelLayoutTag>.size)
                    var tag: AudioChannelLayoutTag = kAudioChannelLayoutTag_Unknown
                    var dataSize: UInt32 = 0
                    var data: Data? = nil
                    var err: OSStatus = noErr;
                    let item: UnsafePointer<AudioFormatListItem>? =
                        CMAudioFormatDescriptionGetMostCompatibleFormat(desc)
                    if let item = item {
                        tag = item.pointee.mChannelLayoutTag // kAudioChannelLayoutTag_Stereo //
                        err = AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForTag,
                                                         tagSize, &tag, &dataSize)
                        if err == noErr && dataSize > 0 {
                            data = Data(count: Int(dataSize))
                        }
                    }
                    data?.withUnsafeMutableBytes { (dataPtr) -> Void in
                        var aclSize: UInt32 = dataSize
                        let aclPtr: UnsafeMutableRawPointer? = dataPtr.baseAddress
                        err = AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag,
                                                     tagSize, &tag, &aclSize, aclPtr)
                        if err == noErr {
                            var nameSize: UInt32 = UInt32(MemoryLayout<CFString?>.size)
                            var name: Unmanaged<CFString>? = nil
                            err = withUnsafeMutablePointer(to: &name) { namePtr in
                                AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutName,
                                                       aclSize, aclPtr, &nameSize, namePtr)
                            }
                            if err == noErr, let name = name {
                                layoutString = name.takeUnretainedValue() as String
                            }
                        }
                    }
                }
                do {
                    var err: OSStatus = noErr;
                    var aclSize: Int = 0
                    let aclPtr: UnsafePointer<AudioChannelLayout>? =
                        CMAudioFormatDescriptionGetChannelLayout(desc, sizeOut: &aclSize)
                    if aclSize > 0, let aclPtr = aclPtr {
                        var nameSize: UInt32 = UInt32(MemoryLayout<CFString?>.size)
                        var name: Unmanaged<CFString>? = nil
                        err = withUnsafeMutablePointer(to: &name) { namePtr in
                            AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutName,
                                                   UInt32(aclSize), aclPtr, &nameSize, namePtr)
                        }
                        if err == noErr, let name = name {
                            layoutString = name.takeUnretainedValue() as String
                        }
                    }
                }
                if reference {
                    trackString.append("\(trackID): \(formatString), \(layoutString), \(rateString), Reference")
                } else {
                    trackString.append("\(trackID): \(formatString), \(layoutString), \(rateString)")
                }
            }
            trackStrings.append(contentsOf: trackString)
        }
        cachedAudioFormats = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedAudioFormats
    }
    
    // subs for UTCreateStringForOSType()
    private func osTypeToString(_ code:OSType) -> String {
        let s0 = UInt8(code >> 24 & 255)
        let s1 = UInt8(code >> 16 & 255)
        let s2 = UInt8(code >> 8  & 255)
        let s3 = UInt8(code       & 255)
        return [s0, s1, s2, s3].map{ String(UnicodeScalar($0)) }.joined()
    }
}
