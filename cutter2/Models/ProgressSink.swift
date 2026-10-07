//
//  ProgressSink.swift
//  cutter2
//
//  Copyright © 2026 MyCometG3. All rights reserved.
//

import Foundation
import os.lock

/// `os_unfair_lock` box holding the sink's mutable state.
///
/// A file-private copy, matching `PerformanceMetrics.swift:20-34`. `AsyncBridge.swift:21`
/// declares a **non-generic** box with a different `withLock` signature, so the two
/// existing copies cannot be unified without adapting `AsyncResultBox`; that cleanup is
/// tracked separately rather than done opportunistically here.
private final class UnfairLockBox<T>: @unchecked Sendable {
    private var rawLock = os_unfair_lock_s()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    @inline(__always)
    func withLock<U>(_ body: (inout T) throws -> U) rethrows -> U {
        os_unfair_lock_lock(&rawLock)
        defer { os_unfair_lock_unlock(&rawLock) }
        return try body(&value)
    }
}

/// Destination for movie progress values.
///
/// ## Contract
/// `ProgressSink.publish(_:)` invokes `receive(_:)` **while holding the sink's lock**, so
/// a conforming type must never call back into `ProgressSink` (`install`, `detach`,
/// `publish`, `publishUngated`). Doing so would deadlock on `os_unfair_lock`.
///
/// Neither current conformer touches `ProgressSink`: `AsyncStreamProgressDestination`
/// forwards to `AsyncStream.Continuation.yield` and test destinations only append under
/// their own lock. The type system cannot forbid a future conformer from holding a sink,
/// so the contract is enforced by review instead.
///
/// A named protocol is used rather than an arbitrary closure so that the destination
/// stays a documented type whose storage is visible at the call site.
protocol ProgressDestination: Sendable {
    /// Receives one progress value in `0.0...1.0`.
    ///
    /// - Parameter value: The value to emit.
    func receive(_ value: Float)
}

/// Production destination: yields into the progress `AsyncStream`.
struct AsyncStreamProgressDestination: ProgressDestination {
    private let continuation: AsyncStream<Float>.Continuation

    /// Wraps an `AsyncStream` continuation as a progress destination.
    ///
    /// - Parameter continuation: The continuation produced by
    ///   `MovieMutatorBase.progressStream()`.
    init(_ continuation: AsyncStream<Float>.Continuation) {
        self.continuation = continuation
    }

    func receive(_ value: Float) {
        continuation.yield(value)
    }
}

/// Thread-safe destination for movie progress values, shared by `MovieMutator` and the
/// `MovieWriter` it creates.
///
/// ## Why the destination is held by reference
/// `AsyncStream.init` runs its builder closure synchronously, so
/// `MovieMutatorBase.progressStream()` installs the destination before returning, and
/// `progressStream()` must be called before the operation starts (see that method's
/// timing requirement). The reference is therefore not about an initialization race.
///
/// It is about which destination is *current*. A later `progressStream()` call replaces
/// the installation, and the previous stream's `onTermination` may `detach` at any moment.
/// A writer that captured the continuation would keep publishing into a stream nobody is
/// consuming. Holding the installation behind this reference and resolving it on every
/// publish means a writer always reaches whichever destination is live, and emits nothing
/// once none is.
///
/// ## Why admission and emission share one critical section
/// Deciding under one lock and emitting under another lets two channels interleave as
/// `admit(0.2)`, `admit(0.3)`, `emit(0.3)`, `emit(0.2)` and drive `NSProgress` backwards.
/// Because the high-water mark is updated **and** the destination invoked inside the same
/// section, concurrent channels can only ever observe a strictly increasing sequence.
///
/// ## Buffering
/// `AsyncStream.Continuation.yield` does not block, so invoking it while holding the lock
/// is safe and cheap. The delta gate additionally bounds how many values are ever queued.
final class ProgressSink: @unchecked Sendable {

    /// Minimum advance of the high-water mark between two emissions, in `0.0...1.0`.
    ///
    /// The consumer renders `Int64(progress * 100)` (`Document+Export.swift:124`), so a
    /// 0.2 % step is five emissions per rendered percent: visually smooth while capping a
    /// full-length export at 500 emissions.
    static let minimumDelta: Float64 = 0.002

