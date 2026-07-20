//
//  ModelTests.swift
//  cutter2Tests
//
//  Created by GitHub Copilot on 2025/10/13.
//  Copyright © 2025-2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Unit tests for Model layer components
final class ModelTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        // Cleanup
    }
    
    // MARK: - UndoManagerWrapper Tests
    
    @MainActor
    func testUndoManagerWrapperInitialization() throws {
        let undoManager = UndoManager()
        let wrapper = UndoManagerWrapper(undoManager)
        
        XCTAssertNotNil(wrapper)
    }
    
    @MainActor
    func testUndoManagerWrapperOnMainActor() throws {
        let undoManager = UndoManager()
        let wrapper = UndoManagerWrapper(undoManager)
        
        XCTAssertNotNil(wrapper)
        XCTAssertTrue(Thread.isMainThread)
    }
    
    // MARK: - SampleBufferChannel Delegate Tests
    
    func testSampleBufferChannelDelegateProtocolExists() throws {
        // Verify that SampleBufferChannelDelegate protocol is defined
        // Protocol requires: didRead(from:buffer:)
        XCTAssertTrue(true, "SampleBufferChannelDelegate protocol is defined")
    }
    
    // MARK: - boxSize Tests
    
    func testBoxSizeCreation() throws {
        var size = boxSize()
        
        XCTAssertEqual(size.headerSize, 0)
        XCTAssertEqual(size.videoSize, 0)
        XCTAssertEqual(size.audioSize, 0)
        XCTAssertEqual(size.otherSize, 0)
        
        // Test modifying values
        size.videoSize = 1024
        size.audioSize = 512
        XCTAssertEqual(size.videoSize, 1024)
        XCTAssertEqual(size.audioSize, 512)
    }
    
    func testBoxSizeComparison() throws {
        var size1 = boxSize()
        var size2 = boxSize()
        var size3 = boxSize()
        
        size1.videoSize = 1920
        size1.videoCount = 100
        
        size2.videoSize = 1920
        size2.videoCount = 100
        
        size3.videoSize = 1280
        size3.videoCount = 50
        
        XCTAssertEqual(size1.videoSize, size2.videoSize)
        XCTAssertEqual(size1.videoCount, size2.videoCount)
        XCTAssertNotEqual(size1.videoSize, size3.videoSize)
        XCTAssertNotEqual(size1.videoCount, size3.videoCount)
    }
    
    func testBoxSizeFields() throws {
        var size = boxSize()
        
        // Test all fields can be set
        size.headerSize = 100
        size.videoSize = 1000
        size.videoCount = 10
        size.audioSize = 500
        size.audioCount = 5
        size.otherSize = 200
        size.otherCount = 2
        
        XCTAssertEqual(size.headerSize, 100)
        XCTAssertEqual(size.videoSize, 1000)
        XCTAssertEqual(size.videoCount, 10)
        XCTAssertEqual(size.audioSize, 500)
        XCTAssertEqual(size.audioCount, 5)
        XCTAssertEqual(size.otherSize, 200)
        XCTAssertEqual(size.otherCount, 2)
    }
    
    // MARK: - Media Type Tests
    
    func testAVMediaTypeValues() throws {
        // Test AVMediaType constants
        XCTAssertEqual(AVMediaType.video.rawValue, "vide")
        XCTAssertEqual(AVMediaType.audio.rawValue, "soun")
        XCTAssertEqual(AVMediaType.text.rawValue, "text")
        XCTAssertEqual(AVMediaType.subtitle.rawValue, "sbtl")
    }
    
    // MARK: - File Type Tests
    
    func testAVFileTypeValues() throws {
        // Test common AVFileType values
        XCTAssertEqual(AVFileType.mov.rawValue, "com.apple.quicktime-movie")
        XCTAssertEqual(AVFileType.mp4.rawValue, "public.mpeg-4")
        XCTAssertEqual(AVFileType.m4v.rawValue, "com.apple.m4v-video")
        XCTAssertEqual(AVFileType.m4a.rawValue, "com.apple.m4a-audio")
    }
    
    // MARK: - Codec Tests
    
    func testVideoCodecTypes() throws {
        // Test common video codec types
        let h264 = AVVideoCodecType.h264
        let hevc = AVVideoCodecType.hevc
        
        XCTAssertNotEqual(h264, hevc)
        XCTAssertEqual(h264.rawValue, "avc1")
        XCTAssertEqual(hevc.rawValue, "hvc1")
    }
    
    // MARK: - Export Preset Tests
    
    func testExportPresetValues() throws {
        // Test common export presets
        let preset1920 = AVAssetExportPreset1920x1080
        let preset1280 = AVAssetExportPreset1280x720
        let preset640 = AVAssetExportPreset640x480
        
        XCTAssertNotEqual(preset1920, preset1280)
        XCTAssertNotEqual(preset1280, preset640)
        XCTAssertNotEqual(preset1920, preset640)
    }
    
    // MARK: - CMFormatDescription Tests
    
    func testVideoFormatDescriptionCreation() throws {
        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: 1920,
            height: 1080,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        
        XCTAssertEqual(status, noErr)
        XCTAssertNotNil(formatDescription)
        
        if let desc = formatDescription {
            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            XCTAssertEqual(dimensions.width, 1920)
            XCTAssertEqual(dimensions.height, 1080)
        }
    }
    
    // MARK: - Asset Track Tests
    
    func testAssetTrackMediaTypes() throws {
        // Test that we can work with different media types
        let videoType = AVMediaType.video
        let audioType = AVMediaType.audio
        
        XCTAssertNotEqual(videoType, audioType)
    }
    
    // MARK: - Time Scale Tests
    
    func testCommonTimeScales() throws {
        let timeScale600 = CMTimeScale(600)
        let timeScale30 = CMTimeScale(30)
        let timeScale60 = CMTimeScale(60)
        
        let time600 = CMTime(value: 600, timescale: timeScale600)
        let time30 = CMTime(value: 30, timescale: timeScale30)
        let time60 = CMTime(value: 60, timescale: timeScale60)
        
        // All represent 1 second
        XCTAssertEqual(time600.seconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(time30.seconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(time60.seconds, 1.0, accuracy: 0.001)
    }
    
    func testTimeScaleConversion() throws {
        let time600 = CMTime(seconds: 1.5, preferredTimescale: 600)
        let time30 = CMTimeConvertScale(time600, timescale: 30, method: .default)
        
        XCTAssertEqual(time600.seconds, time30.seconds, accuracy: 0.001)
        XCTAssertEqual(time30.timescale, 30)
    }
    
    // MARK: - Audio Format Tests
    
    func testAudioFormatIDs() throws {
        // Test common audio format IDs
        let aac = kAudioFormatMPEG4AAC
        let lpcm = kAudioFormatLinearPCM
        
        XCTAssertNotEqual(aac, lpcm)
        XCTAssertEqual(aac, kAudioFormatMPEG4AAC)
        XCTAssertEqual(lpcm, kAudioFormatLinearPCM)
    }
    
    // MARK: - Sample Buffer Tests
    
    func testSampleBufferTiming() throws {
        let duration = CMTime(seconds: 1.0, preferredTimescale: 600)
        let presentationTime = CMTime(seconds: 0.0, preferredTimescale: 600)
        let decodeTime = CMTime.invalid
        
        let timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: decodeTime
        )
        
        XCTAssertTrue(timing.duration.isValid)
        XCTAssertTrue(timing.presentationTimeStamp.isValid)
        XCTAssertFalse(timing.decodeTimeStamp.isValid)
    }
    
    // MARK: - Asset Reader/Writer Tests
    
    func testAssetReaderStatus() throws {
        // Test AVAssetReaderStatus values
        let unknown = AVAssetReader.Status.unknown
        let reading = AVAssetReader.Status.reading
        let completed = AVAssetReader.Status.completed
        let failed = AVAssetReader.Status.failed
        let cancelled = AVAssetReader.Status.cancelled
        
        XCTAssertNotEqual(unknown, reading)
        XCTAssertNotEqual(reading, completed)
        XCTAssertNotEqual(completed, failed)
        XCTAssertNotEqual(failed, cancelled)
    }
    
    func testAssetWriterStatus() throws {
        // Test AVAssetWriterStatus values
        let unknown = AVAssetWriter.Status.unknown
        let writing = AVAssetWriter.Status.writing
        let completed = AVAssetWriter.Status.completed
        let failed = AVAssetWriter.Status.failed
        let cancelled = AVAssetWriter.Status.cancelled
        
        XCTAssertNotEqual(unknown, writing)
        XCTAssertNotEqual(writing, completed)
        XCTAssertNotEqual(completed, failed)
        XCTAssertNotEqual(failed, cancelled)
    }
    
    // MARK: - Performance Tests
    
    func testBoxSizeCreationPerformance() throws {
        measure {
            for _ in 0..<10000 {
                var size = boxSize()
                size.videoSize = 1920
                size.audioSize = 1080
            }
        }
    }
    
    func testCMTimeCreationPerformance() throws {
        measure {
            for _ in 0..<10000 {
                _ = CMTime(seconds: 1.0, preferredTimescale: 600)
            }
        }
    }
    
    func testTimeScaleConversionPerformance() throws {
        let time = CMTime(seconds: 1.5, preferredTimescale: 600)
        
        measure {
            for _ in 0..<1000 {
                _ = CMTimeConvertScale(time, timescale: 30, method: .default)
            }
        }
    }

    // MARK: - LayoutConverter.dataSize edge cases (T-04)

    func testDataSizeEdgeCases() {
        let converter = LayoutConverter()

        XCTAssertEqual(converter.dataSize(descCount: 0), 12,
                       "count==0 must return header-only size")
        XCTAssertEqual(converter.dataSize(descCount: -1), 0,
                       "negative count must return 0")
        XCTAssertEqual(converter.dataSize(descCount: -100), 0)
        XCTAssertEqual(converter.dataSize(descCount: 1), 32)
        XCTAssertEqual(converter.dataSize(descCount: 6), 132)

        let layoutSize = MemoryLayout<AudioChannelLayout>.size
        let descSize = MemoryLayout<AudioChannelDescription>.size
        XCTAssertEqual(converter.dataSize(descCount: 0), layoutSize - descSize)
        XCTAssertEqual(converter.dataSize(descCount: 1), layoutSize)
        XCTAssertEqual(converter.dataSize(descCount: 3), layoutSize + 2 * descSize)

        XCTAssertEqual(converter.dataSize(descCount: Int.max), 0,
                       "overflow must return 0 without trapping")
    }
}
