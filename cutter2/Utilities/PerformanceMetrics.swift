//
//  PerformanceMetrics.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/15.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation
import os.lock
import os.log

/* ============================================ */
// MARK: - Performance Measurement Utility
/* ============================================ */

// UnfairLockBox — 軽量ロック（AsyncBridge.swift と同一パターン）。
// PerformanceMetrics はコードベース内で Private 利用のため、
// ローカル定義とする（AsyncBridge.swift の private final class は外部アクセス不可）。
private final class UnfairLockBox<T>: @unchecked Sendable {
    private var rawLock = os_unfair_lock_s()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    @inline(__always)
    func withLock<U>(_ body: (inout T) throws -> U) rethrows -> U {
        os_unfair_lock_lock(&rawLock)
        defer { os_unfair_lock_unlock(&rawLock) }
        return try body(&value)
    }
}

/// Performance measurement utility for tracking operation timing and generating reports
///
/// This class provides tools to measure and track the performance of various operations
/// in the application. It supports both synchronous and asynchronous operations.
///
/// Usage:
/// ```swift
/// // Synchronous operation
/// let result = PerformanceMetrics.shared.measure("FileOpen") {
///     // Your operation here
///     return someValue
/// }
///
/// // Asynchronous operation
/// let result = await PerformanceMetrics.shared.measureAsync("Export") {
///     // Your async operation here
///     return await someAsyncValue
/// }
///
/// // Generate report
/// print(PerformanceMetrics.shared.report())
/// ```
@MainActor
class PerformanceMetrics {
    
    /* ============================================ */
    // MARK: - Singleton
    /* ============================================ */
    
    static let shared = PerformanceMetrics()
    
    /* ============================================ */
    // MARK: - Properties
    /* ============================================ */
    
    /// Lock-protected state holding the measurements and the logging flags.
    /// `recordMeasurement` is `nonisolated` and may run off the main actor, so both
    /// the dictionary and the flags are synchronized through one lock instead of
    /// relying on `nonisolated(unsafe)`, which would drop compile-time isolation.
    private struct MetricsState {
        var measurements: [String: [TimeInterval]] = [:]
        var loggingEnabled: Bool = true
        var verboseLogging: Bool = false
    }

    private let state = UnfairLockBox(MetricsState())

    /// Flag to enable/disable performance logging
    public nonisolated var loggingEnabled: Bool {
        get { state.withLock { $0.loggingEnabled } }
        set { state.withLock { $0.loggingEnabled = newValue } }
    }

    /// Flag to enable/disable detailed console output
    public nonisolated var verboseLogging: Bool {
        get { state.withLock { $0.verboseLogging } }
        set { state.withLock { $0.verboseLogging = newValue } }
    }
    
    /* ============================================ */
    // MARK: - Initialization
    /* ============================================ */
    
    private init() {}
    
    /* ============================================ */
    // MARK: - Measurement Methods
    /* ============================================ */
    
