//
//  MovieMutator.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVKit
import AVFoundation

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
private let clipPBoardType : NSPasteboard.PasteboardType = NSPasteboard.PasteboardType(rawValue: clipPBoardTypeRaw)

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

/// Wrapper of AVMutableMovie as model object of movie editor
class MovieMutator: NSObject {
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
    private var internalMovie : AVMutableMovie
    
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

    /* ============================================ */
    // MARK: - private method - Notification
    /* ============================================ */
    
    /// Trigger notification to update GUI when the internal movie is edited.
    /// userInfo will contain "timeValue" and "timeRangeValue".
    ///
    /// - Parameters:
    ///   - time: Preferred cursor position in CMTime
    ///   - range: Preferred selection range in CMTimeRange
    private func internalMovieDidChange(_ time : CMTime, _ range : CMTimeRange) {
        let timeValue : NSValue = NSValue(time: time)
        let timeRangeValue : NSValue = NSValue(timeRange: range)
        let userInfo : [AnyHashable:Any] = ["timeValue":timeValue,
                                            "timeRangeValue":timeRangeValue]
        let notification = Notification(name: .movieWasMutated,
                                        object: self, userInfo: userInfo)
        NotificationCenter.default.post(notification)
    }
    
    /* ============================================ */
    // MARK: - private method - utilities
    /* ============================================ */
    
    @inline(__always) private func validateClip(_ clip : AVMovie) -> Bool {
        return clip.range.duration > kCMTimeZero
    }
    
    @inline(__always) private func validateTime (_ time : CMTime) -> Bool {
        let movieRange : CMTimeRange = self.movieRange()
        return (movieRange.start <= time && time <= movieRange.end)
    }
    
    @inline(__always) private func validateRange(_ range : CMTimeRange, _ needsDuration : Bool) -> Bool {
        let movieRange : CMTimeRange = self.movieRange()
        return (range.duration > kCMTimeZero)
            ? CMTimeRangeContainsTimeRange(movieRange, range)
            : (needsDuration ? false : validateTime(range.start))
    }
    
    @inline(__always) private func clampRange(_ range : CMTimeRange) -> CMTimeRange {
        let movieRange : CMTimeRange = self.movieRange()
        return CMTimeRangeGetIntersection(range, movieRange)
    }
    
    @inline(__always) private func validatePosition(_ position : Float64) -> Bool {
        return (position >= 0.0 && position <= 1.0) ? true : false
    }
    
    @inline(__always) private func clampPosition(_ position : Float64) -> Float64 {
        return min(max(position, 0.0), 1.0)
    }
    
    /// Get Data representation of Internal movie
    ///
    /// - Returns: Data
    private func movieData() -> Data? {
        let movie : AVMovie = internalMovie.copy() as! AVMovie
        let data = try? movie.makeMovieHeader(fileType: AVFileType.mov)
        return data
    }
    
