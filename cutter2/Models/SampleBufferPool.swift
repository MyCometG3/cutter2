//
//  SampleBufferPool.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/18.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia

/* ============================================ */
// MARK: - SampleBufferPool Statistics
/* ============================================ */

/// Statistics for buffer pool performance monitoring
public struct BufferPoolStatistics: Sendable {
    /// Total number of buffer acquisition requests
    public var totalAcquires: Int = 0
    
    /// Number of times a buffer was reused from the pool
    public var poolHits: Int = 0
    
    /// Number of times a new buffer was allocated
    public var poolMisses: Int = 0
    
    /// Current number of buffers in the pool
    public var currentPoolSize: Int = 0
    
    /// Peak number of buffers that have been in the pool
    public var peakPoolSize: Int = 0
    
    /// Total number of buffers drained from the pool
    public var totalDrains: Int = 0
    
    /// Cache hit rate (0.0 - 1.0)
    public var hitRate: Double {
        guard totalAcquires > 0 else { return 0.0 }
        return Double(poolHits) / Double(totalAcquires)
    }
    
    /// Format statistics as human-readable string
    public var description: String {
        """
        Buffer Pool Statistics:
          Total Acquires: \(totalAcquires)
          Pool Hits: \(poolHits)
          Pool Misses: \(poolMisses)
          Hit Rate: \(String(format: "%.1f%%", hitRate * 100))
          Current Pool Size: \(currentPoolSize)
          Peak Pool Size: \(peakPoolSize)
          Total Drains: \(totalDrains)
        """
    }
}

/* ============================================ */
// MARK: - Buffer Size Class
/* ============================================ */

/// Size classification for buffer pooling
enum BufferSizeClass: Sendable {
    case small      // < 100 KB (audio, small video frames)
    case medium     // 100 KB - 1 MB (HD video frames)
    case large      // > 1 MB (4K video frames, ProRes)
    
    /// Create size class from byte size
    /// - Parameter size: Size in bytes
    /// - Returns: Appropriate size class
    static func from(size: Int) -> BufferSizeClass {
        if size < 100_000 {
            return .small
        } else if size < 1_000_000 {
            return .medium
        } else {
            return .large
        }
    }
    
    /// Maximum number of buffers to keep in pool for this size class
    var maxPoolSize: Int {
        switch self {
        case .small:
            return 20  // Audio and small frames
        case .medium:
            return 10  // HD video frames
        case .large:
            return 5   // 4K/ProRes frames
        }
    }
}

/* ============================================ */
// MARK: - Pooled Buffer Info
/* ============================================ */

/// Information about a pooled buffer
struct PooledBufferInfo: Sendable {
    let capacity: Int
    let sizeClass: BufferSizeClass
    let mediaType: AVMediaType
    let createdAt: Date
    var lastUsedAt: Date
}

/* ============================================ */
// MARK: - SampleBufferPool Actor
/* ============================================ */

