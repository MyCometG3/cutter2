//
//  LayoutConverterMappingTests.swift
//  cutter2Tests
//
//  Created by GitHub Copilot on 2026/09/23.
//  Copyright © 2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Pins the tag/label mapping tables of LayoutConverter+Mapping.swift (T-16).
final class LayoutConverterMappingTests: XCTestCase {

    private static let allTags: [(tag: AudioChannelLayoutTag, labels: Set<AudioChannelLabel>)] = [
        (kAudioChannelLayoutTag_Mono, [42]),
        (kAudioChannelLayoutTag_Stereo, [1, 2]),
        (kAudioChannelLayoutTag_StereoHeadphones, [301, 302]),
        (kAudioChannelLayoutTag_MatrixStereo, [38, 39]),
        (kAudioChannelLayoutTag_MidSide, [204, 205]),
        (kAudioChannelLayoutTag_XY, [206, 207]),
        (kAudioChannelLayoutTag_Binaural, [208, 209]),
        (kAudioChannelLayoutTag_Ambisonic_B_Format, [200, 201, 202, 203]),
        (kAudioChannelLayoutTag_Quadraphonic, [1, 2, 5, 6]),
        (kAudioChannelLayoutTag_Pentagonal, [1, 2, 5, 6, 3]),
        (kAudioChannelLayoutTag_Hexagonal, [1, 2, 5, 6, 3, 9]),
        (kAudioChannelLayoutTag_Octagonal, [1, 2, 5, 6, 3, 9, 35, 36]),
        (kAudioChannelLayoutTag_Cube, [1, 2, 33, 34, 13, 15, 16, 18]),
        (kAudioChannelLayoutTag_MPEG_3_0_A, [1, 2, 3]),
        (kAudioChannelLayoutTag_MPEG_3_0_B, [3, 1, 2]),
        (kAudioChannelLayoutTag_MPEG_4_0_A, [1, 2, 3, 9]),
        (kAudioChannelLayoutTag_MPEG_4_0_B, [3, 1, 2, 9]),
        (kAudioChannelLayoutTag_MPEG_5_0_A, [1, 2, 3, 5, 6]),
        (kAudioChannelLayoutTag_MPEG_5_0_B, [1, 2, 5, 6, 3]),
        (kAudioChannelLayoutTag_MPEG_5_0_C, [1, 3, 2, 5, 6]),
        (kAudioChannelLayoutTag_MPEG_5_0_D, [3, 1, 2, 5, 6]),
        (kAudioChannelLayoutTag_MPEG_5_1_A, [1, 2, 3, 4, 5, 6]),
        (kAudioChannelLayoutTag_MPEG_5_1_B, [1, 2, 5, 6, 3, 4]),
        (kAudioChannelLayoutTag_MPEG_5_1_C, [1, 3, 2, 5, 6, 4]),
        (kAudioChannelLayoutTag_MPEG_5_1_D, [3, 1, 2, 5, 6, 4]),
        (kAudioChannelLayoutTag_MPEG_6_1_A, [1, 2, 3, 4, 5, 6, 9]),
        (kAudioChannelLayoutTag_MPEG_7_1_A, [1, 2, 3, 4, 5, 6, 7, 8]),
        (kAudioChannelLayoutTag_MPEG_7_1_B, [3, 7, 8, 1, 2, 5, 6, 4]),
        (kAudioChannelLayoutTag_MPEG_7_1_C, [1, 2, 3, 4, 5, 6, 33, 34]),
        (kAudioChannelLayoutTag_Emagic_Default_7_1, [1, 2, 5, 6, 3, 4, 7, 8]),
        (kAudioChannelLayoutTag_SMPTE_DTV, [1, 2, 3, 4, 5, 6, 38, 39]),
        (kAudioChannelLayoutTag_ITU_2_1, [1, 2, 9]),
        (kAudioChannelLayoutTag_ITU_2_2, [1, 2, 5, 6]),
        (kAudioChannelLayoutTag_DVD_4, [1, 2, 4]),
        (kAudioChannelLayoutTag_DVD_5, [1, 2, 4, 9]),
        (kAudioChannelLayoutTag_DVD_6, [1, 2, 4, 5, 6]),
        (kAudioChannelLayoutTag_DVD_10, [1, 2, 3, 4]),
        (kAudioChannelLayoutTag_DVD_11, [1, 2, 3, 4, 9]),
        (kAudioChannelLayoutTag_DVD_18, [1, 2, 5, 6, 4]),
        (kAudioChannelLayoutTag_AudioUnit_6_0, [1, 2, 5, 6, 3, 9]),
        (kAudioChannelLayoutTag_AudioUnit_7_0, [1, 2, 5, 6, 3, 33, 34]),
        (kAudioChannelLayoutTag_AudioUnit_7_0_Front, [1, 2, 5, 6, 3, 7, 8]),
        (kAudioChannelLayoutTag_AAC_3_0, [3, 1, 2]),
        (kAudioChannelLayoutTag_AAC_Quadraphonic, [1, 2, 5, 6]),
        (kAudioChannelLayoutTag_AAC_4_0, [3, 1, 2, 9]),
        (kAudioChannelLayoutTag_AAC_5_0, [3, 1, 2, 5, 6]),
        (kAudioChannelLayoutTag_AAC_5_1, [3, 1, 2, 5, 6, 4]),
        (kAudioChannelLayoutTag_AAC_6_0, [3, 1, 2, 5, 6, 9]),
        (kAudioChannelLayoutTag_AAC_6_1, [3, 1, 2, 5, 6, 9, 4]),
        (kAudioChannelLayoutTag_AAC_7_1, [3, 7, 8, 1, 2, 5, 6, 4]),
        (kAudioChannelLayoutTag_AAC_7_0, [3, 1, 2, 5, 6, 33, 34]),
        (kAudioChannelLayoutTag_AAC_7_1_B, [3, 1, 2, 5, 6, 33, 34, 4]),
        (kAudioChannelLayoutTag_AAC_7_1_C, [3, 1, 2, 5, 6, 4, 13, 15]),
        (kAudioChannelLayoutTag_AAC_Octagonal, [3, 1, 2, 5, 6, 33, 34, 9]),
        (kAudioChannelLayoutTag_AC3_1_0_1, [3, 4]),
        (kAudioChannelLayoutTag_AC3_3_0, [1, 3, 2]),
        (kAudioChannelLayoutTag_AC3_3_1, [1, 3, 2, 9]),
        (kAudioChannelLayoutTag_AC3_3_0_1, [1, 3, 2, 4]),
        (kAudioChannelLayoutTag_AC3_2_1_1, [1, 2, 9, 4]),
        (kAudioChannelLayoutTag_AC3_3_1_1, [1, 3, 2, 9, 4]),
        (kAudioChannelLayoutTag_EAC_6_0_A, [1, 3, 2, 5, 6, 9]),
        (kAudioChannelLayoutTag_EAC_7_0_A, [1, 3, 2, 5, 6, 33, 34]),
        (kAudioChannelLayoutTag_EAC3_6_1_A, [1, 3, 2, 5, 6, 4, 9]),
        (kAudioChannelLayoutTag_EAC3_6_1_B, [1, 3, 2, 5, 6, 4, 12]),
        (kAudioChannelLayoutTag_EAC3_6_1_C, [1, 3, 2, 5, 6, 4, 14]),
        (kAudioChannelLayoutTag_EAC3_7_1_A, [1, 3, 2, 5, 6, 4, 33, 34]),
        (kAudioChannelLayoutTag_EAC3_7_1_B, [1, 3, 2, 5, 6, 4, 7, 8]),
        (kAudioChannelLayoutTag_EAC3_7_1_C, [1, 3, 2, 5, 6, 4, 10, 11]),
        (kAudioChannelLayoutTag_EAC3_7_1_D, [1, 3, 2, 5, 6, 4, 35, 36]),
        (kAudioChannelLayoutTag_EAC3_7_1_E, [1, 3, 2, 5, 6, 4, 13, 15]),
        (kAudioChannelLayoutTag_EAC3_7_1_F, [1, 3, 2, 5, 6, 4, 9, 12]),
        (kAudioChannelLayoutTag_EAC3_7_1_G, [1, 3, 2, 5, 6, 4, 9, 14]),
        (kAudioChannelLayoutTag_EAC3_7_1_H, [1, 3, 2, 5, 6, 4, 12, 14]),
        (kAudioChannelLayoutTag_DTS_3_1, [3, 1, 2, 4]),
        (kAudioChannelLayoutTag_DTS_4_1, [3, 1, 2, 9, 4]),
        (kAudioChannelLayoutTag_DTS_6_0_A, [7, 8, 1, 2, 5, 6]),
        (kAudioChannelLayoutTag_DTS_6_0_B, [3, 1, 2, 33, 34, 12]),
        (kAudioChannelLayoutTag_DTS_6_0_C, [3, 9, 1, 2, 33, 34]),
        (kAudioChannelLayoutTag_DTS_6_1_A, [7, 8, 1, 2, 5, 6, 4]),
        (kAudioChannelLayoutTag_DTS_6_1_B, [3, 1, 2, 33, 34, 12, 4]),
        (kAudioChannelLayoutTag_DTS_6_1_C, [3, 9, 1, 2, 33, 34, 4]),
        (kAudioChannelLayoutTag_DTS_7_0, [7, 3, 8, 1, 2, 5, 6]),
        (kAudioChannelLayoutTag_DTS_7_1, [7, 3, 8, 1, 2, 5, 6, 4]),
        (kAudioChannelLayoutTag_DTS_8_0_A, [7, 8, 1, 2, 5, 6, 33, 34]),
        (kAudioChannelLayoutTag_DTS_8_0_B, [7, 3, 8, 1, 2, 5, 9, 6]),
        (kAudioChannelLayoutTag_DTS_8_1_A, [7, 8, 1, 2, 5, 6, 33, 34, 4]),
        (kAudioChannelLayoutTag_DTS_8_1_B, [7, 3, 8, 1, 2, 5, 9, 6, 4]),
        (kAudioChannelLayoutTag_DTS_6_1_D, [3, 1, 2, 5, 6, 4, 9]),
        (kAudioChannelLayoutTag_WAVE_4_0_B, [1, 2, 33, 34]),
        (kAudioChannelLayoutTag_WAVE_5_0_B, [1, 2, 3, 33, 34]),
        (kAudioChannelLayoutTag_WAVE_5_1_B, [1, 2, 3, 4, 33, 34]),
        (kAudioChannelLayoutTag_WAVE_6_1, [1, 2, 3, 4, 9, 5, 6]),
        (kAudioChannelLayoutTag_WAVE_7_1, [1, 2, 3, 4, 33, 34, 5, 6]),
        (kAudioChannelLayoutTag_Atmos_7_1_4, [1, 2, 3, 4, 5, 6, 33, 34, 13, 15, 52, 54]),
        (kAudioChannelLayoutTag_Atmos_9_1_6, [1, 2, 3, 4, 5, 6, 33, 34, 35, 36, 13, 15, 49, 51, 52, 54]),
        (kAudioChannelLayoutTag_Atmos_5_1_2, [1, 2, 3, 4, 5, 6, 52, 54]),
    ]

