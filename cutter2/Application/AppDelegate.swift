//
//  AppDelegate.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import os.log

@main @MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    /* ============================================ */
    // MARK: - Private properties/constants
    /* ============================================ */
    
    private let bookmarksKey: String = "bookmarks"
    
    /* ============================================ */
    // MARK: - NSApplicationDelegate protocol
    /* ============================================ */
    
    /// Clears bookmarks when the reset modifier is active, then starts security-scoped access.
    ///
    /// - Parameter aNotification: The application launch notification.
    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        clearBookmarks(false)
        startBookmarkAccess()
    }
    
    /// Stops security-scoped access before the application terminates.
    ///
    /// - Parameter aNotification: The application termination notification.
    public func applicationWillTerminate(_ aNotification: Notification) {
        stopBookmarkAccess()
    }
    
    /// Prevents the application from creating an untitled document at launch.
    ///
    /// - Parameter sender: The application requesting the decision.
    /// - Returns: Always `false`.
    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    /* ============================================ */
    // MARK: - Documents rotation
    /* ============================================ */
    
    /// Select next document
    ///
    /// - Parameter sender: Any
    @IBAction func nextDocument(_ sender: Any) {
        
        let docList: [Document] = NSApp.orderedDocuments.compactMap { $0 as? Document }
        if docList.count > 0 {
            if let doc = docList.last, let window = doc.window {
                window.makeKeyAndOrderFront(self)
            }
        }
    }
    
    /* ============================================ */
    // MARK: - Sandbox support
    /* ============================================ */
    
    /// Remove all bookmarks on startup
    public func clearBookmarks(_ force: Bool) {
        let needClear: Bool = force ? true : NSEvent.modifierFlags.contains(.option)
        if needClear {
            let defaults = UserDefaults.standard
            defaults.set(nil, forKey: bookmarksKey)
            
            LoggingSystem.security.notice("All bookmarks removed")
        }
    }
    
    /// Register url as bookmark
    ///
    /// - Parameter newURL: url to register as bookmark
    public func addBookmark(for newURL: URL) {
        // Check duplicate
        var found: Bool = false
        validateBookmarks(false, using: {(url) in
            if url.path == newURL.path {
                found = true
            }
        })
        if found {
            return
        }
        
        // Register new bookmark
        if let data = createBookmark(for: newURL) {
            LoggingSystem.security.info("Registered bookmark: \(newURL.lastPathComponent)")
            
            let defaults = UserDefaults.standard
            var bookmarks: [Data] = []
            if let array = defaults.array(forKey: bookmarksKey) as? [Data] {
                bookmarks = array
            }
            bookmarks.append(data)
            defaults.set(bookmarks, forKey: bookmarksKey)
        } else {
            LoggingSystem.security.error("Failed to create bookmark for: \(newURL.lastPathComponent)")
        }
    }
    
    /// Start access bookmarks in sandbox
    private func startBookmarkAccess() {
        
        validateBookmarks(true, using: {(url) in
            _ = url.startAccessingSecurityScopedResource()
        })
    }
    
    /// Stop access bookmarks in sandbox
    private func stopBookmarkAccess() {
        
        validateBookmarks(true, using: {(url) in
            url.stopAccessingSecurityScopedResource()
        })
    }
    
    /// Validates all stored security-scoped bookmarks and refreshes them when required.
    ///
    /// Only valid or successfully renewed bookmark data is retained and written back
    /// to `UserDefaults`. Stale bookmarks that cannot be renewed and invalid bookmarks
    /// are discarded. The block is called once for each retained bookmark's resolved URL.
    ///
    /// - Parameters:
    ///   - verbose: Whether to enable bookmark validation logging.
    ///   - block: A closure called with the resolved URL of each retained bookmark.
    private func validateBookmarks(_ verbose: Bool, using block: ((URL) -> Void)) {
        var validItems: [Data] = []
        let defaults = UserDefaults.standard
        if let bookmarks = defaults.array(forKey: bookmarksKey) as? [Data] {
            for item: Data in bookmarks {
                /*
                 Preserve source movie file information as security-scoped bookmark data.
                 
                 Restriction:
                 Different from legacy QuickTime framework, AVMovie does not use bookmark/alias for
                 sample reference. It depends on filepath string and doesn't follow file path change.
                 */
                let (validated, url): (Data?, URL?) = refreshBookmarkIfRequired(item, acceptStale: false, verbose: verbose)
                if let validated = validated, let url = url {
                    validItems.append(validated)
                    block(url)
                }
            }
        }
        defaults.set(validItems, forKey: bookmarksKey)
    }
    
    /// Validates bookmark data and renews it when the resolved bookmark is stale.
    ///
    /// A stale bookmark is returned unchanged when `acceptStale` is `true` and renewal
    /// fails; otherwise, renewal failure returns a `nil` data value. Invalid bookmark
    /// data returns `(nil, nil)`. The URL may still be returned when stale bookmark data
    /// is rejected, allowing callers to distinguish an invalid bookmark from an
    /// unrenewable stale bookmark.
    ///
    /// - Parameters:
    ///   - item: The bookmark data to validate.
    ///   - acceptStale: Whether to retain stale bookmark data when renewal fails.
    ///   - verbose: Whether to enable validation logging.
    /// - Returns: A tuple containing retained or renewed bookmark data and its resolved URL.
    private func refreshBookmarkIfRequired(_ item: Data, acceptStale: Bool, verbose: Bool = false) -> (data: Data?, url: URL?) {
        // Validate bookmark item
        do {
            var stale: Bool = false
            let url: URL = try URL(resolvingBookmarkData: item,
                                   options: .withSecurityScope,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &stale)
            if !stale {
                if verbose {
                    LoggingSystem.security.info("Valid bookmark: \(url.lastPathComponent)")
                }
                return (item, url) // Valid bookmark - No change
            } else {
                // Try renewing bookmark item
                if let newItem = createBookmark(for: url) {
                    if verbose {
                        LoggingSystem.security.info("Valid bookmark (renewed): \(url.lastPathComponent)")
                    }
                    return (newItem, url) // Renewed bookmark
                }
            }
            
            // Failed to create new bookmark for the url
            if acceptStale {
                if verbose {
                    LoggingSystem.security.notice("Valid bookmark (stale): \(url.lastPathComponent)")
                }
                return (item, url) // Staled bookmark - No change
            } else {
                if verbose {
                    LoggingSystem.security.notice("Invalidate bookmark (stale): \(url.lastPathComponent)")
                }
                return (nil, url) // Staled => Invalidate
            }
        } catch {
            if verbose {
                LoggingSystem.security.error("Invalid bookmark: \(error.localizedDescription)")
            }
            return (nil, nil) // Invalid bookmark - nil returned
        }
    }
    
    /// Creates security-scoped bookmark data for a URL.
    ///
    /// - Parameter url: The source URL.
    /// - Returns: The generated bookmark data, or `nil` when creation fails.
    private func createBookmark(for url: URL) -> Data? {
        let data: Data? = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        return data
    }
}

/// Access security-scoped URLs for the duration of `body`.
/// Duplicate URLs are coalesced before access starts.
func bracketSecurityScopedAccess<T>(
    for urls: [URL],
    perform body: () async throws -> T
) async throws -> T {
    let uniqueURLs = Array(Set(urls.map { $0.standardizedFileURL }))
    var startedURLs: [URL] = []
    for url in uniqueURLs {
        if url.startAccessingSecurityScopedResource() {
            startedURLs.append(url)
        }
    }
    defer {
        for url in startedURLs.reversed() {
            url.stopAccessingSecurityScopedResource()
        }
    }
    return try await body()
}
