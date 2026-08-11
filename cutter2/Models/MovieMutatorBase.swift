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
    
    /// Creates a mutator with a mutable copy of the supplied movie.
    ///
    /// - Parameter movie: The movie to copy into the mutator.
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
    
    /// The mutable movie being edited.
    ///
    /// Replacing the movie also clears cached inspector values.
    public var internalMovie: AVMutableMovie {
        didSet {
            flushCachedValues() // Reset inspector properties cache
        }
    }
    
    /// The current insertion marker time in the movie's timescale.
    public var insertionTime: CMTime = CMTime.zero
    
    /// The selected time range in the movie's timescale.
    public var selectedTimeRange: CMTimeRange = CMTimeRange()
    
    /// The formatter used for diagnostic timestamps.
    public var timestampFormatter: DateFormatter
    
    /// Callback used to restore user interaction after an asynchronous operation.
    public var unblockUserInteraction: (@Sendable () -> Void)? = nil
    
    /// Progress stream continuation for asynchronous progress reporting.
    internal var progressContinuation: AsyncStream<Float>.Continuation?
    
    /// The current movie writer used to cancel an export or write operation.
    public var currentMovieWriter: MovieWriter? = nil
    
    /// Whether clean-aperture detection should respect the `tapt` atom.
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
    
    /// Validates movie clip data by creating a movie and checking that it has a positive duration.
    ///
    /// - Parameter data: Serialized movie data to validate.
    /// - Returns: `true` when the data describes a clip with a positive duration.
    @inline(__always) public func validateClipData(_ data: Data) -> Bool {
        let clip = AVMutableMovie(data: data, options: nil)
        return validateClip(clip)
    }
    
    /// Validates that a movie has a positive duration.
    ///
    /// - Parameter clip: The movie clip to validate.
    /// - Returns: `true` when the clip duration is greater than zero.
    @inline(__always) public func validateClip(_ clip: AVMutableMovie) -> Bool {
        return clip.range.duration > CMTime.zero
    }
    
    /// Checks whether a time lies within the internal movie range, including its boundaries.
    ///
    /// - Parameter time: The movie time to validate.
    /// - Returns: `true` when `time` is within the movie range.
    @inline(__always) public func validateTime (_ time: CMTime) -> Bool {
        let movieRange: CMTimeRange = self.movieRange()
        return (movieRange.start <= time && time <= movieRange.end)
    }
    
    /// Checks whether a time range lies within the internal movie range.
    ///
    /// A non-positive-duration range is valid only when `needsDuration` is `false` and its
    /// start time lies within the movie range.
    ///
    /// - Parameters:
    ///   - range: The movie time range to validate.
    ///   - needsDuration: Whether a positive duration is required.
    /// - Returns: `true` when the range satisfies the movie-boundary and duration rules.
    @inline(__always) public func validateRange(_ range: CMTimeRange, _ needsDuration: Bool) -> Bool {
        let movieRange: CMTimeRange = self.movieRange()
        return ((range.duration > CMTime.zero)
                ? (movieRange.start <= range.start && range.end <= movieRange.end)
                : (needsDuration ? false : validateTime(range.start)))
    }
    
    /// Clamps a time to the internal movie range, including its boundaries.
    ///
    /// - Parameter time: The time to clamp.
    /// - Returns: The clamped time.
    @inline(__always) public func clampTime(_ time: CMTime) -> CMTime {
        let movieRange: CMTimeRange = self.movieRange()
        return CMTimeClampToRange(time, range: movieRange)
    }
    
    /// Clamps a time range to the internal movie range.
    ///
    /// Positive-duration ranges are intersected with the movie range. Non-positive-duration
    /// ranges retain zero duration and clamp only their start time.
    ///
    /// - Parameter range: The time range to clamp.
    /// - Returns: The clamped time range.
    @inline(__always) public func clampRange(_ range: CMTimeRange) -> CMTimeRange {
        let movieRange: CMTimeRange = self.movieRange()
        return ((range.duration > CMTime.zero)
                ? (CMTimeRangeGetIntersection(range, otherRange: movieRange))
                : (CMTimeRange(start: clampTime(range.start), duration: .zero)))
    }
    
    /// Checks whether a relative movie position is within the inclusive 0.0 to 1.0 range.
    ///
    /// - Parameter position: The relative movie position to validate.
    /// - Returns: `true` when the position is between 0.0 and 1.0.
    @inline(__always) public func validatePosition(_ position: Float64) -> Bool {
        return (position >= 0.0 && position <= 1.0) ? true : false
    }
    
    /// Clamps a relative movie position to the inclusive 0.0 to 1.0 range.
    ///
    /// - Parameter position: The relative movie position to clamp.
    /// - Returns: The clamped relative position.
    @inline(__always) public func clampPosition(_ position: Float64) -> Float64 {
        return min(max(position, 0.0), 1.0)
    }
    
    /// Checks whether a size has positive width and height that are not NaN.
    ///
    /// - Parameter size: The size to validate.
    /// - Returns: `true` when both dimensions are positive and not NaN.
    @inline(__always) public func validSize(_ size: NSSize) -> Bool {
        if size.width.isNaN || size.height.isNaN { return false }
        if size.width <= 0 || size.height <= 0 { return false }
        return true
    }
    
    /// Checks whether a point has non-NaN coordinates.
    ///
    /// - Parameter point: The point to validate.
    /// - Returns: `true` when neither coordinate is NaN.
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
        
        // Clamp insertionTime and selection into the new range.
        var clampedTime: CMTime = clampTime(insertionTime)
        var clampedRange: CMTimeRange = clampRange(selectedTimeRange)
        
        // Reset invalid time/range
        clampedTime = (validateTime(clampedTime) ? clampedTime : clampTime(clampedTime))
        clampedRange = (validateRange(clampedRange, false) ? clampedRange : clampRange(clampedRange))
        
        // Notify observers after internalMovie is replaced.
        resetMarker(clampedTime, clampedRange, true)
        
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
        
        guard validateRange(range, false), validateTime(time) else {
            LoggingSystem.video.error("\(self.ts()) Invalid marker state: time=\(CMTimeGetSeconds(time)) range=\(CMTimeGetSeconds(range.start))...\(CMTimeGetSeconds(range.end))")
            return
        }
        
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
    
    /// Calculates the movie header and sample-data size information.
    ///
    /// The returned byte sizes are grouped by video, audio, and other tracks; the
    /// corresponding counts contain the number of tracks in each group. When the
    /// movie header cannot be read, all fields remain zero.
    ///
    /// - Returns: Header and per-track sample-data sizes and track counts in bytes.
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
    
    /// Returns the union of all track time ranges in the internal movie.
    ///
    /// - Returns: The internal movie's track range in its movie timescale.
    public func movieRange() -> CMTimeRange {
        let range: CMTimeRange = internalMovie.range
        return range
    }
    
    /// Returns the duration of the internal movie's union of track ranges.
    ///
    /// - Returns: The internal movie range duration in its movie timescale.
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
