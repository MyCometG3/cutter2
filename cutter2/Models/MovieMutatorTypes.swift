import Foundation

public struct boxSize {
    var headerSize: Int64 = 0
    var videoSize: Int64 = 0, videoCount: Int64 = 0
    var audioSize: Int64 = 0, audioCount: Int64 = 0
    var otherSize: Int64 = 0, otherCount: Int64 = 0
}

/// type of dimensions - for use in dimensions(of:)
enum dimensionsType {
    case clean
    case production
    case encoded
}

struct RefOrSelfCont: OptionSet {
    let rawValue: Int
    static let hasReferenceTrack = RefOrSelfCont(rawValue: 1<<0)
    static let hasSelfContTrack = RefOrSelfCont(rawValue: 1<<1)
}
