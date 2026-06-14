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
            // Defensive: ensure the buffer holds at least the AudioChannelLayout
            // header (12 bytes) before reading tag / bitmap / description count.
            guard p.count >= MemoryLayout<AudioChannelLayout>.size else { return }
            let ptr = baseAddress.bindMemory(to: AudioChannelLayout.self, capacity: 1)
            // For kAudioChannelLayoutTag_UseChannelDescriptions, channelLabelSet reads
            // `mNumberChannelDescriptions` AudioChannelDescription values (8 bytes each)
            // past the header. Verify the buffer holds the full size before calling,
            // matching the L-04 intent of the commented-out precondition
            // LayoutConverter+LayoutData.swift:23 (precondition(size >= acLayoutSize)).
            let header = ptr.pointee
            if header.mChannelLayoutTag == kAudioChannelLayoutTag_UseChannelDescriptions {
                let descCount = Int(header.mNumberChannelDescriptions)
                let requiredSize = MemoryLayout<AudioChannelLayout>.size
                    + max(0, descCount - 1) * MemoryLayout<AudioChannelDescription>.size
                guard p.count >= requiredSize else { return }
            }
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
