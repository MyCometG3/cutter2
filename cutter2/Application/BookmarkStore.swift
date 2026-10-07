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
/// protocol so the Save As commit/rollback policy is unit testable without a live
/// `NSApplication`.
@MainActor
protocol SecurityScopedBookmarkRegistering: AnyObject {
    /// Registers `url` unless an equivalent entry already exists.
    ///
    /// - Parameter url: The url to register.
    /// - Returns: `true` when a new entry was created by this call, `false` when an
    ///   equivalent entry already existed or bookmark creation failed.
    @discardableResult
    func addBookmark(for url: URL) -> Bool

    /// Removes the entry registered for `url`, if any.
    ///
    /// - Parameter url: The url to unregister.
    func removeBookmark(for url: URL)
}

/// Pure helpers over the stored security-scoped bookmark array.
///
/// Extracted from `AppDelegate` so the retention policy can be unit tested without
/// sandbox entitlements and without mutating the developer's real `UserDefaults`.
enum BookmarkStore {

    /// Whether two urls denote the same bookmark target.
    ///
    /// Both sides are standardized so the duplicate check in `AppDelegate.addBookmark(for:)`
    /// and the removal in `removing(url:from:resolving:)` can never disagree. That matters
    /// because `addBookmark` reports whether *this* call created the entry, and
    /// `removeBookmark` then has to remove exactly that entry: if the two compared paths
    /// differently, a redundant `addBookmark` could report `true` while the matching
    /// `removeBookmark` also dropped an entry created by an earlier session.
    ///
    /// Standardizing collapses redundant separators and `..` segments. It does **not**
    /// resolve macOS firmlinks, so `/tmp/x.mov` and `/private/tmp/x.mov` stay distinct.
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
    /// function over the urls `validateBookmarks` resolves so it can be tested against
    /// `removing(url:from:resolving:)` on the same inputs. The two must agree: whatever this
    /// reports `true` for, a subsequent `removeBookmark` will also match. Otherwise a
    /// redundant `addBookmark` returns `true`, and the rollback deletes an entry an earlier
    /// session created.
    ///
    /// - Parameters:
    ///   - url: The url about to be registered.
    ///   - registered: Urls of the entries currently retained in the registry.
    /// - Returns: `true` when an equivalent entry already exists.
    static func contains(url: URL, among registered: [URL]) -> Bool {
        registered.contains { denotesSameTarget($0, url) }
    }

    /// Removes every stored entry that resolves to `url`.
    ///
    /// Entries whose bookmark data cannot be resolved are retained, leaving their
    /// disposal to `AppDelegate.validateBookmarks` (`AppDelegate.swift:166-186`).
    ///
    /// - Parameters:
    ///   - url: The url whose entries should be removed.
    ///   - items: The stored bookmark entries.
    ///   - resolve: Resolves one entry to its url, or `nil` when unresolvable.
    /// - Returns: The retained entries, and whether any entry was removed.
    static func removing(url: URL,
                         from items: [Data],
                         resolving resolve: (Data) -> URL?) -> (retained: [Data], removed: Bool) {
        var retained: [Data] = []
        retained.reserveCapacity(items.count)
        var removed: Bool = false
        for item in items {
            if let resolved = resolve(item), denotesSameTarget(resolved, url) {
                removed = true
                continue
            }
            retained.append(item)
        }
        return (retained, removed)
    }
}
