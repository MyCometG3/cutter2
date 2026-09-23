//
//  LayoutConverter+Mapping.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import AVFoundation

// MARK: - Unsupported AudioChannelLayoutTag

// The following CoreAudio channel layout tags exist as enumerator values but are intentionally
// excluded from the mapping tables in this file because the required AudioChannelLabel constants
// are either undefined or unconfirmed in the CoreAudio headers:
//
// | Tag                                    | Reason                                          |
// |----------------------------------------|-------------------------------------------------|
// | kAudioChannelLayoutTag_TMH_10_2_std    | LFELeft/LFERight/VI label values unconfirmed     |
// | kAudioChannelLayoutTag_TMH_10_2_full   | Same as above                                    |
//
// Specifically:
// - TMH_10_2_std requires label values for LFELeft (LFE1), LFERight (LFE2), and VI.
// - TMH_10_2_full requires the same plus additional labels.
// - These labels do not have obvious correspondents in the kAudioChannelLabel enumeration
//   documented by Apple. Until these are confirmed, the tags are kept commented-out
//   in both the forward (tag -> label set) and reverse (label set -> tag) mapping functions.

private enum LayoutMappingTables {
    // Keep table order aligned with the original switch cases.
    static let tagToLabels: [(AudioChannelLayoutTag, [AudioChannelLabel])] = [
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

    static let aacDirect: [([AudioChannelLabel], AudioChannelLayoutTag)] = [
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

    static let aacFallback: [([AudioChannelLabel], AudioChannelLayoutTag)] = [
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

    static let lpcmReverse: [([AudioChannelLabel], AudioChannelLayoutTag)] = [
        ([42], kAudioChannelLayoutTag_Mono),
        ([3], kAudioChannelLayoutTag_Mono),
        ([1, 2], kAudioChannelLayoutTag_Stereo),
        ([301, 302], kAudioChannelLayoutTag_StereoHeadphones),
        ([38, 39], kAudioChannelLayoutTag_MatrixStereo),
        ([204, 205], kAudioChannelLayoutTag_MidSide),
        ([206, 207], kAudioChannelLayoutTag_XY),
        ([208, 209], kAudioChannelLayoutTag_Binaural),
        ([200, 201, 202, 203], kAudioChannelLayoutTag_Ambisonic_B_Format),
        ([1, 2, 5, 6], kAudioChannelLayoutTag_Quadraphonic),
        ([1, 2, 5, 6, 3], kAudioChannelLayoutTag_Pentagonal),
        ([1, 2, 5, 6, 3, 9], kAudioChannelLayoutTag_Hexagonal),
        ([1, 2, 5, 6, 3, 9, 35, 36], kAudioChannelLayoutTag_Octagonal),
        ([1, 2, 33, 34, 13, 15, 16, 18], kAudioChannelLayoutTag_Cube),
        ([1, 2, 3], kAudioChannelLayoutTag_MPEG_3_0_A),
        ([3, 1, 2], kAudioChannelLayoutTag_MPEG_3_0_B),
        ([1, 2, 3, 9], kAudioChannelLayoutTag_MPEG_4_0_A),
        ([3, 1, 2, 9], kAudioChannelLayoutTag_MPEG_4_0_B),
        ([1, 2, 3, 5, 6], kAudioChannelLayoutTag_MPEG_5_0_A),
        ([1, 2, 5, 6, 3], kAudioChannelLayoutTag_MPEG_5_0_B),
        ([1, 3, 2, 5, 6], kAudioChannelLayoutTag_MPEG_5_0_C),
        ([3, 1, 2, 5, 6], kAudioChannelLayoutTag_MPEG_5_0_D),
        ([1, 2, 3, 4, 5, 6], kAudioChannelLayoutTag_MPEG_5_1_A),
        ([1, 2, 5, 6, 3, 4], kAudioChannelLayoutTag_MPEG_5_1_B),
        ([1, 3, 2, 5, 6, 4], kAudioChannelLayoutTag_MPEG_5_1_C),
        ([3, 1, 2, 5, 6, 4], kAudioChannelLayoutTag_MPEG_5_1_D),
        ([1, 2, 3, 4, 5, 6, 9], kAudioChannelLayoutTag_MPEG_6_1_A),
        ([1, 2, 3, 4, 5, 6, 7, 8], kAudioChannelLayoutTag_MPEG_7_1_A),
        ([3, 7, 8, 1, 2, 5, 6, 4], kAudioChannelLayoutTag_MPEG_7_1_B),
        ([1, 2, 3, 4, 5, 6, 33, 34], kAudioChannelLayoutTag_MPEG_7_1_C),
        ([1, 2, 5, 6, 3, 4, 7, 8], kAudioChannelLayoutTag_Emagic_Default_7_1),
        ([1, 2, 3, 4, 5, 6, 38, 39], kAudioChannelLayoutTag_SMPTE_DTV),
        ([1, 2, 9], kAudioChannelLayoutTag_ITU_2_1),
        ([1, 2, 5, 6], kAudioChannelLayoutTag_ITU_2_2),
        ([1, 2, 4], kAudioChannelLayoutTag_DVD_4),
        ([1, 2, 4, 9], kAudioChannelLayoutTag_DVD_5),
        ([1, 2, 4, 5, 6], kAudioChannelLayoutTag_DVD_6),
        ([1, 2, 3, 4], kAudioChannelLayoutTag_DVD_10),
        ([1, 2, 3, 4, 9], kAudioChannelLayoutTag_DVD_11),
        ([1, 2, 5, 6, 4], kAudioChannelLayoutTag_DVD_18),
        ([1, 2, 5, 6, 3, 9], kAudioChannelLayoutTag_AudioUnit_6_0),
        ([1, 2, 5, 6, 3, 33, 34], kAudioChannelLayoutTag_AudioUnit_7_0),
        ([1, 2, 5, 6, 3, 7, 8], kAudioChannelLayoutTag_AudioUnit_7_0_Front),
        ([3, 1, 2, 5, 6, 9], kAudioChannelLayoutTag_AAC_6_0),
        ([3, 1, 2, 5, 6, 9, 4], kAudioChannelLayoutTag_AAC_6_1),
        ([3, 1, 2, 5, 6, 33, 34], kAudioChannelLayoutTag_AAC_7_0),
        ([3, 1, 2, 5, 6, 33, 34, 4], kAudioChannelLayoutTag_AAC_7_1_B),
        ([3, 1, 2, 5, 6, 4, 13, 15], kAudioChannelLayoutTag_AAC_7_1_C),
        ([3, 1, 2, 5, 6, 33, 34, 9], kAudioChannelLayoutTag_AAC_Octagonal),
        ([3, 4], kAudioChannelLayoutTag_AC3_1_0_1),
        ([1, 3, 2], kAudioChannelLayoutTag_AC3_3_0),
        ([1, 3, 2, 9], kAudioChannelLayoutTag_AC3_3_1),
        ([1, 3, 2, 4], kAudioChannelLayoutTag_AC3_3_0_1),
        ([1, 2, 9, 4], kAudioChannelLayoutTag_AC3_2_1_1),
        ([1, 3, 2, 9, 4], kAudioChannelLayoutTag_AC3_3_1_1),
        ([1, 3, 2, 5, 6, 9], kAudioChannelLayoutTag_EAC_6_0_A),
        ([1, 3, 2, 5, 6, 33, 34], kAudioChannelLayoutTag_EAC_7_0_A),
        ([1, 3, 2, 5, 6, 4, 9], kAudioChannelLayoutTag_EAC3_6_1_A),
        ([1, 3, 2, 5, 6, 4, 12], kAudioChannelLayoutTag_EAC3_6_1_B),
        ([1, 3, 2, 5, 6, 4, 14], kAudioChannelLayoutTag_EAC3_6_1_C),
        ([1, 3, 2, 5, 6, 4, 33, 34], kAudioChannelLayoutTag_EAC3_7_1_A),
        ([1, 3, 2, 5, 6, 4, 7, 8], kAudioChannelLayoutTag_EAC3_7_1_B),
        ([1, 3, 2, 5, 6, 4, 10, 11], kAudioChannelLayoutTag_EAC3_7_1_C),
        ([1, 3, 2, 5, 6, 4, 35, 36], kAudioChannelLayoutTag_EAC3_7_1_D),
        ([1, 3, 2, 5, 6, 4, 13, 15], kAudioChannelLayoutTag_EAC3_7_1_E),
        ([1, 3, 2, 5, 6, 4, 9, 12], kAudioChannelLayoutTag_EAC3_7_1_F),
        ([1, 3, 2, 5, 6, 4, 9, 14], kAudioChannelLayoutTag_EAC3_7_1_G),
        ([1, 3, 2, 5, 6, 4, 12, 14], kAudioChannelLayoutTag_EAC3_7_1_H),
        ([3, 1, 2, 4], kAudioChannelLayoutTag_DTS_3_1),
        ([3, 1, 2, 9, 4], kAudioChannelLayoutTag_DTS_4_1),
        ([7, 8, 1, 2, 5, 6], kAudioChannelLayoutTag_DTS_6_0_A),
        ([3, 1, 2, 33, 34, 12], kAudioChannelLayoutTag_DTS_6_0_B),
        ([3, 9, 1, 2, 33, 34], kAudioChannelLayoutTag_DTS_6_0_C),
        ([7, 8, 1, 2, 5, 6, 4], kAudioChannelLayoutTag_DTS_6_1_A),
        ([3, 1, 2, 33, 34, 12, 4], kAudioChannelLayoutTag_DTS_6_1_B),
        ([3, 9, 1, 2, 33, 34, 4], kAudioChannelLayoutTag_DTS_6_1_C),
        ([7, 3, 8, 1, 2, 5, 6], kAudioChannelLayoutTag_DTS_7_0),
        ([7, 3, 8, 1, 2, 5, 6, 4], kAudioChannelLayoutTag_DTS_7_1),
        ([7, 8, 1, 2, 5, 6, 33, 34], kAudioChannelLayoutTag_DTS_8_0_A),
        ([7, 3, 8, 1, 2, 5, 9, 6], kAudioChannelLayoutTag_DTS_8_0_B),
        ([7, 8, 1, 2, 5, 6, 33, 34, 4], kAudioChannelLayoutTag_DTS_8_1_A),
        ([7, 3, 8, 1, 2, 5, 9, 6, 4], kAudioChannelLayoutTag_DTS_8_1_B),
        ([3, 1, 2, 5, 6, 4, 9], kAudioChannelLayoutTag_DTS_6_1_D),
        ([1, 2, 33, 34], kAudioChannelLayoutTag_WAVE_4_0_B),
        ([1, 2, 3, 33, 34], kAudioChannelLayoutTag_WAVE_5_0_B),
        ([1, 2, 3, 4, 33, 34], kAudioChannelLayoutTag_WAVE_5_1_B),
        ([1, 2, 3, 4, 9, 5, 6], kAudioChannelLayoutTag_WAVE_6_1),
        ([1, 2, 3, 4, 33, 34, 5, 6], kAudioChannelLayoutTag_WAVE_7_1),
        ([1, 2, 3, 4, 5, 6, 33, 34, 13, 15, 52, 54], kAudioChannelLayoutTag_Atmos_7_1_4),
        ([1, 2, 3, 4, 5, 6, 33, 34, 35, 36, 13, 15, 49, 51, 52, 54], kAudioChannelLayoutTag_Atmos_9_1_6),
        ([1, 2, 3, 4, 5, 6, 52, 54], kAudioChannelLayoutTag_Atmos_5_1_2),
    ]

    static let bitmapMappings: [(UInt32, AudioChannelLabel)] = [
        (AudioChannelBitmap.bit_Left.rawValue, kAudioChannelLabel_Left),
        (AudioChannelBitmap.bit_Right.rawValue, kAudioChannelLabel_Right),
        (AudioChannelBitmap.bit_Center.rawValue, kAudioChannelLabel_Center),
        (AudioChannelBitmap.bit_LFEScreen.rawValue, kAudioChannelLabel_LFEScreen),
        (AudioChannelBitmap.bit_LeftSurround.rawValue, kAudioChannelLabel_LeftSurround),
        (AudioChannelBitmap.bit_RightSurround.rawValue, kAudioChannelLabel_RightSurround),
        (AudioChannelBitmap.bit_LeftCenter.rawValue, kAudioChannelLabel_LeftCenter),
        (AudioChannelBitmap.bit_RightCenter.rawValue, kAudioChannelLabel_RightCenter),
        (AudioChannelBitmap.bit_CenterSurround.rawValue, kAudioChannelLabel_CenterSurround),
        (AudioChannelBitmap.bit_LeftSurroundDirect.rawValue, kAudioChannelLabel_LeftSurroundDirect),
        (AudioChannelBitmap.bit_RightSurroundDirect.rawValue, kAudioChannelLabel_RightSurroundDirect),
        (AudioChannelBitmap.bit_TopCenterSurround.rawValue, kAudioChannelLabel_TopCenterSurround),
        (AudioChannelBitmap.bit_VerticalHeightLeft.rawValue, kAudioChannelLabel_VerticalHeightLeft),
        (AudioChannelBitmap.bit_VerticalHeightCenter.rawValue, kAudioChannelLabel_VerticalHeightCenter),
        (AudioChannelBitmap.bit_VerticalHeightRight.rawValue, kAudioChannelLabel_VerticalHeightRight),
        (AudioChannelBitmap.bit_TopBackLeft.rawValue, kAudioChannelLabel_TopBackLeft),
        (AudioChannelBitmap.bit_TopBackCenter.rawValue, kAudioChannelLabel_TopBackCenter),
        (AudioChannelBitmap.bit_TopBackRight.rawValue, kAudioChannelLabel_TopBackRight),
        (AudioChannelBitmap.bit_LeftTopFront.rawValue, kAudioChannelLabel_LeftTopFront),
        (AudioChannelBitmap.bit_CenterTopFront.rawValue, kAudioChannelLabel_CenterTopFront),
        (AudioChannelBitmap.bit_RightTopFront.rawValue, kAudioChannelLabel_RightTopFront),
        (AudioChannelBitmap.bit_LeftTopMiddle.rawValue, kAudioChannelLabel_LeftTopMiddle),
        (AudioChannelBitmap.bit_CenterTopMiddle.rawValue, kAudioChannelLabel_CenterTopMiddle),
        (AudioChannelBitmap.bit_RightTopMiddle.rawValue, kAudioChannelLabel_RightTopMiddle),
        (AudioChannelBitmap.bit_LeftTopRear.rawValue, kAudioChannelLabel_LeftTopRear),
        (AudioChannelBitmap.bit_CenterTopRear.rawValue, kAudioChannelLabel_CenterTopRear),
        (AudioChannelBitmap.bit_RightTopRear.rawValue, kAudioChannelLabel_RightTopRear),
    ]
}

extension LayoutConverter {
    
    /* ============================================ */
    // MARK: - Converter helpers
    /* ============================================ */
    
    func channelLabelSet(forBitmap bitmap: AudioChannelBitmap) -> Set<AudioChannelLabel> {
        Set(LayoutMappingTables.bitmapMappings.compactMap { bit, label in
            bitmap.contains(AudioChannelBitmap(rawValue: bit)) ? label : nil
        })
    }
    
    func channelLabelSet(forDescriptions layoutPtr: LayoutPtr, count acDescCount: Int) -> Set<AudioChannelLabel> {
        // translate Channel Description(s) to AudioChannelLabel Set
        let unsupported: [AudioChannelLabel] = [kAudioChannelLabel_Unused,
                                                kAudioChannelLabel_Unknown,
                                                kAudioChannelLabel_UseCoordinates]
        
        // Get UnsafeBufferPointer<AudioChannelDescription> inside AudioChannelLayout
        let offset :UnsafePointer<AudioChannelDescription> = layoutPtr.pointer(to: \AudioChannelLayout.mChannelDescriptions)!
        let acDescPtr = DescriptionsPtr(start: offset, count: acDescCount)
        
        // Validate AudioChannelLabel(s) to process
        let srcPos: [AudioChannelLabel] = (0..<acDescCount).map { acDescPtr[$0].mChannelLabel }
        let dstPos: [AudioChannelLabel] = srcPos.filter { !unsupported.contains($0) }
        
        // Make Set<AudioChannelLabel>
        let pos = Set(dstPos)
        
        #if DEBUG
        LoggingSystem.video.debug("Channel validation - Input count: \(acDescCount, privacy: .public), Output count: \(dstPos.count, privacy: .public)")
        acDescPtr.forEach { desc in
            LoggingSystem.video.debug("  Channel: label=\(desc.mChannelLabel, privacy: .public), flags=\(desc.mChannelFlags.rawValue, privacy: .public)")
        }
        LoggingSystem.video.debug("AudioChannelLabel validation - Input: \(srcPos), Output: \(dstPos), Set: \(pos)")
        #endif
        
        return pos
    }
    
    func channelLabelSet(forTag tag: AudioChannelLayoutTag) -> Set<AudioChannelLabel> {
        if let (_, labels) = LayoutMappingTables.tagToLabels.first(where: { $0.0 == tag }) {
            return Set(labels)
        }
        // Unknown / DiscreteInOrder-style tags use the low 16-bit channel count payload.
        let discrete: AudioChannelLabel = kAudioChannelLabel_Discrete_0
        let numChannels: UInt32 = tag & 0x0000FFFF
        return Set((0..<numChannels).map { discrete | $0 })
    }
    
    func channelLayoutTagAACForChannelLabelSet(_ pos: Set<AudioChannelLabel>, _ strict: Bool) -> AudioChannelLayoutTag {
        if let (_, tag) = LayoutMappingTables.aacDirect.first(where: { Set($0.0) == pos }) {
            return tag
        }
        if strict {
            // Incompatible with AAC.
            return kAudioChannelLayoutTag_Unknown | AudioChannelLayoutTag(pos.count)
        }
        if let (_, tag) = LayoutMappingTables.aacFallback.first(where: { Set($0.0) == pos }) {
            return tag
        }
        return kAudioChannelLayoutTag_Unknown | AudioChannelLayoutTag(pos.count)
    }
    
    func channelLayoutTagLPCMForChannelLabelSet(_ pos: Set<AudioChannelLabel>) -> AudioChannelLayoutTag {
        if let (_, tag) = LayoutMappingTables.lpcmReverse.first(where: { Set($0.0) == pos }) {
            return tag
        }
        // Fallback into numbered discrete channels.
        let discrete = kAudioChannelLayoutTag_DiscreteInOrder
        let numChannels = AudioChannelLayoutTag(pos.count)
        return discrete | numChannels
    }
    
    func channelBitmapForChannelLabelSet(_ pos: Set<AudioChannelLabel>) -> AudioChannelBitmap {
        var bitmap: AudioChannelBitmap = []
        for (bit, label) in LayoutMappingTables.bitmapMappings where pos.contains(label) {
            bitmap.insert(AudioChannelBitmap(rawValue: bit))
        }
        return bitmap
    }
    
    func channelDescriptionsForChannelLabelSet(_ pos: Set<AudioChannelLabel>) -> [AudioChannelDescription] {
        var descArray: [AudioChannelDescription] = []
        for label in pos {
            let desc = AudioChannelDescription(mChannelLabel: label,
                                               mChannelFlags: [],
                                               mCoordinates: (0.0,0.0,0.0))
            descArray.append(desc)
        }
        return descArray
    }
}
