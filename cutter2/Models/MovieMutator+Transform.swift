//
//  MovieMutator+Transform.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Transform Operations
/* ============================================ */

extension MovieMutator {
    
    /* ============================================ */
    // MARK: - private method - clap/pasp
    /* ============================================ */
    
    //
    private func doReplace(_ movie: Data, _ range: CMTimeRange, _ time: CMTime) {
        guard validateRange(range, false) else {
            LoggingSystem.video.error("invalid range in doReplace")
            return
        }
        
        // perform replacement
        do {
            guard reloadMovie(from: movie) else {
                LoggingSystem.video.error("reloadMovie failed in doReplace")
                return
            }
            
            // Update Marker
            let movie = internalMovie
            let newTime: CMTime = (time < movie.range.end) ? time : movie.range.end
            let newRange: CMTimeRange = CMTimeRangeGetIntersection(range, otherRange: movie.range)
            resetMarker(newTime, newRange, true)
        }
    }
    
    //
    private func undoReplace(_ data: Data, _ range: CMTimeRange, _ time: CMTime) {
        let reloadDone: Bool = reloadAndNotify(from: data, range: range, time: time)
        guard reloadDone else {
            LoggingSystem.video.error("reloadAndNotify failed in undoReplace")
            return
        }
    }
    
    //
    private func updateFormat(_ movie: Data, using undoManager: UndoManagerWrapper) {
        
        let time = self.insertionTime
        let range = self.selectedTimeRange
        
        guard validateRange(range, false) else { NSSound.beep(); return; }
        guard let data = internalMovie.movHeader else { NSSound.beep(); return; }
        
        // register undo record
        let undoFormatHandler: @MainActor (MovieMutator) -> Void = {[data, range, time, movie, unowned undoManager] (me1) in // @escaping
            let redoFormatHandler: @MainActor (MovieMutator) -> Void = {[movie, unowned undoManager] (me2) in // @escaping
                me2.updateFormat(movie, using: undoManager)
            }
            undoManager.registerUndo(withTarget: me1, handler: redoFormatHandler)
            undoManager.setActionName("Update format")
            
            // perform undo replace
            me1.undoReplace(data, range, time)
        }
        undoManager.registerUndo(withTarget: self, handler: undoFormatHandler)
        undoManager.setActionName("Update format")
        
        // perform replacement
        self.doReplace(movie, range, time)
        refreshMovie()
    }
    
    /* ============================================ */
    // MARK: - public method - clap/pasp
    /* ============================================ */
    
