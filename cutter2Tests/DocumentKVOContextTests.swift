//
//  DocumentKVOContextTests.swift
//  cutter2Tests
//

import XCTest
@testable import cutter2

/// Unit tests for the per-document KVO context token contract (L-33).
///
/// NOTE: Constructing `Document` directly crashes in the test environment
/// (see DocumentTests.swift), so these tests verify the token + pointer
/// derivation contract that `Document.playerKVOContext` forwards to.
final class DocumentKVOContextTests: XCTestCase {

    // MARK: - Pointer stability (registration <-> callback identity)

    /// Repeated derivation from the same token instance must yield the same
    /// pointer — the register-time / callback-time identity contract.
    func testContextPointerIsStableAcrossRepeatedDerivations() {
        let token = PlayerKVOContextToken()
        let first = token.contextPointer
        for _ in 0..<100 {
            XCTAssertEqual(token.contextPointer, first)
        }
    }

    // MARK: - Per-document uniqueness

    /// Distinct token instances (one per Document) must never share a pointer.
    func testContextPointerDiffersAcrossTokenInstances() {
        let tokens: [PlayerKVOContextToken] = (0..<10).map { _ in PlayerKVOContextToken() }
        let pointers = tokens.map { $0.contextPointer }
        XCTAssertEqual(Set(pointers).count, pointers.count)
    }

    // MARK: - Foreign context mismatch (super forwarding condition)

    /// Any foreign pointer must not match the token pointer — the condition
    /// that routes foreign KVO notifications to `super.observeValue`.
    func testContextPointerDiffersFromForeignPointer() {
        let token = PlayerKVOContextToken()
        let foreignObject = NSObject() // kept alive so its address stays unique
        let foreign = Unmanaged.passUnretained(foreignObject).toOpaque()
        XCTAssertNotEqual(token.contextPointer, foreign)
        let foreignRaw = UnsafeMutableRawPointer(bitPattern: 0xdead_beef)!
        XCTAssertNotEqual(token.contextPointer, foreignRaw)
    }
}
