//  TestMovieFixtureWriter.swift
//  cutter2Tests
//
//  Shared test helper: write a sample H.264 .mov. Callers must invoke on a background thread.

import AVFoundation
import CoreMedia
import Foundation

/// Thread-safe fixture URL store (tearDown is nonisolated; tests are serial per instance).
public final class TestFixtureURLStore: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    public func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    public func takeAll() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = urls
        urls.removeAll()
        return snapshot
    }
}

/// nonisolated synchronous helper: write a sample H.264 .mov.
/// Callers must invoke on a background thread to avoid blocking the main actor.
func writeSampleMovie(
    to url: URL,
    duration: TimeInterval = 1.0,
    timescale: CMTimeScale = 600,
    frameRate: Int = 30
) -> Bool {
    guard frameRate > 0, timescale > 0, duration > 0 else {
        return false
    }
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }

    let width = 320
    let height = 180
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
    )
    guard writer.canAdd(input) else { return false }
    writer.add(input)

    guard writer.startWriting() else { return false }
    writer.startSession(atSourceTime: .zero)

    let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
    ]
    var pixelBuffer: CVPixelBuffer?
    let pstatus = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                      kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
    guard pstatus == kCVReturnSuccess, let pb = pixelBuffer else { return false }
    let lockStatus = CVPixelBufferLockBaseAddress(pb, [])
    defer {
        if lockStatus == kCVReturnSuccess {
            CVPixelBufferUnlockBaseAddress(pb, [])
        }
    }
    guard lockStatus == kCVReturnSuccess, let base = CVPixelBufferGetBaseAddress(pb) else { return false }
    memset(base, 0, CVPixelBufferGetDataSize(pb))

    let frameDuration = CMTime(value: CMTimeValue(timescale), timescale: CMTimeScale(frameRate) * CMTimeScale(timescale))
    let frameCount = Int((duration * Double(frameRate)).rounded())
    let deadline = DispatchTime.now() + .seconds(30)
    var presentation = CMTime.zero
    for _ in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            if DispatchTime.now() > deadline { return false }
            usleep(1000)
        }
        let ok = adaptor.append(pb, withPresentationTime: presentation)
        if !ok { return false }
        presentation = CMTimeAdd(presentation, frameDuration)
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: presentation)
    let group = DispatchGroup()
    group.enter()
    writer.finishWriting { group.leave() }
    let timeout = DispatchTime.now() + .seconds(10)
    let result = group.wait(timeout: timeout)
    guard result == .success else { return false }
    return writer.status == .completed
}
