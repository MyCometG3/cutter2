//
//  MovieWriterWriteTests.swift
//  cutter2Tests
//
//  Copyright © 2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

final class MovieWriterWriteTests: XCTestCase {

    func testFlattenFailurePreservesErrorAndPostsEndNotification() async throws {
        let writer = MovieWriter(params: MovieWriterParams(
            movie: AVMutableMovie(),
            unblockUserInteraction: nil,
            progressContinuation: nil
        ))
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = parent.appendingPathComponent("failure.mov")
        let expectation = expectation(forNotification: .movieDidWriteHeaderOnly, object: writer)

        do {
            try await writer.writeMovie(
                to: destination,
                fileType: .mov,
                copySampleData: false
            )
            XCTFail("Expected flattening to fail for a destination with no parent directory")
        } catch {
            XCTAssertNotNil(error as NSError?)
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        let writeError = await writer.writeError
        let writeSuccess = await writer.writeSuccess
        let writeEnd = await writer.writeEnd
        let writeInProgress = await writer.writeInProgress

        XCTAssertNotNil(writeError)
        XCTAssertFalse(writeSuccess)
        XCTAssertNotNil(writeEnd)
        XCTAssertFalse(writeInProgress)
    }
}