    /// Refresh Internal movie using Data
    ///
    /// - Parameter data: MovieHeader data
    /// - Returns: true if success
    private func reloadMovie(from data : Data?) -> Bool {
        if let data = data {
            let newMovie : AVMutableMovie? = AVMutableMovie(data: data, options: nil)
            if let newMovie = newMovie {
                internalMovie = newMovie
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
    private func reloadAndNotify(from data : Data?, range : CMTimeRange, time : CMTime) -> Bool {
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
    private func refreshMovie() {
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
    
    /* ============================================ */
    // MARK: - public method - utilities
    /* ============================================ */
    
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
    
    /// URLs which contains media data
    ///
    /// - Returns: URL array including movie source URL
    public func mediaDataURLs() -> [URL]? {
        guard let movieURL = internalMovie.url else { return nil }
        
        let urlSet : NSMutableSet = NSMutableSet()
        for track in internalMovie.tracks {
            if track.isSelfContained {
                urlSet.add(movieURL)
            }
            else if let storage = track.mediaDataStorage, let url = storage.url() {
                urlSet.add(url)
            }
        }
        if let storage = internalMovie.defaultMediaDataStorage, let url = storage.url() {
            urlSet.add(url)
        }
        if urlSet.count > 0 {
            return urlSet.allObjects as? [URL]
        } else {
            return nil
        }
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
    // MARK: - private method - get movie clip
    /* ============================================ */
    
    /// Create movie clip from specified CMTimeRange
    ///
    /// - Parameter range: clip range
    /// - Returns: clip as AVMutableMovie
    private func movieClip(_ range : CMTimeRange) -> AVMutableMovie? {
        guard validateRange(range, true) else {
            assert(false, #function) //
            return nil
        }
        
        // Prepare clip
        var clip : AVMutableMovie = internalMovie.mutableCopy() as! AVMutableMovie
        if clip.timescale != range.duration.timescale {
            // Create new Movie with exact timescale; it should match before operation
            clip = AVMutableMovie()
            let scale = range.duration.timescale
            clip.timescale = scale
            clip.preferredRate = 1.0
            clip.preferredVolume = 1.0
            clip.interleavingPeriod = CMTimeMakeWithSeconds(0.5, scale)
            clip.preferredTransform = CGAffineTransform.identity
            clip.isModified = false
            // convert all into different timescale
            do {
                let movieRange : CMTimeRange = self.movieRange()
                Swift.print(ts(), #function, #line)
                try clip.insertTimeRange(movieRange, of: internalMovie, at: kCMTimeZero, copySampleData: false)
                Swift.print(ts(), #function, #line)
            } catch {
                Swift.print(error)
                assert(false, #function)
            }
        }
        
        // Trim clip
        let rangeAfter : CMTimeRange = CMTimeRangeMake(range.end, clip.range.duration - range.end)
        if rangeAfter.duration > kCMTimeZero {
            clip.removeTimeRange(rangeAfter)
        }
        let rangeBefore : CMTimeRange = CMTimeRangeMake(kCMTimeZero, range.start)
        if rangeBefore.duration > kCMTimeZero {
            clip.removeTimeRange(rangeBefore)
        }
        
        if range.duration != clip.range.duration {
            Swift.print(ts(), "NOTICE: diff", CMTimeGetSeconds(range.duration),
                        CMTimeGetSeconds(clip.range.duration), "at", #function, #line)
            Swift.print(ts(), range.duration)
            Swift.print(ts(), clip.range.duration)
            assert(false, #function) //
            return nil
        }
        
        if validateClip(clip) {
            return clip
        } else {
            assert(false, #function) //
            return nil
        }
    }
    
    /* ============================================ */
    // MARK: - private method - work w/ PasteBoard
    /* ============================================ */
    
    /// Read movie clip data from PasteBoard
    ///
    /// - Returns: AVMutableMovie
    private func readClipFromPBoard() -> AVMutableMovie? {
        let pBoard : NSPasteboard = NSPasteboard.general
        
        // extract movie header data from PBoard
        let data : Data? = pBoard.data(forType: clipPBoardType)
        
        if let data = data {
            // create movie from movieHeader data
            //Swift.print(ts(), #function, #line)
            let clip : AVMutableMovie? = AVMutableMovie(data: data, options: nil)
            //Swift.print(ts(), #function, #line)
            
            if let clip = clip, validateClip(clip) {
                return clip
            } else {
                assert(false, #function) //
                return nil
            }
        } else {
            // assert(false, #function) //
            return nil
        }
    }
    
    /// Write movie clip data to PasteBoard
    ///
    /// - Parameter clip: AVMutableMovie
    /// - Returns: true if success
    private func writeClipToPBoard(_ clip : AVMutableMovie) -> Bool {
        assert( validateClip(clip), #function ) //
        
        // create movieHeader data from movie
        do {
            //Swift.print(ts(), #function, #line)
            let data : Data? = try clip.makeMovieHeader(fileType: AVFileType.mov)
            //Swift.print(ts(), #function, #line)
            
            if let data = data {
                // register data to PBoard
                let pBoard : NSPasteboard = NSPasteboard.general
                pBoard.clearContents()
                pBoard.setData(data, forType: clipPBoardType)
                
                return true
            } else {
                assert(false, #function) //
                return false
            }
        } catch {
            Swift.print(error)
            assert(false, #function)
        }
        return false
    }
    
    /// Write movie clip data to PasteBoard
    ///
    /// - Parameter range: CMTimeRange of clip
    /// - Returns: AVMutableMovie of clip
    private func writeRangeToPBoard(_ range : CMTimeRange) -> AVMutableMovie? {
        guard let clip = self.movieClip(range) else { return nil }
        guard self.writeClipToPBoard(clip) else { return nil }
        return clip
    }
    
    /* ============================================ */
    // MARK: - public method - work w/ PasteBoard
    /* ============================================ */
    
    /// Check if pasteboard has valid movie clip
    ///
    /// - Returns: true if available
    public func validateClipFromPBoard() -> Bool {
        let pBoard : NSPasteboard = NSPasteboard.general
        
        if let _ = pBoard.data(forType: clipPBoardType) {
            return true
        } else {
            return false
        }
    }
    
    /* ============================================ */
    // MARK: - private method - remove/insert clip
    /* ============================================ */
    
    /// Remove range. Adjust insertionTime.
    ///
    /// - Parameters:
    ///   - range: Range to remove
    ///   - time: insertionTime
    private func doRemove(_ range: CMTimeRange, _ time: CMTime) {
        assert( validateRange(range, true), #function )
        
        // perform delete selection
        do {
            //Swift.print(ts(), #function, #line)
            internalMovie.removeTimeRange(range)
            //Swift.print(ts(), #function, #line)
            
            // Update Marker
            insertionTime = (time < range.start ? time
                : (CMTimeRangeContainsTime(range, time) ? range.start : time - range.duration))
            selectedTimeRange = CMTimeRangeMake(range.start, kCMTimeZero)
            internalMovieDidChange(insertionTime, selectedTimeRange)
        }
    }
    
    /// Undo remove range. Restore movie, insertionTime and selection.
    ///
    /// - Parameters:
    ///   - data: movieHeader data to be restored.
    ///   - range: original selection
    ///   - time: original intertionTime
    ///   - clip: removed clip - unused
    private func undoRemove(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip : AVMutableMovie) {
        assert( validateClip(clip), #function )
        
        guard reloadAndNotify(from: data, range: range, time: time) else {
            assert(false, #function) //
            NSSound.beep(); return
        }
    }
    
    /// Insert clip at insertionTime. Adjust insertionTime/selection.
    ///
    /// - Parameters:
    ///   - clip: insertionTime
    ///   - time: selection
    private func doInsert(_ clip: AVMutableMovie, _ time: CMTime) {
        assert( validateClip(clip), #function )
        assert( validateTime(time), #function )
        
        // perform insert clip at marker
        do {
            var clipRange : CMTimeRange = CMTimeRange(start: kCMTimeZero,
                                                      duration: clip.range.duration)
            if clip.timescale != internalMovie.timescale {
                // Shorten if fraction is not zero
                let duration : CMTime = CMTimeConvertScale(clip.range.duration,
                                                           internalMovie.timescale,
                                                           .roundTowardZero)
                clipRange = CMTimeRange(start: kCMTimeZero,
                                        duration: duration)
            }
            let beforeDuration = self.movieDuration()
            
            Swift.print(ts(), #function, #line)
            try internalMovie.insertTimeRange(clipRange,
                                              of: clip,
                                              at: time,
                                              copySampleData: false)
            Swift.print(ts(), #function, #line)
            
            // Update Marker
            let afterDuration = self.movieDuration()
            let actualDelta = afterDuration - beforeDuration
            insertionTime = time + actualDelta
            selectedTimeRange = CMTimeRangeMake(time, actualDelta)
            
            internalMovieDidChange(insertionTime, selectedTimeRange)
        } catch {
            Swift.print(error)
            assert(false, #function) //
        }
    }
    
    /// Undo insert clip. Restore movie, insertionTime and selection.
    ///
    /// - Parameters:
    ///   - data: movieHeader data to be restored.
    ///   - range: original selection
    ///   - time: original insertionTime
    ///   - clip: inserted clip
    private func undoInsert(_ data: Data, _ range: CMTimeRange, _ time: CMTime, _ clip : AVMutableMovie) {
        assert( validateClip(clip), #function )
        
        // populate PBoard with original clip
        guard writeClipToPBoard(clip) else {
            assert(false, #function) //
            NSSound.beep(); return
        }
        
        guard reloadAndNotify(from: data, range: range, time: time) else {
            assert(false, #function) //
            NSSound.beep(); return
        }
    }
    
    /* ============================================ */
    // MARK: - public method - edit action
    /* ============================================ */
    
    /// Copy selection of internalMovie
    public func copySelection() {
        // Swift.print(#function, #line)
        
        // perform copy selection
        let range = self.selectedTimeRange
        if !validateRange(range, true) { NSSound.beep(); return; }
        
        guard let _ = writeRangeToPBoard(range) else {
            assert(false, #function) //
            NSSound.beep(); return;
        }
    }
    
    /// Cut selection of internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func cutSelection(using undoManager : UndoManager) {
        // Swift.print(#function, #line)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        if !validateRange(range, true) { NSSound.beep(); return; }
        
        guard let clip = writeRangeToPBoard(range) else { NSSound.beep(); return; }
        guard let data = movieData() else { NSSound.beep(); return; }
        
        // register undo record
        let undoCutHandler : (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in
            // register redo record
            let redoCutHandler : (MovieMutator) -> Void = {[unowned undoManager] (me2) in
                me2.cutSelection(using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoCutHandler)
            undoManager.setActionName("Cut selection")
            
            // perform undo cut
            me1.undoRemove(data, range, time, clip)
        }
        undoManager.registerUndo(withTarget: self, handler: undoCutHandler)
        undoManager.setActionName("Cut selection")
        
        // perform cut
        self.doRemove(range, time)
        refreshMovie()
    }
    
    /// Paste clip into internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func pasteAtInsertionTime(using undoManager : UndoManager) {
        // Swift.print(#function, #line)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        if !validateRange(range, false) { NSSound.beep(); return; }
        
        guard let clip = readClipFromPBoard() else { NSSound.beep(); return; }
        guard let data = movieData() else { NSSound.beep(); return; }

        // register undo record
        let undoPasteHandler : (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in
            // register redo record
            let redoPasteHandler : (MovieMutator) -> Void = {[unowned undoManager] (me2) in
                me2.pasteAtInsertionTime(using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoPasteHandler)
            undoManager.setActionName("Paste at marker")
            
            // perform undo paste
            me1.undoInsert(data, range, time, clip)
        }
        undoManager.registerUndo(withTarget: self, handler: undoPasteHandler)
        undoManager.setActionName("Paste at marker")
        
        // perform paste
        self.doInsert(clip, time)
        refreshMovie()
    }
    
    /// Delete selection of internalMovie
    ///
    /// - Parameter undoManager: UndoManager for this operation
    public func deleteSelection(using undoManager : UndoManager) {
        // Swift.print(#function, #line)
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        if !validateRange(range, true) { NSSound.beep(); return; }
        
        guard let clip = movieClip(range) else {
            assert(false, #function) //
            NSSound.beep(); return;
        }
        guard let data = movieData() else { NSSound.beep(); return; }

        // register undo redord
        let undoDeleteHandler : (MovieMutator) -> Void = {[range = range, time = time, unowned undoManager] (me1) in
            
            // register redo record
            let redoDeleteHandler : (MovieMutator) -> Void = {[unowned undoManager] (me2) in
                me2.deleteSelection(using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoDeleteHandler)
            undoManager.setActionName("Delete selection")
            
            // perform undo delete
            me1.undoRemove(data, range, time, clip)
        }
        undoManager.registerUndo(withTarget: self, handler: undoDeleteHandler)
        undoManager.setActionName("Delete selection")
        
        // perform delete
        self.doRemove(range, time)
        refreshMovie()
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
