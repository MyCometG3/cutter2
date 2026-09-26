//
//  MovieMutatorBase+PresentationInfo.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/04.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation
import AVFoundation

/// Presentation information for a movie sample or time segment.
///
/// Positions are calculated relative to the movie duration when it is positive.
/// For a zero-duration movie, both relative positions remain 0.0. The values are
/// not clamped, so a range outside the movie can produce a position outside 0.0 to
/// 1.0. The sample's end position may extend beyond the queried segment's end when
/// the final sample spans that boundary.
public struct PresentationInfo {
    /// The sample or segment time range in the movie's timescale.
    public private(set) var timeRange: CMTimeRange = CMTimeRange.zero
    /// The start of `timeRange` in seconds.
    public private(set) var startSecond: Float64 = 0.0
    /// The end of `timeRange` in seconds.
    public private(set) var endSecond: Float64 = 0.0
    /// The movie duration in seconds.
    public private(set) var movieDuration: Float64 = 0.0
    /// The start position relative to the movie duration.
    public private(set) var startPosition: Float64 = 0.0
    /// The end position relative to the movie duration.
    public private(set) var endPosition: Float64 = 0.0
    
    /// Creates presentation information for a time range in a movie.
    ///
    /// - Parameters:
    ///   - range: The sample or segment time range.
    ///   - movie: The movie used to calculate the duration-relative positions.
    public init(range: CMTimeRange, of movie: AVMutableMovie) {
        timeRange = range
        startSecond = CMTimeGetSeconds(range.start)
        endSecond = CMTimeGetSeconds(range.end)
        movieDuration = CMTimeGetSeconds(movie.range.duration)
        guard movieDuration > 0 else { return }
        startPosition = startSecond / movieDuration
        endPosition = endSecond / movieDuration
    }
}

@MainActor
extension MovieMutatorBase {
    /// Tracks ordered in video-timecode-audio
    ///
    /// - Returns: array of AVMutableMovieTrack
    private func orderedTracks() -> [AVMutableMovieTrack] {
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
    private func samplePresentationInfo(_ startPTS: CMTime, _ endPTS: CMTime, from mapping: CMTimeMapping) -> PresentationInfo? {
        if !(mapping.source.duration > CMTime.zero) {
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
    private func trackTime(of samplePTS: CMTime, from mapping: CMTimeMapping) -> CMTime {
        let mediaSegment: CMTimeRange = mapping.source
        let trackSegment: CMTimeRange = mapping.target
        
        var time: CMTime = CMTimeMapTimeFromRangeToRange(samplePTS,
                                                         fromRange: mediaSegment,
                                                         toRange: trackSegment)
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
    private func mediaTime(of trackTime: CMTime, from mapping: CMTimeMapping) -> CMTime {
        let mediaSegment: CMTimeRange = mapping.source
        let trackSegment: CMTimeRange = mapping.target
        
        var time: CMTime = CMTimeMapTimeFromRangeToRange(trackTime,
                                                         fromRange: trackSegment,
                                                         toRange: mediaSegment)
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
            let target2: CMTime = CMTimeConvertScale(target,
                                                     timescale: timescale,
                                                     method: .roundAwayFromZero)
            let duration2: CMTime = CMTimeConvertScale(duration,
                                                       timescale: timescale,
                                                       method: .roundAwayFromZero)
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
        let lastSample: Bool = time == internalMovie.range.end
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
            guard !segment.isEmpty else { continue }
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
                let next: PresentationInfo? = nextInfo(of: range)
                return next
            }
        }
        return nil
    }
    
    private enum AdjacentDirection {
        case previous
        case next
    }

    private func adjacentInfo(of range: CMTimeRange,
                              direction: AdjacentDirection) -> PresentationInfo? {
        let boundary: CMTime
        let step: Int
        let sampleRange: CMTimeRange
        switch direction {
        case .previous:
            guard range.start != CMTime.zero else { return nil }
            boundary = range.start
            step = -1
            sampleRange = CMTimeRangeFromTimeToTime(start: range.start, end: range.start)
        case .next:
            guard range.end < movieDuration() else { return nil }
            boundary = range.end
            step = 1
            sampleRange = CMTimeRangeFromTimeToTime(start: range.start, end: range.end)
        }

        for track in orderedTracks() {
            let pts = track.samplePresentationTime(forTrackTime: sampleRange.start)
            guard CMTIME_IS_VALID(pts),
                  let cursor = track.makeSampleCursor(presentationTimeStamp: pts),
                  let segment = track.segment(forTrackTime: sampleRange.start),
                  !segment.isEmpty else { continue }

            let mapping = segment.timeMapping
            let mediaBoundary = direction == .previous ? mapping.source.start : mapping.source.end
            let trackBoundary = direction == .previous ? mapping.target.start : mapping.target.end
            let resolution = movieResolution()
            var reachedSegmentBoundary = false

            while (direction == .previous && cursor.presentationTimeStamp > mediaBoundary)
                    || (direction == .next && cursor.presentationTimeStamp < mediaBoundary) {
                guard cursor.stepInPresentationOrder(byCount: Int64(step)) == Int64(step) else { break }
                let crossedBoundary = direction == .previous
                    ? cursor.presentationTimeStamp <= mediaBoundary
                    : cursor.presentationTimeStamp >= mediaBoundary
                reachedSegmentBoundary = crossedBoundary
                let candidateTime = trackTime(of: cursor.presentationTimeStamp, from: mapping)
                let distance = direction == .previous
                    ? boundary - candidateTime
                    : candidateTime - boundary
                guard distance >= resolution else {
                    if crossedBoundary { break }
                    continue
                }

                let candidateRange = direction == .previous
                    ? CMTimeRangeFromTimeToTime(start: candidateTime, end: boundary)
                    : CMTimeRangeFromTimeToTime(start: boundary, end: candidateTime)
                return PresentationInfo(range: candidateRange, of: internalMovie)
            }

            let segmentDistance = direction == .previous
                ? boundary - trackBoundary
                : trackBoundary - boundary
            if reachedSegmentBoundary && segmentDistance >= resolution {
                let candidateRange = direction == .previous
                    ? CMTimeRangeFromTimeToTime(start: trackBoundary, end: boundary)
                    : CMTimeRangeFromTimeToTime(start: boundary, end: trackBoundary)
                return PresentationInfo(range: candidateRange, of: internalMovie)
            }
        }

        let testTime = direction == .previous
            ? range.start - movieResolution()
            : range.end + movieResolution()
        if let info = presentationInfoAtTime(testTime) {
            return info
        }

        let directionName = direction == .previous ? "previous" : "next"
        LoggingSystem.video.error("\(self.ts()) Cannot find \(directionName) sample's PresentationInfo for range: \(self.shortTimeString(range.start, withDecimals: false))..\(self.shortTimeString(range.end, withDecimals: false))")
        return nil
    }

    /// Query Previous sample's PresentationInfo.
    public func previousInfo(of range: CMTimeRange) -> PresentationInfo? {
        adjacentInfo(of: range, direction: .previous)
    }

    /// Query Next sample's PresentationInfo.
    public func nextInfo(of range: CMTimeRange) -> PresentationInfo? {
        adjacentInfo(of: range, direction: .next)
    }
}
