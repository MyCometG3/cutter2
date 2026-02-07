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
    
    /// Make new AVPlayerItem for internalMovie
    ///
    /// - Returns: AVPlayerItem
    public func makePlayerItem() -> AVPlayerItem {
        let asset: AVAsset = internalMovie.copy() as! AVAsset
        let playerItem: AVPlayerItem = AVPlayerItem(asset: asset)
        if let comp = makeVideoComposition() {
            playerItem.videoComposition = comp
        }
        return playerItem
    }
    
    /* ============================================ */
    // MARK: private method
    /* ============================================ */
    
    /// Make new AVVideoComposition for internalMovie
    ///
    /// - Returns: AVVideoComposition
    private func makeVideoComposition() -> AVVideoComposition? {
        let vCount = internalMovie.tracks(withMediaType: .video).count
        if vCount > 1 {
            let comp: AVVideoComposition = AVVideoComposition(propertiesOf: internalMovie)
            return comp
        }
        return nil
    }
}
