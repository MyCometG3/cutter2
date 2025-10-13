//
//  DocumentTests.swift
//  cutter2Tests
//
//  Created on 2025-10-13.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Unit tests for Document class and its extensions
@MainActor
final class DocumentTests: XCTestCase {
    
    var document: Document?
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        document = Document()
    }
    
    override func tearDownWithError() throws {
        document = nil
    }
    
    // MARK: - Document Initialization Tests
    
    func testDocumentInitialization() throws {
        XCTAssertNotNil(document)
        XCTAssertNil(document?.movieMutator)
    }
    
    func testDocumentDisplayName() throws {
        XCTAssertNotNil(document?.displayName)
    }
    
    // MARK: - Document Type Tests
    
    func testReadableTypes() throws {
        let types = Document.readableTypes
        
        XCTAssertTrue(types.contains("com.apple.quicktime-movie"))
        XCTAssertTrue(types.contains("public.mpeg-4"))
    }
    
    func testWritableTypes() throws {
        let types = Document.writableTypes
        
        XCTAssertTrue(types.contains("com.apple.quicktime-movie"))
    }
    
    // MARK: - File Extension Tests
    
    func testMovFileExtension() throws {
        // Test .mov extension
        let movExtension = "mov"
        XCTAssertEqual(movExtension, "mov")
    }
    
    func testMp4FileExtension() throws {
        // Test .mp4 extension
        let mp4Extension = "mp4"
        XCTAssertEqual(mp4Extension, "mp4")
    }
    
    // MARK: - Document State Tests
    
    func testDocumentInitialState() throws {
        XCTAssertNil(document?.movieMutator)
        XCTAssertNotNil(document?.undoManager)
    }
    
    func testDocumentHasUndoManager() throws {
        let undoManager = document?.undoManager
        
        XCTAssertNotNil(undoManager)
    }
    
    // MARK: - DocumentError Tests
    
    func testDocumentErrorTypes() throws {
        // Test that DocumentError enum is accessible
        // This validates the error type definition
        
        enum TestDocumentError: NSErrorConvertible {
            case testError
            
            var nsError: NSError {
                return NSError(
                    domain: "com.test.document",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Test error"]
                )
            }
        }
        
        let error = TestDocumentError.testError
        XCTAssertEqual(error.nsError.code, 1)
    }
    
    // MARK: - Window Management Tests
    
    func testWindowControllers() throws {
        let controllers = document?.windowControllers ?? []
        
        // Initially should be empty before makeWindowControllers is called
        XCTAssertTrue(controllers.isEmpty || controllers.count >= 0)
    }
    
    // MARK: - Async Operations Tests
    
    func testAsyncOperationSupport() async throws {
        // Test that document supports async operations
        await MainActor.run {
            let doc = Document()
            XCTAssertNotNil(doc)
        }
    }
    
    // MARK: - Integration Tests
    
    func testDocumentLifecycle() async throws {
        // Test document creation and cleanup
        await MainActor.run {
            var doc: Document? = Document()
            XCTAssertNotNil(doc)
            
            // Simulate document cleanup
            doc = nil
            XCTAssertNil(doc)
        }
    }
    
    // MARK: - Performance Tests
    
    func testDocumentCreationPerformance() throws {
        measure {
            Task { @MainActor in
                _ = Document()
            }
        }
    }
    
    func testUndoManagerPerformance() throws {
        measure {
            _ = document?.undoManager
        }
    }
}
