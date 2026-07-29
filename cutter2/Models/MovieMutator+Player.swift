//
//  MovieMutator+Player.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - AVPlayer support
/* ============================================ */

extension MovieMutator {
    
    /// Make new AVPlayerItem for internalMovie.
    ///
    /// The video-composition derivation path is asynchronous on macOS 15+ and
    /// falls back to the legacy synchronous API on macOS 14.
    ///
    /// - Returns: AVPlayerItem
    /// - Throws: Errors thrown by async video-composition generation on macOS 15+.
    public func makePlayerItem() async throws -> AVPlayerItem {
        guard let asset = internalMovie.copy() as? AVAsset else {
            LoggingSystem.video.error("copy() of AVMutableMovie returned non-AVAsset")
            throw CocoaError(.fileReadUnknown)
        }
        let playerItem: AVPlayerItem = AVPlayerItem(asset: asset)
        if let comp = try await makeVideoComposition(for: asset) {
            playerItem.videoComposition = comp
        }
        return playerItem
    }
    
    /* ============================================ */
    // MARK: private method
    /* ============================================ */
    
    /// Make new AVVideoComposition for the supplied asset when multiple video
    /// tracks require composition.
    ///
    /// - Parameter asset: Asset copied from `internalMovie`.
    /// - Returns: AVVideoComposition, or nil when composition is unnecessary.
    /// - Throws: Errors thrown by async AVFoundation property loading /
    ///   composition generation on macOS 15+.
    private func makeVideoComposition(for asset: AVAsset) async throws -> AVVideoComposition? {
        let vCount = try await asset.loadTracks(withMediaType: .video).count
        if vCount > 1 {
            if #available(macOS 15, *) {
                return try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
            } else {
                return AVVideoComposition(propertiesOf: asset)
            }
        }
        return nil
    }
}