    private static let lpcmExceptions: [(AudioChannelLayoutTag, AudioChannelLayoutTag)] = [
        (kAudioChannelLayoutTag_ITU_2_2, kAudioChannelLayoutTag_Quadraphonic),
        (kAudioChannelLayoutTag_AAC_Quadraphonic, kAudioChannelLayoutTag_Quadraphonic),
        (kAudioChannelLayoutTag_MPEG_5_0_A, kAudioChannelLayoutTag_Pentagonal),
        (kAudioChannelLayoutTag_MPEG_5_0_B, kAudioChannelLayoutTag_Pentagonal),
        (kAudioChannelLayoutTag_MPEG_5_0_C, kAudioChannelLayoutTag_Pentagonal),
        (kAudioChannelLayoutTag_MPEG_5_0_D, kAudioChannelLayoutTag_Pentagonal),
        (kAudioChannelLayoutTag_AAC_5_0, kAudioChannelLayoutTag_Pentagonal),
        (kAudioChannelLayoutTag_AudioUnit_6_0, kAudioChannelLayoutTag_Hexagonal),
        (kAudioChannelLayoutTag_AAC_6_0, kAudioChannelLayoutTag_Hexagonal),
        (kAudioChannelLayoutTag_EAC_6_0_A, kAudioChannelLayoutTag_Hexagonal),
        (kAudioChannelLayoutTag_MPEG_3_0_B, kAudioChannelLayoutTag_MPEG_3_0_A),
        (kAudioChannelLayoutTag_AAC_3_0, kAudioChannelLayoutTag_MPEG_3_0_A),
        (kAudioChannelLayoutTag_AC3_3_0, kAudioChannelLayoutTag_MPEG_3_0_A),
        (kAudioChannelLayoutTag_MPEG_4_0_B, kAudioChannelLayoutTag_MPEG_4_0_A),
        (kAudioChannelLayoutTag_AAC_4_0, kAudioChannelLayoutTag_MPEG_4_0_A),
        (kAudioChannelLayoutTag_AC3_3_1, kAudioChannelLayoutTag_MPEG_4_0_A),
        (kAudioChannelLayoutTag_MPEG_5_1_B, kAudioChannelLayoutTag_MPEG_5_1_A),
        (kAudioChannelLayoutTag_MPEG_5_1_C, kAudioChannelLayoutTag_MPEG_5_1_A),
        (kAudioChannelLayoutTag_MPEG_5_1_D, kAudioChannelLayoutTag_MPEG_5_1_A),
        (kAudioChannelLayoutTag_AAC_5_1, kAudioChannelLayoutTag_MPEG_5_1_A),
        (kAudioChannelLayoutTag_MPEG_7_1_B, kAudioChannelLayoutTag_MPEG_7_1_A),
        (kAudioChannelLayoutTag_AAC_7_1, kAudioChannelLayoutTag_MPEG_7_1_A),
        (kAudioChannelLayoutTag_Emagic_Default_7_1, kAudioChannelLayoutTag_MPEG_7_1_A),
        (kAudioChannelLayoutTag_EAC3_7_1_B, kAudioChannelLayoutTag_MPEG_7_1_A),
        (kAudioChannelLayoutTag_DTS_7_1, kAudioChannelLayoutTag_MPEG_7_1_A),
        (kAudioChannelLayoutTag_WAVE_7_1, kAudioChannelLayoutTag_MPEG_7_1_C),
        (kAudioChannelLayoutTag_AAC_7_1_B, kAudioChannelLayoutTag_MPEG_7_1_C),
        (kAudioChannelLayoutTag_EAC3_7_1_A, kAudioChannelLayoutTag_MPEG_7_1_C),
        (kAudioChannelLayoutTag_DVD_18, kAudioChannelLayoutTag_DVD_6),
        (kAudioChannelLayoutTag_EAC_7_0_A, kAudioChannelLayoutTag_AudioUnit_7_0),
        (kAudioChannelLayoutTag_AAC_7_0, kAudioChannelLayoutTag_AudioUnit_7_0),
        (kAudioChannelLayoutTag_AAC_6_1, kAudioChannelLayoutTag_MPEG_6_1_A),
        (kAudioChannelLayoutTag_WAVE_6_1, kAudioChannelLayoutTag_MPEG_6_1_A),
        (kAudioChannelLayoutTag_EAC3_6_1_A, kAudioChannelLayoutTag_MPEG_6_1_A),
        (kAudioChannelLayoutTag_DTS_6_1_D, kAudioChannelLayoutTag_MPEG_6_1_A),
        (kAudioChannelLayoutTag_EAC3_7_1_E, kAudioChannelLayoutTag_AAC_7_1_C),
        (kAudioChannelLayoutTag_DTS_3_1, kAudioChannelLayoutTag_DVD_10),
        (kAudioChannelLayoutTag_AC3_3_0_1, kAudioChannelLayoutTag_DVD_10),
        (kAudioChannelLayoutTag_AC3_2_1_1, kAudioChannelLayoutTag_DVD_5),
        (kAudioChannelLayoutTag_DTS_4_1, kAudioChannelLayoutTag_DVD_11),
        (kAudioChannelLayoutTag_AC3_3_1_1, kAudioChannelLayoutTag_DVD_11),
        (kAudioChannelLayoutTag_DTS_7_0, kAudioChannelLayoutTag_AudioUnit_7_0_Front),
    ]

