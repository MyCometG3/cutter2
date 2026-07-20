//
//  UtilitiesTests.swift
//  cutter2Tests
//
//  Created by GitHub Copilot on 2025/10/13.
//  Copyright © 2025-2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Unit tests for utility classes and extensions
final class UtilitiesTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        // Cleanup
    }
    
    // MARK: - Constants Tests
    
    func testTranscodeConstants() throws {
        // Verify UserDefaults keys for transcoding
        XCTAssertEqual(kTranscodePresetKey, "transcodePreset")
        XCTAssertEqual(kTranscodeTypeKey, "transcodeType")
        XCTAssertEqual(kTrancode0Key, "transcode0")
        XCTAssertEqual(kTrancode1Key, "transcode1")
        XCTAssertEqual(kTrancode2Key, "transcode2")
        XCTAssertEqual(kTrancode3Key, "transcode3")
        XCTAssertEqual(kAVFileTypeKey, "avFileType")
        XCTAssertEqual(kHEVCReadyKey, "hevcReady")
        XCTAssertEqual(kTranscodePresetCustom, "Custom")
    }
    
    func testMovieWriterConstants() throws {
        // Verify UserDefaults keys for MovieWriter
        XCTAssertEqual(kLPCMDepthKey, "lpcmDepth")
        XCTAssertEqual(kAudioKbpsKey, "audioKbps")
        XCTAssertEqual(kVideoKbpsKey, "videoKbps")
        XCTAssertEqual(kCopyFieldKey, "copyField")
        XCTAssertEqual(kCopyNCLCKey, "copyNCLC")
        XCTAssertEqual(kCopyOtherMediaKey, "copyOtherMedia")
        XCTAssertEqual(kVideoEncodeKey, "videoEncode")
        XCTAssertEqual(kAudioEncodeKey, "audioEncode")
        XCTAssertEqual(kVideoCodecKey, "videoCodec")
        XCTAssertEqual(kAudioCodecKey, "audioCodec")
    }
    
    func testInfoDictionaryConstants() throws {
        // Verify InfoDictionary keys
        XCTAssertEqual(timeValueInfoKey, "timeValue")
        XCTAssertEqual(timeRangeValueInfoKey, "timeRangeValue")
        XCTAssertEqual(timeInfoKey, "time")
        XCTAssertEqual(rangeInfoKey, "range")
        XCTAssertEqual(curPositionInfoKey, "curPosition")
        XCTAssertEqual(startPositionInfoKey, "startPosition")
        XCTAssertEqual(endPositionInfoKey, "endPosition")
        XCTAssertEqual(stringInfoKey, "string")
        XCTAssertEqual(durationInfoKey, "duration")
    }
    
    func testClapPaspConstants() throws {
        // Verify Clean Aperture and Pixel Aspect Ratio keys
        XCTAssertEqual(clapSizeKey, "clapSize")
        XCTAssertEqual(clapOffsetKey, "clapOffset")
        XCTAssertEqual(paspRatioKey, "paspRatio")
        XCTAssertEqual(dimensionsKey, "dimensions")
        XCTAssertEqual(modClapPaspKey, "modClapPasp")
    }
    
    func testInspectConstants() throws {
        // Verify inspect keys
        XCTAssertEqual(titleInspectKey, "title")
        XCTAssertEqual(pathInspectKey, "path")
        XCTAssertEqual(videoFormatInspectKey, "videoFormat")
        XCTAssertEqual(videoFPSInspectKey, "videoFPS")
        XCTAssertEqual(audioFormatInspectKey, "audioFormat")
        XCTAssertEqual(videoDataSizeInspectKey, "videoDataSize")
        XCTAssertEqual(audioDataSizeInspectKey, "audioDataSize")
        XCTAssertEqual(currentTimeInspectKey, "currentTime")
        XCTAssertEqual(movieDurationInspectKey, "movieDuration")
        XCTAssertEqual(selectionStartInspectKey, "selectionStart")
        XCTAssertEqual(selectionEndInspectKey, "selectionEnd")
        XCTAssertEqual(selectionDurationInspectKey, "selectionDuration")
    }
    
    func testProgressInfoConstants() throws {
        // Verify progress info keys for MovieWriter
        XCTAssertEqual(urlInfoKey, "url")
        XCTAssertEqual(startInfoKey, "start")
        XCTAssertEqual(endInfoKey, "end")
        XCTAssertEqual(completedInfoKey, "completed")
        XCTAssertEqual(intervalInfoKey, "interval")
        XCTAssertEqual(progressInfoKey, "progress")
        XCTAssertEqual(statusInfoKey, "status")
        XCTAssertEqual(elapsedInfoKey, "elapsed")
        XCTAssertEqual(estimatedRemainingInfoKey, "estimatedRemaining")
        XCTAssertEqual(estimatedTotalInfoKey, "estimatedTotal")
    }
    
    // MARK: - Error Utilities Tests
    
    func testNSErrorConvertibleProtocol() throws {
        // Create a test error type
        enum TestError: NSErrorConvertible {
            case testCase
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.error",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Test error"]
                )
            }
        }
        
        let error = TestError.testCase
        let nsError = error.nsError
        
        XCTAssertEqual(nsError.domain, "com.test.error")
        XCTAssertEqual(nsError.code, 1)
        XCTAssertEqual(nsError.localizedDescription, "Test error")
    }
    
    func testNSErrorConvertibleWithReason() throws {
        enum TestError: NSErrorConvertible {
            case testCase
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.error",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Base error"]
                )
            }
        }
        
        let error = TestError.testCase
        let nsError = error.nsError(with: "Custom reason")
        
        XCTAssertEqual(nsError.domain, "com.test.error")
        XCTAssertEqual(nsError.code, 2)
        XCTAssertEqual(nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, "Custom reason")
    }
    
    func testErrorUtilitiesThrow() throws {
        enum TestError: NSErrorConvertible {
            case testCase
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.error",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Throw test"]
                )
            }
        }
        
        XCTAssertThrowsError(try ErrorUtilities.throwError(TestError.testCase)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "com.test.error")
            XCTAssertEqual(nsError.code, 3)
        }
    }
    
    func testErrorUtilitiesThrowWithReason() throws {
        enum TestError: NSErrorConvertible {
            case testCase
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.error",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Throw test with reason"]
                )
            }
        }
        
        XCTAssertThrowsError(try ErrorUtilities.throwError(TestError.testCase, reason: "Detailed reason")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "com.test.error")
            XCTAssertEqual(nsError.code, 4)
            XCTAssertEqual(nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, "Detailed reason")
        }
    }
    
    // MARK: - Actor Utilities Tests
    
    func testMainActorExecution() throws {
        let expectation = self.expectation(description: "Main actor execution")
        
        Task { @MainActor in
            // Verify execution on main actor
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testAsyncMainActorExecution() async throws {
        // Test async/await on main actor
        await MainActor.run {
            XCTAssertTrue(Thread.isMainThread)
        }
    }
    
    func testLayoutConverterConvertsHeaderOnlyAAC51Layout() throws {
        let converter = LayoutConverter()
        let sourceData = converter.dataFor(tag: kAudioChannelLayoutTag_AAC_5_1)
        
        guard let convertedData = converter.convertAsAACTag(from: sourceData) else {
            XCTFail("Expected header-only AAC 5.1 layout to convert")
            return
        }
        
        let convertedTag = convertedData.withUnsafeBytes { rawBuffer -> AudioChannelLayoutTag in
            guard let baseAddress = rawBuffer.baseAddress else {
                XCTFail("Expected converted AAC layout bytes")
                return 0
            }
            
            var tag: AudioChannelLayoutTag = 0
            memcpy(&tag, baseAddress, MemoryLayout<AudioChannelLayoutTag>.size)
            return tag
        }
        
        XCTAssertEqual(convertedTag, kAudioChannelLayoutTag_AAC_5_1)
    }
    
    // MARK: - Notification Tests
    
    func testMovieWasMutatedNotification() throws {
        // Verify notification name
        let notificationName = Notification.Name.movieWasMutated
        XCTAssertEqual(notificationName.rawValue, "movieWasMutated")
    }
    
    func testNotificationPosting() throws {
        let expectation = self.expectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .movieWasMutated,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.name, .movieWasMutated)
            expectation.fulfill()
        }
        
        NotificationCenter.default.post(name: .movieWasMutated, object: nil)
        
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    // MARK: - Performance Tests
    
    func testConstantAccessPerformance() throws {
        measure {
            for _ in 0..<1000 {
                _ = kTranscodePresetKey
                _ = kVideoCodecKey
                _ = timeInfoKey
            }
        }
    }
    
    func testErrorCreationPerformance() throws {
        enum TestError: NSErrorConvertible {
            case testCase
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.error",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Performance test"]
                )
            }
        }
        
        measure {
            for _ in 0..<100 {
                _ = TestError.testCase.nsError
            }
        }
    }

    // MARK: - DateFormatter factory (T-05)

    func testLogFormatterSetsDateFormat() {
        let format = "yyyy-MM-dd HH:mm:ss.SSS"
        let formatter = DateFormatter.logFormatter(format: format)
        XCTAssertEqual(formatter.dateFormat, format)
    }

    func testLogFormatterReturnsDistinctInstances() {
        let format = "HH:mm:ss"
        let a = DateFormatter.logFormatter(format: format)
        let b = DateFormatter.logFormatter(format: format)
        XCTAssertFalse(a === b, "factory must not share instances")
    }

    func testLogFormatterProducesNonEmptyString() {
        let formatter = DateFormatter.logFormatter(format: "yyyy-MM-dd'T'HH:mm:ss")
        let s = formatter.string(from: Date())
        XCTAssertFalse(s.isEmpty)
    }
}
