//
//  LoggingSystemTests.swift
//  cutter2Tests
//
//  Created by Takashi Mochizuki on 2025/10/18.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import XCTest
import os.log
@testable import cutter2

/// Unit tests for LoggingSystem
///
/// These tests verify that the logging infrastructure is properly configured
/// and that logging operations do not cause crashes or performance issues.
final class LoggingSystemTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        // Cleanup if needed
    }
    
    /* ============================================ */
    // MARK: - Logger Configuration Tests
    /* ============================================ */
    
    /// Test that all logger categories are properly configured
    func testLoggerCategories() throws {
        // Verify all loggers exist and are not nil
        XCTAssertNotNil(LoggingSystem.document)
        XCTAssertNotNil(LoggingSystem.video)
        XCTAssertNotNil(LoggingSystem.ui)
        XCTAssertNotNil(LoggingSystem.performance)
        XCTAssertNotNil(LoggingSystem.fileIO)
        XCTAssertNotNil(LoggingSystem.security)
        XCTAssertNotNil(LoggingSystem.export)
        XCTAssertNotNil(LoggingSystem.input)
        XCTAssertNotNil(LoggingSystem.app)
    }
    
    /// Test that subsystem identifier is correctly set
    func testSubsystemIdentifier() throws {
        let subsystem = LoggingSystem.subsystem()
        
        // Should be bundle identifier or fallback
        XCTAssertFalse(subsystem.isEmpty)
        XCTAssertTrue(subsystem == "com.mycometg3.cutter2" || 
                     subsystem.contains("cutter2"))
    }
    
    /// Test that all categories are listed
    func testCategories() throws {
        let categories = LoggingSystem.categories()
        
        XCTAssertEqual(categories.count, 9)
        XCTAssertTrue(categories.contains("document"))
        XCTAssertTrue(categories.contains("video"))
        XCTAssertTrue(categories.contains("ui"))
        XCTAssertTrue(categories.contains("performance"))
        XCTAssertTrue(categories.contains("fileIO"))
        XCTAssertTrue(categories.contains("security"))
        XCTAssertTrue(categories.contains("export"))
        XCTAssertTrue(categories.contains("input"))
        XCTAssertTrue(categories.contains("app"))
    }
    
    /* ============================================ */
    // MARK: - Logging Functionality Tests
    /* ============================================ */
    
    /// Test that logging at different levels does not crash
    func testLoggingDoesNotCrash() throws {
        // Test document logger
        LoggingSystem.document.debug("Test debug message")
        LoggingSystem.document.info("Test info message")
        LoggingSystem.document.notice("Test notice message")
        LoggingSystem.document.error("Test error message")
        
        // Test video logger
        LoggingSystem.video.info("Video test message")
        
        // Test all other loggers
        LoggingSystem.ui.info("UI test message")
        LoggingSystem.performance.info("Performance test message")
        LoggingSystem.fileIO.info("FileIO test message")
        LoggingSystem.security.info("Security test message")
        LoggingSystem.export.info("Export test message")
        LoggingSystem.input.info("Input test message")
        LoggingSystem.app.info("App test message")
    }
    
    /// Test logging with string interpolation
    func testLoggingWithInterpolation() throws {
        let filename = "test.mov"
        let count = 42
        let duration = 123.456
        
        LoggingSystem.document.info("Opening file: \(filename)")
        LoggingSystem.video.info("Processing \(count) frames")
        LoggingSystem.performance.notice("Completed in \(duration)s")
        
        // Should not crash
    }
    
    /// Test logging with privacy annotations
    func testLoggingWithPrivacy() throws {
        let publicData = "public data"
        let privateData = "private data"
        let sensitiveData = "sensitive data"
        
        LoggingSystem.document.info("Public: \(publicData, privacy: .public)")
        LoggingSystem.fileIO.debug("Private: \(privateData, privacy: .private)")
        LoggingSystem.security.debug("Sensitive: \(sensitiveData, privacy: .sensitive)")
        
        // Should not crash
    }
    
    /* ============================================ */
    // MARK: - Performance Tests
    /* ============================================ */
    
    /// Test performance of logging operations
    func testLoggingPerformance() throws {
        // Measure performance of repeated logging
        measure {
            for i in 0..<1000 {
                LoggingSystem.performance.debug("Performance test iteration \(i)")
            }
        }
        
        // Should complete quickly (< 100ms baseline)
    }
    
    /// Test performance with privacy annotations
    func testLoggingPerformanceWithPrivacy() throws {
        let data = "test data string"
        
        measure {
            for _ in 0..<1000 {
                LoggingSystem.security.debug("Data: \(data, privacy: .private)")
            }
        }
        
        // Should have minimal overhead
    }
    
    /// Test performance of different log levels
    func testLoggingPerformanceByLevel() throws {
        measure {
            for _ in 0..<500 {
                LoggingSystem.document.debug("Debug message")
                LoggingSystem.document.info("Info message")
            }
        }
        
        // Should be efficient
    }
    
    /* ============================================ */
    // MARK: - Utility Methods Tests
    /* ============================================ */
    
    /// Test console filter generation
    func testConsoleFilter() throws {
        // Test subsystem-only filter
        let filter1 = LoggingSystem.consoleFilter()
        XCTAssertTrue(filter1.contains("subsystem:"))
        // Subsystem may vary (app bundle or XCTest host), just verify format
        
        // Test category-specific filter
        let filter2 = LoggingSystem.consoleFilter(category: "document")
        XCTAssertTrue(filter2.contains("subsystem:"))
        XCTAssertTrue(filter2.contains("category:document"))
        XCTAssertTrue(filter2.contains("AND"))
    }
    
    /// Test timestamp logging helper
    func testLogWithTimestamp() throws {
        // Should not crash
        LoggingSystem.logWithTimestamp(LoggingSystem.document, "Test message")
    }
    
    /// Test function entry logging helper
    func testLogFunctionEntry() throws {
        // Should not crash
        LoggingSystem.logFunctionEntry(LoggingSystem.document)
    }
    
    /// Test function exit logging helper
    func testLogFunctionExit() throws {
        // Should not crash
        LoggingSystem.logFunctionExit(LoggingSystem.document)
    }
    
    /* ============================================ */
    // MARK: - Integration Tests
    /* ============================================ */
    
    /// Test logging in real-world scenario: document operations
    func testDocumentOperationLogging() throws {
        // Simulate document operation
        LoggingSystem.document.info("Document operation starting")
        
        let filename = "test.mov"
        LoggingSystem.document.debug("Opening file: \(filename)")
        
        // Simulate success
        LoggingSystem.document.notice("Document opened successfully")
        
        // Should complete without issues
    }
    
    /// Test logging in real-world scenario: export operation
    func testExportOperationLogging() throws {
        // Simulate export operation
        LoggingSystem.export.info("Export started")
        
        for progress in stride(from: 0.0, through: 1.0, by: 0.25) {
            let percentage = Int(progress * 100)
            LoggingSystem.export.notice("Export progress: \(percentage)%")
        }
        
        LoggingSystem.export.notice("Export completed")
        
        // Should complete without issues
    }
    
    /// Test logging in real-world scenario: error handling
    func testErrorLogging() throws {
        // Simulate error condition
        let errorMessage = "File not found"
        LoggingSystem.fileIO.error("Operation failed: \(errorMessage)")
        
        // Simulate recovery
        LoggingSystem.fileIO.notice("Attempting recovery")
        LoggingSystem.fileIO.info("Recovery successful")
        
        // Should complete without issues
    }
    
    /// Test concurrent logging from multiple operations
    func testConcurrentLogging() throws {
        let expectation1 = expectation(description: "Document logging")
        let expectation2 = expectation(description: "Video logging")
        let expectation3 = expectation(description: "Export logging")
        
        // Simulate concurrent operations
        DispatchQueue.global().async {
            for i in 0..<10 {
                LoggingSystem.document.info("Document operation \(i)")
            }
            expectation1.fulfill()
        }
        
        DispatchQueue.global().async {
            for i in 0..<10 {
                LoggingSystem.video.info("Video operation \(i)")
            }
            expectation2.fulfill()
        }
        
        DispatchQueue.global().async {
            for i in 0..<10 {
                LoggingSystem.export.info("Export operation \(i)")
            }
            expectation3.fulfill()
        }
        
        wait(for: [expectation1, expectation2, expectation3], timeout: 5.0)
    }
}
