import Foundation
import AVFoundation

@MainActor
extension MovieMutatorBase {
    /// visual size of media in a track using CMVideoFormatDescription
    /// - Parameters:
    ///   - type: dimensionsType
    ///   - track: AVMutableMovieTrack
    /// - Returns: visual size of media in a track
    private func mediaDimensionsFD(of type: dimensionsType, in track: AVMutableMovieTrack) -> NSSize {
        guard(track.mediaType == .video) else { return NSSize.zero }
        
        var size = NSZeroSize
        let formats = track.formatDescriptions as! [CMFormatDescription] // CF typealias — as! always succeeds
        for format in formats {
            switch type {
            case .clean:
                size = CMVideoFormatDescriptionGetPresentationDimensions(format,
                                                                         usePixelAspectRatio: true,
                                                                         useCleanAperture: true)
            case .production:
                size = CMVideoFormatDescriptionGetPresentationDimensions(format,
                                                                         usePixelAspectRatio: true,
                                                                         useCleanAperture: false)
            case .encoded:
                size = CMVideoFormatDescriptionGetPresentationDimensions(format,
                                                                         usePixelAspectRatio: false,
                                                                         useCleanAperture: false)
            }
            if size != NSZeroSize {
                break
            }
        }
        return size
    }
    
    /// visual size of media in a track using tapt atom (track aperture mode dimentions)
    /// - Parameters:
    ///   - type: dimensionsType
    ///   - track: AVMutableMovieTrack
    /// - Returns: visual size of media in a track
    private func mediaDimensionsTapt(of type: dimensionsType, in track: AVMutableMovieTrack) -> NSSize {
        guard(track.mediaType == .video) else { return NSSize.zero }
        
        var size: NSSize
        switch type {
        case .clean:      size = track.cleanApertureDimensions
        case .production: size = track.productionApertureDimensions
        case .encoded:    size = track.encodedPixelsDimensions
        }
        return size
    }
    
    /// visual size of media in a track using either FormatDescription or tapt atom
    /// - Parameters:
    ///   - type: dimensionsType
    ///   - track: AVMutableMovieTrack
    ///   - useTapt: Bool
    /// - Returns: visual size of media in a track
    public func mediaDimensions(of type: dimensionsType, in track: AVMutableMovieTrack, useTapt: Bool) -> NSSize {
        var size: NSSize
        if useTapt {
            size = mediaDimensionsTapt(of: type, in: track)
            if size == NSSize.zero {
                size = mediaDimensionsFD(of: type, in: track)
            }
        } else {
            size = mediaDimensionsFD(of: type, in: track)
        }
        return size
    }
    
    /// visual size of movie
    /// - Parameter type: dimensionsType
    /// - Returns: visual size of the movie
    public func dimensions(of type: dimensionsType) -> NSSize {
        let movie = internalMovie
        let tracks = movie.tracks(withMediaType: .video)
        guard tracks.count > 0 else {
            // use dummy size for 16:9 (commonly used for .m4a format)
            return NSSize(width: 320, height: 180)
        }
        
        var targetRect: NSRect = NSZeroRect
        var foundValidTrack = false
        for track in tracks {
            let trackTransform: CGAffineTransform = track.preferredTransform
            let size: NSSize = mediaDimensions(of: type, in: track, useTapt: acceptTapt)
            guard size != NSZeroSize else {
                LoggingSystem.video.error("\(self.ts()) Failed to get presentation dimensions for track \(track.trackID); skipping track")
                continue
            }
            
            foundValidTrack = true
            let point: NSPoint = NSPoint(x: -size.width/2, y: -size.height/2)
            let rect: NSRect = NSRect(origin: point, size: size)
            let resultedRect: NSRect = rect.applying(trackTransform)
            
            targetRect = NSUnionRect(targetRect, resultedRect)
        }
        
        guard foundValidTrack else {
            return NSSize.zero
        }
        
        let movieTransform: CGAffineTransform = movie.preferredTransform
        targetRect = targetRect.applying(movieTransform)
        
        let targetSize = NSSize(width: targetRect.width, height: targetRect.height)
        return targetSize
    }
}
