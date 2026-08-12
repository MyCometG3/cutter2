//
//  LayoutConverter+Convert.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

extension LayoutConverter {
    
    /* ============================================ */
    // MARK: - private helpers
    /* ============================================ */
    
    private typealias AudioChannelLayoutHeader = (
        tag: AudioChannelLayoutTag,
        bitmap: AudioChannelBitmap,
        descCount: Int
    )
    
    /// Reads an integer-like header field from potentially unaligned Data bytes.
    private func loadHeaderValue<T>(_ type: T.Type, from baseAddress: UnsafeRawPointer, offset: Int) -> T {
        baseAddress.loadUnaligned(fromByteOffset: offset, as: T.self)
    }
    
    /// Reads only the fixed-size AudioChannelLayout header from raw bytes.
    ///
    /// CoreMedia may provide tag-only AudioChannelLayout buffers that contain
    /// just the 12-byte header, so this helper intentionally reads only the
    /// header fields and leaves full-layout validation to the caller.
    private func extractChannelLayoutHeader(from aclData: AudioChannelLayoutData) -> AudioChannelLayoutHeader? {
        let tagOffset = MemoryLayout<AudioChannelLayout>.offset(of: \AudioChannelLayout.mChannelLayoutTag)!
        let bitmapOffset = MemoryLayout<AudioChannelLayout>.offset(of: \AudioChannelLayout.mChannelBitmap)!
        let countOffset = MemoryLayout<AudioChannelLayout>.offset(of: \AudioChannelLayout.mNumberChannelDescriptions)!
        let headerSize = countOffset + MemoryLayout<UInt32>.size
        
        return aclData.withUnsafeBytes { rawBuffer in
            guard rawBuffer.count >= headerSize else { return nil }
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            
            let tag = loadHeaderValue(AudioChannelLayoutTag.self, from: baseAddress, offset: tagOffset)
            let bitmap = loadHeaderValue(AudioChannelBitmap.self, from: baseAddress, offset: bitmapOffset)
            let descCount = loadHeaderValue(UInt32.self, from: baseAddress, offset: countOffset)
            
            return (tag, bitmap, Int(descCount))
        }
    }
    
    /// Safely extracts channel label set from AudioChannelLayoutData.
    ///
    /// Tag-only / bitmap layouts require only the fixed-size header, while
    /// UseChannelDescriptions layouts must provide the full trailing array.
    /// Returns nil if the buffer is empty or structurally invalid.
    private func extractChannelLabelSet(from aclData: AudioChannelLayoutData) -> Set<AudioChannelLabel>? {
        var pos: Set<AudioChannelLabel>?
        
        guard let header = extractChannelLayoutHeader(from: aclData) else { return nil }
        
        let requiredSize: Int
        if header.tag == kAudioChannelLayoutTag_UseChannelDescriptions {
            guard header.descCount > 0 else { return nil }
            requiredSize = dataSize(descCount: header.descCount)
        } else {
            requiredSize = dataSize(descCount: 0)
        }
        guard requiredSize > 0 else { return nil }
        
        aclData.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            guard p.count >= requiredSize, let baseAddress = p.baseAddress else { return }
            
            switch header.tag {
            case kAudioChannelLayoutTag_UseChannelBitmap:
                pos = channelLabelSet(forBitmap: header.bitmap)
            case kAudioChannelLayoutTag_UseChannelDescriptions:
                let alignedStorage = UnsafeMutableRawPointer.allocate(
                    byteCount: requiredSize,
                    alignment: MemoryLayout<AudioChannelLayout>.alignment
                )
                defer { alignedStorage.deallocate() }
                memcpy(alignedStorage, baseAddress, requiredSize)
                let layoutPtr = alignedStorage.bindMemory(to: AudioChannelLayout.self, capacity: 1)
                pos = channelLabelSet(forDescriptions: layoutPtr, count: header.descCount)
            default:
                pos = channelLabelSet(forTag: header.tag)
            }
        }
        return pos
    }
    
    /* ============================================ */
    // MARK: - public Converter
    /* ============================================ */
    
    /// Try to translate AudioChannelLayoutData with kAudioChannelLayoutTag_AAC_*
    ///
    /// - Parameter aclData: AudioChannelLayoutData
    /// - Returns: AudioChannelLayoutData
    public func convertAsAACTag(from aclData: AudioChannelLayoutData) -> AudioChannelLayoutData? {
        guard let pos = extractChannelLabelSet(from: aclData) else { return nil }
        var tag: AudioChannelLayoutTag = channelLayoutTagAACForChannelLabelSet(pos, true)
        if (tag & 0xFFFF0000) == kAudioChannelLayoutTag_Unknown {
            let tag1 = channelLayoutTagAACForChannelLabelSet(pos, false)
            tag = tag1
        }
        if (tag & 0xFFFF0000) != kAudioChannelLayoutTag_Unknown {
            guard let data = dataFor(tag: tag) else { return nil }
            return data
        } else {
            return nil
        }
    }
    
    /// Try to translate AudioChannelLayoutData with kAudioChannelLayoutTag_*
    ///
    /// - Parameter aclData: AudioChannelLayoutData
    /// - Returns: AudioChannelLayoutData
    public func convertAsPCMTag(from aclData: AudioChannelLayoutData) -> AudioChannelLayoutData? {
        guard let pos = extractChannelLabelSet(from: aclData) else { return nil }
        let tag: AudioChannelLayoutTag = channelLayoutTagLPCMForChannelLabelSet(pos)
        if (tag & 0xFFFF0000) != kAudioChannelLayoutTag_Unknown {
            guard let data = dataFor(tag: tag) else { return nil }
            return data
        } else {
            return nil
        }
    }
    
    /// Try to translate AudioChannelLayoutData with AudioChannelBitmap
    ///
    /// - Parameter aclData: AudioChannelLayoutData
    /// - Returns: AudioChannelLayoutData
    public func convertAsBitmap(from aclData: AudioChannelLayoutData) -> AudioChannelLayoutData? {
        guard let pos = extractChannelLabelSet(from: aclData) else { return nil }
        let bitmap: AudioChannelBitmap = channelBitmapForChannelLabelSet(pos)
        if bitmap != [] {
            guard let data = dataFor(bitmap: bitmap) else { return nil }
            return data
        } else {
            return nil
        }
    }
    
    /// Try to translate AudioChannelLayoutData with AudioChannelDescriptions
    ///
    /// - Parameter aclData: AudioChannelLayoutData
    /// - Returns: AudioChannelLayoutData
    public func convertAsDescriptions(from aclData: AudioChannelLayoutData) -> AudioChannelLayoutData? {
        guard let pos = extractChannelLabelSet(from: aclData) else { return nil }
        let descs: [AudioChannelDescription] = channelDescriptionsForChannelLabelSet(pos)
        if !descs.isEmpty {
            guard let data = dataFor(descriptions: descs) else { return nil }
            return data
        } else {
            return nil
        }
    }
}