    private static func lpcmExpected(for tag: AudioChannelLayoutTag) -> AudioChannelLayoutTag {
        return Self.lpcmExceptions.first(where: { $0.0 == tag })?.1 ?? tag
    }

    private static let aacDirectCases: [(Set<AudioChannelLabel>, AudioChannelLayoutTag)] = [
        ([42], kAudioChannelLayoutTag_Mono),
        ([3], kAudioChannelLayoutTag_Mono),
        ([1, 2], kAudioChannelLayoutTag_Stereo),
        ([3, 1, 2], kAudioChannelLayoutTag_AAC_3_0),
        ([1, 2, 5, 6], kAudioChannelLayoutTag_AAC_Quadraphonic),
        ([3, 1, 2, 9], kAudioChannelLayoutTag_AAC_4_0),
        ([3, 1, 2, 5, 6], kAudioChannelLayoutTag_AAC_5_0),
        ([3, 1, 2, 5, 6, 4], kAudioChannelLayoutTag_AAC_5_1),
        ([3, 1, 2, 5, 6, 9], kAudioChannelLayoutTag_AAC_6_0),
        ([3, 1, 2, 5, 6, 9, 4], kAudioChannelLayoutTag_AAC_6_1),
        ([3, 1, 2, 5, 6, 33, 34], kAudioChannelLayoutTag_AAC_7_0),
        ([3, 7, 8, 1, 2, 5, 6, 4], kAudioChannelLayoutTag_AAC_7_1),
        ([3, 1, 2, 5, 6, 33, 34, 4], kAudioChannelLayoutTag_AAC_7_1_B),
        ([3, 1, 2, 5, 6, 4, 13, 15], kAudioChannelLayoutTag_AAC_7_1_C),
        ([3, 1, 2, 5, 6, 33, 34, 9], kAudioChannelLayoutTag_AAC_Octagonal),
    ]

