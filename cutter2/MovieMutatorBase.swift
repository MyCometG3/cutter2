//
//  MovieMutatorBase.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/04.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVKit
import AVFoundation

// MovieMutatorBase + Document
let timeValueInfoKey : String = "timeValue" // CMTime
let timeRangeValueInfoKey : String = "timeRangeValue" // CMTimeRange

// MovieMutator + MovieMutatorBase + CAPARViewController
let clapSizeKey : String = "clapSize" // NSSize
let clapOffsetKey : String = "clapOffset" // NSPoint
let paspRatioKey : String = "paspRatio" // NSSize
let dimensionsKey : String = "dimensions" // NSSize

extension Notification.Name {
    static let movieWasMutated = Notification.Name("movieWasMutated")
    static let movieWillExportSession = Notification.Name("movieWillExportSession")
    static let movieDidExportSession = Notification.Name("movieDidExportSession")
    static let movieWillWriteHeaderOnly = Notification.Name("movieWillWriteHeaderOnly")
    static let movieDidWriteHeaderOnly = Notification.Name("movieDidWriteHeaderOnly")
    static let movieWillWriteWithData = Notification.Name("movieWillWriteWithData")
    static let movieDidWriteWithData = Notification.Name("movieDidWriteWithData")
    static let movieWillRefreshHeader = Notification.Name("movieWillRefreshHeader")
    static let movieDidRefreshHeader = Notification.Name("movieDidRefreshHeader")
}

extension AVMovie {
    /// Movie timeRange (union of all track range)
    ///
    /// NOTE: See MovieMutator.refreshMovie()
    public var range : CMTimeRange {
        var range : CMTimeRange = kCMTimeRangeZero
        for track : AVMovieTrack in self.tracks {
            range = CMTimeRangeGetUnion(range, track.timeRange)
        }
        return range
    }
}

public struct boxSize {
    var headerSize : Int64 = 0
    var videoSize : Int64 = 0, videoCount : Int64 = 0
    var audioSize : Int64 = 0, audioCount : Int64 = 0
    var otherSize : Int64 = 0, otherCount : Int64 = 0
}

private let clipPBoardTypeRaw : String = "com.mycometg3.cutter.MovieMutator"
internal let clipPBoardType : NSPasteboard.PasteboardType = NSPasteboard.PasteboardType(rawValue: clipPBoardTypeRaw)

/// type of dimensions - for use in dimensions(of:)
enum dimensionsType {
    case clean
    case production
    case encoded
}

/// Sample Presentation Info.
///
/// NOTE: At final sample of segment, end position could be after end of segment.
public struct PresentationInfo {
    var timeRange : CMTimeRange = kCMTimeRangeZero
    var startSecond : Float64 = 0.0
    var endSecond : Float64 = 0.0
    var movieDuration : Float64 = 0.0
    var startPosition : Float64 = 0.0
    var endPosition : Float64 = 0.0
    
    init(range : CMTimeRange, of movie : AVMovie) {
        timeRange = range
        startSecond = CMTimeGetSeconds(range.start)
        endSecond = CMTimeGetSeconds(range.end)
        movieDuration = CMTimeGetSeconds(movie.range.duration)
        startPosition = startSecond / movieDuration
        endPosition = endSecond / movieDuration
    }
}

class MovieMutatorBase: NSObject {
    /* ============================================ */
    // MARK: - public init
    /* ============================================ */
    
    init(with movie:AVMovie) {
        internalMovie = movie.mutableCopy() as! AVMutableMovie
    }
    
    /* ============================================ */
    // MARK: - properties
    /* ============================================ */
    
    /// Wrapped AVMutableMovie object
    internal var internalMovie : AVMutableMovie

    /// Current Marker
    public var insertionTime : CMTime = kCMTimeZero
    
    /// Selection Marker Range
    public var selectedTimeRange : CMTimeRange = CMTimeRange()
    
    /// Timestamp formatter
    public var timestampFormatter : DateFormatter = {() -> DateFormatter in
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss.SSS" // "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return formatter
    }()
    
    public var unblockUserInteraction : (() -> Void)? = nil
    public var updateProgress : ((Float) -> Void)? = nil
    
    // Caching inspector properties
    private var cachedMediaDataURLs : [URL]? = nil
    private var cachedVideoFPSs : [String]? = nil
    private var cachedVideoDataSizes : [String]? = nil
    private var cachedAudioDataSizes : [String]? = nil
    private var cachedVideoFormats : [String]? = nil
    private var cachedAudioFormats : [String]? = nil
    
    /* ============================================ */
    // MARK: - private method - utilities
    /* ============================================ */
    
    @inline(__always) internal func validateClip(_ clip : AVMovie) -> Bool {
        return clip.range.duration > kCMTimeZero
    }
    
    @inline(__always) internal func validateTime (_ time : CMTime) -> Bool {
        let movieRange : CMTimeRange = self.movieRange()
        return (movieRange.start <= time && time <= movieRange.end)
    }
    
