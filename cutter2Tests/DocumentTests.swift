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
    
    // MARK: - Document read error handling (T-14)
    
    /// `validateMovieType` が不正な UTI で `incompatibleFileType` をスローすることを検証。
    /// `Document()` 直接生成は `windowControllers[0]` アクセス（NSRangeException）でクラッシュするため、
    /// `readAsync` の UTI 検証ロジック（`Self.validateMovieType`）を分離してテストする。
    ///
    /// 注: `ErrorUtilities.throwError` は `DocumentError` を `NSError` に変換して throw する。
    /// `DocumentError.incompatibleFileType` は `NSOSStatusErrorDomain` / `unimpErr` (-4) にマップされる。
    func testValidateMovieTypeRejectsInvalidUTI() throws {
        XCTAssertThrowsError(try Document.validateMovieType("invalid.type")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSOSStatusErrorDomain)
            XCTAssertEqual(nsError.code, unimpErr)
        }
    }
    
    /// `validateMovieType` が有効な movie UTI を許可することを検証。
    func testValidateMovieTypeAcceptsMovieUTI() throws {
        XCTAssertNoThrow(try Document.validateMovieType("com.apple.quicktime-movie"))
    }
    
    /// トラックを含まない無効な movHeader から生成した AVMutableMovie が
    /// `MovieHeaderValidator.isValid` で false になることを検証。
    /// `readAsync` のヘッダー検証は `MovieHeaderValidator.isValid` に委譲しているため、
    /// ヘッダー検証エラー経路（`.unableToOpenFile` 相当）を直接テストする。
    ///
    /// 注: `AVMutableMovie(data:)` は空データ（length 0）を NSInvalidArgumentException で拒否するため、
    /// トラックを含まない非ゼロ長のダミーデータを使用する。
    func testInvalidHeaderFailsValidation() {
        let dummyHeader = Data([0x00, 0x00, 0x00, 0x00]) // 非ゼロ長・トラックなし
        let movie = AVMutableMovie(data: dummyHeader)
        XCTAssertFalse(MovieHeaderValidator.isValid(movie))
        if let error = MovieHeaderValidator.validate(movie) {
            guard case .noTracks = error else {
                return XCTFail("Unexpected validation error: \(error)")
            }
        } else {
            XCTFail("Expected noTracks validation error for track-less movie")
        }
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
