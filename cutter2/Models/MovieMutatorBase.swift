//
//  MovieMutatorBase.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/04.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

@MainActor
class MovieMutatorBase: NSObject {
    /* ============================================ */
    // MARK: - public init
    /* ============================================ */
    
    init(with movie:AVMutableMovie) {
        guard let copy = movie.mutableCopy() as? AVMutableMovie else {
            preconditionFailure("mutableCopy() of AVMutableMovie returned non-AVMutableMovie")
        }
        internalMovie = copy
        
        do {
            self.timestampFormatter = DateFormatter.logFormatter(format: "yyyy/MM/dd HH:mm:ss.SSS")
        }
    }
    
    /* ============================================ */
    // MARK: - public properties
    /* ============================================ */
    
    /// Wrapped AVMutableMovie object
    public var internalMovie: AVMutableMovie {
        didSet {
            flushCachedValues() // Reset inspector properties cache
        }
    }
    
    /// Current Marker
    public var insertionTime: CMTime = CMTime.zero
    
    /// Selection Marker Range
    public var selectedTimeRange: CMTimeRange = CMTimeRange()
    
    /// Timestamp formatter
    public var timestampFormatter: DateFormatter
    
    public var unblockUserInteraction: (@Sendable () -> Void)? = nil
    
    /// Progress stream continuation for async progress reporting
    internal var progressContinuation: AsyncStream<Float>.Continuation?
    
    /// Current MovieWriter instance (for cancellation support)
    public var currentMovieWriter: MovieWriter? = nil
    
    /// Respect tapt atom on clean aperture detection
    public var acceptTapt: Bool = true
    
    /* ============================================ */
    // MARK: - private properties
    /* ============================================ */
    
    // Caching inspector properties
    internal var cachedMediaDataPaths: [String]? = nil
    internal var cachedVideoFPSs: [String]? = nil
    internal var cachedVideoDataSizes: [String]? = nil
    internal var cachedAudioDataSizes: [String]? = nil
    internal var cachedVideoFormats: [String]? = nil
    internal var cachedAudioFormats: [String]? = nil
    
    /* ============================================ */
    // MARK: - public method - validation and clamp
    /* ============================================ */
    
    @inline(__always) public func validateClipData(_ data: Data) -> Bool {
        let clip = AVMutableMovie(data: data, options: nil)
        return validateClip(clip)
    }
    
    @inline(__always) public func validateClip(_ clip: AVMutableMovie) -> Bool {
        return clip.range.duration > CMTime.zero
    }
    
    @inline(__always) public func validateTime (_ time: CMTime) -> Bool {
        let movieRange: CMTimeRange = self.movieRange()
        return (movieRange.start <= time && time <= movieRange.end)
    }
    
    @inline(__always) public func validateRange(_ range: CMTimeRange, _ needsDuration: Bool) -> Bool {
        let movieRange: CMTimeRange = self.movieRange()
        return (range.duration > CMTime.zero)
            ? (movieRange.start <= range.start && range.end <= movieRange.end)
            : (needsDuration ? false : validateTime(range.start))
    }
    
    @inline(__always) public func clampRange(_ range: CMTimeRange) -> CMTimeRange {
        let movieRange: CMTimeRange = self.movieRange()
        return CMTimeRangeGetIntersection(range, otherRange: movieRange)
    }
    
    @inline(__always) public func validatePosition(_ position: Float64) -> Bool {
        return (position >= 0.0 && position <= 1.0) ? true : false
    }
    
    @inline(__always) public func clampPosition(_ position: Float64) -> Float64 {
        return min(max(position, 0.0), 1.0)
    }
    
    @inline(__always) public func validSize(_ size: NSSize) -> Bool {
        if size.width.isNaN || size.height.isNaN { return false }
        if size.width <= 0 || size.height <= 0 { return false }
        return true
    }
    
    @inline(__always) public func validPoint(_ point: NSPoint) -> Bool {
        if point.x.isNaN || point.y.isNaN { return false }
        return true
    }
    
    /* ============================================ */
    // MARK: - public method - movie management
    /* ============================================ */
    
    /// Refresh Internal movie/insertion/selection, then Notify modification
    ///
    /// - Parameters:
    ///   - data: MovieHeader data
    ///   - range: new selection range
    ///   - time: new insertion time
    /// - Returns: true if success
    public func reloadAndNotify(from data: Data?, range: CMTimeRange, time: CMTime) -> Bool {
        
        if reloadMovie(from: data) {
            // Update Marker
            resetMarker(time, range, true)
            return true
        }
        return false
    }
    
