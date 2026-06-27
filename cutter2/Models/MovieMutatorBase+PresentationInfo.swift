import Foundation
import AVFoundation

/// Sample Presentation Info.
///
/// NOTE: At final sample of segment, end position could be after end of segment.
public struct PresentationInfo {
    var timeRange: CMTimeRange = CMTimeRange.zero
    var startSecond: Float64 = 0.0
    var endSecond: Float64 = 0.0
    var movieDuration: Float64 = 0.0
    var startPosition: Float64 = 0.0
    var endPosition: Float64 = 0.0
    
    init(range: CMTimeRange, of movie: AVMutableMovie) {
        timeRange = range
        startSecond = CMTimeGetSeconds(range.start)
        endSecond = CMTimeGetSeconds(range.end)
        movieDuration = CMTimeGetSeconds(movie.range.duration)
        startPosition = startSecond / movieDuration
        endPosition = endSecond / movieDuration
    }
}

@MainActor
extension MovieMutatorBase {
    /// Tracks ordered in video-timecode-audio
    ///
    /// - Returns: array of AVMutableMovieTrack
    internal func orderedTracks() -> [AVMutableMovieTrack] {
        let videoTracks: [AVMutableMovieTrack] = internalMovie.tracks(withMediaType: .video)
        let timecodeTracks: [AVMutableMovieTrack] = internalMovie.tracks(withMediaType: .timecode)
        let audioTracks: [AVMutableMovieTrack] = internalMovie.tracks(withMediaType: .audio)
        let tracks: [AVMutableMovieTrack] = videoTracks + timecodeTracks + audioTracks
        return tracks
    }
    
    /// Get presentationInfo from PTS pair and timeMapping
    ///
    /// - Parameters:
    ///   - startPTS: startPTS (mediaTime)
    ///   - endPTS: endPTS (mediaTime)
    ///   - mapping: timeMapping
    /// - Returns: PresentationInfo (trackTime)
    internal func samplePresentationInfo(_ startPTS: CMTime, _ endPTS: CMTime, from mapping: CMTimeMapping) -> PresentationInfo? {
        if (mapping.source.duration > CMTime.zero) == false {
            return nil
        }
        
        // Get sample timeRange and PresentationInfo
        let start: CMTime = trackTime(of: startPTS, from: mapping)
        let end: CMTime = trackTime(of: endPTS, from: mapping)
        let range: CMTimeRange = CMTimeRangeFromTimeToTime(start: start, end: end)
        let info: PresentationInfo = PresentationInfo(range: range, of: internalMovie)
        return info
    }
    
    /// Convert mediaTime to trackTime using timeMapping
    ///
    /// - Parameters:
    ///   - samplePTS: mediaTime
    ///   - mapping: timeMapping
    /// - Returns: trackTime in Movie Timescale
    internal func trackTime(of samplePTS: CMTime, from mapping: CMTimeMapping) -> CMTime {
        let mediaSegment: CMTimeRange = mapping.source
        let trackSegment: CMTimeRange = mapping.target
        
        var time: CMTime =
            CMTimeMapTimeFromRangeToRange(samplePTS, fromRange: mediaSegment, toRange: trackSegment)
        time = CMTimeConvertScale(time, timescale: internalMovie.timescale, method: .roundAwayFromZero)
        time = CMTimeClampToRange(time, range: trackSegment)
        return time
    }
    
    /// Convert trackTime to mediaTime using timeMapping
    ///
    /// - Parameters:
    ///   - trackTime: trackTime
    ///   - mapping: timeMapping
    /// - Returns: mediaTime
    internal func mediaTime(of trackTime: CMTime, from mapping: CMTimeMapping) -> CMTime {
        let mediaSegment: CMTimeRange = mapping.source
        let trackSegment: CMTimeRange = mapping.target
        
        var time: CMTime =
            CMTimeMapTimeFromRangeToRange(trackTime, fromRange: trackSegment, toRange: mediaSegment)
        time = CMTimeClampToRange(time, range: mediaSegment)
        return time
    }
    
    /// Convert Float64 to CMTime value of internalMovie.
    ///
    /// - Parameter position: Float64 as relative position of internalMovie (0.0 - 1.0)
    /// - Returns: CMTime at the position of internalMovie
    public func timeOfPosition(_ position: Float64) -> CMTime {
        let position: Float64 = clampPosition(position)
        let duration: CMTime = self.movieDuration()
        let target: CMTime = CMTimeMultiplyByFloat64(duration, multiplier: position)
        return target
    }
    
