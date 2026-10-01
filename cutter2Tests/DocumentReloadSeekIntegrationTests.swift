//
//  DocumentReloadSeekIntegrationTests.swift
//  cutter2Tests
//
//  Created by Takashi Mochizuki on 2026-09-30.
//  Copyright © 2026 MyCometG3. All rights reserved.
//
//  T-19: integration seam tests for `Document.updateGUI` / `updatePlayer` —
//  generation propagation across the awaited player-item regeneration and the
//  initial-setup wiring (player attachment, polling timer, suppression).

import XCTest
import AVFoundation
import AVKit
@testable import cutter2

/// Deterministic gate for the injected player-item factory (T-19).
///
/// The factory announces its arrival and suspends until the test releases it.
/// `waitForArrival(of:)` returns immediately when the generation already
/// arrived, so the test never depends on scheduling order.
///
/// Exactly-once resume invariant:
/// - `arriveAndSuspend` removes its waiter and resumes it with `true`.
/// - `timeoutGeneration` removes its waiter and resumes it with `false`.
/// - `release` / `releaseAll` resume suspended factories.
/// Whichever side removes an entry from `arrivalWaiters` is the only party that
/// resumes it, and each side cancels the other's counterpart first, so neither a
/// double resume nor a stale timeout is possible. At most one waiter exists per
/// generation; concurrent waits are rejected by a thrown
/// `GateMisuse.concurrentWait` in `waitForArrival`.
private actor ReloadGate {
    private var arrived: Set<UInt64> = []
    private var suspended: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var arrivalWaiters: [UInt64: (token: UInt64, continuation: CheckedContinuation<Bool, Never>)] = [:]
    /// Armed timeout per generation; cancelled as soon as the waiter resolves.
    private var timeoutTasks: [UInt64: Task<Void, Never>] = [:]
    private var released: Set<UInt64> = []
    private var waiterTokenCounter: UInt64 = 0
    /// Set by `releaseAll()`: the gate is spent and must not be reused.
    private var isTerminal: Bool = false

    private func nextWaiterToken() -> UInt64 {
        waiterTokenCounter += 1
        return waiterTokenCounter
    }

    /// Factory side: announce arrival at `generation`, then suspend.
    ///
    /// Each generation may arrive at most once: a second arrival for the same
    /// generation would overwrite the suspended continuation in `suspended`, so
    /// it is rejected as misuse rather than silently corrupting the gate.
    /// Returns immediately once the gate is terminal, so a late arrival after
    /// teardown cannot suspend a factory nobody will release.
    func arriveAndSuspend(_ generation: UInt64) async throws {
        if isTerminal { return }
        guard !arrived.contains(generation) else {
            throw GateMisuse.duplicateArrival
        }
        arrived.insert(generation)
        if let waiter = arrivalWaiters.removeValue(forKey: generation) {
            timeoutTasks.removeValue(forKey: generation)?.cancel()
            waiter.continuation.resume(returning: true)
        }
        if released.remove(generation) != nil { return }   // early release
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            suspended[generation] = continuation
        }
    }

    /// Test side: wait until `generation`'s factory has announced arrival.
    /// Throws `ReloadGateError.timedOut` if it has not arrived in time.
    ///
    /// The arrival check and the waiter registration happen in the same actor
    /// hop, so an arrival racing with this call cannot be missed: `arriveAndSuspend`
    /// either runs first (`arrived` already contains the generation, so we return
    /// early) or runs after (and finds the waiter registered here, resuming it
    /// with `true`).
    func waitForArrival(of generation: UInt64, timeout: Duration = .seconds(10)) async throws {
        if isTerminal { throw GateMisuse.gateAlreadySpent }
        if arrived.contains(generation) { return }
        if arrivalWaiters[generation] != nil {
            throw GateMisuse.concurrentWait
        }

        let didArrive: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let token = nextWaiterToken()
            arrivalWaiters[generation] = (token, continuation)
            // `Task.detached` keeps the timeout task off the actor, so the hop
            // into the actor below is a real cross-actor await (no
            // "no async operations occur within await" warning under Swift 6).
            timeoutTasks[generation] = Task.detached { [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return   // cancelled by arrival or releaseAll — not a timeout
                }
                await self?.timeoutGeneration(generation, token: token)
            }
        }
        if !didArrive {
            throw ReloadGateError.timedOut(generation)
        }
    }

    /// Timeout side: resume the waiter with `false` **only if** the registered
    /// waiter is still the one this timeout was armed for. A late timeout from a
    /// previous waiter (whose `Task.sleep` already completed before the cancel)
    /// therefore cannot resolve a fresh waiter.
    private func timeoutGeneration(_ generation: UInt64, token: UInt64) {
        // Verify the waiter FIRST: a stale timeout must not evict the armed
        // timeout task or the waiter belonging to a different wait.
        guard let waiter = arrivalWaiters[generation], waiter.token == token else { return }
        arrivalWaiters.removeValue(forKey: generation)
        timeoutTasks.removeValue(forKey: generation)?.cancel()
        waiter.continuation.resume(returning: false)
    }

    /// Test side: let `generation`'s factory return.
    ///
    /// Each generation is released at most once by the documented test steps.
    /// A call before arrival is remembered in `released` so `arriveAndSuspend`
    /// returns without suspending. Repeated calls for an already-arrived
    /// generation would re-arm that early-release note, which is why the
    /// single-release-per-generation usage is a documented contract.
    func release(_ generation: UInt64) {
        if let continuation = suspended.removeValue(forKey: generation) {
            continuation.resume()
        } else {
            released.insert(generation)
        }
    }

    /// Test side: resume every factory still suspended, cancel every armed
    /// timeout, and fail any pending arrival waiters with `false` so neither a
    /// factory nor a waiter is stranded.
    func releaseAll() {
        isTerminal = true
        let pending = suspended.values
        suspended.removeAll()
        for continuation in pending { continuation.resume() }
        released.removeAll()
        arrived.removeAll()
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
        let waiters = arrivalWaiters.values
        arrivalWaiters.removeAll()
        for waiter in waiters { waiter.continuation.resume(returning: false) }
    }

    /// Observable terminal flag so a test can assert the spent state directly.
    var isTerminalForTesting: Bool { isTerminal }

    /// Misuse cases are thrown, never trapped: a `precondition` would terminate
    /// the whole XCTest process, making the case untestable in-process.
    enum GateMisuse: Error {
        case gateAlreadySpent
        case concurrentWait
        case duplicateArrival
    }
}

