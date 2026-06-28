import Foundation

public struct boxSize {
    public internal(set) var headerSize: Int64 = 0
    public internal(set) var videoSize: Int64 = 0, videoCount: Int64 = 0
    public internal(set) var audioSize: Int64 = 0, audioCount: Int64 = 0
    public internal(set) var otherSize: Int64 = 0, otherCount: Int64 = 0

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
    case clean
    case production
    case encoded
}

public struct RefOrSelfCont: OptionSet, Sendable {
    public let rawValue: Int
    public static let hasReferenceTrack = RefOrSelfCont(rawValue: 1<<0)
    public static let hasSelfContTrack = RefOrSelfCont(rawValue: 1<<1)

    public init(rawValue: Int) { self.rawValue = rawValue }
}
