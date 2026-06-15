//
//  LoggingSystem.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/18.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation
import os.log

/* ============================================ */
// MARK: - Logging System
/* ============================================ */

/// Centralized logging system for cutter2 using Apple's unified logging (os.Logger)
///
/// This enum provides structured logging with multiple categories and proper log levels.
/// All logs are integrated with the system and can be viewed in Console.app.
///
/// ## Categories
///
/// The logging system is organized into the following categories:
/// - **document**: Document operations (open, save, close)
/// - **video**: Video processing and editing operations
/// - **ui**: User interface and interaction events
/// - **performance**: Performance measurements and metrics
/// - **fileIO**: File I/O operations and data access
/// - **security**: Security-scoped bookmarks and permissions
/// - **export**: Export and transcode operations
/// - **input**: Keyboard and input handling
/// - **app**: Application lifecycle events
///
/// ## Log Levels
///
/// - **debug**: Development debugging, detailed traces (DEBUG builds only)
/// - **info**: Informational messages, operation tracking
/// - **notice**: Significant but normal events, and warning-like events (use for potential issues, non-fatal errors)
/// - **error**: Error conditions, operation failures
/// - **fault**: Critical failures, app stability at risk
///
/// ## Usage Examples
///
/// ```swift
/// // Document operations
/// LoggingSystem.document.info("Opening movie file: \(url.lastPathComponent)")
///
/// // Error reporting with context
/// LoggingSystem.fileIO.error("Failed to read file: \(error.localizedDescription)")
///
/// // Performance measurement
/// LoggingSystem.performance.notice("Export completed in \(duration, format: .fixed(precision: 2))s")
///
/// // Debug logging (development only)
/// #if DEBUG
/// LoggingSystem.video.debug("Processing frame \(frameNumber)")
/// #endif
///
/// // Privacy control
/// LoggingSystem.document.info("Document count: \(count, privacy: .public)")
/// LoggingSystem.fileIO.debug("File path: \(url.path)") // private by default
/// ```
///
/// ## Console.app Filtering
///
/// To view logs in Console.app, use:
/// ```
/// subsystem:com.mycometg3.cutter2
/// subsystem:com.mycometg3.cutter2 AND category:document
/// subsystem:com.mycometg3.cutter2 AND level:error
/// ```
///
/// ## Privacy
///
/// - **public**: Safe to log in production (counts, durations, status codes)
/// - **private**: Redacted in production (file paths, names) - default
/// - **sensitive**: Always redacted (user data, security tokens)
///
public enum LoggingSystem {
    
    /* ============================================ */
    // MARK: - Subsystem
    /* ============================================ */
    
    /// The application subsystem identifier for unified logging
    private static let subsystemIdentifier = Bundle.main.bundleIdentifier ?? "com.mycometg3.cutter2"
    
    /* ============================================ */
    // MARK: - Logger Categories
    /* ============================================ */
    
    /// Document operations (open, save, export)
    ///
    /// Use for logging document lifecycle events, file operations, and document state changes.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.document.info("Document opened: \(filename)")
    /// LoggingSystem.document.notice("Document saved successfully")
    /// LoggingSystem.document.error("Failed to save document: \(error)")
    /// ```
    public static let document = Logger(subsystem: subsystemIdentifier, category: "document")
    
    /// Video processing and editing operations
    ///
    /// Use for logging video editing operations, transformations, and movie processing.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.video.info("Starting video edit operation")
    /// LoggingSystem.video.debug("Processing frame at \(time)")
    /// LoggingSystem.video.notice("Codec not available, using fallback")
    /// ```
    public static let video = Logger(subsystem: subsystemIdentifier, category: "video")
    
    /// User interface and interaction events
    ///
    /// Use for logging UI state changes, user interactions, and interface updates.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.ui.info("Window resized to \(size)")
    /// LoggingSystem.ui.debug("UI state updated")
    /// ```
    public static let ui = Logger(subsystem: subsystemIdentifier, category: "ui")
    
    /// Performance measurements and metrics
    ///
    /// Use for logging performance-related data, timing measurements, and resource usage.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.performance.notice("Export completed in \(duration)s")
    /// LoggingSystem.performance.info("Memory usage: \(bytes) bytes")
    /// ```
    public static let performance = Logger(subsystem: subsystemIdentifier, category: "performance")
    
    /// File I/O operations
    ///
    /// Use for logging file reading, writing, and data access operations.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.fileIO.info("Reading file: \(filename)")
    /// LoggingSystem.fileIO.error("Failed to write file: \(error)")
    /// ```
    public static let fileIO = Logger(subsystem: subsystemIdentifier, category: "fileIO")
    
    /// Bookmark and security-scoped resource management
    ///
    /// Use for logging security-scoped bookmarks, permissions, and sandbox operations.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.security.info("Bookmark created for file")
    /// LoggingSystem.security.debug("Security-scoped resource accessed")
    /// LoggingSystem.security.notice("Bookmark validation failed")
    /// ```
    public static let security = Logger(subsystem: subsystemIdentifier, category: "security")
    