    @inline(__always) internal func validateRange(_ range : CMTimeRange, _ needsDuration : Bool) -> Bool {
        let movieRange : CMTimeRange = self.movieRange()
        return (range.duration > kCMTimeZero)
            ? CMTimeRangeContainsTimeRange(movieRange, range)
            : (needsDuration ? false : validateTime(range.start))
    }
    
    @inline(__always) internal func clampRange(_ range : CMTimeRange) -> CMTimeRange {
        let movieRange : CMTimeRange = self.movieRange()
        return CMTimeRangeGetIntersection(range, movieRange)
    }
    
    @inline(__always) internal func validatePosition(_ position : Float64) -> Bool {
        return (position >= 0.0 && position <= 1.0) ? true : false
    }
    
    @inline(__always) internal func clampPosition(_ position : Float64) -> Float64 {
        return min(max(position, 0.0), 1.0)
    }
    
    @inline(__always) internal func validSize(_ size : NSSize) -> Bool {
        if size.width.isNaN || size.height.isNaN { return false }
        if size.width <= 0 || size.height <= 0 { return false }
        return true
    }
    
    @inline(__always) internal func validPoint(_ point : NSPoint) -> Bool {
        if point.x.isNaN || point.y.isNaN { return false }
        return true
    }
    
    /// Get Data representation of Internal movie
    ///
    /// - Returns: Data
    internal func movieData() -> Data? {
        let movie : AVMovie = internalMovie.mutableCopy() as! AVMutableMovie
        let data = try? movie.makeMovieHeader(fileType: AVFileType.mov)
        return data
    }
    
    /// Refresh Internal movie using Data
    ///
    /// - Parameter data: MovieHeader data
    /// - Returns: true if success
    internal func reloadMovie(from data : Data?) -> Bool {
        if let data = data {
            let newMovie : AVMutableMovie? = AVMutableMovie(data: data, options: nil)
            if let newMovie = newMovie {
                internalMovie = newMovie
                flushCachedValues() // Reset inspector properties cache
                return true
            }
        }
        return false
    }
    
    /// Refresh Internal movie/insertion/selection, then Notify modification
    ///
    /// - Parameters:
    ///   - data: MovieHeader data
    ///   - range: new selection range
    ///   - time: new insertion time
    /// - Returns: true if success
    internal func reloadAndNotify(from data : Data?, range : CMTimeRange, time : CMTime) -> Bool {
        if reloadMovie(from: data) {
            // Update Marker
            insertionTime = time
            selectedTimeRange = range
            internalMovieDidChange(insertionTime, selectedTimeRange)
            return true
        }
        return false
    }
    
