//
//  DocumentTests.swift
//  cutter2Tests
//
//  Created by GitHub Copilot on 2025/10/13.
//  Copyright © 2025-2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

/// Unit tests for Document class and its extensions
@MainActor
final class DocumentTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
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
    
    // MARK: - DocumentError Tests
    
    func testDocumentErrorTypes() throws {
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
}
