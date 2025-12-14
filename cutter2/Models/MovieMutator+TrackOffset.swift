//
//  MovieMutator+TrackOffset.swift
//  cutter2
//
//  Created on 2025-12-07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Track Offset Types
/* ============================================ */

/// Descriptor for a track with offset information
public struct TrackDescriptor {
    /// Persistent track ID
    public let id: CMPersistentTrackID
    
    /// Media type of the track
    public let mediaType: AVMediaType
    
    /// Duration of the track
    public let duration: CMTime
    
    /// Current offset (calculated from leading zero-duration segments)
    public var currentOffset: CMTime
}

/// Undo payload for track offset operations
struct TrackOffsetUndoPayload {
    /// Track ID that was modified
    let trackID: CMPersistentTrackID
    
    /// Delta applied to the track
    let delta: CMTime
    
    /// Removed clip data for negative offsets (for undo)
    let removedClipData: Data?
}

/// Parser for CMTime from various string formats
struct CMTimeParser {
    /// Parse time offset string into CMTime
    /// Supports:
    /// - Timecode format: HH:MM:SS.mmm (e.g., "00:01:23.456")
    /// - Frames: <number>f (e.g., "30f" or "-15f")
    /// - Seconds: plain float (e.g., "1.5" or "-2.3")
    ///
    /// - Parameters:
    ///   - string: Input string to parse
    ///   - timescale: Timescale to use for the resulting CMTime
    /// - Returns: Parsed CMTime, or nil if parsing failed
    /// - Throws: DocumentError if input is invalid
    static func parse(_ string: String, timescale: CMTimeScale) throws -> CMTime {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        // Try timecode format: HH:MM:SS.mmm or H:MM:SS.mmm
        let timecodePattern = "^(\\d{1,2}):(\\d{2}):(\\d{2})(\\.\\d+)?$"
        if let regex = try? NSRegularExpression(pattern: timecodePattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            
            let hours = Int((trimmed as NSString).substring(with: match.range(at: 1)))!
            let minutes = Int((trimmed as NSString).substring(with: match.range(at: 2)))!
            let seconds = Int((trimmed as NSString).substring(with: match.range(at: 3)))!
            
            var milliseconds = 0.0
            if match.range(at: 4).location != NSNotFound {
                let msString = (trimmed as NSString).substring(with: match.range(at: 4))
                milliseconds = Double(msString) ?? 0.0
            }
            
            let totalSeconds = Double(hours * 3600 + minutes * 60 + seconds) + milliseconds
            let result = CMTime(seconds: totalSeconds, preferredTimescale: timescale)
            
            // Check for negative values
            if result < CMTime.zero {
                throw DocumentError.negativeOffsetNotAllowed
            }
            
            return result
        }
        
        // Try frames format: <number>f
        let framesPattern = "^(-?\\d+)f$"
        if let regex = try? NSRegularExpression(pattern: framesPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            
            let framesString = (trimmed as NSString).substring(with: match.range(at: 1))
            if let frames = Int64(framesString) {
                let result = CMTime(value: frames, timescale: timescale)
                
                // Check for negative values
                if result < CMTime.zero {
                    throw DocumentError.negativeOffsetNotAllowed
                }
                
                return result
            }
        }
        
        // Try plain seconds (fallback)
        if let seconds = Double(trimmed) {
            let result = CMTime(seconds: seconds, preferredTimescale: timescale)
            
            // Check for negative values
            if result < CMTime.zero {
                throw DocumentError.negativeOffsetNotAllowed
            }
            
            return result
        }
        
        // Invalid format
        throw DocumentError.invalidTimeFormat
    }
}

/* ============================================ */
// MARK: - Track Offset Operations
/* ============================================ */

extension MovieMutator {
    
    /* ============================================ */
    // MARK: - Track descriptor cache
    /* ============================================ */
    
    /// Cache key for track offset information
    private static var trackOffsetCacheKey: UInt8 = 0
    