    /// Convert CMTime to Float64 value of internalMovie.
    ///
    /// - Parameter target: CMTime value
    /// - Returns: Float64 as relative position of internalMovie (0.0 - 1.0)
    public func positionOfTime(_ target: CMTime) -> Float64 {
        var position: Float64 = 0.0
        let duration: CMTime = self.movieDuration()
        if duration.timescale == target.timescale {
            // use movie/track timescale resolution
            position = Float64(target.value) / Float64(duration.value)
        } else {
            let timescale: CMTimeScale = internalMovie.timescale
            let target2: CMTime =
                CMTimeConvertScale(target, timescale: timescale, method: .roundAwayFromZero)
            let duration2: CMTime =
                CMTimeConvertScale(duration, timescale: timescale, method: .roundAwayFromZero)
            position = Float64(target2.value) / Float64(duration2.value)
        }
        return clampPosition(position)
    }
    
    /// Get PresentationInfo struct of position
    ///
    /// - Parameter position: Float64 as relative position of internalMovie (0.0 - 1.0)
    /// - Returns: PresentationInfo of the position
    public func presentationInfoAtPosition(_ position: Float64) -> PresentationInfo? {
        let time = timeOfPosition(position)
        let valid: Bool = CMTIME_IS_VALID(time)
        return (valid ? presentationInfoAtTime(time) : nil)
    }
    
    /// Query current sample's PresentationInfo at CMTime
    ///
    /// - Parameter time: CMTime at the position of internalMovie
    /// - Returns: PresentationInfo of the position
    public func presentationInfoAtTime(_ time: CMTime) -> PresentationInfo? {
        var time: CMTime = CMTimeClampToRange(time, range: internalMovie.range)
        let lastSample: Bool = (time == internalMovie.range.end) ? true : false
        if lastSample {
            // Adjust micro difference from tail of movie
            time = time - movieResolution()
        }
        
        for track: AVMutableMovieTrack in orderedTracks() {
            // Get AVSampleCursor/AVAssetTrackSegment at specified track time
            let mediaRange = track.mediaPresentationTimeRange
            guard mediaRange.start <= time && time <= mediaRange.end else { continue }
            let pts = track.samplePresentationTime(forTrackTime: time)
            guard CMTIME_IS_VALID(pts) else { continue }
            guard let cursor: AVSampleCursor = track.makeSampleCursor(presentationTimeStamp: pts)
                else { continue }
            guard let segment: AVAssetTrackSegment = track.segment(forTrackTime: time)
                else { continue }
            guard (segment.isEmpty == false) else { continue }
            // Prepare
            let mapping: CMTimeMapping = segment.timeMapping
            let startPTS: CMTime = cursor.presentationTimeStamp
            let endPTS: CMTime = cursor.presentationTimeStamp + cursor.currentSampleDuration
            guard let info: PresentationInfo = samplePresentationInfo(startPTS,
                                                                      endPTS,
                                                                      from: mapping)
                else { continue }
            if info.timeRange.duration > CMTime.zero {
                return info
            } else {
                // Exact sample is invisible (zero length in track timescale)
                let range: CMTimeRange = info.timeRange
                let info: PresentationInfo? = nextInfo(of: range)
                return info
            }
        }
        return nil
    }
    
