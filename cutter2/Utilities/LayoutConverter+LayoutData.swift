//
//  LayoutConverter+LayoutData.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import AVFoundation

extension LayoutConverter {
    
    /* ============================================ */
    // MARK: - public AudioChannelLayoutData
    /* ============================================ */
    
    /// Create AudioChannelLayoutData (copied)
    ///
    /// - Parameters:
    ///   - ptr: pointer to AudioChannelLayout
    ///   - size: length of AudioChannelLayout
    /// - Returns: Data (copied) of AudioChannelLayout
    public func dataFor(layoutBytes ptr: UnsafePointer<AudioChannelLayout>, size: Int) -> AudioChannelLayoutData {
        // "Copy" struct into Data as backing store
        //let acDescCount: Int = Int(ptr.pointee.mNumberChannelDescriptions)
        //let acLayoutSize: Int = dataSize(descCount: acDescCount)
        //precondition(size >= acLayoutSize, "Not enough space for AudioChannelLayout")
        let aclData: Data = Data.init(bytes: ptr, count: size)
        return aclData
    }
    
    /// Create AudioChannelLayoutData (copied)
    ///
    /// - Parameter ptr: pointer to AudioChannelLayout
    /// - Returns: Data (copied) of AudioChannelLayout
    public func dataFor(layoutBytes ptr: UnsafePointer<AudioChannelLayout>) -> AudioChannelLayoutData {
        // "Copy" struct into Data as backing store
        let acDescCount: Int = Int(ptr.pointee.mNumberChannelDescriptions)
        let acLayoutSize: Int = dataSize(descCount: acDescCount)
        let aclData: Data = Data.init(bytes: ptr, count: acLayoutSize)
        return aclData
    }
    
    /* ============================================ */
    // MARK: - AudioChannelLayoutData helpers
    /* ============================================ */
    
    func dataFor(tag: AudioChannelLayoutTag) -> AudioChannelLayoutData {
        precondition(tag != 0, "ERROR: AudioChannelLayoutTag must not be zero")
        precondition(tag != kAudioChannelLayoutTag_UseChannelDescriptions, "ERROR: AudioChannelLayoutTag must not be kAudioChannelLayoutTag_UseChannelDescriptions")
        precondition(tag != kAudioChannelLayoutTag_UseChannelBitmap, "ERROR: AudioChannelLayoutTag must not be kAudioChannelLayoutTag_UseChannelBitmap")
        let count: Int = dataSize(descCount: 0)
        var aclData: Data = Data.init(count: count)
        aclData.withUnsafeMutableBytes {(p: UnsafeMutableRawBufferPointer) in
            guard let baseAddress: UnsafeMutableRawPointer = p.baseAddress else { preconditionFailure("ERROR: Invalid AudioChannelLayoutData") }
            let ptr: MutableLayoutPtr = baseAddress.bindMemory(to: AudioChannelLayout.self, capacity: 1)
            ptr.pointee.mChannelLayoutTag = tag
        }
        return aclData
    }
    
    func dataFor(bitmap: AudioChannelBitmap) -> AudioChannelLayoutData {
        precondition(bitmap != [], "ERROR: AudioChannelBitmap must not be empty")
        let count: Int = dataSize(descCount: 0)
        var aclData: Data = Data.init(count: count)
        aclData.withUnsafeMutableBytes {(p: UnsafeMutableRawBufferPointer) in
            guard let baseAddress: UnsafeMutableRawPointer = p.baseAddress else { preconditionFailure("ERROR: Invalid AudioChannelLayoutData") }
            let ptr: MutableLayoutPtr = baseAddress.bindMemory(to: AudioChannelLayout.self, capacity: 1)
            ptr.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap
            ptr.pointee.mChannelBitmap = bitmap
        }
        return aclData
    }
    
    func dataFor(descriptions array: [AudioChannelDescription]) -> AudioChannelLayoutData {
        let acDescCount = array.count
        precondition(acDescCount > 0, "ERROR: AudioChannelDescription array must not be empty")
        let count: Int = dataSize(descCount: acDescCount)
        var aclData: Data = Data.init(count: count)
        aclData.withUnsafeMutableBytes {(p: UnsafeMutableRawBufferPointer) in
            guard let baseAddress: UnsafeMutableRawPointer = p.baseAddress else { preconditionFailure("ERROR: Invalid AudioChannelLayoutData") }
            let ptr: MutableLayoutPtr = baseAddress.bindMemory(to: AudioChannelLayout.self, capacity: 1)
            ptr.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
            ptr.pointee.mNumberChannelDescriptions = UInt32(acDescCount)
            let offset :UnsafeMutablePointer<AudioChannelDescription> = ptr.pointer(to: \AudioChannelLayout.mChannelDescriptions)!
            let acDescPtr = MutableDescriptionsPtr(start: offset, count: acDescCount)
            for index in 0..<acDescCount {
                acDescPtr[index] = array[index]
            }
            
            #if DEBUG
            // Debug: Log channel descriptions
            LoggingSystem.video.debug("AudioChannelLayout - Input count: \(acDescCount, privacy: .public)")
            acDescPtr.forEach { desc in
                LoggingSystem.video.debug("  Channel: label=\(desc.mChannelLabel, privacy: .public), flags=\(desc.mChannelFlags.rawValue, privacy: .public)")
            }
            let srcPos: [AudioChannelLabel] = array.map { $0.mChannelLabel }
            let dstPos: [AudioChannelLabel] = (0..<acDescCount).map { acDescPtr[$0].mChannelLabel }
            LoggingSystem.video.debug("AudioChannelLabel mapping - Input: \(srcPos), Output: \(dstPos)")
            #endif
        }
        return aclData
    }
    
    func dataSize(descCount count: Int) -> Int {
        // Negative counts have no valid interpretation here: mNumberChannelDescriptions
        // is UInt32 in the Apple SDK, so the only way to get a negative Int is a bug
        // upstream (or a future API change). The original `count > 1 ? count : 1 ;
        // CoreMedia allows 0 length` comment captured this safety intent but never
        // implemented it. Without this guard, `count = -1` returns -8 (32 + (-2) * 20)
        // which propagates as a negative size into `dataFor` and `Data.init`. Return
        // 0 so the L-04 `guard size >= acLayoutSize` rejects it gracefully and the
        // existing `if let dataSrc = dataSrc` pattern absorbs the nil.
        guard count >= 0 else { return 0 }

        let acDescSize: Int = MemoryLayout<AudioChannelDescription>.size
        if count == 0 {
            // Header-only layout (no description array). Matches CoreMedia's
            // header-only mNumberChannelDescriptions == 0 case. Without this
            // early-return the expression below would underflow to 12 via
            // `32 + (-1) * 20`, which is accidental.
            return MemoryLayout<AudioChannelLayout>.size - acDescSize
        } else {
            // structSize (header + 1 trailing mChannelDescriptions[1]) plus any
            // descriptions beyond the first.
            return MemoryLayout<AudioChannelLayout>.size + (count - 1) * acDescSize
        }
    }
}