/// Thread-safe buffer pool for CMSampleBuffer reuse during export operations
///
/// This actor manages a pool of reusable sample buffers to reduce memory allocation
/// overhead during video/audio export. Buffers are classified by size and media type
/// for efficient reuse.
///
/// Key Features:
/// - Thread-safe access via Swift actor
/// - LRU eviction when pool exceeds size limits
/// - Memory pressure monitoring and automatic draining
/// - Comprehensive statistics tracking
///
/// Usage:
/// ```swift
/// let pool = SampleBufferPool()
///
/// // During export
/// while processing {
///     let info = // ... buffer size and type info
///     if let reusedBuffer = await pool.acquire(capacity: info.capacity, mediaType: info.mediaType) {
///         // Use reused buffer
///     }
///     // After use
///     await pool.release(buffer, capacity: info.capacity, mediaType: info.mediaType)
/// }
///
/// // Check statistics
/// let stats = await pool.statistics
/// print(stats.description)
/// ```
public actor SampleBufferPool {
    
    /* ============================================ */
    // MARK: - Configuration
    /* ============================================ */
    
    /// Maximum total memory for pooled buffers (in bytes)
    /// Default: 20 MB (sufficient for HD video export with buffer reuse)
    private let maxTotalMemory: Int
    
    /// Enable automatic memory pressure monitoring
    private let enableMemoryPressureMonitoring: Bool
    
    /* ============================================ */
    // MARK: - Private State
    /* ============================================ */
    
    /// Pool of available buffers, organized by size class and media type
    private var availableBuffers: [AVMediaType: [BufferSizeClass: [CMSampleBuffer]]] = [:]
    
    /// Metadata for tracking buffer usage patterns
    private var bufferInfo: [ObjectIdentifier: PooledBufferInfo] = [:]
    
    /// Current total memory used by pooled buffers
    private var currentMemoryUsage: Int = 0
    
    /// Performance statistics
    private var _statistics = BufferPoolStatistics()
    
    /// Memory pressure monitoring source
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    /* ============================================ */
    // MARK: - Initialization
    /* ============================================ */
    
    /// Initialize a new sample buffer pool
    /// - Parameters:
    ///   - maxTotalMemory: Maximum total memory for pooled buffers in bytes (default: 20 MB)
    ///   - enableMemoryPressureMonitoring: Enable automatic draining on memory pressure (default: true)
    public init(maxTotalMemory: Int = 20_000_000, 
                enableMemoryPressureMonitoring: Bool = true) {
        self.maxTotalMemory = maxTotalMemory
        self.enableMemoryPressureMonitoring = enableMemoryPressureMonitoring
        
        if enableMemoryPressureMonitoring {
            setupMemoryPressureMonitoring()
        }
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    /* ============================================ */
    // MARK: - Public Interface
    /* ============================================ */
    
    /// Acquire a buffer from the pool or create a new one
    ///
    /// This method attempts to reuse an existing buffer from the pool that matches
    /// the requested capacity and media type. If no suitable buffer is available,
    /// returns nil and the caller should create a new buffer.
    ///
    /// - Parameters:
    ///   - capacity: Required buffer capacity in bytes
    ///   - mediaType: Media type (video or audio)
    /// - Returns: Reused buffer if available, nil otherwise
    public func acquire(capacity: Int, mediaType: AVMediaType) -> CMSampleBuffer? {
        _statistics.totalAcquires += 1
        
        let sizeClass = BufferSizeClass.from(size: capacity)
        
        // Try to find a suitable buffer in the pool
        guard var classBuffers = availableBuffers[mediaType]?[sizeClass],
              !classBuffers.isEmpty else {
            _statistics.poolMisses += 1
            return nil
        }
        
        // Get the most recently used buffer (last in array = most recent)
        let buffer = classBuffers.removeLast()
        availableBuffers[mediaType]?[sizeClass] = classBuffers
        
        // Update metadata
        let bufferID = ObjectIdentifier(buffer as AnyObject)
        if var info = bufferInfo[bufferID] {
            info.lastUsedAt = Date()
            bufferInfo[bufferID] = info
        }
        
        _statistics.poolHits += 1
        _statistics.currentPoolSize -= 1
        currentMemoryUsage -= capacity
        
        return buffer
    }
    
    /// Release a buffer back to the pool for reuse
    ///
    /// The buffer is added to the appropriate pool based on its size class and media type.
    /// If the pool is full, the least recently used buffer is evicted.
    ///
    /// - Parameters:
    ///   - buffer: Buffer to release
    ///   - capacity: Buffer capacity in bytes
    ///   - mediaType: Media type
    public func release(_ buffer: CMSampleBuffer, capacity: Int, mediaType: AVMediaType) {
        let sizeClass = BufferSizeClass.from(size: capacity)
        
        // Check if we've exceeded total memory limit
        if currentMemoryUsage + capacity > maxTotalMemory {
            evictLRUBuffer()
        }
        
        // Ensure nested dictionaries exist
        if availableBuffers[mediaType] == nil {
            availableBuffers[mediaType] = [:]
        }
        if availableBuffers[mediaType]?[sizeClass] == nil {
            availableBuffers[mediaType]?[sizeClass] = []
        }
        
        // Check size class limit
        let currentCount = availableBuffers[mediaType]?[sizeClass]?.count ?? 0
        if currentCount >= sizeClass.maxPoolSize {
            // Pool is full for this size class, evict oldest
            if var classBuffers = availableBuffers[mediaType]?[sizeClass],
               !classBuffers.isEmpty {
                let evicted = classBuffers.removeFirst()
                availableBuffers[mediaType]?[sizeClass] = classBuffers
                
                let evictedID = ObjectIdentifier(evicted as AnyObject)
                if let evictedInfo = bufferInfo[evictedID] {
                    currentMemoryUsage -= evictedInfo.capacity
                    bufferInfo.removeValue(forKey: evictedID)
                }
            }
        }
        
        // Add buffer to pool
        availableBuffers[mediaType]?[sizeClass]?.append(buffer)
        
        // Store metadata
        let bufferID = ObjectIdentifier(buffer as AnyObject)
        let now = Date()
        bufferInfo[bufferID] = PooledBufferInfo(
            capacity: capacity,
            sizeClass: sizeClass,
            mediaType: mediaType,
            createdAt: bufferInfo[bufferID]?.createdAt ?? now,
            lastUsedAt: now
        )
        
        currentMemoryUsage += capacity
        _statistics.currentPoolSize += 1
        _statistics.peakPoolSize = max(_statistics.peakPoolSize, _statistics.currentPoolSize)
    }
    
    /// Drain all buffers from the pool
    ///
    /// This method is called automatically on memory pressure warnings,
    /// or can be called manually to free all pooled buffers.
    public func drain() {
        availableBuffers.removeAll()
        bufferInfo.removeAll()
        currentMemoryUsage = 0
        _statistics.currentPoolSize = 0
        _statistics.totalDrains += 1
    }
    
    /// Get current statistics
    public var statistics: BufferPoolStatistics {
        return _statistics
    }
    
    /// Log current statistics to console
    public func logStatistics() {
        print(_statistics.description)
    }
    
    /* ============================================ */
    // MARK: - Private Methods
    /* ============================================ */
    
    /// Evict the least recently used buffer from the pool
    private func evictLRUBuffer() {
        guard !bufferInfo.isEmpty else { return }
        
        // Find oldest buffer
        let oldestID = bufferInfo.min { $0.value.lastUsedAt < $1.value.lastUsedAt }?.key
        guard let oldestID = oldestID,
              let oldestInfo = bufferInfo[oldestID] else { return }
        
        // Remove from pool
        if var classBuffers = availableBuffers[oldestInfo.mediaType]?[oldestInfo.sizeClass] {
            classBuffers.removeAll { ObjectIdentifier($0 as AnyObject) == oldestID }
            availableBuffers[oldestInfo.mediaType]?[oldestInfo.sizeClass] = classBuffers
        }
        
        currentMemoryUsage -= oldestInfo.capacity
        bufferInfo.removeValue(forKey: oldestID)
        _statistics.currentPoolSize -= 1
    }
    
    /// Setup memory pressure monitoring
    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.drain()
                print("SampleBufferPool: Drained due to memory pressure")
            }
        }
        
        source.resume()
        self.memoryPressureSource = source
    }
}

/* ============================================ */
// MARK: - Testing Support
/* ============================================ */

#if DEBUG
extension SampleBufferPool {
    /// Test-only method to get current memory usage
    public var currentMemoryUsageForTesting: Int {
        return currentMemoryUsage
    }
    
    /// Test-only method to get buffer count by type and size
    public func bufferCount(mediaType: AVMediaType, sizeClass: BufferSizeClass) -> Int {
        return availableBuffers[mediaType]?[sizeClass]?.count ?? 0
    }
}
#endif
