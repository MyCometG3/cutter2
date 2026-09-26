//
//  MovieWriterWriteTests.swift
//  cutter2Tests
//
//  Copyright © 2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

@MainActor
final class MovieWriterWriteTests: XCTestCase {

    private func makeWriter() -> MovieWriter {
        return MovieWriter(params: MovieWriterParams(
            movie: AVMutableMovie(),
            unblockUserInteraction: nil,
            progressContinuation: nil
        ))
    }

    func testFlattenFailurePreservesErrorAndPostsEndNotification() async throws {
        let writer = makeWriter()
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

    func testFinalizeTemporaryMovieReplacesExistingDestination() async throws {
        let writer = makeWriter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let temporaryURL = directory.appendingPathComponent("temporary.mov")
        let destinationURL = directory.appendingPathComponent("destination.mov")
        try Data("new".utf8).write(to: temporaryURL)
        try Data("old".utf8).write(to: destinationURL)

        try await writer.finalizeTemporaryMovie(at: temporaryURL, to: destinationURL)

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
    }

    func testFinalizeTemporaryMovieMovesToMissingDestination() async throws {
        let writer = makeWriter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let temporaryURL = directory.appendingPathComponent("temporary.mov")
        let destinationURL = directory.appendingPathComponent("destination.mov")
        try Data("new".utf8).write(to: temporaryURL)

        try await writer.finalizeTemporaryMovie(at: temporaryURL, to: destinationURL)

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
    }
}
