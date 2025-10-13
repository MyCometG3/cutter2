//
//  ErrorUtilities.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/01/27.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Foundation

/* ============================================ */
// MARK: - Error handling utilities
/* ============================================ */

/// Protocol for errors that can provide NSError representations
public protocol NSErrorConvertible: Error {
    var nsError: NSError { get }
    func nsError(with reason: String) -> NSError
}

/// Default implementation for NSErrorConvertible
public extension NSErrorConvertible {
    func nsError(with reason: String) -> NSError {
        let error = self.nsError
        var userInfo = error.userInfo
        userInfo[NSLocalizedFailureReasonErrorKey] = reason
        return NSError(domain: error.domain, code: error.code, userInfo: userInfo)
    }
}

/// Shared utilities for error handling
public struct ErrorUtilities {
    
    /// Throw an error with a specific reason.
    /// - Parameters:
    ///   - error: The error conforming to NSErrorConvertible to throw.
    ///   - reason: An optional reason for the error.
    /// - Returns: Never
    public static func throwError<E: NSErrorConvertible>(_ error: E, reason: String? = nil) throws -> Never {
        let nsError = reason != nil ? error.nsError(with: reason!) : error.nsError
        throw nsError
    }
}
