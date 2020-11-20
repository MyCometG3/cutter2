//
//  Constants.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2020/08/14.
//  Copyright © 2020 MyCometG3. All rights reserved.
//

import Foundation

/* ============================================ */
// MARK: - Document + TranscodeViewController (UserDefaultsKey)
/* ============================================ */

let kTranscodePresetKey = "transcodePreset"
let kTranscodeTypeKey = "transcodeType"
let kTrancode0Key = "transcode0"
let kTrancode1Key = "transcode1"
let kTrancode2Key = "transcode2"
let kTrancode3Key = "transcode3"
let kAVFileTypeKey = "avFileType"
let kHEVCReadyKey = "hevcReady"

let kTranscodePresetCustom = "Custom"

/* ============================================ */
// MARK: - Document + MovieWriter (UserDefaultsKey)
/* ============================================ */

let kLPCMDepthKey = "lpcmDepth"
let kAudioKbpsKey = "audioKbps"
let kVideoKbpsKey = "videoKbps"
let kCopyFieldKey = "copyField"
let kCopyNCLCKey = "copyNCLC"
let kCopyOtherMediaKey = "copyOtherMedia"
let kVideoEncodeKey = "videoEncode"
let kAudioEncodeKey = "audioEncode"
let kVideoCodecKey = "videoCodec"
let kAudioCodecKey = "audioCodec"

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
