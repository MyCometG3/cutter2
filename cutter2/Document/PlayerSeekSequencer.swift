//
//  PlayerSeekSequencer.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import AVFoundation

/// Owns the player reload/seek suppression state machine.
///
/// - Seek generations invalidate every superseded seek completion.
/// - Suppression is released only by the current seek and reload generation.
/// - The seek generation is advanced before a superseding seek or item replacement.
///
/// This type performs state transitions only; AVPlayer, MovieMutator, and GUI side effects stay in Document.
/// Every method is MainActor-isolated. Nonisolated callers must reach it through `ActorUtilities.performSyncOnMainActor`.
/// MainActor execution is reentrant, so only generation snapshots may cross awaits. Stale tokens must be no-ops.
/// `SeekToken` owns no mutable state and is safe to capture in `@Sendable` completion handlers.
@MainActor
final class PlayerSeekSequencer {

    struct SeekToken: Sendable {
        let seekGeneration: UInt64
        let reloadGeneration: UInt64
    }

    private(set) var reloadGeneration: UInt64 = 0
    private(set) var seekGeneration: UInt64 = 0
    private(set) var suppressQueryPosition: Bool = false

    private var reloadTask: Task<Void, Never>? = nil
    private var suppressionWatchdogTask: Task<Void, Never>? = nil
    private let suppressionWatchdogNanoseconds: UInt64
    private var isInvalidated = false

    init(suppressionWatchdogNanoseconds: UInt64 = 5_000_000_000) {
        self.suppressionWatchdogNanoseconds = suppressionWatchdogNanoseconds
    }

    func suppressForReload() {
        self.suppressQueryPosition = true
    }

    func beginReload() -> UInt64 {
        self.reloadGeneration += 1
        self.reloadTask?.cancel()
        self.cancelSuppressionWatchdog()
        return self.reloadGeneration
    }

    func registerReloadTask(_ task: Task<Void, Never>) {
        self.reloadTask = task
    }

    func reloadTaskDidFinish(generation: UInt64) {
        guard self.reloadGeneration == generation else { return }
        self.reloadTask = nil
    }

    func cancelReloadTask() {
        self.reloadTask?.cancel()
        self.reloadTask = nil
    }

    func beginUserSeek() -> SeekToken {
        self.seekGeneration += 1
        self.cancelSuppressionWatchdog()
        return SeekToken(seekGeneration: self.seekGeneration,
                         reloadGeneration: self.reloadGeneration)
    }

    func beginItemReplacement(expectedReloadGeneration: UInt64) -> SeekToken? {
        guard self.reloadGeneration == expectedReloadGeneration else { return nil }
        self.seekGeneration += 1
        self.cancelSuppressionWatchdog()
        return SeekToken(seekGeneration: self.seekGeneration,
                         reloadGeneration: self.reloadGeneration)
    }

    func isCurrent(_ token: SeekToken) -> Bool {
        return !self.isInvalidated
            && self.seekGeneration == token.seekGeneration
            && self.reloadGeneration == token.reloadGeneration
    }

    func canReleaseSuppression(_ token: SeekToken) -> Bool {
        return self.reloadGeneration == token.reloadGeneration
    }

    func releaseSuppression(for token: SeekToken) {
        guard self.isCurrent(token) else { return }
        self.cancelSuppressionWatchdog()
        self.suppressQueryPosition = false
    }

    func liftSuppression(for generation: UInt64) {
        guard self.reloadGeneration == generation else { return }
        self.cancelSuppressionWatchdog()
        self.suppressQueryPosition = false
    }

    func armSuppressionWatchdog(for token: SeekToken) {
        self.cancelSuppressionWatchdog()
        let timeout = self.suppressionWatchdogNanoseconds
        self.suppressionWatchdogTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            guard let self, !self.isInvalidated else { return }
            guard self.isCurrent(token) else { return }
            self.suppressionWatchdogTask = nil
            self.suppressQueryPosition = false
            LoggingSystem.ui.warning("Seek suppression watchdog expired")
        }
    }

    func releaseCurrentSuppressionAfterFailure() {
        guard self.suppressQueryPosition, !self.isInvalidated else { return }
        self.cancelSuppressionWatchdog()
        self.suppressQueryPosition = false
    }

    func invalidate() {
        self.isInvalidated = true
        self.cancelSuppressionWatchdog()
        self.reloadTask?.cancel()
        self.reloadTask = nil
        self.suppressQueryPosition = false
    }

    private func cancelSuppressionWatchdog() {
        self.suppressionWatchdogTask?.cancel()
        self.suppressionWatchdogTask = nil
    }
}
