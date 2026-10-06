//
//  MovieWriterCustomProgressTests.swift
//  cutter2Tests
//
//  Copyright © 2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Covers `ProgressSink`'s admission rule and the `MovieWriter.didRead` wiring.
///
/// The tests drive a `ProgressDestination` directly and never construct an
/// `AsyncStream`, so no expectation is needed and the results are deterministic.
/// `SampleBufferChannelDelegate.didRead(buffer:)` no longer takes a channel, which is
/// what made this possible: building a `SampleBufferChannel` requires real
/// `AVAssetReaderOutput` / `AVAssetWriterInput` instances.
final class MovieWriterCustomProgressTests: XCTestCase {

    // MARK: - Helpers

    /// Carries a non-`Sendable` value across a concurrency boundary in tests.
    ///
    /// `CMSampleBuffer` is a CoreMedia reference type with no `Sendable` conformance, so
    /// the background-queue check has to opt out explicitly.
    private struct UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T

        init(_ value: T) {
            self.value = value
        }
    }

    /// `ProgressDestination` that records every emitted value.
    ///
    /// Touches only its own `NSLock`, never `ProgressSink`, so the
    /// `ProgressDestination` re-entrancy contract holds by construction.
    private final class RecordingProgressDestination: ProgressDestination, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Float] = []

        func receive(_ value: Float) {
            lock.lock()
            storage.append(value)
            lock.unlock()
        }

        var values: [Float] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    /// Builds a minimal `CMSampleBuffer` carrying only timing information.
    ///
    /// `ProgressSink` admission is driven by the presentation end, so the payload is
    /// irrelevant; a one-byte block buffer is enough to satisfy `CMSampleBufferCreate`.
    private func makeSampleBuffer(pts: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        var formatDescription: CMFormatDescription?
        // `extensions` precedes `formatDescriptionOut` in this SDK's signature.
        let formatStatus = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                          codecType: kCMVideoCodecType_422YpCbCr8,
                                                          width: 16,
                                                          height: 16,
                                                          extensions: nil,
                                                          formatDescriptionOut: &formatDescription)
        XCTAssertEqual(formatStatus, noErr)
        let format = try XCTUnwrap(formatDescription)

        let byteCount = 16
        let blockBuffer: CMBlockBuffer = try {
            var created: CMBlockBuffer?
            let createStatus = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                                  memoryBlock: nil,
                                                                  blockLength: byteCount,
                                                                  blockAllocator: kCFAllocatorDefault,
                                                                  customBlockSource: nil,
                                                                  offsetToData: 0,
                                                                  dataLength: byteCount,
                                                                  flags: 0,
                                                                  blockBufferOut: &created)
            XCTAssertEqual(createStatus, kCMBlockBufferNoErr)
            return try XCTUnwrap(created)
        }()

        var timing = CMSampleTimingInfo(duration: duration,
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        var sampleSize = byteCount
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                                dataBuffer: blockBuffer,
                                                dataReady: true,
                                                makeDataReadyCallback: nil,
                                                refcon: nil,
                                                formatDescription: format,
                                                sampleCount: 1,
                                                sampleTimingEntryCount: 1,
                                                sampleTimingArray: &timing,
                                                sampleSizeEntryCount: 1,
                                                sampleSizeArray: &sampleSize,
                                                sampleBufferOut: &sampleBuffer)
        XCTAssertEqual(sampleStatus, noErr)
        return try XCTUnwrap(sampleBuffer)
    }

    private func makeAttachedSink() -> (ProgressSink, RecordingProgressDestination) {
        let recorder = RecordingProgressDestination()
        let sink = ProgressSink()
        sink.install(recorder)
        return (sink, recorder)
    }

    // MARK: - ProgressSink admission rule

    func testProgressSinkDropsValuesBelowMinimumDelta() throws {
        let (sink, recorder) = makeAttachedSink()

        // 0.001 steps from 0.002 up to 1.000. With a 0.002 gate roughly every second
        // sample is admitted, so emissions must be far fewer than inputs.
        //
        // Each value is produced by a single division rather than by accumulating `+=`,
        // which would drift and stop short of 1.0.
        let inputs: [Float64] = (2...1000).map { Double($0) / 1000.0 }
        XCTAssertEqual(inputs.count, 999)
        XCTAssertEqual(inputs[inputs.count - 1], 1.0)
        for candidate in inputs {
            sink.publish(candidate)
        }

        let emitted = recorder.values
        // Roughly every second sample clears the 0.002 gate; the measured value is 488,
        // slightly under 999/2 because `0.001` steps drift in binary floating point, so
        // an occasional gap falls just short of the threshold. A band is used instead of
        // an exact count so the assertion survives that drift while still failing for
        // both regressions it guards: a removed gate emits ~999, and a sink that never
        // emits emits 0. The lower bound is what makes the upper bound non-vacuous.
        XCTAssertGreaterThanOrEqual(emitted.count, 470)
        XCTAssertLessThanOrEqual(emitted.count, 510)
        XCTAssertEqual(Double(emitted[0]), 0.002, accuracy: 0.0001)
        XCTAssertEqual(Double(emitted[emitted.count - 1]), 1.0, accuracy: 0.0001)
    }

    func testProgressSinkRejectsOutOfOrderValues() throws {
        let (sink, recorder) = makeAttachedSink()

        XCTAssertTrue(sink.publish(0.5))
        // 0.1 is behind the high-water mark, so `0.1 - 0.5` is negative and the single
        // admission rule rejects it.
        XCTAssertFalse(sink.publish(0.1))
        XCTAssertTrue(sink.publish(0.9))

        XCTAssertEqual(recorder.values, [0.5, 0.9])
    }

    func testProgressSinkStaysMonotonicAcrossInterleavedSources() throws {
        let (sink, recorder) = makeAttachedSink()

        // Two channels interleaved so that a channel which is behind the global
        // high-water mark arrives *after* a faster one. A purely ascending interleave
        // would pass even without the monotonic property.
        let ordered: [Float64] = [0.10, 0.20, 0.15, 0.25, 0.30, 0.20, 0.35, 0.40, 0.30, 0.45]
        for candidate in ordered {
            sink.publish(candidate)
        }

        // 0.15 (after 0.20), 0.20 (after 0.30) and 0.30 (after 0.35) are the three
        // backward steps; each of the remaining advances by at least 0.002 and is kept.
        let emitted = recorder.values
        XCTAssertEqual(emitted, [0.10, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45])
        for pair in zip(emitted, emitted.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
    }

    // MARK: - Late-bound destination

    func testProgressSinkEmitsAfterDestinationIsInstalledLate() throws {
        let recorder = RecordingProgressDestination()
        let sink = ProgressSink()

        // A MovieWriter may already exist when the AsyncStream builder closure runs, so
        // nothing may be emitted while no destination is installed.
        XCTAssertFalse(sink.publish(0.5))
        XCTAssertTrue(recorder.values.isEmpty)

        sink.install(recorder)
        XCTAssertTrue(sink.isAttached)
        XCTAssertTrue(sink.publish(0.5))

        XCTAssertEqual(recorder.values, [0.5])
    }

    func testProgressSinkDropsValuesWhileDetached() throws {
        let recorder = RecordingProgressDestination()
        let sink = ProgressSink()
        sink.install(nil)

        XCTAssertFalse(sink.isAttached)
        XCTAssertFalse(sink.publish(0.5))
        // `publishUngated` needs a destination too, so it is equally inert here.
        XCTAssertFalse(sink.publishUngated(0.5))
        XCTAssertTrue(recorder.values.isEmpty)
    }

    func testProgressSinkDetachIgnoresStaleToken() throws {
        let (sink, recorder) = makeAttachedSink()

        // A superseded stream's onTermination runs in a detached Task whose ordering
        // relative to the next operation is not guaranteed. Its token must not clear the
        // destination the newer stream installed.
        let staleToken = ProgressSink().install(recorder)
        let currentToken = sink.install(recorder)
        sink.detach(staleToken)

        XCTAssertTrue(sink.isAttached)
        XCTAssertTrue(sink.publish(0.5))
        XCTAssertEqual(recorder.values, [0.5])

        sink.detach(currentToken)
        XCTAssertFalse(sink.isAttached)
        XCTAssertFalse(sink.publish(0.6))
        XCTAssertEqual(recorder.values, [0.5])
    }

    func testProgressSinkInstallResetsHighWaterMark() throws {
        let (sink, recorder) = makeAttachedSink()

        XCTAssertTrue(sink.publish(0.9))
        XCTAssertEqual(sink.lastEmittedValue, 0.9)

        // A destination belongs to one operation, so the previous operation's mark must
        // not gate the next one.
        sink.install(recorder)
        XCTAssertEqual(sink.lastEmittedValue, -.infinity)
        XCTAssertTrue(sink.publish(0.1))

        XCTAssertEqual(recorder.values, [0.9, 0.1])
        XCTAssertEqual(sink.lastEmittedValue, 0.1)
    }

    func testProgressSinkPublishUngatedBypassesDeltaGate() throws {
        let (sink, recorder) = makeAttachedSink()

        // The AVAssetExportSession path is already throttled at the session level and
        // must not be filtered by the custom-export gate, so equal values still emit.
        XCTAssertTrue(sink.publishUngated(0.4))
        XCTAssertTrue(sink.publishUngated(0.4))
        XCTAssertEqual(recorder.values, [0.4, 0.4])

        // The high-water mark moved, so a later gated value cannot overtake it.
        XCTAssertFalse(sink.publish(0.1))
        XCTAssertTrue(sink.publish(0.9))
        XCTAssertEqual(recorder.values, [0.4, 0.4, 0.9])
    }

    // MARK: - Progress arithmetic

    func testProgressIsZeroForZeroLengthMovie() throws {
        let value = MovieWriter.progress(presentationEnd: CMTime(seconds: 5.0, preferredTimescale: 600),
                                         movieDurationSeconds: 0.0)

        XCTAssertEqual(value, 0.0)
        XCTAssertTrue(value.isFinite)
    }

    func testProgressRejectsInvalidPresentationTimeStamp() throws {
        let (sink, recorder) = makeAttachedSink()

        let value = MovieWriter.progress(presentationEnd: .invalid,
                                         movieDurationSeconds: 10.0)
        XCTAssertTrue(value.isNaN)

        // NaN fails every comparison against the high-water mark, so the single
        // admission rule drops it and never poisons the destination.
        XCTAssertFalse(sink.publish(value))
        XCTAssertTrue(recorder.values.isEmpty)
        XCTAssertTrue(sink.publish(0.5))
        XCTAssertEqual(recorder.values, [0.5])
    }

    // MARK: - didRead wiring

    func testDidReadPublishesSynchronouslyWithoutTask() throws {
        let (sink, recorder) = makeAttachedSink()
        // An empty movie has a zero-length range, so every sample maps to 0.0. The gate
        // admits the first one and rejects the rest, which makes the assertion exact.
        let writer = MovieWriter(params: MovieWriterParams(movie: AVMutableMovie(),
                                                            unblockUserInteraction: nil,
                                                            progressSink: sink))
        let buffer = try makeSampleBuffer(pts: CMTime(seconds: 0.0, preferredTimescale: 600),
                                          duration: CMTime(seconds: 0.0, preferredTimescale: 600))

        writer.didRead(buffer: buffer)
        writer.didRead(buffer: buffer)

        // Synchronous: with the previous Task-based implementation nothing would have
        // been emitted yet at this point.
        XCTAssertEqual(recorder.values, [0.0])
        XCTAssertEqual(writer.movieDurationSeconds, 0.0)
    }

    func testDidReadPublishesFromBackgroundQueue() async throws {
        let (sink, recorder) = makeAttachedSink()
        let writer = MovieWriter(params: MovieWriterParams(movie: AVMutableMovie(),
                                                            unblockUserInteraction: nil,
                                                            progressSink: sink))
        let buffer = UncheckedSendableBox(
            try makeSampleBuffer(pts: CMTime(seconds: 0.0, preferredTimescale: 600),
                                 duration: CMTime(seconds: 0.0, preferredTimescale: 600)))

        // `withCheckedContinuation` keeps the test class and any expectation out of the
        // `@Sendable` closure, which only captures the actor, the sink's recorder and the
        // boxed buffer.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                writer.didRead(buffer: buffer.value)
                continuation.resume()
            }
        }

        // The publish happens on the calling queue, so the record is already complete.
        XCTAssertEqual(recorder.values, [0.0])
    }
}