    private static let aacFallbackCases: [(Set<AudioChannelLabel>, AudioChannelLayoutTag)] = [
        ([301, 302], kAudioChannelLayoutTag_Stereo),
        ([38, 39], kAudioChannelLayoutTag_Stereo),
        ([204, 205], kAudioChannelLayoutTag_Stereo),
        ([206, 207], kAudioChannelLayoutTag_Stereo),
        ([208, 209], kAudioChannelLayoutTag_Stereo),
        ([200, 201, 202, 203], kAudioChannelLayoutTag_AAC_7_1_C),
        ([1, 2, 5, 6, 3, 9, 35, 36], kAudioChannelLayoutTag_AAC_Octagonal),
        ([1, 2, 33, 34, 13, 15, 16, 18], kAudioChannelLayoutTag_AAC_7_1_C),
        ([1, 2, 3, 4, 5, 6, 38, 39], kAudioChannelLayoutTag_AAC_Octagonal),
        ([1, 2, 9], kAudioChannelLayoutTag_AAC_4_0),
        ([1, 2, 4], kAudioChannelLayoutTag_AAC_5_1),
        ([1, 2, 4, 9], kAudioChannelLayoutTag_AAC_6_1),
        ([1, 2, 4, 5, 6], kAudioChannelLayoutTag_AAC_5_1),
        ([1, 2, 3, 4], kAudioChannelLayoutTag_AAC_5_1),
        ([1, 2, 3, 4, 9], kAudioChannelLayoutTag_AAC_6_1),
        ([1, 2, 5, 6, 3, 7, 8], kAudioChannelLayoutTag_AAC_Octagonal),
    ]

