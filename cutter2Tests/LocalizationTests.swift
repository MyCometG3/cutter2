//
//  LocalizationTests.swift
//  cutter2Tests
//
//  Created by GitHub Copilot on 2025/10/15.
//

import XCTest
@testable import cutter2

/* ============================================ */
// MARK: - LocalizationTests
/* ============================================ */

final class LocalizationTests: XCTestCase {
    
    /* ============================================ */
    // MARK: - Error Message Tests
    /* ============================================ */
    
    func testDocumentErrorMessagesAreLocalized() {
        // Test that all DocumentError cases have localized strings
        let errors: [DocumentError] = [
            .incompatibleFileType,
            .unableToOpenFile,
            .emptyMovie,
            .unsupportedSaveOperation,
            .unsupportedFileExtension,
            .fileTypeAndExtensionMismatch,
            .overwriteSelfContainedWithReference,
            .internalError,
            .modifyCaparFailed
        ]
        
        for error in errors {
            let nsError = error.nsError
            let description = nsError.localizedDescription
            
            // Verify the description is not empty
            XCTAssertFalse(description.isEmpty, "Error description should not be empty for \(error)")
            
            // Verify the description doesn't contain the key itself (not localized)
            XCTAssertFalse(description.hasPrefix("error."), "Error should be localized, not show key for \(error)")
        }
    }
    
    func testMovieWriterErrorMessagesAreLocalized() {
        // Test that all MovieWriterError cases have localized strings
        let errors: [MovieWriterError] = [
            .compatibilityError,
            .assetReaderWriterUnavailable,
            .anotherExportSessionRunning,
            .movieWriterFailed,
            .assetReaderWriterFailed,
            .operationCancelled,
            .unknown
        ]
        
        for error in errors {
            let nsError = error.nsError
            let description = nsError.localizedDescription
            
            // Verify the description is not empty
            XCTAssertFalse(description.isEmpty, "Error description should not be empty for \(error)")
            
            // Verify the description doesn't contain the key itself (not localized)
            XCTAssertFalse(description.hasPrefix("error."), "Error should be localized, not show key for \(error)")
        }
    }
    
    /* ============================================ */
    // MARK: - UI String Tests
    /* ============================================ */
    
    func testButtonLabelsAreLocalized() {
        // Test common button labels
        let cancelButton = NSLocalizedString("ui.button.cancel", comment: "")
        let okButton = NSLocalizedString("ui.button.ok", comment: "")
        let saveButton = NSLocalizedString("ui.button.save", comment: "")
        let exportButton = NSLocalizedString("ui.button.export", comment: "")
        
        XCTAssertFalse(cancelButton.isEmpty)
        XCTAssertFalse(okButton.isEmpty)
        XCTAssertFalse(saveButton.isEmpty)
        XCTAssertFalse(exportButton.isEmpty)
        
        // Verify they don't return the key itself
        XCTAssertNotEqual(cancelButton, "ui.button.cancel")
        XCTAssertNotEqual(okButton, "ui.button.ok")
        XCTAssertNotEqual(saveButton, "ui.button.save")
        XCTAssertNotEqual(exportButton, "ui.button.export")
    }
    
    func testProgressMessagesAreLocalized() {
        // Test progress messages
        let exportTitle = NSLocalizedString("progress.exporting.title", comment: "")
        let exportMessage = NSLocalizedString("progress.exporting.message", comment: "")
        
        XCTAssertFalse(exportTitle.isEmpty)
        XCTAssertFalse(exportMessage.isEmpty)
        XCTAssertNotEqual(exportTitle, "progress.exporting.title")
        XCTAssertNotEqual(exportMessage, "progress.exporting.message")
    }
    
    func testMenuItemsAreLocalized() {
        // Test menu items
        let fileMenu = NSLocalizedString("menu.file", comment: "")
        let editMenu = NSLocalizedString("menu.edit", comment: "")
        let windowMenu = NSLocalizedString("menu.window", comment: "")
        
        XCTAssertFalse(fileMenu.isEmpty)
        XCTAssertFalse(editMenu.isEmpty)
        XCTAssertFalse(windowMenu.isEmpty)
        XCTAssertNotEqual(fileMenu, "menu.file")
        XCTAssertNotEqual(editMenu, "menu.edit")
        XCTAssertNotEqual(windowMenu, "menu.window")
    }
    
    func testInspectorLabelsAreLocalized() {
        // Test inspector labels
        let currentTime = NSLocalizedString("inspector.current_time", comment: "")
        let movieDuration = NSLocalizedString("inspector.movie_duration", comment: "")
        let selectionStart = NSLocalizedString("inspector.selection_start", comment: "")
        
        XCTAssertFalse(currentTime.isEmpty)
        XCTAssertFalse(movieDuration.isEmpty)
        XCTAssertFalse(selectionStart.isEmpty)
        XCTAssertNotEqual(currentTime, "inspector.current_time")
        XCTAssertNotEqual(movieDuration, "inspector.movie_duration")
        XCTAssertNotEqual(selectionStart, "inspector.selection_start")
    }
    
    /* ============================================ */
    // MARK: - Format String Tests
    /* ============================================ */
    
    func testFormattedStringsWork() {
        // Test that formatted strings work correctly
        let percentFormat = NSLocalizedString("progress.format.percent", comment: "")
        let formattedString = String(format: percentFormat, 75)
        
        XCTAssertFalse(formattedString.isEmpty)
        XCTAssertTrue(formattedString.contains("75"), "Formatted string should contain the percentage value")
    }
    
    func testAccessoryViewFormattedStrings() {
        // Test accessory view formatted strings
        let headerFormat = NSLocalizedString("ui.accessory.movie_header_size", comment: "")
        let videoFormat = NSLocalizedString("ui.accessory.video_tracks", comment: "")
        
        let headerString = String(format: headerFormat, "100")
        let videoString = String(format: videoFormat, "2", "500")
        
        XCTAssertFalse(headerString.isEmpty)
        XCTAssertFalse(videoString.isEmpty)
        XCTAssertTrue(headerString.contains("100"))
        XCTAssertTrue(videoString.contains("2"))
        XCTAssertTrue(videoString.contains("500"))
    }
    
    /* ============================================ */
    // MARK: - LocalizationHelper Tests
    /* ============================================ */
    
    func testLocalizationHelperButtonConstants() {
        // Test LocalizationHelper button constants
        XCTAssertFalse(LocalizationHelper.Button.ok.isEmpty)
        XCTAssertFalse(LocalizationHelper.Button.cancel.isEmpty)
        XCTAssertFalse(LocalizationHelper.Button.save.isEmpty)
        XCTAssertFalse(LocalizationHelper.Button.export.isEmpty)
    }
    
    func testLocalizationHelperFormatting() {
        // Test LocalizationHelper formatting methods
        let percentage = LocalizationHelper.formatPercentage(0.75)
        XCTAssertFalse(percentage.isEmpty)
        
        let fileSize = LocalizationHelper.formatFileSize(1024 * 1024)
        XCTAssertFalse(fileSize.isEmpty)
        
        let timeInterval = LocalizationHelper.formatTimeInterval(125.5)
        XCTAssertFalse(timeInterval.isEmpty)
    }
    
    /* ============================================ */
    // MARK: - String Extension Tests
    /* ============================================ */
    
    func testStringLocalizationExtension() {
        // Test String extension for localization
        let localized = "ui.button.cancel".localized(comment: "Test")
        XCTAssertFalse(localized.isEmpty)
        XCTAssertNotEqual(localized, "ui.button.cancel")
    }
}
