//
//  MovieMutatorTypes.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/04.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation

/// Size and track-count information for a movie header and its sample data.
public struct boxSize {
    /// The movie header size in bytes.
    public internal(set) var headerSize: Int64 = 0
    /// The combined video sample-data size in bytes and video track count.
    public internal(set) var videoSize: Int64 = 0, videoCount: Int64 = 0
    /// The combined audio sample-data size in bytes and audio track count.
    public internal(set) var audioSize: Int64 = 0, audioCount: Int64 = 0
    /// The combined sample-data size in bytes and track count for non-video/audio tracks.
    public internal(set) var otherSize: Int64 = 0, otherCount: Int64 = 0
    
    /// Creates size and track-count information.
    ///
    /// - Parameters:
    ///   - headerSize: The movie header size in bytes.
    ///   - videoSize: The combined video sample-data size in bytes.
    ///   - videoCount: The number of video tracks.
    ///   - audioSize: The combined audio sample-data size in bytes.
    ///   - audioCount: The number of audio tracks.
    ///   - otherSize: The combined sample-data size in bytes for other tracks.
    ///   - otherCount: The number of other tracks.
    public init(
        headerSize: Int64 = 0,
        videoSize: Int64 = 0,
        videoCount: Int64 = 0,
        audioSize: Int64 = 0,
        audioCount: Int64 = 0,
        otherSize: Int64 = 0,
        otherCount: Int64 = 0
    ) {
        self.headerSize = headerSize
        self.videoSize = videoSize
        self.videoCount = videoCount
        self.audioSize = audioSize
        self.audioCount = audioCount
        self.otherSize = otherSize
        self.otherCount = otherCount
    }
}

/// type of dimensions - for use in dimensions(of:)
public enum dimensionsType {
    /// The clean-aperture dimensions.
    case clean
    /// The production-aperture dimensions.
    case production
    /// The encoded pixel dimensions.
    case encoded
}

/// Describes whether a movie contains reference or self-contained tracks.
public struct RefOrSelfCont: OptionSet, Sendable {
    /// The raw option-set value.
    public let rawValue: Int
    /// Indicates that at least one reference track is present.
    public static let hasReferenceTrack = RefOrSelfCont(rawValue: 1<<0)
    /// Indicates that at least one self-contained track is present.
    public static let hasSelfContTrack = RefOrSelfCont(rawValue: 1<<1)
    
    /// Creates a reference/self-contained track option set from its raw value.
    ///
    /// - Parameter rawValue: The raw option-set value.
    public init(rawValue: Int) { self.rawValue = rawValue }
}