    private static func aacExpectation(for labels: Set<AudioChannelLabel>, strict: Bool) -> AudioChannelLayoutTag {
        if let (_, tag) = Self.aacDirectCases.first(where: { $0.0 == labels }) { return tag }
        if strict { return kAudioChannelLayoutTag_Unknown | AudioChannelLayoutTag(labels.count) }
        if let (_, tag) = Self.aacFallbackCases.first(where: { $0.0 == labels }) { return tag }
        return kAudioChannelLayoutTag_Unknown | AudioChannelLayoutTag(labels.count)
    }

    func testChannelLabelSetForTagMatchesForwardTable() {
        XCTAssertEqual(Self.allTags.count, 96)
        XCTAssertEqual(Set(Self.allTags.map(\.tag)).count, 90)
        let converter = LayoutConverter()
        for (tag, expected) in Self.allTags {
            XCTAssertEqual(converter.channelLabelSet(forTag: tag), expected,
                           "forward table drifted for tag \(tag)")
        }
    }

    func testChannelLayoutTagLPCMForChannelLabelSetMatchesReverseTable() {
        let converter = LayoutConverter()
        for (tag, labels) in Self.allTags {
            let expected = Self.lpcmExpected(for: tag)
            let reversed = converter.channelLayoutTagLPCMForChannelLabelSet(labels)
            XCTAssertEqual(reversed, expected,
                           "LPCM reverse for \(tag) must yield \(expected), got \(reversed)")
            XCTAssertEqual(converter.channelLabelSet(forTag: expected), labels,
                           "forward(winner) must reproduce the original set for \(tag)")
        }
    }