    /// Identity of one destination installation.
    ///
    /// Returned by `install(_:)` and required by `detach(_:)` so a late termination from a
    /// superseded stream cannot clear the destination a newer stream installed.
    struct Token: Sendable, Hashable {
        fileprivate let generation: UInt64
    }

    private struct State {
        /// Monotonic counter handing out `Token` values.
        var generation: UInt64 = 0
        /// Generation of the currently installed destination; `0` means none.
        var current: UInt64 = 0
        var destination: (any ProgressDestination)?
        /// High-water mark of emitted values. `-infinity` admits the first value.
        var lastEmitted: Float64 = -.infinity
    }

    private let state = UnfairLockBox(State())

    /// Installs or clears the destination and returns its identity.
    ///
    /// Installing resets the high-water mark: a destination belongs to one operation, so
    /// the previous operation's mark must not gate the new one.
    ///
    /// - Parameter destination: The destination, or `nil` to detach unconditionally.
    /// - Returns: The token identifying this installation.
    @discardableResult
    func install(_ destination: (any ProgressDestination)?) -> Token {
        state.withLock { current in
            current.generation &+= 1
            current.current = current.generation
            current.destination = destination
            current.lastEmitted = -.infinity
            return Token(generation: current.current)
        }
    }

    /// Detaches the destination only when `token` still identifies the installed one.
    ///
    /// A termination callback from a superseded stream carries a stale token and is
    /// ignored, so it cannot clear the destination a newer stream installed.
    ///
    /// - Parameter token: The token returned by `install(_:)`.
    func detach(_ token: Token) {
        state.withLock { current in
            guard current.current == token.generation else { return }
            current.destination = nil
        }
    }

    /// Whether a destination is currently installed.
    var isAttached: Bool {
        state.withLock { $0.destination != nil }
    }

    /// Emits `value` when it is finite and advances the high-water mark by at least
    /// `minimumDelta`.
    ///
    /// A single admission rule for the high-water mark, because `minimumDelta > 0` makes
    /// `value - lastEmitted >= minimumDelta` imply `value > lastEmitted`. Out-of-order
    /// values are therefore rejected by that same condition, which is what makes emissions
    /// monotonic across concurrent channels. Admission and emission happen in one critical
    /// section.
    ///
    /// ## Non-finite values
    /// That one comparison is not sufficient on its own. `NaN` is rejected because every
    /// comparison against it is false, but **`±inf` is accepted**: `inf - (-inf)` is `inf`,
    /// which satisfies the gate. `CMTime.positiveInfinity` survives
    /// `MovieWriter.presentationEnd(of:)` when the *presentation timestamp* is infinite (the
    /// duration branch is already excluded by `CMTIME_IS_NUMERIC`), and
    /// `Document+Export` then evaluates `Int64(value * 100)`, which **traps** on infinity.
    /// Both entry points therefore reject non-finite values explicitly, which makes "the
    /// sink never emits a non-finite value" an invariant of the type rather than of each
    /// progress source.
    ///
    /// - Parameter value: Candidate progress in `0.0...1.0`.
    /// - Returns: `true` when the value was emitted.
    @discardableResult
    func publish(_ value: Float64) -> Bool {
        state.withLock { current in
            // Rejected before the destination lookup so the invariant costs nothing:
            // nothing non-finite ever reaches `current` or the destination.
            guard value.isFinite else { return false }
            guard let destination = current.destination else { return false }
            guard value - current.lastEmitted >= Self.minimumDelta else { return false }
            current.lastEmitted = value
            destination.receive(Float(value))
            return true
        }
    }

    /// Emits `value` without consulting the delta gate, and moves the high-water mark so
    /// later gated values cannot overtake it.
    ///
    /// Used by the `AVAssetExportSession` path, which already throttles its own updates
    /// (`MovieWriter.exportSessionTimerRefreshInterval`) and therefore must not be
    /// filtered by the custom-export gate. Non-finite values are rejected for the same
    /// reason as in `publish(_:)`.
    ///
    /// - Parameter value: The progress to emit.
    /// - Returns: `true` when a destination was installed and the value was emitted.
    @discardableResult
    func publishUngated(_ value: Float) -> Bool {
        state.withLock { current in
            guard value.isFinite else { return false }
            guard let destination = current.destination else { return false }
            current.lastEmitted = Double(value)
            destination.receive(value)
            return true
        }
    }

    /// The current high-water mark. Test support.
    var lastEmittedValue: Float64 {
        state.withLock { $0.lastEmitted }
    }
}