    /// Cached track descriptors
    private var cachedTrackDescriptors: [TrackDescriptor]? {
        get {
            objc_getAssociatedObject(self, &Self.trackOffsetCacheKey) as? [TrackDescriptor]
        }
        set {
            objc_setAssociatedObject(self, &Self.trackOffsetCacheKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// Invalidate track descriptor cache
    private func invalidateTrackDescriptorCache() {
        cachedTrackDescriptors = nil
    }
    
    /* ============================================ */
    // MARK: - Public methods
    /* ============================================ */
    
    /// Get all tracks with their current offsets
    ///
    /// Returns tracks in order: video → audio → timecode → other
    /// Caches results until internalMovie mutates
    ///
    /// - Returns: Array of track descriptors
    public func trackDescriptors() -> [TrackDescriptor] {
        // Return cached value if available
        if let cached = cachedTrackDescriptors {
            return cached
        }
        
        // Build descriptor list
        var descriptors: [TrackDescriptor] = []
        
        // Order: video → audio → timecode → other
        let videoTracks = internalMovie.tracks(withMediaType: .video)
        let audioTracks = internalMovie.tracks(withMediaType: .audio)
        let timecodeTracks = internalMovie.tracks(withMediaType: .timecode)
        
        // Get all other tracks
        var otherTracks: [AVMutableMovieTrack] = []
        for track in internalMovie.tracks {
            if track.mediaType != .video && 
               track.mediaType != .audio && 
               track.mediaType != .timecode {
                otherTracks.append(track)
            }
        }
        
        let orderedTracks = videoTracks + audioTracks + timecodeTracks + otherTracks
        
        for track in orderedTracks {
            let offset = calculateCurrentOffset(for: track)
            let descriptor = TrackDescriptor(
                id: track.trackID,
                mediaType: track.mediaType,
                duration: track.timeRange.duration,
                currentOffset: offset
            )
            descriptors.append(descriptor)
        }
        
        // Cache results
        cachedTrackDescriptors = descriptors
        return descriptors
    }
    
    /// Calculate current offset for a track by scanning leading empty/zero-duration segments
    ///
    /// - Parameter track: Track to analyze
    /// - Returns: Total offset as CMTime
    private func calculateCurrentOffset(for track: AVMutableMovieTrack) -> CMTime {
        var offset = CMTime.zero
        
        for segment in track.segments {
            let sourceStart = segment.timeMapping.source.start
            let sourceDuration = segment.timeMapping.source.duration
            let targetDuration = segment.timeMapping.target.duration
            
            // Check if this is an empty segment (inserted via insertEmptyTimeRange)
            // Empty segments have CMTIME_IS_INVALID or have zero timescale
            let isEmpty = !CMTIME_IS_VALID(sourceStart) || sourceStart.timescale == 0
            
            // Also check for traditional zero-duration segments
            let isZeroDuration = sourceDuration == CMTime.zero
            
            if isEmpty || isZeroDuration {
                // Accumulate target duration
                offset = offset + targetDuration
            } else {
                // Hit actual content - stop accumulating
                break
            }
        }
        
        return offset
    }
    
    /// Apply track offsets with transaction semantics
    ///
    /// This method validates all offsets first. If any validation fails, no changes are applied.
    /// For positive offsets, silence is inserted. For negative offsets, content is removed and
    /// stored for undo.
    ///
    /// - Parameters:
    ///   - offsets: Dictionary mapping track IDs to their desired offsets
    ///   - undoManager: Undo manager wrapper for undo/redo support
    /// - Throws: DocumentError if validation fails
    public func applyTrackOffsets(_ offsets: [CMPersistentTrackID: CMTime], undoManager: UndoManagerWrapper) throws {
        guard !offsets.isEmpty else { return }
        
        // Phase 1: Validation
        var validatedOffsets: [(track: AVMutableMovieTrack, delta: CMTime)] = []
        
        // Get ordered tracks for consistent processing
        let descriptors = trackDescriptors()
        for descriptor in descriptors {
            guard let requestedOffset = offsets[descriptor.id] else { continue }
            guard let track = internalMovie.track(withTrackID: descriptor.id) else { continue }
            
            // Calculate delta from current offset
            let delta = requestedOffset - descriptor.currentOffset
            
            // Skip if no change
            if delta == CMTime.zero {
                continue
            }
            
            // Validate CMTime
            guard CMTIME_IS_VALID(delta) else {
                throw DocumentError.trackOffsetValidationFailed
            }
            
            // Validate offset magnitude doesn't exceed track duration
            let absOffset = abs(delta.seconds)
            let trackDuration = track.timeRange.duration.seconds
            
            if absOffset > trackDuration {
                if delta < CMTime.zero {
                    LoggingSystem.video.error("Track \(descriptor.id) (\(descriptor.mediaType.rawValue)): Cannot remove \(absOffset)s from track with duration \(trackDuration)s")
                } else {
                    LoggingSystem.video.error("Track \(descriptor.id) (\(descriptor.mediaType.rawValue)): Cannot add \(absOffset)s offset to track with duration \(trackDuration)s")
                }
                throw DocumentError.trackOffsetExceedsDuration
            }
            
            validatedOffsets.append((track, delta))
        }
        
        guard !validatedOffsets.isEmpty else { return }
        
        // Phase 2: Capture current state for undo
        guard let currentMovieData = internalMovie.movHeader else {
            throw DocumentError.internalError
        }
        let currentTime = self.insertionTime
        let currentRange = self.selectedTimeRange
        
        // Phase 3: Execute mutations in order
        var undoPayloads: [TrackOffsetUndoPayload] = []
        
        do {
            for (track, delta) in validatedOffsets {
                if delta > CMTime.zero {
                    // Positive offset: insert silence
                    try insertSilence(duration: delta, at: CMTime.zero, in: track)
                    undoPayloads.append(TrackOffsetUndoPayload(trackID: track.trackID, delta: delta, removedClipData: nil))
                } else {
                    // Negative offset: remove content
                    let removeRange = CMTimeRange(start: CMTime.zero, duration: CMTime.zero - delta)
                    let clipData = try extractAndRemove(range: removeRange, from: track)
                    undoPayloads.append(TrackOffsetUndoPayload(trackID: track.trackID, delta: delta, removedClipData: clipData))
                }
            }
            
            // Phase 4: Adjust movie duration and notify
            refreshMovie()
            
            // Adjust markers if needed
            let newTime = currentTime
            let newRange = currentRange
            resetMarker(newTime, newRange, true)
            
            // Invalidate cache
            invalidateTrackDescriptorCache()
            
        } catch {
            // Rollback on error
            _ = reloadMovie(from: currentMovieData)
            resetMarker(currentTime, currentRange, false)
            throw error
        }
        
        // Phase 5: Register undo
        registerTrackOffsetUndo(
            undoManager: undoManager,
            payloads: undoPayloads,
            originalMovieData: currentMovieData,
            originalTime: currentTime,
            originalRange: currentRange
        )
    }
    
    /// Insert silence at the beginning of a track
    ///
    /// - Parameters:
    ///   - duration: Duration of silence to insert
    ///   - time: Time to insert at (typically .zero)
    ///   - track: Track to modify
    /// - Throws: Error if insertion fails
    private func insertSilence(duration: CMTime, at time: CMTime, in track: AVMutableMovieTrack) throws {
        // Insert an empty time range (gap/silence)
        track.insertEmptyTimeRange(CMTimeRange(start: time, duration: duration))
    }
    
    /// Extract and remove a time range from a track
    ///
    /// - Parameters:
    ///   - range: Time range to extract and remove
    ///   - track: Track to modify
    /// - Returns: Movie header data of the extracted clip
    /// - Throws: Error if extraction or removal fails
    private func extractAndRemove(range: CMTimeRange, from track: AVMutableMovieTrack) throws -> Data? {
        var clipData: Data? = nil
        
        // For reference tracks or as a safety measure, extract the clip first
        if !track.isSelfContained {
            // Create a clip of the removal range
            let clip = internalMovie.mutableCopy() as! AVMutableMovie
            
            // Remove everything after the range
            let rangeAfter = CMTimeRange(
                start: range.end,
                duration: clip.range.duration - range.end
            )
            if rangeAfter.duration > CMTime.zero {
                clip.removeTimeRange(rangeAfter)
            }
            
            // Remove everything before the range
            if range.start > CMTime.zero {
                let rangeBefore = CMTimeRange(start: CMTime.zero, duration: range.start)
                clip.removeTimeRange(rangeBefore)
            }
            
            clipData = clip.movHeader
            
            // Safety check for clip size
            if let data = clipData, data.count > 250_000_000 {
                LoggingSystem.video.warning("Extracted clip data exceeds 250 MB (\(data.count) bytes)")
            }
        }
        
        // Remove the range from the track
        track.removeTimeRange(range)
        
        return clipData
    }
    
    /// Register undo for track offset operation
    ///
    /// - Parameters:
    ///   - undoManager: Undo manager wrapper
    ///   - payloads: Undo payloads for each modified track
    ///   - originalMovieData: Original movie state
    ///   - originalTime: Original insertion time
    ///   - originalRange: Original selection range
    private func registerTrackOffsetUndo(
        undoManager: UndoManagerWrapper,
        payloads: [TrackOffsetUndoPayload],
        originalMovieData: Data,
        originalTime: CMTime,
        originalRange: CMTimeRange
    ) {
        let undoHandler: @Sendable (MovieMutator) -> Void = { [originalMovieData, originalTime, originalRange, payloads, unowned undoManager, unowned self] mutator in
            performSyncOnMainActor {
                // Register redo
                let redoHandler: @Sendable (MovieMutator) -> Void = { [payloads, unowned undoManager, unowned self] mutator in
                    performSyncOnMainActor {
                        // Reconstruct offsets from payloads
                        var offsets: [CMPersistentTrackID: CMTime] = [:]
                        for payload in payloads {
                            // Get current offset and add delta
                            if let track = mutator.internalMovie.track(withTrackID: payload.trackID) {
                                let currentOffset = mutator.calculateCurrentOffset(for: track)
                                offsets[payload.trackID] = currentOffset + payload.delta
                            }
                        }
                        try? mutator.applyTrackOffsets(offsets, undoManager: undoManager)
                    }
                }
                undoManager.registerUndo(withTarget: mutator, handler: redoHandler)
                undoManager.setActionName(NSLocalizedString("undo.apply_track_offsets", comment: ""))
                
                // Perform undo: restore original state
                _ = mutator.reloadMovie(from: originalMovieData)
                mutator.resetMarker(originalTime, originalRange, true)
                mutator.invalidateTrackDescriptorCache()
            }
        }
        
        undoManager.registerUndo(withTarget: self, handler: undoHandler)
        undoManager.setActionName(NSLocalizedString("undo.apply_track_offsets", comment: ""))
    }
    
    /// Parse time offset string into CMTime
    ///
    /// - Parameter string: Input string to parse
    /// - Returns: Parsed CMTime
    /// - Throws: DocumentError if parsing fails
    public func parseTimeOffset(_ string: String) throws -> CMTime {
        let timescale = internalMovie.timescale
        return try CMTimeParser.parse(string, timescale: timescale)
    }
}
