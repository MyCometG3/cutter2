//
//  BookmarkStore.swift
//  cutter2
//
//  Copyright © 2026 MyCometG3. All rights reserved.
//

import Foundation

/// Abstraction over the security-scoped bookmark registry.
///
/// `AppDelegate` is the production implementation. `Document` reaches it through this
/// protocol so the Save As registration policy is unit testable without a live
/// `NSApplication`.
@MainActor
protocol SecurityScopedBookmarkRegistering: AnyObject {
    /// Registers `url` unless an equivalent entry already exists.
    ///
    /// - Parameter url: The url to register.
    func addBookmark(for url: URL)
}

/// Pure helpers over the security-scoped bookmark registry.
///
/// Extracted from `AppDelegate` so the duplicate-detection policy can be unit tested
/// without sandbox entitlements and without mutating the developer's real `UserDefaults`.
enum BookmarkStore {

    /// Whether two urls denote the same bookmark target.
    ///
    /// Both sides are standardized, so a redundant separator or a `..` segment cannot make
    /// one spelling of a path look like a different file. Standardizing does **not** resolve
    /// macOS firmlinks, so `/tmp/x.mov` and `/private/tmp/x.mov` stay distinct; that limit is
    /// pinned by a test.
    ///
    /// - Parameters:
    ///   - lhs: One candidate url.
    ///   - rhs: The other candidate url.
    /// - Returns: `true` when both urls standardize to the same path.
    static func denotesSameTarget(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    /// Whether any already-registered url denotes `url`.
    ///
    /// This is the duplicate check `AppDelegate.addBookmark(for:)` performs, kept as a pure
    /// function over the urls `validateBookmarks` resolves. `addBookmark` itself needs a
    /// live `NSApplication` and the real `UserDefaults`, so extracting the predicate is what
    /// makes the policy testable at all.
    ///
    /// - Parameters:
    ///   - url: The url about to be registered.
    ///   - registered: Urls of the entries currently retained in the registry.
    /// - Returns: `true` when an equivalent entry already exists.
    static func contains(url: URL, among registered: [URL]) -> Bool {
        registered.contains { denotesSameTarget($0, url) }
    }
}