    /// Debugging purpose - refresh internal movie object
    public func refreshMovie() {
        
        // AVMovie.duration seems to be broken after edit operation
        // S-08: graceful return instead of preconditionFailure (user-reachable crash path)
        guard let data: Data = internalMovie.movHeader else {
            LoggingSystem.video.error("\(self.ts()) Failed to create Data from AVMovie")
            NSSound.beep()
            return
        }
        // S-08: graceful return instead of preconditionFailure
        guard self.reloadMovie(from: data) else {
            LoggingSystem.video.error("\(self.ts()) Failed to create AVMovie from Data")
            NSSound.beep()
            return
        }
        do {
            let prop: CMTime = internalMovie.duration
            let calc: CMTime = internalMovie.range.duration // extension
            if prop != calc {
                LoggingSystem.video.notice("\(self.ts()) AVMovie.duration discrepancy detected")
                LoggingSystem.video.notice("\(self.ts())  Property: \(Int(prop.value))/\(Int(prop.timescale))")
                LoggingSystem.video.notice("\(self.ts())  Calculated: \(Int(calc.value))/\(Int(calc.timescale))")
            }
        }
    }
    
    /// Refresh selection marker position
    ///
    /// - Parameters:
    ///   - time: original insertionTime
    ///   - range: original selection
    ///   - notify: trigger notification for GUI update
    public func resetMarker(_ time: CMTime, _ range: CMTimeRange, _ notify: Bool) {
        
        precondition(validateRange(range, false), "ERROR: Invalid range: \(range)")
        precondition(validateTime(time), "ERROR: Invalid time: \(time)")
        
        insertionTime = time
        selectedTimeRange = range
        if notify {
            internalMovieDidChange(insertionTime, selectedTimeRange)
        }
    }
    
    /// Refresh Internal movie using Data
    ///
    /// - Parameter data: MovieHeader data
    /// - Returns: true if success
    public func reloadMovie(from data: Data?) -> Bool {
        
        if let data = data {
            let newMovie = AVMutableMovie(data: data)
            internalMovie = newMovie
            return true
        }
        return false
    }
    
    /* ============================================ */
    // MARK: - private method - movie management
    /* ============================================ */
    
    /// Trigger notification to update GUI when the internal movie is edited.
    /// userInfo will contain timeValueKey and timeRangeValueKey.
    ///
    /// - Parameters:
    ///   - time: Preferred cursor position in CMTime
    ///   - range: Preferred selection range in CMTimeRange
    private func internalMovieDidChange(_ time: CMTime, _ range: CMTimeRange) {
        
        let timeValue: NSValue = NSValue(time: time)
        let timeRangeValue: NSValue = NSValue(timeRange: range)
        let userInfo: [AnyHashable:Any] = [timeValueInfoKey:timeValue,
                                           timeRangeValueInfoKey:timeRangeValue]
        let notification = Notification(name: .movieWasMutated,
                                        object: self, userInfo: userInfo)
        NotificationCenter.default.post(notification)
    }
    
    /// Reset inspector properties cache (on movie edit)
    private func flushCachedValues() {
        
        cachedMediaDataPaths = nil
        cachedVideoFPSs = nil
        cachedVideoDataSizes = nil
        cachedAudioDataSizes = nil
        cachedVideoFormats = nil
        cachedAudioFormats = nil
    }
    
    /* ============================================ */
    // MARK: - public method - properties (headerSize, movieRange, etc.)
    /* ============================================ */
    
    /// Calculate movie header size information
    public func headerSize() -> boxSize {
        let movie = internalMovie
        let tracks = movie.tracks
        var size: boxSize = boxSize()
        
        if let data = movie.movHeader {
            let headerSize: Int64 = Int64(data.count)
            var videoSize: Int64 = 0, videoCount: Int64 = 0
            var audioSize: Int64 = 0, audioCount: Int64 = 0
            var otherSize: Int64 = 0, otherCount: Int64 = 0
            
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
        let range: CMTimeRange = internalMovie.range
        return range
    }
    
    /// Get Internal movie duration (calculated)
    ///
    /// - Returns: CMTime
    public func movieDuration() -> CMTime {
        let duration: CMTime = internalMovie.range.duration
        return duration
    }
    
    /// Get minimum resolution of movieTimeScale
    ///
    /// - Returns: CMTime of 1 per movie timeScale
    public func movieResolution() -> CMTime {
        let timeScale: CMTimeScale = internalMovie.timescale
        let resolution: CMTime = CMTimeMake(value: 1, timescale: timeScale)
        return resolution
    }
    
    /// Validate all tracks and return Reference or Self-Contained state.
    ///
    /// - Returns: OptionSet with .hasSelfContTrack and .hasReferenceTrack
    public func evalRefOrSelfCont() -> RefOrSelfCont {
        var flag: RefOrSelfCont = []
        for track in internalMovie.tracks {
            if track.isSelfContained {
                flag = flag.union(.hasSelfContTrack)
            } else {
                flag = flag.union(.hasReferenceTrack)
            }
        }
        return flag
    }
    
    /// Direct query the referencing URLs of internalMovie.
    /// - Unlike mediaDataPaths() this does not use cached operation.
    /// - Returns: all referenced file URLs by every track samples
    public func queryMediaDataURLs() -> [URL]? {
        let urls: [URL]? = internalMovie.findReferenceURLs()
        return urls
    }
}