    /// Returns the current video dimensions, clean-aperture, and pixel-aspect-ratio settings.
    ///
    /// - Returns: A dictionary containing the four CAPAR settings, or `nil` when the movie
    ///   has no usable video format description.
    public func clappaspDictionary() -> [AnyHashable: Any]? {
        var dict: [AnyHashable:Any] = [:]
        
        let vTracks: [AVMutableMovieTrack] = internalMovie.tracks(withMediaType: .video)
        guard vTracks.count > 0 else { NSSound.beep(); return nil }
        
        let formats: [Any] = (vTracks[0]).formatDescriptions
        guard !formats.isEmpty else { NSSound.beep(); return nil }
        // formats[0] is CMFormatDescription (CF type). as! is safe: the Swift
        // compiler guarantees the cast always succeeds ("conditional downcast
        // will always succeed"). as? is rejected by the compiler for this reason.
        // If the SDK ever changes the type hierarchy, the force-cast will trap
        // loudly rather than silently misbehave. Index 0 is safe after isEmpty guard.
        let desc = formats[0] as! CMFormatDescription
        
        dict[dimensionsKey] = CMVideoFormatDescriptionGetPresentationDimensions(desc,
                                                                                usePixelAspectRatio: false,
                                                                                useCleanAperture: false)
        
        let extCA: CFPropertyList? = CMFormatDescriptionGetExtension(desc,
                                                                     extensionKey: kCMFormatDescriptionExtension_CleanAperture)
        if let extCA = extCA,
           let width = extCA[kCMFormatDescriptionKey_CleanApertureWidth] as? NSNumber,
           let height = extCA[kCMFormatDescriptionKey_CleanApertureHeight] as? NSNumber,
           let wOffset = extCA[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] as? NSNumber,
           let hOffset = extCA[kCMFormatDescriptionKey_CleanApertureVerticalOffset] as? NSNumber {
            dict[clapSizeKey] = NSSize(width: width.intValue, height: height.intValue)
            dict[clapOffsetKey] = NSPoint(x: wOffset.intValue, y: hOffset.intValue)
        } else {
            dict[clapSizeKey] = dict[dimensionsKey]
            dict[clapOffsetKey] = NSZeroPoint
        }
        
        let extPA: CFPropertyList? = CMFormatDescriptionGetExtension(desc,
                                                                     extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio)
        if let extPA = extPA,
           let hSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as? NSNumber,
           let vSpacing = extPA[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as? NSNumber {
            dict[paspRatioKey] = NSSize(width: hSpacing.doubleValue, height: vSpacing.doubleValue)
        } else {
            dict[paspRatioKey] = NSSize(width: 1.0, height: 1.0)
        }
        
        return dict
    }
    
    /// Applies clean-aperture and pixel-aspect-ratio settings to compatible video tracks.
    ///
    /// The operation registers an undo record and skips tracks whose encoded dimensions
    /// do not match the supplied dimensions.
    ///
    /// - Parameters:
    ///   - dict: A CAPAR settings dictionary produced by `clappaspDictionary()`.
    ///   - undoManager: The undo manager used to register the transformation.
    /// - Returns: `true` when the settings are applied to at least one compatible track.
    public func applyClapPasp(_ dict: [AnyHashable:Any], using undoManager: UndoManagerWrapper) -> Bool {
        guard let clapSize = dict[clapSizeKey] as? NSSize else { return false }
        guard let clapOffset = dict[clapOffsetKey] as? NSPoint else { return false }
        guard let paspRatio = dict[paspRatioKey] as? NSSize else { return false }
        guard let dimensions = dict[dimensionsKey] as? NSSize else { return false }
        
        var count: Int = 0
        
        guard let movie = internalMovie.mutableCopy() as? AVMutableMovie else {
            LoggingSystem.video.error("mutableCopy() of AVMutableMovie returned non-AVMutableMovie")
            return false
        }
        
        let vTracks: [AVMutableMovieTrack] = movie.tracks(withMediaType: .video)
        for track in vTracks {
            // CMFormatDescription is a CF type. as! is safe: the Swift compiler
            // guarantees the cast always succeeds ("conditional downcast will
            // always succeed"). as? is rejected by the compiler for this reason.
            // If the SDK ever changes the type hierarchy, the force-cast will trap
            // loudly rather than silently misbehave.
            let formats = track.formatDescriptions as! [CMFormatDescription]
            
            // Verify if track.encodedDimension is equal to target dimensions
            var valid: Bool = false
            for format in formats {
                let rawSize: CGSize = CMVideoFormatDescriptionGetPresentationDimensions(format,
                                                                                        usePixelAspectRatio: false,
                                                                                        useCleanAperture: false)
                if dimensions == rawSize {
                    valid = true
                    break
                }
            }
            guard valid else {
                LoggingSystem.video.debug("Encoded pixels dimensions: \(track.encodedPixelsDimensions.width)x\(track.encodedPixelsDimensions.height)")
                LoggingSystem.video.debug("Production aperture dimensions: \(track.productionApertureDimensions.width)x\(track.productionApertureDimensions.height)")
                LoggingSystem.video.debug("Clean aperture dimensions: \(track.cleanApertureDimensions.width)x\(track.cleanApertureDimensions.height)")
                LoggingSystem.video.debug("Track natural size: \(track.naturalSize.width)x\(track.naturalSize.height)")
                LoggingSystem.video.debug("Required dimension: \(dimensions.width)x\(dimensions.height)")
                LoggingSystem.video.info("\(self.ts()) Different dimension for track \(track.trackID): \(track.naturalSize.width)x\(track.naturalSize.height)")
                continue
            }
            
            do {
                let ratio = paspRatio.width / paspRatio.height
                let newCAD = NSSize(width: clapSize.width * ratio, height: clapSize.height)
                let newPAD = NSSize(width: dimensions.width * ratio, height: dimensions.height)
                track.encodedPixelsDimensions = dimensions
                track.cleanApertureDimensions = newCAD
                track.productionApertureDimensions = newPAD
            }
            
            for format in formats {
                // Prepare new extensionDictionary
                guard let cfDict = CMFormatDescriptionGetExtensions(format) else { continue }
                let dict: NSMutableDictionary = NSMutableDictionary(dictionary: cfDict)
                dict[kCMFormatDescriptionExtension_VerbatimSampleDescription] = nil
                dict[kCMFormatDescriptionExtension_VerbatimISOSampleEntry] = nil
                
                // Replace CleanAperture if available
                if !validSize(clapSize) || !validPoint(clapOffset) {
                    dict[kCMFormatDescriptionExtension_CleanAperture] = nil
                } else {
                    let clap: NSMutableDictionary = [:]
                    clap[kCMFormatDescriptionKey_CleanApertureWidth] = clapSize.width
                    clap[kCMFormatDescriptionKey_CleanApertureHeight] = clapSize.height
                    clap[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] = clapOffset.x
                    clap[kCMFormatDescriptionKey_CleanApertureVerticalOffset] = clapOffset.y
                    dict[kCMFormatDescriptionExtension_CleanAperture] = clap
                }
                
                // Replace PixelAspectRatio if available
                if !validSize(paspRatio) {
                    dict[kCMFormatDescriptionExtension_PixelAspectRatio] = nil
                } else {
                    let pasp: NSMutableDictionary = [:]
                    pasp[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] = paspRatio.width
                    pasp[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] = paspRatio.height
                    dict[kCMFormatDescriptionExtension_PixelAspectRatio] = pasp
                }
                
                // Create New formatDescription as replacement
                var newFormat: CMVideoFormatDescription? = nil
                let codecType = CMFormatDescriptionGetMediaSubType(format) as CMVideoCodecType
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                let result = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                            codecType: codecType,
                                                            width: dimensions.width,
                                                            height: dimensions.height,
                                                            extensions: dict,
                                                            formatDescriptionOut: &newFormat)
                if result == noErr, let newFormat = newFormat {
                    track.replaceFormatDescription(format, with: newFormat)
                    count += 1
                } else {
                    //
                }
            }
        }
        
        if count > 0, let movie = movie.movHeader {
            // Replace movie object with undo record
            self.updateFormat(movie, using: undoManager)
            return true
        } else {
            LoggingSystem.video.error("\(self.ts()) Failed to modify CAPAR extensions")
            return false
        }
    }
}