    /// Debugging purpose - refresh internal movie object
    internal func refreshMovie() {
        // AVMovie.duration seems to be broken after edit operation
        guard let data : Data = self.movieData() else {
            Swift.print(ts(), "ERROR: Failed to create Data from AVMovie")
            assert(false, #function); return
        }
        guard self.reloadMovie(from: data) else {
            Swift.print(ts(), "ERROR: Failed to create AVMovie from Data")
            assert(false, #function); return
        }
        do {
            let prop : CMTime = internalMovie.duration
            let calc : CMTime = internalMovie.range.duration // extension
            if prop != calc {
                Swift.print(ts(), "BUG: AVMovie.duration is buggy as:")
                Swift.print(ts(), " prop: ",Int(prop.value),"/",Int(prop.timescale))
                Swift.print(ts(), " calc: ",Int(calc.value),"/",Int(calc.timescale))
            }
        }
    }
    
    /// Trigger notification to update GUI when the internal movie is edited.
    /// userInfo will contain timeValueKey and timeRangeValueKey.
    ///
    /// - Parameters:
    ///   - time: Preferred cursor position in CMTime
    ///   - range: Preferred selection range in CMTimeRange
    internal func internalMovieDidChange(_ time : CMTime, _ range : CMTimeRange) {
        let timeValue : NSValue = NSValue(time: time)
        let timeRangeValue : NSValue = NSValue(timeRange: range)
        let userInfo : [AnyHashable:Any] = [timeValueInfoKey:timeValue,
                                            timeRangeValueInfoKey:timeRangeValue]
        let notification = Notification(name: .movieWasMutated,
                                        object: self, userInfo: userInfo)
        NotificationCenter.default.post(notification)
    }
    
    /// Reset inspector properties cache (on movie edit)
    internal func flushCachedValues() {
        // Swift.print(ts(), #function, #line)
        cachedMediaDataURLs = nil
        cachedVideoFPSs = nil
        cachedVideoDataSizes = nil
        cachedAudioDataSizes = nil
        cachedVideoFormats = nil
        cachedAudioFormats = nil
    }
    
    /* ============================================ */
    // MARK: - public method - utilities
    /* ============================================ */
    
    /// visual size of media in a track
    public func mediaDimensions(of type : dimensionsType, in track : AVMutableMovieTrack) -> NSSize {
        var size = NSZeroSize
        
        let formats = track.formatDescriptions as! [CMFormatDescription]
        for format in formats {
            switch type {
            case .clean:
                size = CMVideoFormatDescriptionGetPresentationDimensions(format, true, true)
            case .production:
                size = CMVideoFormatDescriptionGetPresentationDimensions(format, true, false)
            case .encoded:
                size = CMVideoFormatDescriptionGetPresentationDimensions(format, false, false)
            }
            if size != NSZeroSize {
                break
            }
        }
        
        return size
    }
    
    /// visual size of movie
    public func dimensions(of type : dimensionsType) -> NSSize {
        let movie = internalMovie
        let tracks = movie.tracks(withMediaCharacteristic: .visual)
        guard tracks.count > 0 else {
            // use dummy size for 16:9 (commonly used for .m4a format)
            return NSSize(width: 320, height: 180)
        }
        
        var targetRect : NSRect = NSZeroRect
        for track in tracks {
            let trackTransform : CGAffineTransform = track.preferredTransform
            var size : NSSize
            switch type {
            case .clean:      size = track.cleanApertureDimensions
            case .production: size = track.productionApertureDimensions
            case .encoded:    size = track.encodedPixelsDimensions
            }
            
            if size == NSZeroSize {
                size = mediaDimensions(of: type, in: track)
                assert(size != NSZeroSize, "ERROR: Failed to get presentation dimensions.")
            }
            
            let rect : NSRect = NSRect(origin: NSPoint(x: -size.width/2, y: -size.height/2),
                                       size: size)
            let resultedRect : NSRect = rect.applying(trackTransform)
            
            targetRect = NSUnionRect(targetRect, resultedRect)
        }
        
        let movieTransform : CGAffineTransform = movie.preferredTransform
        targetRect = targetRect.applying(movieTransform)
        //targetRect = NSOffsetRect(targetRect, -targetRect.minX, -targetRect.minY)
        
        let targetSize = NSSize(width: targetRect.width, height: targetRect.height)
        return targetSize
    }
    
    /// Calculate movie header size information
    public func headerSize() -> boxSize {
        let movie : AVMovie = internalMovie.copy() as! AVMovie
        let tracks = movie.tracks
        var size : boxSize = boxSize()
        
        if let data = self.movieData() {
            let headerSize : Int64 = Int64(data.count)
            var videoSize : Int64 = 0, videoCount : Int64 = 0
            var audioSize : Int64 = 0, audioCount : Int64 = 0
            var otherSize : Int64 = 0, otherCount : Int64 = 0
            
            for track in tracks {
                let type = track.mediaType
                switch type {
                case AVMediaType.video:
                    videoSize += track.totalSampleDataLength
                    videoCount += 1
                case AVMediaType.audio:
                    audioSize += track.totalSampleDataLength
                    audioCount += 1
                default:
                    otherSize += track.totalSampleDataLength
                    otherCount += 1
                }
            }
            
            size.headerSize = headerSize
            size.videoSize = videoSize
            size.videoCount = videoCount
            size.audioSize = audioSize
            size.audioCount = audioCount
            size.otherSize = otherSize
            size.otherCount = otherCount
        }
        return size
    }
    
    /// Get Internal movie timeRange
    ///
    /// - Returns: CMTimeRange
    public func movieRange() -> CMTimeRange {
        let range : CMTimeRange = internalMovie.range
        return range
    }
    
    /// Get Internal movie duration (calculated)
    ///
    /// - Returns: CMTime
    public func movieDuration() -> CMTime {
        let duration : CMTime = internalMovie.range.duration
        return duration
    }
    
    /// Get minimum resolution of movieTimeScale
    ///
    /// - Returns: CMTime of 1 per movie timeScale
    public func movieResolution() -> CMTime {
        let timeScale : CMTimeScale = internalMovie.timescale
        let resolution : CMTime = CMTimeMake(1, timeScale)
        return resolution
    }
    
    /// Timestamp generator for debug
    ///
    /// - Returns: timestamp string of local timezone
    public func ts() -> String {
        return timestampFormatter.string(from: Date())
    }
    
    /// Return string representation of CMTime
    ///
    /// - Parameters:
    ///   - time: source time
    ///   - flag: includes 3rd decimals of second.
    /// - Returns: Format in "01:02:03" or "01:02:03.004"
    public func shortTimeString(_ time : CMTime, withDecimals flag: Bool) -> String {
        //Swift.print(#function, #line)
        var string : String = ""
        let timeInSec : Float64 = CMTimeGetSeconds(time)
        let timeInt : Int = Int(floor(timeInSec))
        let hInt : Int = Int(timeInt / 3600)
        let mInt : Int = Int(timeInt % 3600 / 60)
        let sInt : Int = Int(timeInt % 3600 % 60)
        
        if flag { // 01:02:03.004
            let fInt : Int = Int(1000.0 * (timeInSec - Float64(timeInt)))
            string = String(format:"%02i:%02i:%02i.%03i", hInt, mInt, sInt, fInt)
        } else { // 01:02:03
            string = String(format:"%02i:%02i:%02i", hInt, mInt, sInt)
        }
        return string
    }
    
    /// Return string representation of fraction from CMTime
    ///
    /// - Parameter time: source time
    /// - Returns: Format in "123456789/600"
    public func rawTimeString(_ time : CMTime) -> String {
        let value : Int = Int(time.value)
        let scale : Int = Int(time.timescale)
        let rawTimeString : String = String(format:"%9i/%i", value, scale)
        return rawTimeString
    }
    
    /// Validate if movie contains external reference track
    ///
    /// - Returns: true if movie has external reference
    public func hasExternalReference() -> Bool {
        guard internalMovie.tracks.count > 0 else { return false }
        
        var selfContained : Bool = true
        for track in internalMovie.tracks {
            if track.isSelfContained == false {
                selfContained = false
                break
            }
        }
        return !selfContained
    }
    
    /// Get track reference - 'dref' Data Reference atom
    ///
    /// - Parameters:
    ///   - track: AVMutableMovieTrack
    ///   - urlSet: url set to put result
    fileprivate func checkTrackReference(_ track: AVMutableMovieTrack, _ urlSet: NSMutableSet) {
        // TODO: Too heavy and buggy (No support for Muxed/Timecode track)
        // This func is based on TN2404 : URL reference movie support
        
        //Swift.print("\n### movie url:", movieURL)
        //Swift.print("### track:", track.trackID, "type:", track.mediaType)
        let reader : AVAssetReader? = try? AVAssetReader(asset: internalMovie)
        let output : AVAssetReaderSampleReferenceOutput? = AVAssetReaderSampleReferenceOutput(track: track)
        if let reader = reader, let output = output {
            reader.add(output)
            let start : Bool = reader.startReading()
            defer {
                reader.cancelReading()
            }
            if start, let sample = output.copyNextSampleBuffer() {
                var mode : CMAttachmentMode = 0
                let url = CMGetAttachment(sample, kCMSampleBufferAttachmentKey_SampleReferenceURL, &mode)
                if let url = url {
                    urlSet.add(url)
                    //Swift.print("url:", url, "/ mode:", mode)
                } else {
                    //Swift.print("url:", "n/a", "/ mode:", "-")
                }
                //let attach1 = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sample, kCMAttachmentMode_ShouldPropagate)
                //let attach2 = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sample, kCMAttachmentMode_ShouldNotPropagate)
                //Swift.print("ShouldPropagate:", attach1 ?? "none")
                //Swift.print("ShouldNotPropagate:", attach2 ?? "none")
                return
            } else {
                //Swift.print("Failed on AVAssetReader:", reader.error ?? "n/a")
            }
        } else {
            //Swift.print("Unable to use AVAssetReaderSampleReferenceOutput:")
        }
    }
    
    /// URLs which contains media data
    ///
    /// - Returns: URL array including movie source URL
    public func mediaDataURLs() -> [URL]? {
        if let cache = cachedMediaDataURLs {
            return cache
        }
        
        guard let movieURL = internalMovie.url else { return nil }
        
        let urlSet : NSMutableSet = NSMutableSet()
        for track in internalMovie.tracks {
            if track.isSelfContained {
                urlSet.add(movieURL)
            }
            else if let storage = track.mediaDataStorage, let url = storage.url() {
                urlSet.add(url)
            }
            else {
                checkTrackReference(track, urlSet)
            }
        }
        if let storage = internalMovie.defaultMediaDataStorage, let url = storage.url() {
            urlSet.add(url)
        }
        if urlSet.count > 0 {
            cachedMediaDataURLs = urlSet.allObjects as? [URL]
            return cachedMediaDataURLs
        } else {
            return nil
        }
    }
    
    /// Inspector - VideoFPS Description
    ///
    /// - Returns: human readable description
    public func videoFPSs() -> [String]? {
        if let cache = cachedVideoFPSs {
            return cache
        }
        
        var trackStrings : [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            let trackID : Int = Int(track.trackID)
            let fps : Float = track.nominalFrameRate
            let trackString : String = String(format:"%d: %.2f fps", trackID, fps)
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
        
        var trackStrings : [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            let trackID : Int = Int(track.trackID)
            let size: Int64 = track.totalSampleDataLength
            let rate: Float = track.estimatedDataRate
            let trackString : String = String(format:"%d: %.2f MB, %.3f Mbps", trackID,
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
        
        var trackStrings : [String] = []
        for track in internalMovie.tracks(withMediaType: .audio) {
            let trackID : Int = Int(track.trackID)
            let size: Int64 = track.totalSampleDataLength
            let rate: Float = track.estimatedDataRate
            let trackString : String = String(format:"%d: %.2f MB, %.3f Mbps", trackID,
                                              Float(size)/1000000.0,
                                              rate/1000000.0)
            trackStrings.append(trackString)
        }
        cachedAudioDataSizes = (trackStrings.count > 0) ? trackStrings : ["-"]
        return cachedAudioDataSizes
    }
    
    //
    @inline(__always) private func stringForOne(_ size1 : CGSize) -> String {
        return String(format: "%dx%d",
                         Int(size1.width), Int(size1.height))
    }
    
    //
    @inline(__always) private func stringForTwo(_ size1 : CGSize, _ size2 : CGSize) -> String {
        return String(format: "%d:%d(%d:%d)",
                         Int(size1.width), Int(size1.height),
                         Int(size2.width), Int(size2.height))
    }
    
    //
    @inline(__always) private func stringForThree(_ size1 : CGSize, _ size2 : CGSize, _ size3 : CGSize) -> String {
        return String(format: "%d:%d(%d:%d/%d:%d)",
                         Int(size1.width), Int(size1.height),
                         Int(size2.width), Int(size2.height),
                         Int(size3.width), Int(size3.height))
    }
    
    /// Inspector - VideoFormats Description
    ///
    /// - Returns: human readable description
    public func videoFormats() -> [String]? {
        if let cache = cachedVideoFormats {
            return cache
        }
        
        var trackStrings : [String] = []
        for track in internalMovie.tracks(withMediaType: .video) {
            var trackString : [String] = []
            let trackID : Int = Int(track.trackID)
            let reference : Bool = !(track.isSelfContained)
            for desc in track.formatDescriptions as! [CMVideoFormatDescription] {
                var name : String = ""
                do {
                    let ext : CFPropertyList? = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FormatName)
                    if let ext = ext {
                        let nameStr = ext as! NSString
                        name = String(nameStr)
                    } else {
                        let fcc : FourCharCode = CMFormatDescriptionGetMediaSubType(desc)
                        let fccString : NSString = UTCreateStringForOSType(fcc).takeUnretainedValue()
                        name = "FourCC(\(fccString))"
                    }
                }
                var dimension : String = ""
                do {
                    let encoded : CGSize = CMVideoFormatDescriptionGetPresentationDimensions(desc, false, false)
                    let prod : CGSize = CMVideoFormatDescriptionGetPresentationDimensions(desc, true, false)
                    let clean : CGSize = CMVideoFormatDescriptionGetPresentationDimensions(desc, true, true)
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
        
        var trackStrings : [String] = []
        for track in internalMovie.tracks(withMediaType: .audio) {
            var trackString : [String] = []
            let trackID : Int = Int(track.trackID)
            let reference : Bool = !(track.isSelfContained)
            for desc in track.formatDescriptions as! [CMVideoFormatDescription] {
                var rateString : String = ""
                do {
                    let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                    if let ptr = basic {
                        let rate : Float64 = ptr.pointee.mSampleRate
                        rateString = String(format:"%.3f kHz", rate/1000.0)
                    }
                }
                var formatString : String = ""
                do {
                    // get AudioStreamBasicDescription ptr
                    let asbdSize : UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                    let asbdPtr : UnsafePointer<AudioStreamBasicDescription>? =
                        CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                    
                    var formatSize : UInt32 = UInt32(MemoryLayout<CFString>.size)
                    var format : CFString!
                    let err : OSStatus =
                        AudioFormatGetProperty(kAudioFormatProperty_FormatName,
                                               asbdSize, asbdPtr, &formatSize,
                                               &format)
                    assert(err == noErr && formatSize > 0)
                    formatString = String(format as NSString)
                }
                var layoutString : String = ""
                do {
                    // get AudioChannelLayout ptr
                    var aclSize : Int = 0
                    let aclPtr : UnsafePointer<AudioChannelLayout>? =
                        CMAudioFormatDescriptionGetChannelLayout(desc, &aclSize)
                    
                    var name : CFString!
                    var nameSize : UInt32 = UInt32(MemoryLayout<CFString>.size)
                    let err : OSStatus =
                        AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutName,
                                               UInt32(aclSize), aclPtr,
                                               &nameSize, &name)
                    assert(err == noErr && nameSize > 0)
                    layoutString = String(name as NSString)
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
    
    /// Make new AVPlayerItem for internalMovie
    ///
    /// - Returns: AVPlayerItem
    public func makePlayerItem() -> AVPlayerItem {
        let asset : AVAsset = internalMovie.copy() as! AVAsset
        let playerItem : AVPlayerItem = AVPlayerItem(asset: asset)
        if let comp = makeVideoComposition() {
            playerItem.videoComposition = comp
        }
        return playerItem
    }
    
    /// Make new AVVideoComposition for internalMovie
    ///
    /// - Returns: AVVideoComposition
    public func makeVideoComposition() -> AVVideoComposition? {
        let vCount = internalMovie.tracks(withMediaType: AVMediaType.video).count
        if vCount > 1 {
            let comp : AVVideoComposition = AVVideoComposition(propertiesOf: internalMovie)
            return comp
        }
        return nil
    }
    
    /// Convert Float64 to CMTime value of internalMovie.
    ///
    /// - Parameter position: Float64 as relative position of internalMovie (0.0 - 1.0)
    /// - Returns: CMTime at the position of internalMovie
    public func timeOfPosition(_ position : Float64) -> CMTime {
        let position : Float64 = clampPosition(position)
        let duration : CMTime = self.movieDuration()
        let target : CMTime = CMTimeMultiplyByFloat64(duration, position)
        return target
    }
    
    /// Convert CMTime to Float64 value of internalMovie.
    ///
    /// - Parameter target: CMTime value
    /// - Returns: Float64 as relative position of internalMovie (0.0 - 1.0)
    public func positionOfTime(_ target : CMTime) -> Float64 {
        var position : Float64 = 0.0
        let duration : CMTime = self.movieDuration()
        if duration.timescale == target.timescale {
            // use movie/track timescale resolution
            position = Float64(target.value) / Float64(duration.value)
        } else {
            let timescale : CMTimeScale = internalMovie.timescale
            let target2 : CMTime = CMTimeConvertScale(target, timescale, .roundAwayFromZero)
            let duration2 : CMTime = CMTimeConvertScale(duration, timescale, .roundAwayFromZero)
            position = Float64(target2.value) / Float64(duration2.value)
        }
        return clampPosition(position)
    }
    
    /* ============================================ */
    // MARK: - private method - presentationInfo
    /* ============================================ */
    
    /// Tracks ordered in video-timecode-audio
    ///
    /// - Returns: array of AVMovieTrack
    private func orderedTracks() -> [AVMovieTrack] {
        let videoTracks : [AVMovieTrack] = internalMovie.tracks(withMediaType: .video)
        let timecodeTracks : [AVMovieTrack] = internalMovie.tracks(withMediaType: .timecode)
        let audioTracks : [AVMovieTrack] = internalMovie.tracks(withMediaType: .audio)
        let tracks : [AVMovieTrack] = videoTracks + timecodeTracks + audioTracks
        return tracks
    }
    
    /// Get presentationInfo from PTS pair and timeMapping
    ///
    /// - Parameters:
    ///   - startPTS: startPTS (mediaTime)
    ///   - endPTS: endPTS (mediaTime)
    ///   - mapping: timeMapping
    /// - Returns: PresentationInfo (trackTime)
    private func samplePresentationInfo(_ startPTS : CMTime, _ endPTS : CMTime, from mapping : CMTimeMapping) -> PresentationInfo? {
        if (mapping.source.duration > kCMTimeZero) == false {
            return nil
        }
        
        // Get sample timeRange and PresentationInfo
        let start : CMTime = trackTime(of: startPTS, from: mapping)
        let end : CMTime = trackTime(of: endPTS, from: mapping)
        let range : CMTimeRange = CMTimeRangeFromTimeToTime(start, end)
        let info : PresentationInfo = PresentationInfo(range: range, of: internalMovie)
        return info
    }
    
    /// Convert mediaTime to trackTime using timeMapping
    ///
    /// - Parameters:
    ///   - samplePTS: mediaTime
    ///   - mapping: timeMapping
    /// - Returns: trackTime in Movie Timescale
    private func trackTime(of samplePTS : CMTime, from mapping : CMTimeMapping) -> CMTime {
        let mediaSegment : CMTimeRange = mapping.source
        let trackSegment : CMTimeRange = mapping.target
        
        var time : CMTime = CMTimeMapTimeFromRangeToRange(samplePTS, mediaSegment, trackSegment)
        time = CMTimeConvertScale(time, internalMovie.timescale, .roundAwayFromZero)
        time = CMTimeClampToRange(time, trackSegment)
        return time
    }
    
    /// Convert trackTime to mediaTime using timeMapping
    ///
    /// - Parameters:
    ///   - trackTime: trackTime
    ///   - mapping: timeMapping
    /// - Returns: mediaTime
    private func mediaTime(of trackTime : CMTime, from mapping : CMTimeMapping) -> CMTime {
        let mediaSegment : CMTimeRange = mapping.source
        let trackSegment : CMTimeRange = mapping.target
        
        var time : CMTime = CMTimeMapTimeFromRangeToRange(trackTime, trackSegment, mediaSegment)
        //time = CMTimeConvertScale(time, mapping.source.duration.timescale, .roundTowardZero)
        time = CMTimeClampToRange(time, mediaSegment)
        return time
    }
    
    /* ============================================ */
    // MARK: - public method - presentationInfo
    /* ============================================ */
    
    /// Get PresentationInfo struct of position
    ///
    /// - Parameter position: Float64 as relative position of internalMovie (0.0 - 1.0)
    /// - Returns: PresentationInfo of the position
    public func presentationInfoAtPosition(_ position : Float64) -> PresentationInfo? {
        let time = timeOfPosition(position)
        let valid : Bool = CMTIME_IS_VALID(time)
        return (valid ? presentationInfoAtTime(time) : nil)
    }
    
    /// Query current sample's PresentationInfo at CMTime
    ///
    /// - Parameter time: CMTime at the position of internalMovie
    /// - Returns: PresentationInfo of the position
    public func presentationInfoAtTime(_ time : CMTime) -> PresentationInfo? {
        var time : CMTime = CMTimeClampToRange(time, internalMovie.range)
        let lastSample : Bool = (time == internalMovie.range.end) ? true : false
        if lastSample {
            // Adjust micro difference from tail of movie
            time = time - movieResolution()
        }
        
        for track : AVMovieTrack in orderedTracks() {
            // Get AVSampleCursor/AVAssetTrackSegment at specified track time
            let pts = track.samplePresentationTime(forTrackTime: time)
            guard CMTIME_IS_VALID(pts) else { continue }
            guard let cursor : AVSampleCursor = track.makeSampleCursor(presentationTimeStamp: pts)
                else { continue }
            guard let segment : AVAssetTrackSegment = track.segment(forTrackTime: time)
                else { continue }
            guard (segment.isEmpty == false) else { continue }
            // Prepare
            let mapping : CMTimeMapping = segment.timeMapping
            let startPTS : CMTime = cursor.presentationTimeStamp
            let endPTS : CMTime = cursor.presentationTimeStamp + cursor.currentSampleDuration
            guard let info : PresentationInfo = samplePresentationInfo(startPTS,
                                                                       endPTS,
                                                                       from: mapping)
                else { continue }
            if info.timeRange.duration > kCMTimeZero {
                return info
            } else {
                // Exact sample is invisible (zero length in track timescale)
                let range : CMTimeRange = info.timeRange
                let info : PresentationInfo? = nextInfo(of: range)
                return info
            }
        }
        return nil
    }
    
    /// Query Previous sample's PresentationInfo
    ///
    /// - Parameter range: current sample's Presentation CMTimeRange in TrackTime
    /// - Returns: PresentationInfo of previous sample
    public func previousInfo(of range : CMTimeRange) -> PresentationInfo? {
        // Check if this is initial sample in internalMovie
        if range.start == kCMTimeZero {
            return nil
        }
        
        for track : AVMovieTrack in orderedTracks() {
            // Get AVSampleCursor/AVAssetTrackSegment at range.start
            let pts = track.samplePresentationTime(forTrackTime: range.start)
            guard CMTIME_IS_VALID(pts) else { continue }
            guard let cursor : AVSampleCursor = track.makeSampleCursor(presentationTimeStamp: pts)
                else { continue }
            guard let segment : AVAssetTrackSegment = track.segment(forTrackTime: range.start)
                else { continue }
            guard (segment.isEmpty == false) else { continue }
            // Prepare
            let mapping = segment.timeMapping
            let trackSegmentMin : CMTime = mapping.target.start
            let mediaSegmentMin : CMTime = mapping.source.start
            let resolution = movieResolution()
            // Seek by Step AVSampleCursor backward (current segment only)
            while cursor.presentationTimeStamp > mediaSegmentMin {
                guard cursor.stepInPresentationOrder(byCount: -1) == -1 else { break }
                if cursor.presentationTimeStamp > mediaSegmentMin {
                    let sampleStartPTS : CMTime = cursor.presentationTimeStamp
                    let sampleStartTT : CMTime = trackTime(of: sampleStartPTS, from: mapping)
                    if (range.start - sampleStartTT) < resolution { continue }
                    let pRange : CMTimeRange = CMTimeRangeFromTimeToTime(sampleStartTT, range.start)
                    let info : PresentationInfo = PresentationInfo(range: pRange, of: internalMovie)
                    return info
                } else {
                    if (range.start - trackSegmentMin) < resolution { break }
                    let pRange : CMTimeRange = CMTimeRangeFromTimeToTime(trackSegmentMin, range.start)
                    let info : PresentationInfo = PresentationInfo(range: pRange, of: internalMovie)
                    return info
                }
            }
        }
        
        // Try to handle track segment boundary
        // Offset 1/movie.timescale as micro difference to test
        let testTime : CMTime = range.start - movieResolution()
        if let info = presentationInfoAtTime(testTime) {
            return info
        }
        
        assert(false, #function) //
        return nil // Should not occur
    }
    
    /// Query Next sample's PresentationInfo
    ///
    /// - Parameter range: current sample's Presentation CMTimeRange in TrackTime
    /// - Returns: PresentationInfo of next sample
    public func nextInfo(of range : CMTimeRange) -> PresentationInfo? {
        // Check if this is last sample in internalMovie
        if range.end >= self.movieDuration() {
            return nil
        }
        
        for track : AVMovieTrack in orderedTracks() {
            // Get AVSampleCursor/AVAssetTrackSegment at range.start
            let pts = track.samplePresentationTime(forTrackTime: range.start)
            guard CMTIME_IS_VALID(pts) else { continue }
            guard let cursor : AVSampleCursor = track.makeSampleCursor(presentationTimeStamp: pts)
                else { continue }
            guard let segment : AVAssetTrackSegment = track.segment(forTrackTime: range.start)
                else { continue }
            guard (segment.isEmpty == false) else { continue }
            // Prepare
            let mapping = segment.timeMapping
            let trackSegmentMax : CMTime = mapping.target.end
            let mediaSegmentMax : CMTime = mapping.source.end
            let resolution = movieResolution()
            // Seek by Step AVSampleCursor forward (current segment only)
            while cursor.presentationTimeStamp < mediaSegmentMax {
                guard cursor.stepInPresentationOrder(byCount: +1) == +1 else { break }
                if cursor.presentationTimeStamp < mediaSegmentMax {
                    let sampleStartPTS : CMTime = cursor.presentationTimeStamp
                    let sampleStartTT : CMTime = trackTime(of: sampleStartPTS, from: mapping)
                    if (sampleStartTT - range.end) < resolution { continue }
                    let nRange : CMTimeRange = CMTimeRangeFromTimeToTime(range.end, sampleStartTT)
                    let info : PresentationInfo = PresentationInfo(range: nRange, of: internalMovie)
                    return info
                } else {
                    if (trackSegmentMax - range.end) < resolution { break }
                    let nRange: CMTimeRange = CMTimeRangeFromTimeToTime(range.end, trackSegmentMax)
                    let info : PresentationInfo = PresentationInfo(range: nRange, of: internalMovie)
                    return info
                }
            }
        }
        
        // Try to handle track segment boundary
        // Offset 1/movie.timescale as micro difference to test
        let testTime : CMTime = range.end + movieResolution()
        if let info = presentationInfoAtTime(testTime) {
            return info
        }
        
        assert(false, #function) //
        return nil // Shouild not occur
    }
    
    /* ============================================ */
    // MARK: - public method - clap/pasp
    /* ============================================ */
    
    //
    public func clappaspDictionary() -> [AnyHashable : Any]? {
        var dict : [AnyHashable : Any] = [:]
        
        let vTracks : [AVMovieTrack] = internalMovie.tracks(withMediaType: .video)
        guard vTracks.count > 0 else { NSSound.beep(); return nil }
        
        let formats : [Any] = (vTracks[0]).formatDescriptions
        let format : CMVideoFormatDescription? = (formats[0] as! CMVideoFormatDescription)
        guard let desc = format else { NSSound.beep(); return nil }
        
        dict[dimensionsKey] =
            CMVideoFormatDescriptionGetPresentationDimensions(desc, false, false)
        
        let extCA : CFPropertyList? =
            CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_CleanAperture)
        if let extCA = extCA {
            let width = extCA[kCMFormatDescriptionKey_CleanApertureWidth] as! NSNumber
            let height = extCA[kCMFormatDescriptionKey_CleanApertureHeight] as! NSNumber
            let wOffset = extCA[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] as! NSNumber
            let hOffset = extCA[kCMFormatDescriptionKey_CleanApertureVerticalOffset] as! NSNumber
            
            dict[clapSizeKey] = NSSize(width: width.intValue, height: height.intValue)
            dict[clapOffsetKey] = NSPoint(x: wOffset.intValue, y: hOffset.intValue)
        } else {
            dict[clapSizeKey] = dict[dimensionsKey]
            dict[clapOffsetKey] = NSZeroPoint
        }
        
        let extPA : CFPropertyList? =
            CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_PixelAspectRatio)
        if let extPA = extPA {
            let hSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as! NSNumber
            let vSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as! NSNumber
            
            dict[paspRatioKey] = NSSize(width: hSpacing.doubleValue, height: vSpacing.doubleValue)
        } else {
            dict[paspRatioKey] = NSSize(width: 1.0, height: 1.0)
        }
        
        return dict
    }
    
    /* ============================================ */
    // MARK: - public method - export/write methods
    /* ============================================ */
    
    public func exportMovie(to url : URL, fileType type : AVFileType, presetName preset : String?) throws {
        let movieWriter = MovieWriter(internalMovie)
        movieWriter.unblockUserInteraction = self.unblockUserInteraction
        movieWriter.updateProgress = self.updateProgress
        try movieWriter.exportMovie(to: url, fileType: type, presetName: preset)
    }
    
    public func exportCustomMovie(to url : URL, fileType type : AVFileType, settings param : [String:Any]) throws {
        let movieWriter = MovieWriter(internalMovie)
        movieWriter.unblockUserInteraction = self.unblockUserInteraction
        movieWriter.updateProgress = self.updateProgress
        try movieWriter.exportCustomMovie(to: url, fileType: type, settings: param)
    }
    
    public func writeMovie(to url : URL, fileType type : AVFileType, copySampleData selfContained : Bool) throws {
        let movieWriter = MovieWriter(internalMovie)
        movieWriter.unblockUserInteraction = self.unblockUserInteraction
        try movieWriter.writeMovie(to: url, fileType: type, copySampleData: selfContained)
    }
    
}
