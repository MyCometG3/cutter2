//
//  LayoutConverter+LayoutData.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

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
        let acDescCount = count // (count > 1) ? count : 1 ; CoreMedia allows 0 length
        let acDescSize: Int = MemoryLayout<AudioChannelDescription>.size
        let acLayoutSize: Int = MemoryLayout<AudioChannelLayout>.size + (Int(acDescCount) - 1) * acDescSize
        return acLayoutSize
    }
}
