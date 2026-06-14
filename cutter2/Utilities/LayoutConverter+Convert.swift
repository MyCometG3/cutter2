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
            // Discover layout at runtime: do not hardcode any offset or size, so
            // the helper adapts to struct definition changes (e.g. Apple adding
            // fields, changing padding, or redefining alignment on a future
            // platform).
            let descSize = MemoryLayout<AudioChannelDescription>.size
            let structSize = MemoryLayout<AudioChannelLayout>.size
            // bindMemory with capacity 1 requires structSize contiguous bytes
            // for the header read; channelLabelSet will bind the same way, so a
            // single guard covers both.
            guard p.count >= structSize else { return }
            let headerPtr = baseAddress.bindMemory(to: AudioChannelLayout.self, capacity: 1)
            let tag = headerPtr.pointee.mChannelLayoutTag
            let descCount = Int(headerPtr.pointee.mNumberChannelDescriptions)
            // For UseChannelDescriptions, channelLabelSet walks descCount
            // AudioChannelDescription values past the header. The first slot is
            // already covered by structSize (the trailing mChannelDescriptions[1]
            // inside AudioChannelLayout), so we only need to add (descCount - 1)
            // more. For other tags, channelLabelSet only touches the header fields
            // and structSize is sufficient.
            let requiredSize: Int
            if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
                // A UseChannelDescriptions tag with descCount == 0 is malformed
                // (the tag promises a description array but declares it empty);
                // reject up front to avoid a redundant 0-size check below.
                guard descCount > 0 else { return }
                requiredSize = structSize + (descCount - 1) * descSize
            } else {
                requiredSize = structSize
            }
            guard p.count >= requiredSize else { return }
            pos = channelLabelSet(headerPtr)
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