private enum ReloadGateError: Error, CustomStringConvertible {
    case timedOut(UInt64)

    var description: String {
        switch self {
        case .timedOut(let generation):
            return "ReloadGate timed out waiting for generation \(generation)"
        }
    }
}

@MainActor
final class DocumentReloadSeekIntegrationTests: XCTestCase {

    private var fixtureStore = TestFixtureURLStore()
    private var document: Document?
    private var gate: ReloadGate?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        // Release any factory still suspended in the gate, and wait for that
        // to complete, so a failed assertion cannot strand a continuation
        // and no gate state survives into the next test.
        let gate = self.gate
        self.gate = nil
        await gate?.releaseAll()
        document?.cleanup()
        document = nil
        for url in fixtureStore.takeAll() {
            try? FileManager.default.removeItem(at: url)
        }
        try await super.tearDown()
    }

    private enum FixtureError: Error { case writeFailed }

    /// Writes an H.264 fixture off the main actor (T-18 regression) and
    /// registers it for teardown cleanup.
    private func writeFixture(duration: TimeInterval = 1.0) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t19-\(UUID().uuidString).mov")
        let ok = await writeSampleMovieOffMainActor(to: url,
                                                    duration: duration,
                                                    timescale: 600,
                                                    frameRate: 30)
        guard ok else {
            try? FileManager.default.removeItem(at: url)
            throw FixtureError.writeFailed
        }
        fixtureStore.append(url)
        return url
    }

    private func makeDocument(fixture url: URL) throws -> Document {
        let movie = AVMutableMovie(url: url, options: nil)
        let document = Document()
        document.movieMutator = MovieMutator(with: movie)
        self.document = document
        return document
    }

    /// One-second selection range used by every reload trigger.
    private static let reloadRange = CMTimeRange(
        start: .zero,
        duration: CMTime(seconds: 1, preferredTimescale: 600)
    )

    // MARK: - A-1 Baseline

    /// A single reload follows the production path (seam-injected player view,
    /// no newer reload) and releases its own suppression when the reload Task
    /// exits. Proves the wiring; does not prove generation interplay.
    func testSingleReloadReleasesSuppression() async throws {
        let url = try await writeFixture()
        let document = try makeDocument(fixture: url)

        let gate = ReloadGate()
        self.gate = gate
        // A fresh view has no player: `updatePlayer` then takes the
        // initial-setup branch, which is the only path that reaches the
        // factory and releases suppression in this test.
        document.testablePlayerView = AVPlayerView()
        // `AVPlayerItem()`'s parameterless initializer is unavailable, so the
        // item is built from the fixture asset (the same initializer the
        // production `makePlayerItem()` uses).
        let item = AVPlayerItem(asset: AVAsset(url: url))
        document.testablePlayerItemFactory = { generation, _ in
            try await gate.arriveAndSuspend(generation)
            return item
        }

        let completed = expectation(description: "reload task finished")
        completed.expectedFulfillmentCount = 1
        document.testableReloadCompletion = { _ in completed.fulfill() }

        // Synchronous call; the reload Task runs in the background.
        document.updateGUI(CMTime.zero, Self.reloadRange, true)

        try await gate.waitForArrival(of: 1)
        await gate.release(1)
        await fulfillment(of: [completed], timeout: 15)

        XCTAssertFalse(document.playerSeekSequencer.suppressQueryPosition)
    }

    // MARK: - A-2 Core regression

    /// A superseded reload (cancelled while awaiting player-item generation)
    /// must not release the newer reload's suppression. Each generation is
    /// released only after the test observed its arrival, and each completion is
    /// awaited individually before moving on; completion order is asserted as
    /// the set {1, 2}, never as an order.
    func testSupersededReloadDoesNotReleaseNewerReloadSuppression() async throws {
        let url = try await writeFixture()
        let document = try makeDocument(fixture: url)

        let gate = ReloadGate()
        self.gate = gate
        // Same initial-setup branch as A-1: fresh view, no player attached.
        document.testablePlayerView = AVPlayerView()
        let item = AVPlayerItem(asset: AVAsset(url: url))
        document.testablePlayerItemFactory = { generation, _ in
            try await gate.arriveAndSuspend(generation)
            return item
        }

        var completedGenerations: Set<UInt64> = []
        var waiters: [UInt64: XCTestExpectation] = [:]
        document.testableReloadCompletion = { generation in
            completedGenerations.insert(generation)
            waiters.removeValue(forKey: generation)?.fulfill()
        }

        /// Registers an expectation for `generation`'s reload completion.
        ///
        /// Registered before the gate is released: the completion can land the
        /// instant the factory returns, and a waiter created afterwards would miss
        /// it and time out.
        func registerCompletionWaiter(for generation: UInt64) -> XCTestExpectation {
            let done = expectation(description: "reload \(generation) finished")
            waiters[generation] = done
            return done
        }

        // 1. generation 1: the reload Task suspends inside the factory.
        document.updateGUI(CMTime.zero, Self.reloadRange, true)
        // 2. Confirm generation 1 reached the await point (no scheduling assumption).
        try await gate.waitForArrival(of: 1)
        // 3. generation 2: `beginReload()` cancels generation 1's Task.
        document.updateGUI(CMTime.zero, Self.reloadRange, true)
        // 4. Confirm generation 2 reached the await point.
        try await gate.waitForArrival(of: 2)
        // 5. Generation 1 exits at its `Task.isCancelled` check (no-op).
        let gen1Done = registerCompletionWaiter(for: 1)
        await gate.release(1)
        // 6. Establish that generation 1's Task has finished.
        await fulfillment(of: [gen1Done], timeout: 15)

        // The superseded generation must not have released the suppression.
        // Generation 2 is still suspended in its factory, so suppression that is
        // still held here cannot have been released by generation 1.
        XCTAssertTrue(document.playerSeekSequencer.suppressQueryPosition)

        // 7. Generation 2 proceeds down the normal path.
        let gen2Done = registerCompletionWaiter(for: 2)
        await gate.release(2)
        // 8. Establish that generation 2's Task has finished.
        await fulfillment(of: [gen2Done], timeout: 15)

        // Generation 2 (not generation 1) released the suppression.
        XCTAssertFalse(document.playerSeekSequencer.suppressQueryPosition)
        // Both completions fired. Task completion order is not guaranteed, so
        // assert the set, not the order.
        XCTAssertEqual(completedGenerations, [1, 2])
    }

    // MARK: - A-3 Item application regression

    /// A cancelled reload's item must never reach `replaceCurrentItem(with:)`.
    ///
    /// A player is attached up front so the item-replacement branch (not the
    /// initial-setup branch) is taken, and each generation receives a distinct
    /// item. After the superseded generation's reload finishes, the player's
    /// current item must be the surviving generation's item.
    ///
    /// Suppression's final state is deliberately not asserted here (the real
    /// AVPlayer seek completion is non-deterministic); A-2 owns that.
    func testSupersededReloadItemIsNeverApplied() async throws {
        let url = try await writeFixture()
        let document = try makeDocument(fixture: url)

        let gate = ReloadGate()
        self.gate = gate

        // Attaching a player up front selects the item-replacement branch.
        let playerView = AVPlayerView()
        let placeholderItem = AVPlayerItem(asset: AVAsset(url: url))
        playerView.player = AVPlayer(playerItem: placeholderItem)
        document.testablePlayerView = playerView

        // Distinct items so `currentItem` identity is a meaningful assertion.
        let asset = AVAsset(url: url)
        let generation1Item = AVPlayerItem(asset: asset)
        let generation2Item = AVPlayerItem(asset: asset)

        var completedGenerations: Set<UInt64> = []
        var waiters: [UInt64: XCTestExpectation] = [:]
        document.testableReloadCompletion = { generation in
            completedGenerations.insert(generation)
            waiters.removeValue(forKey: generation)?.fulfill()
        }

        /// Registers an expectation for `generation`'s reload completion.
        ///
        /// Registered before the gate is released: the completion can land the
        /// instant the factory returns, and a waiter created afterwards would miss
        /// it and time out.
        func registerCompletionWaiter(for generation: UInt64) -> XCTestExpectation {
            let done = expectation(description: "reload \(generation) finished")
            waiters[generation] = done
            return done
        }

        document.testablePlayerItemFactory = { generation, _ in
            try await gate.arriveAndSuspend(generation)
            return generation == 1 ? generation1Item : generation2Item
        }

        document.updateGUI(CMTime.zero, Self.reloadRange, true)
        try await gate.waitForArrival(of: 1)
        document.updateGUI(CMTime.zero, Self.reloadRange, true)
        try await gate.waitForArrival(of: 2)
        let gen1Done = registerCompletionWaiter(for: 1)
        await gate.release(1)
        await fulfillment(of: [gen1Done], timeout: 15)

        // The superseded generation's item must not have been applied, not even
        // transiently: generation 2 is still suspended in its factory, so the
        // player must still be holding the placeholder it started with.
        XCTAssertIdentical(document.player?.currentItem, placeholderItem)

        let gen2Done = registerCompletionWaiter(for: 2)
        await gate.release(2)
        await fulfillment(of: [gen2Done], timeout: 15)

        // The surviving generation's item is the one applied.
        let player = try XCTUnwrap(document.player)
        XCTAssertIdentical(player.currentItem, generation2Item)
        XCTAssertEqual(completedGenerations, [1, 2])

        // The item-replacement branch arms a suppression watchdog whose completion
        // is a real AVFoundation seek callback (non-deterministic). Retire the
        // watchdog deterministically: wait until it has armed and then expired, so
        // tearDown's `cleanup()` → `invalidate()` has no live task to cancel and
        // drop (a cancelled suspended task's deallocation trips a Swift concurrency
        // runtime fatal error).
        if document.playerSeekSequencer.hasArmedSuppressionWatchdog {
            let deadline = Date().addingTimeInterval(10)
            while document.playerSeekSequencer.hasArmedSuppressionWatchdog && Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertFalse(document.playerSeekSequencer.hasArmedSuppressionWatchdog,
                           "suppression watchdog never retired")
        }

        // Detach the player while this test still owns the view. Leaving it attached
        // until tearDown aborts the whole test process (SIGABRT): releasing an
        // `AVPlayer` from an `AVPlayerView` inside XCTest's teardown sequence
        // crashes, so the teardown must find nothing left to release.
        playerView.player = nil
    }

    // MARK: - B-1 Initial setup with the production item factory

    /// Initial setup (`pv.player == nil`) with the factory seam left `nil`, so
    /// the production `MovieMutator.makePlayerItem()` path runs for real:
    /// the player is created and attached, the polling timer starts, and the
    /// suppression is released immediately. KVO observer registration is out
    /// of scope (§0).
    func testInitialSetupAttachesPlayerStartsTimerAndReleasesSuppression() async throws {
        let url = try await writeFixture()
        let document = try makeDocument(fixture: url)

        let playerView = AVPlayerView()
        // Precondition, checked as a failure rather than skipped: a fresh
        // view must not attach a player by itself.
        XCTAssertNil(playerView.player)
        document.testablePlayerView = playerView
        // testablePlayerItemFactory stays nil on purpose: the production
        // makePlayerItem() path (AVAsset copy + video composition) must run.

        let completed = expectation(description: "reload task finished")
        completed.expectedFulfillmentCount = 1
        document.testableReloadCompletion = { _ in completed.fulfill() }

        document.updateGUI(CMTime.zero, Self.reloadRange, true)
        await fulfillment(of: [completed], timeout: 30)

        XCTAssertNotNil(document.player)
        XCTAssertNotNil(document.playerItem)
        XCTAssertNotNil(document.timer)
        XCTAssertFalse(document.playerSeekSequencer.suppressQueryPosition)
    }

    // MARK: - G-1 Gate self-test

    /// Validates `ReloadGate` itself, in isolation from `Document`:
    /// (1) `waitForArrival` throws `ReloadGateError.timedOut` when the factory
    /// never arrives, instead of hanging; (2) after `releaseAll()` the gate is
    /// terminal — `isTerminalForTesting` is true, a late `arriveAndSuspend`
    /// returns without suspending, and `waitForArrival` throws
    /// `GateMisuse.gateAlreadySpent`. Misuse is observable via throws and
    /// state, never via a process-terminating trap.
    func testReloadGateTimeoutFailsWhenFactoryNeverArrives() async throws {
        let gate = ReloadGate()
        self.gate = gate

        // (1) No factory ever announces arrival: the wait must time out.
        do {
            try await gate.waitForArrival(of: 1, timeout: .milliseconds(200))
            XCTFail("waitForArrival(of:) did not throw ReloadGateError.timedOut")
        } catch let error as ReloadGateError {
            // Expected: timed out without hanging, and for the awaited generation.
            guard case .timedOut(let generation) = error else {
                return XCTFail("Unexpected ReloadGateError case: \(error)")
            }
            XCTAssertEqual(generation, 1)
        } catch {
            XCTFail("waitForArrival(of:) threw the wrong error: \(error)")
        }

        // (2) `releaseAll()` completes without throwing.
        await gate.releaseAll()

        // Terminal state is observable.
        let terminal = await gate.isTerminalForTesting
        XCTAssertTrue(terminal)

        // A late arrival after teardown returns without suspending, and without
        // throwing (the terminal check comes first).
        try await gate.arriveAndSuspend(1)

        // Reuse after teardown is rejected with a thrown GateMisuse.
        do {
            try await gate.waitForArrival(of: 1)
            XCTFail("waitForArrival(of:) after releaseAll() did not throw GateMisuse")
        } catch let error as ReloadGate.GateMisuse {
            guard case .gateAlreadySpent = error else {
                return XCTFail("waitForArrival(of:) after releaseAll() threw \(error)")
            }
        } catch {
            XCTFail("waitForArrival(of:) after releaseAll() threw the wrong error: \(error)")
        }
    }
}
