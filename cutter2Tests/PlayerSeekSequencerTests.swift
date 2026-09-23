//
//  PlayerSeekSequencerTests.swift
//  cutter2Tests
//
//  Created by Takashi Mochizuki on 2026/09/23.
//  Copyright © 2026 MyCometG3. All rights reserved.
//

import XCTest
@testable import cutter2

@MainActor
final class PlayerSeekSequencerTests: XCTestCase {

    func testSuppressForReloadSetsFlag() {
        let sequencer = PlayerSeekSequencer()
        XCTAssertFalse(sequencer.suppressQueryPosition)
        sequencer.suppressForReload()
        XCTAssertTrue(sequencer.suppressQueryPosition)
    }

    func testBeginReloadBumpsGenerationAndCancelsInFlightTask() {
        let sequencer = PlayerSeekSequencer()
        let task = Task { @MainActor in
            _ = try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        sequencer.registerReloadTask(task)

        XCTAssertEqual(sequencer.beginReload(), 1)
        XCTAssertTrue(task.isCancelled)
    }

    func testReloadTaskDidFinishClearsHandleOnlyForCurrentGeneration() {
        let sequencer = PlayerSeekSequencer()
        let oldTask = Task { @MainActor in
            _ = try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        sequencer.registerReloadTask(oldTask)
        let oldGeneration = sequencer.beginReload()
        _ = sequencer.beginReload()
        let currentTask = Task { @MainActor in
            _ = try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        sequencer.registerReloadTask(currentTask)

        sequencer.reloadTaskDidFinish(generation: oldGeneration)
        XCTAssertFalse(currentTask.isCancelled)

        sequencer.cancelReloadTask()

        XCTAssertTrue(currentTask.isCancelled)
        XCTAssertTrue(oldTask.isCancelled)
    }

    func testBeginUserSeekSnapshotsBothGenerations() {
        let sequencer = PlayerSeekSequencer()
        XCTAssertEqual(sequencer.beginReload(), 1)
        let token = sequencer.beginUserSeek()

        XCTAssertEqual(token.seekGeneration, 1)
        XCTAssertEqual(token.reloadGeneration, 1)
    }

    func testStaleSeekIsNotCurrent() {
        let sequencer = PlayerSeekSequencer()
        let first = sequencer.beginUserSeek()
        let second = sequencer.beginUserSeek()

        XCTAssertFalse(sequencer.isCurrent(first))
        XCTAssertTrue(sequencer.isCurrent(second))
    }

    func testCanReleaseSuppressionIsGatedByReloadGeneration() {
        let sequencer = PlayerSeekSequencer()
        let token = sequencer.beginUserSeek()
        XCTAssertTrue(sequencer.canReleaseSuppression(token))

        _ = sequencer.beginReload()

        XCTAssertFalse(sequencer.canReleaseSuppression(token))
    }

    func testReleaseSuppressionClearsFlag() {
        let sequencer = PlayerSeekSequencer()
        sequencer.suppressForReload()
        sequencer.releaseSuppression()

        XCTAssertFalse(sequencer.suppressQueryPosition)
    }

    func testBeginItemReplacementBumpsSeekGenerationOnly() {
        let sequencer = PlayerSeekSequencer()
        let reloadGeneration = sequencer.beginReload()
        let token = sequencer.beginItemReplacement(reloadGeneration: reloadGeneration)

        XCTAssertEqual(sequencer.seekGeneration, 1)
        XCTAssertEqual(sequencer.reloadGeneration, reloadGeneration)
        XCTAssertEqual(token.reloadGeneration, reloadGeneration)
        XCTAssertTrue(sequencer.isCurrent(token))
    }

    func testLiftSuppressionIgnoresStaleGeneration() {
        let sequencer = PlayerSeekSequencer()
        sequencer.suppressForReload()
        let staleGeneration = sequencer.beginReload()
        let currentGeneration = sequencer.beginReload()

        sequencer.liftSuppression(for: staleGeneration)
        XCTAssertTrue(sequencer.suppressQueryPosition)

        sequencer.liftSuppression(for: currentGeneration)
        XCTAssertFalse(sequencer.suppressQueryPosition)
    }

    func testCancelReloadTaskCancelsAndClearsWithoutResettingState() {
        let sequencer = PlayerSeekSequencer()
        sequencer.suppressForReload()
        let reloadGeneration = sequencer.beginReload()
        let token = sequencer.beginUserSeek()
        let task = Task { @MainActor in
            _ = try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        sequencer.registerReloadTask(task)

        sequencer.cancelReloadTask()

        XCTAssertTrue(task.isCancelled)
        XCTAssertEqual(sequencer.reloadGeneration, reloadGeneration)
        XCTAssertEqual(sequencer.seekGeneration, token.seekGeneration)
        XCTAssertTrue(sequencer.suppressQueryPosition)
    }

    func testUserSeekFinishReleasesSuppressionWhileReloadInFlight() {
        let sequencer = PlayerSeekSequencer()
        sequencer.suppressForReload()
        _ = sequencer.beginReload()
        let token = sequencer.beginUserSeek()

        XCTAssertTrue(sequencer.isCurrent(token))
        XCTAssertTrue(sequencer.canReleaseSuppression(token))
        sequencer.releaseSuppression()

        XCTAssertFalse(sequencer.suppressQueryPosition)
    }
}
