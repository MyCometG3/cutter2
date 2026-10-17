//
//  MovieMutator.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: -
/* ============================================ */

extension NSPasteboard.PasteboardType {
    static let movieMutator = NSPasteboard.PasteboardType("com.mycometg3.cutter.MovieMutator")
}

/* ============================================ */
// MARK: - Actor isolation
/* ============================================ */

@MainActor
final class UndoManagerWrapper {
    private let undoManager: UndoManager

    init(_ undoManager: UndoManager) {
        self.undoManager = undoManager
    }

    func registerUndo<T: AnyObject>(
        withTarget target: T,
        handler: @MainActor @escaping (T) -> Void
    ) {
        undoManager.registerUndo(withTarget: target, handler: handler)
    }

    func setActionName(_ actionName: String) {
        undoManager.setActionName(actionName)
    }

    func removeAllActions(withTarget target: AnyObject) {
        undoManager.removeAllActions(withTarget: target)
    }
}

/* ============================================ */
// MARK: -
/* ============================================ */

/// Wrapper of AVMutableMovie as model object of movie editor
@MainActor
class MovieMutator: MovieMutatorBase {
    // All functionality has been moved to extensions:
    // - MovieMutator+Edit.swift: Edit operations (cut, copy, paste, delete)
    // - MovieMutator+Transform.swift: Transform operations (clap/pasp)
    // - MovieMutator+Inspector.swift: Inspector utilities
    // - MovieMutator+Export.swift: Export/write support

    /* ============================================ */
    // MARK: - Clipboard Operations
    /* ============================================ */

    /// Read movie clip data from PasteBoard
    ///
    /// - Returns: Data of movie header
    internal func readClipFromPBoard() -> Data? {
        let pBoard: NSPasteboard = NSPasteboard.general

        // extract movie header data from PBoard
        let data: Data? = pBoard.data(forType: .movieMutator)
        return data
    }

    /// Write movie header data to PasteBoard
    ///
    /// - Parameter data: Data of movie header
    /// - Returns: true if success
    internal func writeClipToPBoard(_ data: Data) -> Bool {
        // register data to PBoard
        let pBoard: NSPasteboard = NSPasteboard.general
        pBoard.clearContents()
        let result = pBoard.setData(data, forType: .movieMutator)
        return result
    }

    /// Write movie clip data to PasteBoard
    ///
    /// - Parameter range: CMTimeRange of clip
    /// - Returns: Data of movie header
    internal func writeRangeToPBoard(_ range: CMTimeRange) -> Data? {
        guard let clip = self.movieClip(range) else { return nil }
        guard let data = clip.movHeader else { return nil }
        guard self.writeClipToPBoard(data) else { return nil }
        return data
    }

    /// Check if pasteboard has valid movie clip
    ///
    /// - Returns: true if available
    public func validateClipFromPBoard() -> Bool {
        let pBoard: NSPasteboard = NSPasteboard.general

        if let _ = pBoard.data(forType: .movieMutator) {
            return true
        } else {
            return false
        }
    }

    /* ============================================ */
    // MARK: - AVPlayer support
    /* ============================================ */

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
