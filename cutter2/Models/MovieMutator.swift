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
    // - MovieMutator+Clipboard.swift: Clipboard operations
    // - MovieMutator+Edit.swift: Edit operations (cut, copy, paste, delete)
    // - MovieMutator+Transform.swift: Transform operations (clap/pasp)
    // - MovieMutator+Inspector.swift: Inspector utilities
    // - MovieMutator+Player.swift: AVPlayer support
    // - MovieMutator+Export.swift: Export/write support
}
