//
//  SecurityScopedBookmarkTests.swift
//  cutter2Tests
//
//  Copyright © 2026 MyCometG3. All rights reserved.
//

import XCTest
import AVFoundation
@testable import cutter2

@MainActor
final class SecurityScopedBookmarkTests: XCTestCase {

    // MARK: - Helpers

    /// Records bookmark registry calls so the Save As registration policy is observable
    /// without a live `NSApplication` (M-31).
    @MainActor
    private final class BookmarkRegistryRecorder: SecurityScopedBookmarkRegistering {
        private(set) var registered: [URL] = []

        func addBookmark(for url: URL) {
            registered.append(url)
        }
    }

    private func makeDocument() -> Document {
        return Document()
    }

    // MARK: - BookmarkStore duplicate detection

    func testBookmarkStoreContainsFindsEquivalentTargetAmongNonNormalizedSpellings() throws {
        // `standardizedFileURL` collapses redundant separators and `..` segments, so an
        // entry registered under a non-normalized spelling must still count as the same
        // target. Without this, a second Save As registers a duplicate of the same file.
        let target = URL(fileURLWithPath: "/tmp/target.mov")
        let spellings: [URL] = [
            URL(fileURLWithPath: "/tmp/sub/../target.mov"),
            URL(fileURLWithPath: "/tmp//target.mov"),
        ]

        for spelling in spellings {
            XCTAssertNotEqual(spelling.path, target.path,
                              "precondition: the raw paths differ, so only standardization can match them")
            XCTAssertTrue(BookmarkStore.contains(url: target, among: [spelling]))
            XCTAssertTrue(BookmarkStore.contains(url: spelling, among: [target]),
                          "the comparison must be symmetric")
        }
    }

    func testBookmarkStoreContainsIgnoresOtherTargets() throws {
        let target = URL(fileURLWithPath: "/tmp/target.mov")
        let other: [URL] = [
            URL(fileURLWithPath: "/tmp/other.mov"),
            URL(fileURLWithPath: "/tmp/target.mp4"),
        ]

        XCTAssertFalse(BookmarkStore.contains(url: target, among: other))
        XCTAssertFalse(BookmarkStore.contains(url: target, among: []))
        XCTAssertTrue(BookmarkStore.contains(url: target, among: other + [target]))
    }

    func testBookmarkStoreDenotesSameTargetKeepsFirmlinksDistinct() throws {
        // `/tmp` and `/private/tmp` are a macOS firmlink; neither `standardizedFileURL` nor
        // `resolvingSymlinksInPath()` maps one onto the other, so they stay distinct.
        // Pinned because it is the documented limit of the shared comparison.
        let viaTmp = URL(fileURLWithPath: "/tmp/x.mov")
        let viaPrivateTmp = URL(fileURLWithPath: "/private/tmp/x.mov")

        XCTAssertFalse(BookmarkStore.denotesSameTarget(viaTmp, viaPrivateTmp))
        XCTAssertTrue(BookmarkStore.denotesSameTarget(viaTmp, viaTmp))
    }

    // MARK: - bookmarkSourceTarget decision matrix

    func testBookmarkSourceTargetReturnsSourceForReferenceMovieSaveAs() throws {
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        let target = Document.bookmarkSourceTarget(typeName: AVFileType.mov.rawValue,
                                                    isSaveAs: true,
                                                    selfContained: false,
                                                    sourceURL: source)

        XCTAssertEqual(target, source)
    }

    func testBookmarkSourceTargetRequiresSaveAs() throws {
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        let target = Document.bookmarkSourceTarget(typeName: AVFileType.mov.rawValue,
                                                    isSaveAs: false,
                                                    selfContained: false,
                                                    sourceURL: source)

        XCTAssertNil(target)
    }

    func testBookmarkSourceTargetRequiresMovTarget() throws {
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        let target = Document.bookmarkSourceTarget(typeName: AVFileType.mp4.rawValue,
                                                    isSaveAs: true,
                                                    selfContained: false,
                                                    sourceURL: source)

        XCTAssertNil(target)
    }

    func testBookmarkSourceTargetRequiresReferenceMovie() throws {
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        let target = Document.bookmarkSourceTarget(typeName: AVFileType.mov.rawValue,
                                                    isSaveAs: true,
                                                    selfContained: true,
                                                    sourceURL: source)

        XCTAssertNil(target)
    }

    func testBookmarkSourceTargetRequiresAccessoryViewSelection() throws {
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        let target = Document.bookmarkSourceTarget(typeName: AVFileType.mov.rawValue,
                                                    isSaveAs: true,
                                                    selfContained: nil,
                                                    sourceURL: source)

        XCTAssertNil(target)
    }

    func testBookmarkSourceTargetRequiresSourceURL() throws {
        let target = Document.bookmarkSourceTarget(typeName: AVFileType.mov.rawValue,
                                                    isSaveAs: true,
                                                    selfContained: false,
                                                    sourceURL: nil)

        XCTAssertNil(target)
    }

    // MARK: - registration policy

    func testCommitSourceBookmarkRegistersPendingTarget() throws {
        let document = makeDocument()
        let recorder = BookmarkRegistryRecorder()
        document.bookmarkRegistryOverride = recorder
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        document.commitSourceBookmark(source)

        XCTAssertEqual(recorder.registered, [source])
    }

    func testCommitSourceBookmarkSkipsNilTarget() throws {
        let document = makeDocument()
        let recorder = BookmarkRegistryRecorder()
        document.bookmarkRegistryOverride = recorder

        // `preparation` yields `nil` for every Save As that is not a reference-movie
        // write, and for operations that are not a Save As at all.
        document.commitSourceBookmark(nil)

        XCTAssertTrue(recorder.registered.isEmpty)
    }

    func testCommitSourceBookmarkSkipsWhenNoRegistryIsReachable() throws {
        let document = makeDocument()
        document.bookmarkRegistryOverride = nil

        // No override installed, and `NSApp.delegate` is not the AppDelegate under test,
        // so this must be a no-op rather than a crash.
        document.commitSourceBookmark(URL(fileURLWithPath: "/tmp/source.mov"))
    }
}
