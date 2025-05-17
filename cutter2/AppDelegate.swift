//
//  AppDelegate.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2023年 MyCometG3. All rights reserved.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    /* ============================================ */
    // MARK: - Private properties/constants
    /* ============================================ */
    
    private let bookmarksKey: String = "bookmarks"
    
    private var useLog: Bool = true
    
    /* ============================================ */
    // MARK: - NSApplicationDelegate protocol
    /* ============================================ */
    
    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        clearBookmarks(false)
        startBookmarkAccess()
    }
    
    public func applicationWillTerminate(_ aNotification: Notification) {
        stopBookmarkAccess()
    }
    
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
        // Swift.print(#function, #line, #file)
        
        let docList: [Document]? = NSApp.orderedDocuments as? [Document]
        if let docList = docList, docList.count > 0 {
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
        // Swift.print(#function, #line, #file)
        
        let needClear: Bool = force ? true : NSEvent.modifierFlags.contains(.option)
        if needClear {
            let defaults = UserDefaults.standard
            defaults.set(nil, forKey: bookmarksKey)
            
            log("NOTE: All bookmarks are removed.")
        }
    }
    
    /// Register url as bookmark
    ///
    /// - Parameter newURL: url to register as bookmark
    public func addBookmark(for newURL: URL) {
        // Swift.print(#function, #line, #file)
        
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
            log("NOTE: Register bookmark -", newURL.path)
            
            let defaults = UserDefaults.standard
            var bookmarks: [Data] = []
            if let array = defaults.array(forKey: bookmarksKey) {
                bookmarks = array as! [Data]
            }
            bookmarks.append(data)
            defaults.set(bookmarks, forKey: bookmarksKey)
        } else {
            log("NOTE: Invalid url -", newURL.path)
        }
    }
    
    /// Start access bookmarks in sandbox
    private func startBookmarkAccess() {
        // Swift.print(#function, #line, #file)
        
        validateBookmarks(true, using: {(url) in
            _ = url.startAccessingSecurityScopedResource()
        })
    }
    
    /// Stop access bookmarks in sandbox
    private func stopBookmarkAccess() {
        // Swift.print(#function, #line, #file)
        
        validateBookmarks(true, using: {(url) in
            url.stopAccessingSecurityScopedResource()
        })
    }
    
    /// Validate bookmarks with block
    ///
    /// - Parameter block: block to process bookmark url
    private func validateBookmarks(_ verbose: Bool, using block: ((URL) -> Void)) {
        // Swift.print(#function, #line, #file)
        
        let useLogOriginal: Bool = useLog
        useLog = verbose
        var validItems: [Data] = []
        let defaults = UserDefaults.standard
        if let bookmarks = defaults.array(forKey: bookmarksKey) {
            for item: Data in (bookmarks as! [Data]) {
                /*
                 Preserve souce movie file information as security scoped bookmark data.
                 
                 Restriction:
                 Different from legacy QuickTime framework, AVMovie does not use bookmark/alias for
                 sample reference. It depends on filepath string and doesn't follow file path change.
                 */
                var url: URL? = nil
                let validated: Data? = refreshBookmarkIfRequired(item, urlOut: &url, acceptStale: false)
                if let validated = validated, let url = url {
                    validItems.append(validated)
                    block(url)
                }
            }
        }
        defaults.set(validItems, forKey: bookmarksKey)
        useLog = useLogOriginal
    }
    
    /// Validate bookmark data and refresh if required.
    /// - Parameters:
    ///   - item: bookmark data to be validated
    ///   - urlOut: resolved url from the bookmark
    ///   - acceptStale: accept stale bookmark or not
    /// - Returns: resulted bookmark data
    private func refreshBookmarkIfRequired(_ item: Data, urlOut: inout URL?, acceptStale: Bool) -> Data? {
        // Swift.print(#function, #line, #file)
        
        // Validate bookmark item
        do {
            var stale: Bool = false
            let url: URL = try URL(resolvingBookmarkData: item,
                                   options: .withSecurityScope,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &stale)
            urlOut = url
            if !stale {
                log("NOTE: Valid bookmark -", url.path)
                return item // Valid bookmark - No change
            } else {
                // Try renewing bookmark item
                if let newItem = createBookmark(for: url) {
                    log("NOTE: Valid bookmark -", url.path, "(renewed)")
                    return newItem // Renewed bookmark
                }
                
                // Failed to create new bookmark for the url
                if acceptStale {
                    log("NOTE: Valid bookmark -", url.path, (stale ? "(stale)" : ""))
                    return item // Staled bookmark - No change
                } else {
                    log("NOTE: Invalidate bookmark -", url.path, (stale ? "(stale)" : ""))
                    return nil // Staled => Invalid
                }
            }
        } catch {
            log("NOTE: Invalid bookmark -", error.localizedDescription)
            return nil // Invalid bookmark - nil returned
        }
    }
    
    /// Create security scoped bookmark data from the url
    /// - Parameter url: source url
    /// - Returns: resulted bookmark data
    private func createBookmark(for url: URL) -> Data? {
        // Swift.print(#function, #line, #file)
        
        let data: Data? = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        return data
    }
    
    /// Debug logging bookmark validation activity when useLog == true.
    /// - Parameter items: bookmark validation strings to be logged
    private func log(_ items: Any...) {
        // Swift.print(#function, #line, #file)
        
        if useLog {
            let output = items.map{ ($0 as AnyObject).description }.joined(separator:" ")
            Swift.print(output)
        }
    }
}
