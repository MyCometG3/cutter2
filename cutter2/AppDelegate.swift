//
//  AppDelegate.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2019年 MyCometG3. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let bookmarksKey : String = "bookmarks"
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        clearBookmarks()
        startBookmarkAccess()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        
        stopBookmarkAccess()
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    /// Select next document
    ///
    /// - Parameter sender: Any
    @IBAction func nextDocument(_ sender: Any) {
        let docList : [Document]? = NSApp.orderedDocuments as? [Document]
        if let docList = docList, docList.count > 1 {
            if let doc = docList.last, let window = doc.window {
                window.makeKeyAndOrderFront(self)
            }
        }
    }
    
    /* ============================================ */
    // MARK: - Sandbox support
    /* ============================================ */
    
    /// Remove all bookmarks on startup
    public func clearBookmarks() {
        // Swift.print(#function, #line, #file)
        
        let needClear : Bool = NSEvent.modifierFlags.contains(.option)
        if needClear {
            let defaults = UserDefaults.standard
            defaults.set(nil, forKey: bookmarksKey)
            
            Swift.print("NOTE: All bookmarks are removed.")
        }
    }
    
    /// Register url as bookmark
    ///
    /// - Parameter newURL: url to register as bookmark
    public func addBookmark(for newURL : URL) {
        // Swift.print(#function, #line, #file)
        
        // Check duplicate
        var found : Bool = false
        validateBookmarks({(url) in
            if url.path == newURL.path {
                found = true
            }
        })
        if found {
            return
        }
        
        // Register new bookmark
        let data : Data? = try? newURL.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
        if let data = data {
            // Swift.print("NOTE: Registered", newURL.path)
            
            let defaults = UserDefaults.standard
            var bookmarks : [Data] = []
            if let array = defaults.array(forKey: bookmarksKey) {
                bookmarks = array as! [Data]
            }
            bookmarks.append(data)
            defaults.set(bookmarks, forKey: bookmarksKey)
        } else {
            // Swift.print("NOTE: Invalid url", newURL.path)
        }
    }
    
    /// Start access bookmarks in sandbox
    public func startBookmarkAccess() {
        // Swift.print(#function, #line, #file)
        
        validateBookmarks({(url) in
            _ = url.startAccessingSecurityScopedResource()
        })
    }
    
    /// Stop access bookmarks in sandbox
    public func stopBookmarkAccess() {
        // Swift.print(#function, #line, #file)
        
        validateBookmarks({(url) in
            url.stopAccessingSecurityScopedResource()
        })
    }
    
    /// Validate bookmarks with block
    ///
    /// - Parameter task: block to process bookmark url
    public func validateBookmarks(_ task : ((URL) -> Void)) {
        // Swift.print(#function, #line, #file)
        var validItems : [Data] = []
        let defaults = UserDefaults.standard
        if let bookmarks = defaults.array(forKey: bookmarksKey) {
            for item : Data in (bookmarks as! [Data]) {
                // NOTE: Preserve staled bookmark for later use.
                // NOTE: AVMovie does not use bookmark. Depends on filePath String.
                // So staled media resource is inaccessible via reference movie. (as of 10.13.x)
                do {
                    var stale : Bool = false
                    let url : URL? = try URL(resolvingBookmarkData: item,
                                             options: .withSecurityScope,
                                             relativeTo: nil,
                                             bookmarkDataIsStale: &stale)
                    if let url = url {
                        // Swift.print("NOTE: Valid bookmark -", url.path, (stale ? "staled" : ""))
                        
                        validItems.append(item)
                        task(url)
                    } else {
                        // Swift.print("NOTE: Invalid bookmark")
                    }
                } catch {
                    // Swift.print("NOTE: Invalid bookmark :", error.localizedDescription)
                }
            }
        }
        defaults.set(validItems, forKey: bookmarksKey)
    }
}

