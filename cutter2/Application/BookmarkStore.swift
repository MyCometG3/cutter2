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

    /// Removes every stored entry that resolves to `url`.
    ///
    /// Entries whose bookmark data cannot be resolved are retained, leaving their
    /// disposal to `AppDelegate.validateBookmarks` (`AppDelegate.swift:166-186`).
    ///
    /// Paths are compared with `standardizedFileURL`, which collapses redundant
    /// separators and `..` segments. It does **not** resolve macOS firmlinks, so
    /// `/tmp/x.mov` and `/private/tmp/x.mov` stay distinct; that matches the duplicate
    /// check in `AppDelegate.addBookmark(for:)`, which compares raw paths too.
    ///
    /// - Parameters:
    ///   - url: The url whose entries should be removed.
    ///   - items: The stored bookmark entries.
    ///   - resolve: Resolves one entry to its url, or `nil` when unresolvable.
    /// - Returns: The retained entries, and whether any entry was removed.
    static func removing(url: URL,
                         from items: [Data],
                         resolving resolve: (Data) -> URL?) -> (retained: [Data], removed: Bool) {
        let target: String = url.standardizedFileURL.path
        var retained: [Data] = []
        retained.reserveCapacity(items.count)
        var removed: Bool = false
        for item in items {
            if let resolved = resolve(item), resolved.standardizedFileURL.path == target {
                removed = true
                continue
            }
            retained.append(item)
        }
        return (retained, removed)
    }
}