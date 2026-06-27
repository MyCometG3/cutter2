import Foundation

public struct boxSize {
    var headerSize: Int64 = 0
    var videoSize: Int64 = 0, videoCount: Int64 = 0
    var audioSize: Int64 = 0, audioCount: Int64 = 0
    var otherSize: Int64 = 0, otherCount: Int64 = 0
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
