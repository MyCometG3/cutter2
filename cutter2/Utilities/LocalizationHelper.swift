//
//  LocalizationHelper.swift
//  cutter2
//
//  Created by GitHub Copilot on 2025/10/14.
//

import Foundation

/* ============================================ */
// MARK: - Localization Helper
/* ============================================ */

/// Helper utilities for localization throughout the application
enum LocalizationHelper {
    
    /* ============================================ */
    // MARK: - String Localization
    /* ============================================ */
    
    /// Localize a string with the given key and comment
    /// - Parameters:
    ///   - key: The localization key
    ///   - comment: Description for translators
    /// - Returns: Localized string
    static func localized(_ key: String, comment: String = "") -> String {
        return NSLocalizedString(key, comment: comment)
    }
    
    /// Localize a string with format arguments
    /// - Parameters:
    ///   - key: The localization key
    ///   - comment: Description for translators
    ///   - arguments: Format arguments
    /// - Returns: Formatted localized string
    static func localizedFormat(_ key: String, comment: String = "", _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: comment)
        return String(format: format, arguments: arguments)
    }
    
    /* ============================================ */
    // MARK: - Common UI Strings
    /* ============================================ */
    
    /// Common button labels
    enum Button {
        static let ok = localized("ui.button.ok", comment: "OK button")
        static let cancel = localized("ui.button.cancel", comment: "Cancel button")
        static let save = localized("ui.button.save", comment: "Save button")
        static let export = localized("ui.button.export", comment: "Export button")
        static let `continue` = localized("ui.button.continue", comment: "Continue button")
        static let stop = localized("ui.button.stop", comment: "Stop button")
    }
    
    /* ============================================ */
    // MARK: - Number and Date Formatting
    /* ============================================ */
    
    /// Format a percentage value for display
    /// - Parameter value: The percentage value (0.0 to 1.0)
    /// - Returns: Formatted percentage string
    static func formatPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value * 100))%"
    }
    
    /// Format a time interval for display
    /// - Parameter interval: Time interval in seconds
    /// - Returns: Formatted time string (e.g., "1:23" or "1:23:45")
    static func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Format file size for display
    /// - Parameter bytes: Size in bytes
    /// - Returns: Formatted size string with appropriate unit
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/* ============================================ */
// MARK: - String Extension
/* ============================================ */

extension String {
    /// Convenience method to get localized string
    /// - Parameter comment: Description for translators
    /// - Returns: Localized string
    func localized(comment: String = "") -> String {
        return NSLocalizedString(self, comment: comment)
    }
    
    /// Convenience method to get localized string with format arguments
    /// - Parameters:
    ///   - comment: Description for translators
    ///   - arguments: Format arguments
    /// - Returns: Formatted localized string
    func localizedFormat(comment: String = "", _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(self, comment: comment)
        return String(format: format, arguments: arguments)
    }
}
