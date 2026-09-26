//
//  MovieWriterVideoChannelMetadataTests.swift
//  cutter2Tests
//
//  Created by Takashi Mochizuki on 2026/09/25.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
import CoreMedia
import VideoToolbox
@testable import cutter2

/// Pins the S-16 video channel metadata builders (S-16).
///
/// Every test calls the production helpers in
/// `cutter2/Models/VideoChannelMetadataBuilder.swift` directly; none of the
/// conversion closures is re-implemented on the test side. The CoreMedia
/// retrieval gate is exercised with synthetic `CMFormatDescription` objects
/// created through `CMFormatDescriptionCreate(extensions:)`.
@MainActor
final class MovieWriterVideoChannelMetadataTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Synthetic value / description helpers

    private func fourCC(_ string: String) -> FourCharCode {
        var code: FourCharCode = 0
        for byte in string.utf8 {
            code = (code << 8) | FourCharCode(byte)
        }
        return code
    }

    /// Creates a synthetic video `CMFormatDescription` composed solely of
    /// the supplied extensions (no sample-entry payload).
    private func makeDescription(extensions: [CFString: Any]) throws -> CMFormatDescription {
        var description: CMFormatDescription?
        let ext: CFDictionary? = extensions.isEmpty ? nil : extensions as CFDictionary
        let status = CMFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            mediaType: kCMMediaType_Video,
            mediaSubType: fourCC("avc1"),
            extensions: ext,
            formatDescriptionOut: &description
        )
        guard status == noErr, let description else {
            throw NSError(domain: "MovieWriterVideoChannelMetadataTests",
                          code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "failed to create synthetic format description"])
        }
        return description
    }

    /// `kCMFormatDescriptionExtension_CleanAperture` payload.
    private func cleanApertureValue(
        width: Any? = NSNumber(value: 100),
        height: Any? = NSNumber(value: 200),
        hOffset: Any? = NSNumber(value: 10),
        vOffset: Any? = NSNumber(value: 20)
    ) -> CFPropertyList {
        var dict: [CFString: Any] = [:]
        if let width { dict[kCMFormatDescriptionKey_CleanApertureWidth] = width }
        if let height { dict[kCMFormatDescriptionKey_CleanApertureHeight] = height }
        if let hOffset { dict[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] = hOffset }
        if let vOffset { dict[kCMFormatDescriptionKey_CleanApertureVerticalOffset] = vOffset }
        return dict as CFPropertyList
    }

    /// `kCMFormatDescriptionExtension_PixelAspectRatio` payload.
    private func pixelAspectRatioValue(
        hSpacing: Any? = NSNumber(value: 8),
        vSpacing: Any? = NSNumber(value: 9)
    ) -> CFPropertyList {
        var dict: [CFString: Any] = [:]
        if let hSpacing { dict[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] = hSpacing }
        if let vSpacing { dict[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] = vSpacing }
        return dict as CFPropertyList
    }

    private func cfString(_ value: String) -> CFPropertyList {
        return value as NSString as CFPropertyList
    }

    /// Non-nil initial compression dictionary standing in for the
    /// non-ProRes target-bitrate entry.
    private var bitrateInitial: NSDictionary {
        return [AVVideoAverageBitRateKey: 2_500_000] as NSDictionary
    }

    /// Mirrors the production call-site expression for the field segment:
    /// `makeExtensionDict(from:keys:build:) ?? compressionProperties`.
    private func fieldMergeResult(
        description: CMFormatDescription,
        copyField: Bool,
        initial: NSDictionary?
    ) -> NSDictionary? {
        return VideoChannelMetadataBuilder.makeExtensionDict(
            from: description,
            keys: VideoChannelMetadataBuilder.fieldExtensionKeys(copyField: copyField)
        ) { values in
            VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
                fieldCountExtension: values[0],
                fieldDetailExtension: values[1],
                initial: initial
            )
        } ?? initial
    }

    // MARK: - Shared extension retrieval gate

    func testMakeExtensionDictReturnsBuilderResultInKeyOrderWhenAllExtensionsPresent() throws {
        let description = try makeDescription(extensions: [
            kCMFormatDescriptionExtension_CleanAperture: cleanApertureValue(),
            kCMFormatDescriptionExtension_PixelAspectRatio: pixelAspectRatioValue(),
        ])

        var builderCalls = 0
        var received: [CFPropertyList] = []
        let marker = ["marker": true] as NSDictionary

        let result = VideoChannelMetadataBuilder.makeExtensionDict(
            from: description,
            keys: [kCMFormatDescriptionExtension_PixelAspectRatio,
                   kCMFormatDescriptionExtension_CleanAperture]
        ) { values in
            builderCalls += 1
            received = values
            return marker
        }

        XCTAssertEqual(builderCalls, 1, "builder must be invoked exactly once")
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0][kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as? NSNumber,
                       NSNumber(value: 8),
                       "values must follow the key order, not the storage order")
        XCTAssertEqual(received[1][kCMFormatDescriptionKey_CleanApertureWidth] as? NSNumber,
                       NSNumber(value: 100))
        XCTAssertEqual(result, marker)
    }

    func testMakeExtensionDictReturnsNilAndSkipsBuilderWhenAnyExtensionMissing() throws {
        let ca = cleanApertureValue()
        let pa = pixelAspectRatioValue()
        let cases: [(String, [CFString: Any])] = [
            ("clean aperture only", [kCMFormatDescriptionExtension_CleanAperture: ca]),
            ("pixel aspect ratio only", [kCMFormatDescriptionExtension_PixelAspectRatio: pa]),
            ("neither extension", [:]),
        ]

        for (label, exts) in cases {
            let description = try makeDescription(extensions: exts)
            var builderCalls = 0
            let result = VideoChannelMetadataBuilder.makeExtensionDict(
                from: description,
                keys: [kCMFormatDescriptionExtension_CleanAperture,
                       kCMFormatDescriptionExtension_PixelAspectRatio]
            ) { _ in
                builderCalls += 1
                return ["x": 1] as NSDictionary
            }
            XCTAssertNil(result, "\(label)")
            XCTAssertEqual(builderCalls, 0, "builder must not run when \(label)")
        }
    }

    func testMakeExtensionDictReturnsNilAndSkipsBuilderForEmptyKeyList() throws {
        let description = try makeDescription(extensions: [
            kCMFormatDescriptionExtension_CleanAperture: cleanApertureValue(),
            kCMFormatDescriptionExtension_PixelAspectRatio: pixelAspectRatioValue(),
        ])

        var builderCalls = 0
        let result = VideoChannelMetadataBuilder.makeExtensionDict(
            from: description,
            keys: []
        ) { _ in
            builderCalls += 1
            return ["x": 1] as NSDictionary
        }

        XCTAssertNil(result, "empty key list must short-circuit to nil")
        XCTAssertEqual(builderCalls, 0, "builder must not run for an empty key list")
    }

    func testSelectorKeysReturnOrderedListsOrEmpty() {
        XCTAssertTrue(VideoChannelMetadataBuilder.nclcExtensionKeys(copyNCLC: false).isEmpty,
                      "copyNCLC=false must produce an empty key list")
        XCTAssertEqual(VideoChannelMetadataBuilder.nclcExtensionKeys(copyNCLC: true),
                       [kCMFormatDescriptionExtension_ColorPrimaries,
                        kCMFormatDescriptionExtension_TransferFunction,
                        kCMFormatDescriptionExtension_YCbCrMatrix])

        XCTAssertTrue(VideoChannelMetadataBuilder.fieldExtensionKeys(copyField: false).isEmpty,
                      "copyField=false must produce an empty key list")
        XCTAssertEqual(VideoChannelMetadataBuilder.fieldExtensionKeys(copyField: true),
                       [kCMFormatDescriptionExtension_FieldCount,
                        kCMFormatDescriptionExtension_FieldDetail])
    }

    // MARK: - Clean aperture transformer

    func testMakeCleanApertureOutputsAllFourKeysWhenAllValuesAreNumbers() {
        let result = VideoChannelMetadataBuilder.makeCleanAperture(from: cleanApertureValue())
        XCTAssertNotNil(result)
        guard let dict = result else { return }

        XCTAssertEqual(dict[AVVideoCleanApertureWidthKey] as? NSNumber, NSNumber(value: 100))
        XCTAssertEqual(dict[AVVideoCleanApertureHeightKey] as? NSNumber, NSNumber(value: 200))
        XCTAssertEqual(dict[AVVideoCleanApertureHorizontalOffsetKey] as? NSNumber, NSNumber(value: 10))
        XCTAssertEqual(dict[AVVideoCleanApertureVerticalOffsetKey] as? NSNumber, NSNumber(value: 20))
        XCTAssertEqual(Set(dict.allKeys.compactMap { $0 as? String }),
                       [AVVideoCleanApertureWidthKey,
                        AVVideoCleanApertureHeightKey,
                        AVVideoCleanApertureHorizontalOffsetKey,
                        AVVideoCleanApertureVerticalOffsetKey])
    }

    func testMakeCleanApertureReturnsNilWhenAnyRequiredKeyMissing() {
        let requiredKeys: [(String, () -> CFPropertyList)] = [
            ("width", { self.cleanApertureValue(width: nil) }),
            ("height", { self.cleanApertureValue(height: nil) }),
            ("horizontal offset", { self.cleanApertureValue(hOffset: nil) }),
            ("vertical offset", { self.cleanApertureValue(vOffset: nil) }),
        ]
        for (label, makeValue) in requiredKeys {
            XCTAssertNil(VideoChannelMetadataBuilder.makeCleanAperture(from: makeValue()),
                         "missing \(label) must yield no clean aperture dictionary")
        }
    }

    func testMakeCleanApertureReturnsNilWhenAnyRequiredKeyIsWrongType() {
        let requiredKeys: [(String, () -> CFPropertyList)] = [
            ("width", { self.cleanApertureValue(width: self.cfString("100")) }),
            ("height", { self.cleanApertureValue(height: self.cfString("200")) }),
            ("horizontal offset", { self.cleanApertureValue(hOffset: self.cfString("10")) }),
            ("vertical offset", { self.cleanApertureValue(vOffset: self.cfString("20")) }),
        ]
        for (label, makeValue) in requiredKeys {
            XCTAssertNil(VideoChannelMetadataBuilder.makeCleanAperture(from: makeValue()),
                         "non-NSNumber \(label) must yield no clean aperture dictionary")
        }
    }

    // MARK: - Pixel aspect ratio transformer

    func testMakePixelAspectRatioOutputsBothKeysWhenBothValuesAreNumbers() {
        let result = VideoChannelMetadataBuilder.makePixelAspectRatio(from: pixelAspectRatioValue())
        XCTAssertNotNil(result)
        guard let dict = result else { return }

        XCTAssertEqual(dict[AVVideoPixelAspectRatioHorizontalSpacingKey] as? NSNumber, NSNumber(value: 8))
        XCTAssertEqual(dict[AVVideoPixelAspectRatioVerticalSpacingKey] as? NSNumber, NSNumber(value: 9))
        XCTAssertEqual(Set(dict.allKeys.compactMap { $0 as? String }),
                       [AVVideoPixelAspectRatioHorizontalSpacingKey,
                        AVVideoPixelAspectRatioVerticalSpacingKey])
    }

    func testMakePixelAspectRatioReturnsNilWhenAnyRequiredKeyMissing() {
        let requiredKeys: [(String, () -> CFPropertyList)] = [
            ("horizontal spacing", { self.pixelAspectRatioValue(hSpacing: nil) }),
            ("vertical spacing", { self.pixelAspectRatioValue(vSpacing: nil) }),
        ]
        for (label, makeValue) in requiredKeys {
            XCTAssertNil(VideoChannelMetadataBuilder.makePixelAspectRatio(from: makeValue()),
                         "missing \(label) must yield no pixel aspect ratio dictionary")
        }
    }

    func testMakePixelAspectRatioReturnsNilWhenAnyRequiredKeyIsWrongType() {
        let requiredKeys: [(String, () -> CFPropertyList)] = [
            ("horizontal spacing", { self.pixelAspectRatioValue(hSpacing: self.cfString("8")) }),
            ("vertical spacing", { self.pixelAspectRatioValue(vSpacing: self.cfString("9")) }),
        ]
        for (label, makeValue) in requiredKeys {
            XCTAssertNil(VideoChannelMetadataBuilder.makePixelAspectRatio(from: makeValue()),
                         "non-NSNumber \(label) must yield no pixel aspect ratio dictionary")
        }
    }

    // MARK: - NCLC transformer

    func testMakeNCLCOutputsAllThreeKeysWhenAllValuesAreStrings() {
        let result = VideoChannelMetadataBuilder.makeNCLC(from: [
            cfString("BT.709"), cfString("BT.709"), cfString("BT.709"),
        ])
        XCTAssertNotNil(result)
        guard let dict = result else { return }

        XCTAssertEqual(dict[AVVideoColorPrimariesKey] as? NSString, "BT.709" as NSString)
        XCTAssertEqual(dict[AVVideoTransferFunctionKey] as? NSString, "BT.709" as NSString)
        XCTAssertEqual(dict[AVVideoYCbCrMatrixKey] as? NSString, "BT.709" as NSString)
        XCTAssertEqual(Set(dict.allKeys.compactMap { $0 as? String }),
                       [AVVideoColorPrimariesKey, AVVideoTransferFunctionKey, AVVideoYCbCrMatrixKey])
    }

    func testMakeNCLCReturnsNilWhenAnyColorExtensionMissingAtGate() throws {
        let complete: [CFString: Any] = [
            kCMFormatDescriptionExtension_ColorPrimaries: cfString("BT.709"),
            kCMFormatDescriptionExtension_TransferFunction: cfString("BT.709"),
            kCMFormatDescriptionExtension_YCbCrMatrix: cfString("BT.709"),
        ]
        let positions: [(String, CFString)] = [
            ("color primaries", kCMFormatDescriptionExtension_ColorPrimaries),
            ("transfer function", kCMFormatDescriptionExtension_TransferFunction),
            ("YCbCr matrix", kCMFormatDescriptionExtension_YCbCrMatrix),
        ]

        for (label, missingKey) in positions {
            var exts = complete
            exts[missingKey] = nil
            let description = try makeDescription(extensions: exts)
            var builderCalls = 0
            let result = VideoChannelMetadataBuilder.makeExtensionDict(
                from: description,
                keys: VideoChannelMetadataBuilder.nclcExtensionKeys(copyNCLC: true)
            ) { _ in
                builderCalls += 1
                return VideoChannelMetadataBuilder.makeNCLC(from: [])
            }
            XCTAssertNil(result, "missing \(label)")
            XCTAssertEqual(builderCalls, 0, "builder must not run when \(label) is missing")
        }
    }

    func testMakeNCLCReturnsNilWhenAnyValueIsNotString() {
        let positions: [(String, Int)] = [("color primaries", 0), ("transfer function", 1), ("YCbCr matrix", 2)]
        for (label, position) in positions {
            var values: [CFPropertyList] = [cfString("BT.709"), cfString("BT.709"), cfString("BT.709")]
            values[position] = NSNumber(value: 709) as CFPropertyList
            XCTAssertNil(VideoChannelMetadataBuilder.makeNCLC(from: values),
                         "non-NSString \(label) must yield no color properties dictionary")
        }
    }

    func testMakeNCLCReturnsNilWhenExtensionCountIsNotThree() {
        XCTAssertNil(VideoChannelMetadataBuilder.makeNCLC(from: [cfString("BT.709"), cfString("BT.709")]))
        XCTAssertNil(VideoChannelMetadataBuilder.makeNCLC(from: [
            cfString("BT.709"), cfString("BT.709"), cfString("BT.709"), cfString("BT.709"),
        ]))
    }

    func testNCLCDisabledSelectorProducesNoColorPropertiesEvenWhenExtensionsPresent() throws {
        let description = try makeDescription(extensions: [
            kCMFormatDescriptionExtension_ColorPrimaries: cfString("BT.709"),
            kCMFormatDescriptionExtension_TransferFunction: cfString("BT.709"),
            kCMFormatDescriptionExtension_YCbCrMatrix: cfString("BT.709"),
        ])

        var builderCalls = 0
        let result = VideoChannelMetadataBuilder.makeExtensionDict(
            from: description,
            keys: VideoChannelMetadataBuilder.nclcExtensionKeys(copyNCLC: false)
        ) { _ in
            builderCalls += 1
            return VideoChannelMetadataBuilder.makeNCLC(from: [])
        }

        XCTAssertNil(result, "copyNCLC=false must not set color properties even when extensions exist")
        XCTAssertEqual(builderCalls, 0, "no CoreMedia retrieval must happen when copyNCLC=false")
    }

    // MARK: - Field metadata merge

    func testFieldDisabledSelectorLeavesCompressionPropertiesUnchanged() throws {
        let description = try makeDescription(extensions: [
            kCMFormatDescriptionExtension_FieldCount: NSNumber(value: 2) as CFPropertyList,
            kCMFormatDescriptionExtension_FieldDetail: cfString("TopFieldFirst"),
        ])

        let nilResult = fieldMergeResult(description: description, copyField: false, initial: nil)
        XCTAssertNil(nilResult, "copyField=false must leave a nil initial value untouched")

        let bitrateResult = fieldMergeResult(description: description, copyField: false, initial: bitrateInitial)
        XCTAssertEqual(bitrateResult, bitrateInitial, "copyField=false must keep the existing bitrate entry")
    }

    func testFieldMissingExtensionLeavesCompressionPropertiesUnchanged() throws {
        let fc = NSNumber(value: 2) as CFPropertyList
        let fd = cfString("TopFieldFirst")
        let cases: [(String, [CFString: Any])] = [
            ("field count only", [kCMFormatDescriptionExtension_FieldCount: fc]),
            ("field detail only", [kCMFormatDescriptionExtension_FieldDetail: fd]),
            ("neither field extension", [:]),
        ]

        for (label, exts) in cases {
            let description = try makeDescription(extensions: exts)
            let nilResult = fieldMergeResult(description: description, copyField: true, initial: nil)
            XCTAssertNil(nilResult, "\(label) must not create a dictionary")

            let bitrateResult = fieldMergeResult(description: description, copyField: true, initial: bitrateInitial)
            XCTAssertEqual(bitrateResult, bitrateInitial, "\(label) must keep the existing bitrate entry")
        }
    }

    func testFieldBothCastSuccessAddsBothKeysAndMergesInitialEntries() {
        let fc = NSNumber(value: 2) as CFPropertyList
        let fd = cfString("TopFieldFirst")

        let fromNil = VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
            fieldCountExtension: fc, fieldDetailExtension: fd, initial: nil)
        XCTAssertNotNil(fromNil)
        if let dict = fromNil {
            XCTAssertEqual(Set(dict.allKeys.compactMap { $0 as? String }),
                           [kVTCompressionPropertyKey_FieldCount as String,
                            kVTCompressionPropertyKey_FieldDetail as String])
            XCTAssertEqual(dict[kVTCompressionPropertyKey_FieldCount] as? NSNumber, NSNumber(value: 2))
            XCTAssertEqual(dict[kVTCompressionPropertyKey_FieldDetail] as? NSString, "TopFieldFirst" as NSString)
        }

        let fromBitrate = VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
            fieldCountExtension: fc, fieldDetailExtension: fd, initial: bitrateInitial)
        XCTAssertNotNil(fromBitrate)
        if let dict = fromBitrate {
            XCTAssertEqual(Set(dict.allKeys.compactMap { $0 as? String }),
                           [kVTCompressionPropertyKey_FieldCount as String,
                            kVTCompressionPropertyKey_FieldDetail as String,
                            AVVideoAverageBitRateKey])
            XCTAssertEqual(dict[AVVideoAverageBitRateKey] as? NSNumber, NSNumber(value: 2_500_000))
        }
    }

    func testFieldPartialCastCountOnlyCreatesFieldlessDictionary() {
        let fc = NSNumber(value: 2) as CFPropertyList
        let fdWrongType = NSNumber(value: 709) as CFPropertyList // "TopFieldFirst" missing → cast fails

        let fromNil = VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
            fieldCountExtension: fc, fieldDetailExtension: fdWrongType, initial: nil)
        XCTAssertNotNil(fromNil, "a partial cast must still create a dictionary (legacy behavior)")
        XCTAssertEqual(fromNil?.count, 0, "no field keys may be added when only one cast succeeds")

        let fromBitrate = VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
            fieldCountExtension: fc, fieldDetailExtension: fdWrongType, initial: bitrateInitial)
        XCTAssertNotNil(fromBitrate)
        if let dict = fromBitrate {
            XCTAssertEqual(Set(dict.allKeys.compactMap { $0 as? String }), [AVVideoAverageBitRateKey])
            XCTAssertEqual(dict[AVVideoAverageBitRateKey] as? NSNumber, NSNumber(value: 2_500_000))
        }
    }

    func testFieldPartialCastDetailOnlyCreatesFieldlessDictionary() {
        let fcWrongType = cfString("2") // not an NSNumber → cast fails
        let fd = cfString("TopFieldFirst")

        let fromNil = VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
            fieldCountExtension: fcWrongType, fieldDetailExtension: fd, initial: nil)
        XCTAssertNotNil(fromNil, "a partial cast must still create a dictionary (legacy behavior)")
        XCTAssertEqual(fromNil?.count, 0, "no field keys may be added when only one cast succeeds")

        let fromBitrate = VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
            fieldCountExtension: fcWrongType, fieldDetailExtension: fd, initial: bitrateInitial)
        XCTAssertNotNil(fromBitrate)
        if let dict = fromBitrate {
            XCTAssertEqual(Set(dict.allKeys.compactMap { $0 as? String }), [AVVideoAverageBitRateKey])
            XCTAssertEqual(dict[AVVideoAverageBitRateKey] as? NSNumber, NSNumber(value: 2_500_000))
        }
    }

    func testFieldBothCastFailuresLeaveInitialUnchanged() {
        let fcWrongType = cfString("2")
        let fdWrongType = NSNumber(value: 709) as CFPropertyList

        let fromNil = VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
            fieldCountExtension: fcWrongType, fieldDetailExtension: fdWrongType, initial: nil)
        XCTAssertNil(fromNil, "no field value must leave a nil initial value untouched")

        let fromBitrate = VideoChannelMetadataBuilder.mergeFieldCompressionProperties(
            fieldCountExtension: fcWrongType, fieldDetailExtension: fdWrongType, initial: bitrateInitial)
        XCTAssertEqual(fromBitrate, bitrateInitial, "no field value must keep the existing bitrate entry")
    }

    // MARK: - Initial compression properties (codec bitrate policy)

    func testInitialCompressionProResFamilyProducesNoBitrateEntry() {
        let proResFourCCs = ["ap4h", "apch", "apcn", "apcs", "apco"]
        for fourCC in proResFourCCs {
            XCTAssertNil(VideoChannelMetadataBuilder.makeInitialCompressionProperties(forCodec: fourCC,
                                                                                      targetBitRate: 2_500_000),
                         "\(fourCC) must not carry a target bitrate")
        }
    }

    func testInitialCompressionAp4xKeepsTargetBitrate() {
        // ap4x (ProRes 4444 XQ) is not in the legacy ProRes list, so it keeps
        // the else-branch behavior: the target bitrate entry is produced.
        let result = VideoChannelMetadataBuilder.makeInitialCompressionProperties(forCodec: "ap4x",
                                                                                  targetBitRate: 2_500_000)
        XCTAssertEqual(Set(result?.allKeys.compactMap { $0 as? String } ?? []), [AVVideoAverageBitRateKey])
        XCTAssertEqual(result?[AVVideoAverageBitRateKey] as? NSNumber, NSNumber(value: 2_500_000))
    }

    func testInitialCompressionOtherCodecsKeepTargetBitrate() {
        for fourCC in ["avc1", "hvc1", "mp4v", "vp09"] {
            let result = VideoChannelMetadataBuilder.makeInitialCompressionProperties(forCodec: fourCC,
                                                                                      targetBitRate: 2_500_000)
            XCTAssertEqual(Set(result?.allKeys.compactMap { $0 as? String } ?? []), [AVVideoAverageBitRateKey],
                           "\(fourCC) must carry only the average bitrate entry")
            XCTAssertEqual(result?[AVVideoAverageBitRateKey] as? NSNumber, NSNumber(value: 2_500_000))
        }
    }

    // MARK: - Real-media custom export (separate result from the unit matrix)

    func testExportCustomMovieProducesReadableVideoTrackWithSameDimensions() async throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutter2_s16_fixture_\(UUID().uuidString).mov")
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutter2_s16_export_\(UUID().uuidString).mov")
        defer {
            try? FileManager.default.removeItem(at: fixtureURL)
            try? FileManager.default.removeItem(at: outURL)
        }

        let writeOK = DispatchQueue.global().sync {
            writeSampleMovie(to: fixtureURL, duration: 1.0, timescale: 600, frameRate: 30)
        }
        guard writeOK else {
            XCTFail("failed to write sample movie fixture")
            return
        }

        let movie = AVMutableMovie(url: fixtureURL, options: nil)
        guard movie.range.duration > CMTime.zero else {
            XCTFail("AVMutableMovie(url:) produced empty movie")
            return
        }
        movie.timescale = 600

        let writer = MovieWriter(params: MovieWriterParams(movie: movie,
                                                           unblockUserInteraction: nil,
                                                           progressContinuation: nil))
        let param: [String: any Sendable] = [
            kVideoEncodeKey: true,
            kVideoCodecKey: "avc1",
            kVideoKbpsKey: 2500,
            kCopyFieldKey: true,
            kCopyNCLCKey: true,
            kCopyOtherMediaKey: true,
            kAudioEncodeKey: true,
            kAudioKbpsKey: 128,
            kAudioCodecKey: "aac ",
            kLPCMDepthKey: 16,
        ]

        try await writer.exportCustomMovie(to: outURL, fileType: .mov, settings: param)

        let cancelled = await writer.writeCancelled
        let error = await writer.writeError
        let success = await writer.writeSuccess
        XCTAssertFalse(cancelled)
        XCTAssertNil(error)
        XCTAssertTrue(success, "custom export must complete successfully")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path), "output file must exist")

        let written = AVMutableMovie(url: outURL, options: nil)
        XCTAssertGreaterThan(written.duration.seconds, 0.5)
        let videoTracks = written.tracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1, "output must contain exactly one video track")
        if let track = videoTracks.first {
            XCTAssertEqual(Int(track.naturalSize.width), 320)
            XCTAssertEqual(Int(track.naturalSize.height), 180)
            XCTAssertGreaterThan(track.naturalTimeScale, 0)
        }
    }
}
