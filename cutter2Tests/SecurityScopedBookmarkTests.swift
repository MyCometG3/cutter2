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

    /// Records bookmark registry calls so the Save As commit/rollback policy is
    /// observable without a live `NSApplication` (M-31).
    @MainActor
    private final class BookmarkRegistryRecorder: SecurityScopedBookmarkRegistering {
        private(set) var calls: [String] = []
        var addResult: Bool = true

        @discardableResult
        func addBookmark(for url: URL) -> Bool {
            calls.append("add:\(url.lastPathComponent)")
            return addResult
        }

        func removeBookmark(for url: URL) {
            calls.append("remove:\(url.lastPathComponent)")
        }
    }

    private func makeDocument() -> Document {
        return Document()
    }

    // MARK: - BookmarkStore.removing

    func testBookmarkStoreRemovesEntryResolvingToTarget() throws {
        let target = URL(fileURLWithPath: "/tmp/target.mov")
        let items: [Data] = [Data([0x01]), Data([0x02]), Data([0x03])]

        let outcome = BookmarkStore.removing(url: target, from: items) { data in
            switch data.first {
            case 0x01: return URL(fileURLWithPath: "/tmp/other.mov")
            case 0x02: return URL(fileURLWithPath: "/tmp/target.mov")
            default: return URL(fileURLWithPath: "/tmp/third.mov")
            }
        }

        XCTAssertTrue(outcome.removed)
        XCTAssertEqual(outcome.retained, [Data([0x01]), Data([0x03])])
    }

    func testBookmarkStoreRetainsEntriesForOtherUrls() throws {
        let target = URL(fileURLWithPath: "/tmp/target.mov")
        let first = Data([0x01])
        let second = Data([0x02])
        let items: [Data] = [first, second]

        let outcome = BookmarkStore.removing(url: target, from: items) { _ in
            URL(fileURLWithPath: "/tmp/unrelated.mov")
        }

        XCTAssertFalse(outcome.removed)
        XCTAssertEqual(outcome.retained, items)
    }

    func testBookmarkStoreRetainsUnresolvableEntries() throws {
        let target = URL(fileURLWithPath: "/tmp/target.mov")
        let resolvable = Data([0x01])
        let unresolvable = Data([0x02])
        let items: [Data] = [unresolvable, resolvable]

        let outcome = BookmarkStore.removing(url: target, from: items) { data in
            data == resolvable ? URL(fileURLWithPath: "/tmp/target.mov") : nil
        }

        XCTAssertTrue(outcome.removed)
        XCTAssertEqual(outcome.retained, [unresolvable])
    }

    func testBookmarkStoreReportsNoRemovalWhenTargetAbsent() throws {
        let target = URL(fileURLWithPath: "/tmp/target.mov")
        let items: [Data] = [Data([0x01]), Data([0x02])]

        let outcome = BookmarkStore.removing(url: target, from: items) { _ in
            URL(fileURLWithPath: "/tmp/unrelated.mov")
        }

        XCTAssertFalse(outcome.removed)
        XCTAssertEqual(outcome.retained, items)
    }

    func testBookmarkStoreNormalizesNonNormalizedPaths() throws {
        // `standardizedFileURL` collapses redundant separators and `..` segments, so a
        // bookmark stored under a non-normalized spelling still matches its target.
        //
        // It deliberately does NOT resolve `/tmp` -> `/private/tmp`: that is a macOS
        // firmlink, and neither `standardizedFileURL` nor `resolvingSymlinksInPath()`
        // maps one to the other. Path-spelling differences of that kind are therefore
        // out of scope here (see the `addBookmark` dedup note in `AppDelegate`).
        let target = URL(fileURLWithPath: "/tmp/target.mov")
        let parentTraversal = Data([0x01])
        let doubledSeparator = Data([0x02])
        let items: [Data] = [parentTraversal, doubledSeparator]

        let outcome = BookmarkStore.removing(url: target, from: items) { data in
            if data == parentTraversal {
                return URL(fileURLWithPath: "/tmp/sub/../target.mov")
            }
            return URL(fileURLWithPath: "/tmp//target.mov")
        }

        XCTAssertTrue(outcome.removed)
        XCTAssertTrue(outcome.retained.isEmpty)
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

    // MARK: - commit / rollback policy

    func testCommitSourceBookmarkRegistersPendingTarget() throws {
        let document = makeDocument()
        let recorder = BookmarkRegistryRecorder()
        document.bookmarkRegistryOverride = recorder
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        let registered = document.commitSourceBookmark(source)

        XCTAssertTrue(registered)
        XCTAssertEqual(recorder.calls, ["add:source.mov"])
    }

    func testCommitSourceBookmarkReturnsFalseWhenDeduplicated() throws {
        let document = makeDocument()
        let recorder = BookmarkRegistryRecorder()
        recorder.addResult = false
        document.bookmarkRegistryOverride = recorder
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        let registered = document.commitSourceBookmark(source)

        XCTAssertFalse(registered)
        XCTAssertEqual(recorder.calls, ["add:source.mov"])
    }

    func testRollbackSourceBookmarkRemovesEntryRegisteredByThisOperation() throws {
        let document = makeDocument()
        let recorder = BookmarkRegistryRecorder()
        document.bookmarkRegistryOverride = recorder
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        document.rollbackSourceBookmark(source, registered: true)

        XCTAssertEqual(recorder.calls, ["remove:source.mov"])
    }

    func testRollbackSourceBookmarkSkipsUnregisteredAndNilTarget() throws {
        let document = makeDocument()
        let recorder = BookmarkRegistryRecorder()
        document.bookmarkRegistryOverride = recorder
        let source = URL(fileURLWithPath: "/tmp/source.mov")

        // `registered == false` means an equivalent entry already existed, created by an
        // earlier session. Removing it would revoke a permission this operation never
        // granted.
        document.rollbackSourceBookmark(source, registered: false)
        document.rollbackSourceBookmark(nil, registered: true)

        XCTAssertTrue(recorder.calls.isEmpty)
    }
}