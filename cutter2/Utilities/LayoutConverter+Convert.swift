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
    
    /// Safely extracts channel label set from AudioChannelLayoutData.
    /// Returns nil if the buffer is empty or invalid.
    private func extractChannelLabelSet(from aclData: AudioChannelLayoutData) -> Set<AudioChannelLabel>? {
        var pos: Set<AudioChannelLabel>?
        aclData.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            guard let baseAddress = p.baseAddress else { return }
            // The AudioChannelLayout header occupies the first 12 bytes:
            //   mChannelLayoutTag (UInt32) + mChannelBitmap (UInt32) + mNumberChannelDescriptions (UInt32).
            // Note: MemoryLayout<AudioChannelLayout>.size is 32 on real platforms
            // (the struct includes a trailing mChannelDescriptions[1] for variable-length
            // array trick), so we use 3 * MemoryLayout<UInt32>.size to express the
            // header-only bound instead. This lets tag/bitmap layouts (12 bytes) through
            // while still rejecting undersized buffers. Matches L-04's commented-out
            // precondition in LayoutConverter+LayoutData.swift:23.
            let headerSize = 3 * MemoryLayout<UInt32>.size
            guard p.count >= headerSize else { return }
            // Peek at the tag without binding AudioChannelLayout (which would require
            // the full struct size, 32 bytes). Treat the first 12 bytes as three UInt32s.
            let tagPtr = baseAddress.assumingMemoryBound(to: AudioChannelLayoutTag.self)
            let tag = tagPtr.pointee
            // For kAudioChannelLayoutTag_UseChannelDescriptions, channelLabelSet reads
            // mNumberChannelDescriptions AudioChannelDescription values (20 bytes each
            // — Float32 label + UInt32 flags + Float32[3] coordinates) past the header.
            // Verify the buffer holds the full size before calling.
            if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
                let descCountPtr = baseAddress
                    .advanced(by: 2 * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self)
                let descCount = Int(descCountPtr.pointee)
                let requiredSize = headerSize
                    + max(0, descCount - 1) * MemoryLayout<AudioChannelDescription>.size
                guard p.count >= requiredSize else { return }
            }
            // Now safe to bind for channelLabelSet (the UseChannelDescriptions
            // branch has already verified sufficient capacity above).
            let ptr = baseAddress.bindMemory(to: AudioChannelLayout.self, capacity: 1)
            pos = channelLabelSet(ptr)
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
            let data = dataFor(tag: tag)
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
            let data = dataFor(tag: tag)
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
            let data = dataFor(bitmap: bitmap)
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
        if descs.count > 0 {
            let data = dataFor(descriptions: descs)
            return data
        } else {
            return nil
        }
    }
}