    /// Export and transcode operations
    ///
    /// Use for logging export progress, transcode operations, and format conversions.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.export.info("Export started: \(preset)")
    /// LoggingSystem.export.notice("Export progress: \(progress)%")
    /// LoggingSystem.export.error("Export failed: \(error)")
    /// ```
    public static let export = Logger(subsystem: subsystemIdentifier, category: "export")
    
    /// Keyboard and input handling
    ///
    /// Use for logging keyboard events, mouse interactions, and input processing.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.input.debug("Key event: \(keyCode)")
    /// LoggingSystem.input.info("Input mode changed: \(mode)")
    /// ```
    public static let input = Logger(subsystem: subsystemIdentifier, category: "input")
    
    /// General application lifecycle
    ///
    /// Use for logging application launch, termination, and lifecycle events.
    ///
    /// Examples:
    /// ```swift
    /// LoggingSystem.app.info("Application launched")
    /// LoggingSystem.app.notice("Application entering background")
    /// LoggingSystem.app.notice("Low memory warning received")
    /// ```
    public static let app = Logger(subsystem: subsystemIdentifier, category: "app")
    
    /* ============================================ */
    // MARK: - Utility Methods
    /* ============================================ */
    
    /// The subsystem identifier used for logging
    ///
    /// - Returns: The subsystem identifier (bundle identifier)
    public static func subsystem() -> String {
        return subsystemIdentifier
    }
    
    /// All available logger categories
    ///
    /// - Returns: Array of category names
    public static func categories() -> [String] {
        return [
            "document",
            "video",
            "ui",
            "performance",
            "fileIO",
            "security",
            "export",
            "input",
            "app"
        ]
    }
    
    /// Generate a Console.app filter string for this subsystem
    ///
    /// - Parameter category: Optional category to filter by
    /// - Returns: Filter string for Console.app
    ///
    /// Examples:
    /// ```swift
    /// // Filter all logs from cutter2
    /// let filter = LoggingSystem.consoleFilter()
    /// // "subsystem:com.mycometg3.cutter2"
    ///
    /// // Filter only document logs
    /// let filter = LoggingSystem.consoleFilter(category: "document")
    /// // "subsystem:com.mycometg3.cutter2 AND category:document"
    /// ```
    public static func consoleFilter(category: String? = nil) -> String {
        var filter = "subsystem:\(subsystemIdentifier)"
        if let category = category {
            filter += " AND category:\(category)"
        }
        return filter
    }
}

/* ============================================ */
// MARK: - Logging Extensions
/* ============================================ */

/// Extension to provide convenient logging methods
extension LoggingSystem {
    
    /// Log a timestamped message at info level
    ///
    /// Useful for maintaining compatibility with existing timestamp-based logging patterns.
    ///
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - message: The message to log
    ///
    /// Example:
    /// ```swift
    /// LoggingSystem.logWithTimestamp(LoggingSystem.document, "Document opened")
    /// // Logs: "12:34:56.789 - Document opened"
    /// ```
    public static func logWithTimestamp(_ logger: Logger, _ message: String) {
        let timestamp = timestampFormatter.string(from: Date())
        logger.info("\(timestamp) - \(message)")
    }
    
    /// Log function entry (debug level)
    ///
    /// Convenient method for logging function entry points during debugging.
    ///
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - function: The function name (use #function)
    ///   - file: The file name (use #file)
    ///   - line: The line number (use #line)
    ///
    /// Example:
    /// ```swift
    /// func myFunction() {
    ///     LoggingSystem.logFunctionEntry(LoggingSystem.document)
    ///     // Your code here
    /// }
    /// ```
    public static func logFunctionEntry(
        _ logger: Logger,
        function: String = #function,
        file: String = #file,
        line: Int = #line
    ) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        logger.debug("→ \(function) [\(filename):\(line)]")
        #endif
    }
    
    /// Log function exit (debug level)
    ///
    /// Convenient method for logging function exit points during debugging.
    ///
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - function: The function name (use #function)
    ///
    /// Example:
    /// ```swift
    /// func myFunction() {
    ///     defer {
    ///         LoggingSystem.logFunctionExit(LoggingSystem.document)
    ///     }
    ///     // Your code here
    /// }
    /// ```
    public static func logFunctionExit(
        _ logger: Logger,
        function: String = #function
    ) {
        #if DEBUG
        logger.debug("← \(function)")
        #endif
    }
}

// MARK: - Private Helpers

extension LoggingSystem {
    /// Thread-local DateFormatter for timestamp generation
    /// 
    /// Thread-safety: Uses Thread.threadDictionary to maintain one formatter per thread,
    /// avoiding data races from concurrent access to a shared DateFormatter instance.
    private static var timestampFormatter: DateFormatter {
        let key = "LoggingSystem.timestampFormatter"
        if let formatter = Thread.current.threadDictionary[key] as? DateFormatter {
            return formatter
        }
        let formatter = DateFormatter.logFormatter(format: "HH:mm:ss.SSS")
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }
}
