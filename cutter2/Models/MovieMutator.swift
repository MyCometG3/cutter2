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
        handler: @Sendable @escaping (T) -> Void
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

extension MovieMutator {
    
    /// Runs a throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A closure isolated to the main actor that may throw an error.
    /// - Returns: The result of the closure's operation.
    /// - Throws: Any error thrown by the closure.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () throws -> T) throws -> T {
        return try ActorUtilities.performSyncOnMainActor(block)
    }
    
    /// Runs a non-throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A non-throwing closure isolated to the main actor.
    /// - Returns: The result of the closure's operation.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () -> T) -> T {
        return ActorUtilities.performSyncOnMainActor(block)
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