    func testChannelLayoutTagAACForChannelLabelSetMatchesAACTable() {
        XCTAssertEqual(Self.aacDirectCases.count, 15)
        XCTAssertEqual(Self.aacFallbackCases.count, 16)
        let converter = LayoutConverter()
        for (tag, labels) in Self.allTags {
            XCTAssertEqual(converter.channelLayoutTagAACForChannelLabelSet(labels, false),
                           Self.aacExpectation(for: labels, strict: false),
                           "AAC reverse (strict=false) drifted for tag \(tag)")
            XCTAssertEqual(converter.channelLayoutTagAACForChannelLabelSet(labels, true),
                           Self.aacExpectation(for: labels, strict: true),
                           "AAC reverse (strict=true) drifted for tag \(tag)")
        }
    }

    func testBitmapLabelSetRoundTrip() {
        let converter = LayoutConverter()
        let bits: [AudioChannelBitmap] = [.bit_Left, .bit_Right, .bit_Center, .bit_LFEScreen,
            .bit_LeftSurround, .bit_RightSurround, .bit_LeftCenter, .bit_RightCenter,
            .bit_CenterSurround, .bit_LeftSurroundDirect, .bit_RightSurroundDirect,
            .bit_TopCenterSurround, .bit_VerticalHeightLeft, .bit_VerticalHeightCenter,
            .bit_VerticalHeightRight, .bit_TopBackLeft, .bit_TopBackCenter, .bit_TopBackRight,
            .bit_LeftTopFront, .bit_CenterTopFront, .bit_RightTopFront, .bit_LeftTopMiddle,
            .bit_CenterTopMiddle, .bit_RightTopMiddle, .bit_LeftTopRear, .bit_CenterTopRear,
            .bit_RightTopRear]
        var all: AudioChannelBitmap = []
        for bit in bits {
            let labels = converter.channelLabelSet(forBitmap: bit)
            XCTAssertEqual(converter.channelBitmapForChannelLabelSet(labels), bit)
            all.insert(bit)
        }
        let allLabels = converter.channelLabelSet(forBitmap: all)
        XCTAssertEqual(converter.channelBitmapForChannelLabelSet(allLabels), all)
        XCTAssertEqual(converter.channelBitmapForChannelLabelSet(converter.channelLabelSet(forBitmap: [])), [])
    }

    func testDiscreteInOrderAndUnknownTagRoundTrip() {
        let converter = LayoutConverter()
        for n: UInt32 in 1...16 {
            let discreteTag = kAudioChannelLayoutTag_DiscreteInOrder | n
            let labels = converter.channelLabelSet(forTag: discreteTag)
            XCTAssertEqual(labels.count, Int(n))
            XCTAssertEqual(converter.channelLayoutTagLPCMForChannelLabelSet(labels), discreteTag)

            let unknownTag = kAudioChannelLayoutTag_Unknown | n
            XCTAssertEqual(converter.channelLayoutTagLPCMForChannelLabelSet(
                converter.channelLabelSet(forTag: unknownTag)), discreteTag)
        }
    }
}