    /// Query Previous sample's PresentationInfo
    ///
    /// - Parameter range: current sample's Presentation CMTimeRange in TrackTime
    /// - Returns: PresentationInfo of previous sample
    public func previousInfo(of range: CMTimeRange) -> PresentationInfo? {
        // Check if this is initial sample in internalMovie
        if range.start == CMTime.zero {
            return nil
        }
        
        for track: AVMutableMovieTrack in orderedTracks() {
            // Get AVSampleCursor/AVAssetTrackSegment at range.start
            let pts = track.samplePresentationTime(forTrackTime: range.start)
            guard CMTIME_IS_VALID(pts) else { continue }
            guard let cursor: AVSampleCursor = track.makeSampleCursor(presentationTimeStamp: pts)
                else { continue }
            guard let segment: AVAssetTrackSegment = track.segment(forTrackTime: range.start)
                else { continue }
            guard (segment.isEmpty == false) else { continue }
            // Prepare
            let mapping = segment.timeMapping
            let trackSegmentMin: CMTime = mapping.target.start
            let mediaSegmentMin: CMTime = mapping.source.start
            let resolution = movieResolution()
            // Seek by Step AVSampleCursor backward (current segment only)
            while cursor.presentationTimeStamp > mediaSegmentMin {
                guard cursor.stepInPresentationOrder(byCount: -1) == -1 else { break }
                if cursor.presentationTimeStamp > mediaSegmentMin {
                    let sampleStartPTS: CMTime = cursor.presentationTimeStamp
                    let sampleStartTT: CMTime = trackTime(of: sampleStartPTS, from: mapping)
                    if (range.start - sampleStartTT) < resolution { continue }
                    let pRange: CMTimeRange =
                        CMTimeRangeFromTimeToTime(start: sampleStartTT, end: range.start)
                    let info: PresentationInfo = PresentationInfo(range: pRange, of: internalMovie)
                    return info
                } else {
                    if (range.start - trackSegmentMin) < resolution { break }
                    let pRange: CMTimeRange =
                        CMTimeRangeFromTimeToTime(start: trackSegmentMin, end: range.start)
                    let info: PresentationInfo = PresentationInfo(range: pRange, of: internalMovie)
                    return info
                }
            }
        }
        
        // Try to handle track segment boundary
        // Offset 1/movie.timescale as micro difference to test
        let testTime: CMTime = range.start - movieResolution()
        if let info = presentationInfoAtTime(testTime) {
            return info
        }
        
        preconditionFailure("ERROR: Cannot find previous sample's PresentationInfo")
    }
    
    /// Query Next sample's PresentationInfo
    ///
    /// - Parameter range: current sample's Presentation CMTimeRange in TrackTime
    /// - Returns: PresentationInfo of next sample
    public func nextInfo(of range: CMTimeRange) -> PresentationInfo? {
        // Check if this is last sample in internalMovie
        if range.end >= self.movieDuration() {
            return nil
        }
        
        for track: AVMutableMovieTrack in orderedTracks() {
            // Get AVSampleCursor/AVAssetTrackSegment at range.start
            let pts = track.samplePresentationTime(forTrackTime: range.start)
            guard CMTIME_IS_VALID(pts) else { continue }
            guard let cursor: AVSampleCursor = track.makeSampleCursor(presentationTimeStamp: pts)
                else { continue }
            guard let segment: AVAssetTrackSegment = track.segment(forTrackTime: range.start)
                else { continue }
            guard (segment.isEmpty == false) else { continue }
            // Prepare
            let mapping = segment.timeMapping
            let trackSegmentMax: CMTime = mapping.target.end
            let mediaSegmentMax: CMTime = mapping.source.end
            let resolution = movieResolution()
            // Seek by Step AVSampleCursor forward (current segment only)
            while cursor.presentationTimeStamp < mediaSegmentMax {
                guard cursor.stepInPresentationOrder(byCount: +1) == +1 else { break }
                if cursor.presentationTimeStamp < mediaSegmentMax {
                    let sampleStartPTS: CMTime = cursor.presentationTimeStamp
                    let sampleStartTT: CMTime = trackTime(of: sampleStartPTS, from: mapping)
                    if (sampleStartTT - range.end) < resolution { continue }
                    let nRange: CMTimeRange =
                        CMTimeRangeFromTimeToTime(start: range.end, end: sampleStartTT)
                    let info: PresentationInfo = PresentationInfo(range: nRange, of: internalMovie)
                    return info
                } else {
                    if (trackSegmentMax - range.end) < resolution { break }
                    let nRange: CMTimeRange =
                        CMTimeRangeFromTimeToTime(start: range.end, end: trackSegmentMax)
                    let info: PresentationInfo = PresentationInfo(range: nRange, of: internalMovie)
                    return info
                }
            }
        }
        
        // Try to handle track segment boundary
        // Offset 1/movie.timescale as micro difference to test
        let testTime: CMTime = range.end + movieResolution()
        if let info = presentationInfoAtTime(testTime) {
            return info
        }
        
        preconditionFailure("ERROR: Cannot find next sample's PresentationInfo")
    }
}
