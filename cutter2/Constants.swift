//
//  Constants.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2020/08/14.
//  Copyright © 2025 MyCometG3. All rights reserved.
//

import Foundation

/* ============================================ */
// MARK: - Document + TranscodeViewController (UserDefaultsKey)
/* ============================================ */

/// User defaults keys for transcoding settings
enum TranscodeUserDefaultsKey: String {
    case transcodePreset = "transcodePreset"
    case transcodeType = "transcodeType"
    case transcode0 = "transcode0"
    case transcode1 = "transcode1"
    case transcode2 = "transcode2"
    case transcode3 = "transcode3"
    case avFileType = "avFileType"
    case hevcReady = "hevcReady"
}

// Legacy constants for backward compatibility
let kTranscodePresetKey = TranscodeUserDefaultsKey.transcodePreset.rawValue
let kTranscodeTypeKey = TranscodeUserDefaultsKey.transcodeType.rawValue
let kTrancode0Key = TranscodeUserDefaultsKey.transcode0.rawValue
let kTrancode1Key = TranscodeUserDefaultsKey.transcode1.rawValue
let kTrancode2Key = TranscodeUserDefaultsKey.transcode2.rawValue
let kTrancode3Key = TranscodeUserDefaultsKey.transcode3.rawValue
let kAVFileTypeKey = TranscodeUserDefaultsKey.avFileType.rawValue
let kHEVCReadyKey = TranscodeUserDefaultsKey.hevcReady.rawValue

let kTranscodePresetCustom = "Custom"

/* ============================================ */
// MARK: - Document + MovieWriter (UserDefaultsKey)
/* ============================================ */

/// User defaults keys for movie writer settings
enum MovieWriterUserDefaultsKey: String {
    case lpcmDepth = "lpcmDepth"
    case audioKbps = "audioKbps"
    case videoKbps = "videoKbps"
    case copyField = "copyField"
    case copyNCLC = "copyNCLC"
    case copyOtherMedia = "copyOtherMedia"
    case videoEncode = "videoEncode"
    case audioEncode = "audioEncode"
    case videoCodec = "videoCodec"
    case audioCodec = "audioCodec"
}

// Legacy constants for backward compatibility
let kLPCMDepthKey = MovieWriterUserDefaultsKey.lpcmDepth.rawValue
let kAudioKbpsKey = MovieWriterUserDefaultsKey.audioKbps.rawValue
let kVideoKbpsKey = MovieWriterUserDefaultsKey.videoKbps.rawValue
let kCopyFieldKey = MovieWriterUserDefaultsKey.copyField.rawValue
let kCopyNCLCKey = MovieWriterUserDefaultsKey.copyNCLC.rawValue
let kCopyOtherMediaKey = MovieWriterUserDefaultsKey.copyOtherMedia.rawValue
let kVideoEncodeKey = MovieWriterUserDefaultsKey.videoEncode.rawValue
let kAudioEncodeKey = MovieWriterUserDefaultsKey.audioEncode.rawValue
let kVideoCodecKey = MovieWriterUserDefaultsKey.videoCodec.rawValue
let kAudioCodecKey = MovieWriterUserDefaultsKey.audioCodec.rawValue

/* ============================================ */
// MARK: - Document + MovieMutatorBase (InfoDictionaryKey)
/* ============================================ */

let timeValueInfoKey: String = "timeValue" // CMTime
let timeRangeValueInfoKey: String = "timeRangeValue" // CMTimeRange

/* ============================================ */
// MARK: - MovieMutator + MovieMutatorBase + CAPARViewController (UserDefaultsKey)
/* ============================================ */

let clapSizeKey: String = "clapSize" // NSSize
let clapOffsetKey: String = "clapOffset" // NSPoint
let paspRatioKey: String = "paspRatio" // NSSize
let dimensionsKey: String = "dimensions" // NSSize

/* ============================================ */
// MARK: - Document + ViewController (InfoDictionaryKey)
/* ============================================ */

let timeInfoKey: String = "time" // CMTime
let rangeInfoKey: String = "range" // CMTimeRange
let curPositionInfoKey: String = "curPosition" // Float64
let startPositionInfoKey: String = "startPosition" // Float64
let endPositionInfoKey: String = "endPosition" // Float64
let stringInfoKey: String = "string" // String
let durationInfoKey: String = "duration" // CMTime

/* ============================================ */
// MARK: - Document (InspectKey)
/* ============================================ */

let titleInspectKey: String = "title" // String
let pathInspectKey: String = "path" // String (numTracks)
let videoFormatInspectKey: String = "videoFormat" // String (numTracks)
let videoFPSInspectKey: String = "videoFPS" // String (numTracks)
let audioFormatInspectKey: String = "audioFormat" // String (numTracks)
let videoDataSizeInspectKey: String = "videoDataSize" // String (numTracks)
let audioDataSizeInspectKey: String = "audioDataSize" // String (numTracks)
let currentTimeInspectKey: String = "currentTime" // String
let movieDurationInspectKey: String = "movieDuration" // String
let selectionStartInspectKey: String = "selectionStart" // String
let selectionEndInspectKey: String = "selectionEnd" // String
let selectionDurationInspectKey: String = "selectionDuration" // String

/* ============================================ */
// MARK: - CAPARViewController (UserDefaultsKey)
/* ============================================ */

let modClapPaspKey: String = "modClapPasp" // Modify Aperture

let labelEncodedKey: String = "labelEncoded"
let labelCleanKey: String = "labelClean"
let labelProductionKey: String = "labelProduction"

let clapSizeWidthKey: String = "clapSizeWidth" // CGFloat
let clapSizeHeightKey: String = "clapSizeHeight" // CGFloat
let clapOffsetXKey: String = "clapOffsetX" // CGFloat
let clapOffsetYKey: String = "clapOffsetY" // CGFloat
let paspRatioWidthKey: String = "paspRatioWidth" // CGFloat
let paspRatioHeightKey: String = "paspRatioHeight" // CGFloat

let validKey: String = "valid"

/* ============================================ */
// MARK: - MovieWriter (InfoDictionaryKey)
/* ============================================ */

let urlInfoKey: String = "url" // URL
let startInfoKey: String = "start" // Date
let endInfoKey: String = "end" // Date
let completedInfoKey: String = "completed" // Bool
let intervalInfoKey: String = "interval" // TimeInterval

let progressInfoKey: String = "progress" // Float
let statusInfoKey: String = "status" // String
let elapsedInfoKey: String = "elapsed" // TimeInterval
let estimatedRemainingInfoKey: String = "estimatedRemaining" // TimeInterval
let estimatedTotalInfoKey: String = "estimatedTotal" // TimeInterval

/* ============================================ */
// MARK: -
/* ============================================ */