    /// Measure the execution time of a synchronous operation
    ///
    /// - Parameters:
    ///   - name: A descriptive name for the operation being measured
    ///   - operation: The operation to measure
    /// - Returns: The result of the operation
    /// - Throws: Any error thrown by the operation
    func measure<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            // S-09: recordMeasurement is nonisolated — no actor hop from @MainActor
            self.recordMeasurement(name, duration: duration)
        }
        return try operation()
    }

    /// Measure the execution time of an asynchronous operation
    ///
    /// - Parameters:
    ///   - name: A descriptive name for the operation being measured
    ///   - operation: The async operation to measure
    /// - Returns: The result of the operation
    /// - Throws: Any error thrown by the operation
    nonisolated func measureAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            // S-09: recordMeasurement is nonisolated — no actor hop from nonisolated measureAsync
            self.recordMeasurement(name, duration: duration)
        }
        return try await operation()
    }
    
    /// Record a measurement manually
    ///
    /// Use this when you need more control over when timing starts and stops
    ///
    /// - Parameters:
    ///   - name: A descriptive name for the operation
    ///   - duration: The duration in seconds
    nonisolated func recordMeasurement(_ name: String, duration: TimeInterval) {
        let (shouldLog, isVerbose) = state.withLock { box in
            box.measurements[name, default: []].append(duration)
            return (box.loggingEnabled, box.verboseLogging)
        }

        if shouldLog {
            let formatted = String(format: "%.3f", duration)
            if isVerbose {
                LoggingSystem.performance.info("[\(name)] completed in \(formatted)s")
            }
        }
    }
    
    /* ============================================ */
    // MARK: - Manual Timing
    /* ============================================ */
    
    /// Start timing an operation (returns start time for manual tracking)
    ///
    /// - Returns: The start time (use with `endMeasurement`)
    func startMeasurement() -> CFAbsoluteTime {
        return CFAbsoluteTimeGetCurrent()
    }
    
    /// End timing and record a measurement
    ///
    /// - Parameters:
    ///   - name: A descriptive name for the operation
    ///   - startTime: The start time returned by `startMeasurement()`
    func endMeasurement(_ name: String, startTime: CFAbsoluteTime) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        // S-09: recordMeasurement is nonisolated — no actor hop from @MainActor
        self.recordMeasurement(name, duration: duration)
    }
    
    /* ============================================ */
    // MARK: - Reporting
    /* ============================================ */
    
    /// Generate a formatted performance report
    ///
    /// - Returns: A multi-line string containing performance statistics
    func report() -> String {
        let snapshot = state.withLock { $0.measurements }
        var output = "=== Performance Report ===\n"
        output += "Generated: \(Date())\n\n"
        
        if snapshot.isEmpty {
            output += "No measurements recorded.\n"
            return output
        }
        
        // Sort by operation name for consistent output
        for (name, durations) in snapshot.sorted(by: { $0.key < $1.key }) {
            let count = durations.count
            let total = durations.reduce(0, +)
            let avg = total / Double(count)
            let min = durations.min() ?? 0
            let max = durations.max() ?? 0
            
            output += "\(name):\n"
            output += "  Samples: \(count)\n"
            output += "  Average: \(String(format: "%.3f", avg))s\n"
            output += "  Min: \(String(format: "%.3f", min))s\n"
            output += "  Max: \(String(format: "%.3f", max))s\n"
            output += "  Total: \(String(format: "%.3f", total))s\n"
            output += "\n"
        }
        
        return output
    }
    
    /// Get statistics for a specific operation
    ///
    /// - Parameter name: The operation name
    /// - Returns: Dictionary with statistics (avg, min, max, count, total), or nil if no data
    func statistics(for name: String) -> [String: Double]? {
        guard let durations = state.withLock({ $0.measurements[name] }), !durations.isEmpty else {
            return nil
        }
        
        let count = durations.count
        let total = durations.reduce(0, +)
        let avg = total / Double(count)
        let min = durations.min() ?? 0
        let max = durations.max() ?? 0
        
        return [
            "average": avg,
            "min": min,
            "max": max,
            "count": Double(count),
            "total": total
        ]
    }
    
    /* ============================================ */
    // MARK: - Data Management
    /* ============================================ */
    
    /// Clear all recorded measurements
    func reset() {
        state.withLock { $0.measurements.removeAll() }
        if loggingEnabled {
            LoggingSystem.performance.info("Performance metrics reset")
        }
    }
    
    /// Clear measurements for a specific operation
    ///
    /// - Parameter name: The operation name to clear
    func reset(for name: String) {
        state.withLock { _ = $0.measurements.removeValue(forKey: name) }
        if loggingEnabled {
            LoggingSystem.performance.info("Performance metrics reset for: \(name)")
        }
    }
    
    /// Export measurements as JSON data
    ///
    /// - Returns: JSON data representation of all measurements, or nil if encoding fails
    func exportJSON() -> Data? {
        var exportData: [String: [[String: Any]]] = [:]
        
        for (name, durations) in state.withLock({ $0.measurements }) {
            exportData[name] = durations.enumerated().map { index, duration in
                return ["index": index, "duration": duration]
            }
        }
        
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    /// Write performance report to a file
    ///
    /// - Parameter url: The URL where the report should be written
    /// - Throws: File writing errors
    func writeReport(to url: URL) throws {
        let reportText = report()
        try reportText.write(to: url, atomically: true, encoding: .utf8)
        
        if loggingEnabled {
            LoggingSystem.performance.notice("Performance report written to: \(url.lastPathComponent)")
        }
    }
}

/* ============================================ */
// MARK: - Convenience Extensions
/* ============================================ */

extension PerformanceMetrics {
    
    /// Common operation names for consistency
    enum Operation {
        static let fileOpen = "FileOpen"
        static let fileSave = "FileSave"
        static let fileExport = "FileExport"
        static let timelineRender = "TimelineRender"
        static let markerUpdate = "MarkerUpdate"
        static let videoExport = "VideoExport"
        static let audioExport = "AudioExport"
        static let customExport = "CustomExport"
        static let progressUpdate = "ProgressUpdate"
    }
}

/* ============================================ */
// MARK: - Debug Helpers
/* ============================================ */

#if DEBUG
extension PerformanceMetrics {
    
    /// Print a summary of all measurements to console
    func printReport() {
        LoggingSystem.performance.info("Performance Report:\n\(self.report())")
    }
    
    /// Print statistics for a specific operation
    ///
    /// - Parameter name: The operation name
    func printStatistics(for name: String) {
        if let stats = self.statistics(for: name) {
            let avg = String(format: "%.3f", stats["average"]!)
            let min = String(format: "%.3f", stats["min"]!)
            let max = String(format: "%.3f", stats["max"]!)
            let count = Int(stats["count"]!)
            LoggingSystem.performance.info("Statistics for \(name): avg=\(avg)s, min=\(min)s, max=\(max)s, samples=\(count)")
        } else {
            LoggingSystem.performance.notice("No statistics available for: \(name)")
        }
    }
}
#endif
