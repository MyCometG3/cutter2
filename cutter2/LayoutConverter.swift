//
//  LayoutConverter.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/10.
//  Copyright © 2018-2019年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

typealias AudioChannelLayoutData = Data

/// LayoutConverter uses AudioChannelLabel as primary channel position.
class LayoutConverter {
    typealias LayoutPtr = UnsafePointer<AudioChannelLayout>
    typealias MutableLayoutPtr = UnsafeMutablePointer<AudioChannelLayout>
    typealias MutableDescriptionsPtr = UnsafeMutableBufferPointer<AudioChannelDescription>

    /* ============================================ */
    // MARK: - public AudioChannelLayoutData
    /* ============================================ */
    
    /// Create AudioChannelLayoutData (copied)
    ///
    /// - Parameters:
    ///   - ptr: pointer to AudioChannelLayout
    ///   - size: length of AudioChannelLayout
    /// - Returns: Data (copied) of AudioChannelLayout
    public func dataFor(layoutBytes ptr : UnsafePointer<AudioChannelLayout>, size : Int) -> AudioChannelLayoutData {
        // "Copy" struct into Data as backing store
        //let acDescCount : Int = Int(ptr.pointee.mNumberChannelDescriptions)
        //let acLayoutSize : Int = dataSize(descCount: acDescCount)
        //assert(size >= acLayoutSize)
        let aclData : Data = Data.init(bytes: ptr, count: size)
        return aclData
    }
    
    /// Create AudioChannelLayoutData (copied)
    ///
    /// - Parameter ptr: pointer to AudioChannelLayout
    /// - Returns: Data (copied) of AudioChannelLayout
    public func dataFor(layoutBytes ptr : UnsafePointer<AudioChannelLayout>) -> AudioChannelLayoutData {
        // "Copy" struct into Data as backing store
        let acDescCount : Int = Int(ptr.pointee.mNumberChannelDescriptions)
        let acLayoutSize : Int = dataSize(descCount: acDescCount)
        let aclData : Data = Data.init(bytes: ptr, count: acLayoutSize)
        return aclData
    }
    
    /* ============================================ */
    // MARK: - private AudioChannelLayoutData
    /* ============================================ */

    private func dataFor(tag : AudioChannelLayoutTag) -> AudioChannelLayoutData {
        assert(tag != 0)
        assert(tag != kAudioChannelLayoutTag_UseChannelDescriptions)
        assert(tag != kAudioChannelLayoutTag_UseChannelBitmap)
        let count : Int = dataSize(descCount: 0)
        var aclData : Data = Data.init(count: count)
        aclData.withUnsafeMutableBytes({(p : UnsafeMutableRawBufferPointer) in
            let ptr : MutableLayoutPtr =
                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count)
            ptr.pointee.mChannelLayoutTag = tag
        })
        return aclData
    }
    
    private func dataFor(bitmap : AudioChannelBitmap) -> AudioChannelLayoutData {
        assert(bitmap != [])
        let count : Int = dataSize(descCount: 0)
        var aclData : Data = Data.init(count: count)
        aclData.withUnsafeMutableBytes({(p : UnsafeMutableRawBufferPointer) in
            let ptr : MutableLayoutPtr =
                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count)
            ptr.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap
            ptr.pointee.mChannelBitmap = bitmap
        })
        return aclData
    }
    
    private func dataFor(desciptions array :[AudioChannelDescription]) -> AudioChannelLayoutData {
        let acDescCount = array.count
        assert(acDescCount > 0)
        let count : Int = dataSize(descCount: acDescCount)
        var aclData : Data = Data.init(count: count)
        aclData.withUnsafeMutableBytes({(p : UnsafeMutableRawBufferPointer) in
            let ptr : MutableLayoutPtr =
                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count)
            ptr.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
            ptr.pointee.mNumberChannelDescriptions = UInt32(acDescCount)
            withUnsafeMutablePointer(to: &(ptr.pointee.mChannelDescriptions)) {offset in
                let descPtr = MutableDescriptionsPtr(start: offset, count: acDescCount)
                for index in 0..<acDescCount {
                    descPtr[index] = array[index]
                }
            }
        })
        return aclData
    }
    
    private func dataSize(descCount count : Int) -> Int {
        let acDescCount = count // (count > 1) ? count : 1 ; CoreMedia allows 0 length
        let acDescSize : Int = MemoryLayout<AudioChannelDescription>.size
        let acLayoutSize : Int = MemoryLayout<AudioChannelLayout>.size + (Int(acDescCount) - 1) * acDescSize
        return acLayoutSize
    }
    
    /* ============================================ */
    // MARK: - public Converter
    /* ============================================ */

    /// Try to translate AudioChannelLayoutData with kAudioChannelLayoutTag_AAC_*
    ///
    /// - Parameter aclData: AudioChannelLayoutData
    /// - Returns: AudioChannelLayoutData
    public func convertAsAACTag(from aclData : AudioChannelLayoutData) -> AudioChannelLayoutData? {
        var pos : Set<AudioChannelLabel>!
        let count : Int = aclData.count
        aclData.withUnsafeBytes({ (p : UnsafeRawBufferPointer) in
            let ptr : LayoutPtr =
                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count)
            pos = channelLabelSet(ptr)
        })
        var tag : AudioChannelLayoutTag = channelLayoutTagAACForChannelLabelSet(pos, true)
        if tag == kAudioChannelLayoutTag_Unknown {
            let tag1 = channelLayoutTagAACForChannelLabelSet(pos, false)
            tag = tag1
        }
        if tag != kAudioChannelLayoutTag_Unknown {
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
    public func convertAsPCMTag(from aclData : AudioChannelLayoutData) -> AudioChannelLayoutData? {
        var pos : Set<AudioChannelLabel>!
        let count : Int = aclData.count
        aclData.withUnsafeBytes({ (p : UnsafeRawBufferPointer) in
            let ptr : LayoutPtr =
                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count)
            pos = channelLabelSet(ptr)
        })
        let tag : AudioChannelLayoutTag = channelLayoutTagLPCMForChannelLabelSet(pos)
        if tag != kAudioChannelLayoutTag_Unknown {
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
    public func convertAsBitmap(from aclData : AudioChannelLayoutData) -> AudioChannelLayoutData? {
        var pos : Set<AudioChannelLabel>!
        let count : Int = aclData.count
        aclData.withUnsafeBytes({ (p : UnsafeRawBufferPointer) in
            let ptr : LayoutPtr =
                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count)
            pos = channelLabelSet(ptr)
        })
        let bitmap : AudioChannelBitmap = channelBitmapForChannelLabelSet(pos)
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
    public func convertAsDescriptions(from aclData : AudioChannelLayoutData) -> AudioChannelLayoutData? {
        var pos : Set<AudioChannelLabel>!
        let count : Int = aclData.count
        aclData.withUnsafeBytes({ (p : UnsafeRawBufferPointer) in
            let ptr : LayoutPtr =
                p.baseAddress!.bindMemory(to: AudioChannelLayout.self, capacity: count)
            pos = channelLabelSet(ptr)
        })
        let descs : [AudioChannelDescription] = channelDescriptionsForChannelLabelSet(pos)
        if descs.count > 0 {
            let data = dataFor(desciptions: descs)
            return data
        } else {
            return nil
        }
    }
    
    /* ============================================ */
    // MARK: - private Converter
    /* ============================================ */

    private func channelLabelSet(_ layoutPtr : LayoutPtr) -> Set<AudioChannelLabel> {
        let layout : AudioChannelLayout = layoutPtr.pointee
        // AudioChannelLayoutTag = UInt32
        // AudioChannelBitmap = OptionSet(UInt32)
        // AudioChannelLabel = UInt32
        var pos : Set<AudioChannelLabel> = []
        let tag : AudioChannelLayoutTag = layout.mChannelLayoutTag
        
        switch tag {
        case kAudioChannelLayoutTag_UseChannelBitmap:
            // translate ChannelBitmap to AudioChannelLabel Set
            let bitmap : AudioChannelBitmap = layout.mChannelBitmap
            if bitmap.contains(.bit_Left)                   { pos.insert(kAudioChannelLabel_Left) }
            if bitmap.contains(.bit_Right)                  { pos.insert(kAudioChannelLabel_Right) }
            if bitmap.contains(.bit_Center)                 { pos.insert(kAudioChannelLabel_Center) }
            if bitmap.contains(.bit_LFEScreen)              { pos.insert(kAudioChannelLabel_LFEScreen) }
            if bitmap.contains(.bit_LeftSurround)           { pos.insert(kAudioChannelLabel_LeftSurround) }
            if bitmap.contains(.bit_RightSurround)          { pos.insert(kAudioChannelLabel_RightSurround) }
            if bitmap.contains(.bit_LeftCenter)             { pos.insert(kAudioChannelLabel_LeftCenter) }
            if bitmap.contains(.bit_RightCenter)            { pos.insert(kAudioChannelLabel_RightCenter) }
            if bitmap.contains(.bit_CenterSurround)         { pos.insert(kAudioChannelLabel_CenterSurround) }
            if bitmap.contains(.bit_LeftSurroundDirect)     { pos.insert(kAudioChannelLabel_LeftSurroundDirect) }
            if bitmap.contains(.bit_RightSurroundDirect)    { pos.insert(kAudioChannelLabel_RightSurroundDirect) }
            if bitmap.contains(.bit_TopCenterSurround)      { pos.insert(kAudioChannelLabel_TopCenterSurround) }
            if bitmap.contains(.bit_VerticalHeightLeft)     { pos.insert(kAudioChannelLabel_VerticalHeightLeft) }
            if bitmap.contains(.bit_VerticalHeightCenter)   { pos.insert(kAudioChannelLabel_VerticalHeightCenter) }
            if bitmap.contains(.bit_VerticalHeightRight)    { pos.insert(kAudioChannelLabel_VerticalHeightRight) }
            if bitmap.contains(.bit_TopBackLeft)            { pos.insert(kAudioChannelLabel_TopBackLeft) }
            if bitmap.contains(.bit_TopBackCenter)          { pos.insert(kAudioChannelLabel_TopBackCenter) }
            if bitmap.contains(.bit_TopBackRight)           { pos.insert(kAudioChannelLabel_TopBackRight) }
            
            if bitmap.contains(.bit_LeftTopMiddle)          { pos.insert(kAudioChannelLabel_LeftTopMiddle) }
            if bitmap.contains(.bit_RightTopMiddle)         { pos.insert(kAudioChannelLabel_RightTopMiddle) }
            if bitmap.contains(.bit_LeftTopRear)            { pos.insert(kAudioChannelLabel_LeftTopRear) }
            if bitmap.contains(.bit_CenterTopRear)          { pos.insert(kAudioChannelLabel_CenterTopRear) }
            if bitmap.contains(.bit_RightTopRear)           { pos.insert(kAudioChannelLabel_RightTopRear) }
        case kAudioChannelLayoutTag_UseChannelDescriptions:
            // translate Channel Description(s) to AudioChannelLabel Set
            let unsupported : [AudioChannelLabel] = [kAudioChannelLabel_Unused,
                                                     kAudioChannelLabel_Unknown,
                                                     kAudioChannelLabel_UseCoordinates]
            let acDescCount = Int(layout.mNumberChannelDescriptions)
            var acLayout = layout
            withUnsafeMutablePointer(to: &(acLayout.mChannelDescriptions)) {offset in
                let acDescPtr = MutableDescriptionsPtr(start: offset, count: acDescCount)
                for desc in acDescPtr {
                    let label : AudioChannelLabel = desc.mChannelLabel
                    if false == unsupported.contains(label) {
                        pos.insert(label)
                    }
                }
            }
        default:
            // translate Channel Layout Tag to AudioChannelLabel Set
            switch layout.mChannelLayoutTag {
            case kAudioChannelLayoutTag_Mono:           pos = [3] // 42 is more better?
            case kAudioChannelLayoutTag_Stereo:         pos = [1,2]
            case kAudioChannelLayoutTag_StereoHeadphones:   pos = [301,302]
            case kAudioChannelLayoutTag_MatrixStereo:   pos = [38,39]
            case kAudioChannelLayoutTag_MidSide:        pos = [204,205]
            case kAudioChannelLayoutTag_XY:             pos = [206,207]
            case kAudioChannelLayoutTag_Binaural:       pos = [208,209]
            case kAudioChannelLayoutTag_Ambisonic_B_Format: pos = [200,201,202,203] // vertical
            case kAudioChannelLayoutTag_Quadraphonic:   pos = [1,2,5,6]
            case kAudioChannelLayoutTag_Pentagonal:     pos = [1,2,5,6,3]
            case kAudioChannelLayoutTag_Hexagonal:      pos = [1,2,5,6,3,9]
            case kAudioChannelLayoutTag_Octagonal:      pos = [1,2,5,6,3,9,35,36]
            case kAudioChannelLayoutTag_Cube:           pos = [1,2,33,34,13,15,16,18] // vertical
                
            case kAudioChannelLayoutTag_MPEG_3_0_A:     pos = [1,2,3]
            case kAudioChannelLayoutTag_MPEG_3_0_B:     pos = [3,1,2]
            case kAudioChannelLayoutTag_MPEG_4_0_A:     pos = [1,2,3,9]
            case kAudioChannelLayoutTag_MPEG_4_0_B:     pos = [3,1,2,9]
            case kAudioChannelLayoutTag_MPEG_5_0_A:     pos = [1,2,3,5,6]
            case kAudioChannelLayoutTag_MPEG_5_0_B:     pos = [1,2,5,6,3]
            case kAudioChannelLayoutTag_MPEG_5_0_C:     pos = [1,3,2,5,6]
            case kAudioChannelLayoutTag_MPEG_5_0_D:     pos = [3,1,2,5,6]
            case kAudioChannelLayoutTag_MPEG_5_1_A:     pos = [1,2,3,4,5,6]
            case kAudioChannelLayoutTag_MPEG_5_1_B:     pos = [1,2,5,6,3,4]
            case kAudioChannelLayoutTag_MPEG_5_1_C:     pos = [1,3,2,5,6,4]
            case kAudioChannelLayoutTag_MPEG_5_1_D:     pos = [3,1,2,5,6,4]
            case kAudioChannelLayoutTag_MPEG_6_1_A:     pos = [1,2,3,4,5,6,9]
            case kAudioChannelLayoutTag_MPEG_7_1_A:     pos = [1,2,3,4,5,6,7,8]
            case kAudioChannelLayoutTag_MPEG_7_1_B:     pos = [3,7,8,1,2,5,6,4]
            case kAudioChannelLayoutTag_MPEG_7_1_C:     pos = [1,2,3,4,5,6,33,34]
            case kAudioChannelLayoutTag_Emagic_Default_7_1: pos = [1,2,5,6,3,4,7,8]
            case kAudioChannelLayoutTag_SMPTE_DTV:      pos = [1,2,3,4,5,6,38,39]
                
            case kAudioChannelLayoutTag_ITU_2_1 :       pos = [1,2,9]
            case kAudioChannelLayoutTag_ITU_2_2:        pos = [1,2,5,6]
                
            case kAudioChannelLayoutTag_DVD_4:          pos = [1,2,4]
            case kAudioChannelLayoutTag_DVD_5:          pos = [1,2,4,9]
            case kAudioChannelLayoutTag_DVD_6:          pos = [1,2,4,5,6]
            case kAudioChannelLayoutTag_DVD_10:         pos = [1,2,3,4]
            case kAudioChannelLayoutTag_DVD_11:         pos = [1,2,3,4,9]
            case kAudioChannelLayoutTag_DVD_18:         pos = [1,2,5,6,4]
                
            case kAudioChannelLayoutTag_AudioUnit_6_0:  pos = [1,2,5,6,3,9]
            case kAudioChannelLayoutTag_AudioUnit_7_0:  pos = [1,2,5,6,3,33,34]
            case kAudioChannelLayoutTag_AudioUnit_7_0_Front:    pos = [1,2,5,6,3,7,8]
                
            case kAudioChannelLayoutTag_AAC_6_0:        pos = [3,1,2,5,6,9]
            case kAudioChannelLayoutTag_AAC_6_1:        pos = [3,1,2,5,6,9,4]
            case kAudioChannelLayoutTag_AAC_7_0:        pos = [3,1,2,5,6,33,34]
            case kAudioChannelLayoutTag_AAC_7_1_B:      pos = [3,1,2,5,6,33,34,4]
            case kAudioChannelLayoutTag_AAC_7_1_C:      pos = [3,1,2,5,6,4,13,15] // vertical
            case kAudioChannelLayoutTag_AAC_Octagonal:  pos = [3,1,2,5,6,33,34,9]
                
            //case kAudioChannelLayoutTag_TMH_10_2_std:   pos = [1,2,3,14,10,11,5,6,13,15,35,36,44,9,??,37]
            //case kAudioChannelLayoutTag_TMH_10_2_full:  pos = [1,2,3,14,10,11,5,6,13,15,35,36,44,9,??,37,7,8,40,??,45]
            // NOTE: Missing value: LFE1. LFE1 is LFELeft, and LFE2 is LFERight
            //       Missing value: VI.
                
            case kAudioChannelLayoutTag_AC3_1_0_1:      pos = [3,4]
            case kAudioChannelLayoutTag_AC3_3_0:        pos = [1,3,2]
            case kAudioChannelLayoutTag_AC3_3_1:        pos = [1,3,2,9]
            case kAudioChannelLayoutTag_AC3_3_0_1:      pos = [1,3,2,4]
            case kAudioChannelLayoutTag_AC3_2_1_1:      pos = [1,2,9,4]
            case kAudioChannelLayoutTag_AC3_3_1_1:      pos = [1,3,2,9,4]
                
            case kAudioChannelLayoutTag_EAC_6_0_A:      pos = [1,3,2,5,6,9]
            case kAudioChannelLayoutTag_EAC_7_0_A:      pos = [1,3,2,5,6,33,34]
            case kAudioChannelLayoutTag_EAC3_6_1_A:     pos = [1,3,2,5,6,4,9]
            case kAudioChannelLayoutTag_EAC3_6_1_B:     pos = [1,3,2,5,6,4,12]
            case kAudioChannelLayoutTag_EAC3_6_1_C:     pos = [1,3,2,5,6,4,14]
            case kAudioChannelLayoutTag_EAC3_7_1_A:     pos = [1,3,2,5,6,4,33,34]
            case kAudioChannelLayoutTag_EAC3_7_1_B:     pos = [1,3,2,5,6,4,7,8]
            case kAudioChannelLayoutTag_EAC3_7_1_C:     pos = [1,3,2,5,6,4,10,11]
            case kAudioChannelLayoutTag_EAC3_7_1_D:     pos = [1,3,2,5,6,4,35,36]
            case kAudioChannelLayoutTag_EAC3_7_1_E:     pos = [1,3,2,5,6,4,13,15]
            case kAudioChannelLayoutTag_EAC3_7_1_F:     pos = [1,3,2,5,6,4,9,12]
            case kAudioChannelLayoutTag_EAC3_7_1_G:     pos = [1,3,2,5,6,4,9,14]
            case kAudioChannelLayoutTag_EAC3_7_1_H:     pos = [1,3,2,5,6,4,12,14]
                
            case kAudioChannelLayoutTag_DTS_3_1:        pos = [3,1,2,4]
            case kAudioChannelLayoutTag_DTS_4_1:        pos = [3,1,2,9,4]
            case kAudioChannelLayoutTag_DTS_6_0_A:      pos = [7,8,1,2,5,6]
            case kAudioChannelLayoutTag_DTS_6_0_B:      pos = [3,1,2,33,34,12]
            case kAudioChannelLayoutTag_DTS_6_0_C:      pos = [3,9,1,2,33,34]
            case kAudioChannelLayoutTag_DTS_6_1_A:      pos = [7,8,1,2,5,6,4]
            case kAudioChannelLayoutTag_DTS_6_1_B:      pos = [3,1,2,33,34,12,4]
            case kAudioChannelLayoutTag_DTS_6_1_C:      pos = [3,9,1,2,33,34,4]
            case kAudioChannelLayoutTag_DTS_7_0:        pos = [7,3,8,1,2,5,6]
            case kAudioChannelLayoutTag_DTS_7_1:        pos = [7,3,8,1,2,5,6,4]
            case kAudioChannelLayoutTag_DTS_8_0_A:      pos = [7,8,1,2,5,6,33,34]
            case kAudioChannelLayoutTag_DTS_8_0_B:      pos = [7,3,8,1,2,5,9,6]
            case kAudioChannelLayoutTag_DTS_8_1_A:      pos = [7,8,1,2,5,6,33,34,4]
            case kAudioChannelLayoutTag_DTS_8_1_B:      pos = [7,3,8,1,2,5,9,6,4]
            case kAudioChannelLayoutTag_DTS_6_1_D:      pos = [3,1,2,5,6,4,9]
                
            case kAudioChannelLayoutTag_WAVE_4_0_B:     pos = [1,2,33,34]
            case kAudioChannelLayoutTag_WAVE_5_0_B:     pos = [1,2,3,33,34]
            case kAudioChannelLayoutTag_WAVE_5_1_B:     pos = [1,2,3,4,33,34]
            case kAudioChannelLayoutTag_WAVE_6_1:       pos = [1,2,3,4,9,5,6]
            case kAudioChannelLayoutTag_WAVE_7_1:       pos = [1,2,3,4,33,34,5,6]
                
            //case kAudioChannelLayoutTag_HOA_ACN_SN3D:   pos = [??]
            // needs to be ORed with the actual number of channels (not the HOA order)
            //case kAudioChannelLayoutTag_HOA_ACN_N3D:    pos = [??]
            // needs to be ORed with the actual number of channels (not the HOA order)
                
            case kAudioChannelLayoutTag_Atmos_7_1_4:    pos = [1,2,3,4,5,6,33,34,13,15,52,54]
            case kAudioChannelLayoutTag_Atmos_9_1_6:    pos = [1,2,3,4,5,6,33,34,35,36,13,15,49,51,52,54]
            case kAudioChannelLayoutTag_Atmos_5_1_2:    pos = [1,2,3,4,5,6,52,54]
                
            //case kAudioChannelLayoutTag_DiscreteInOrder:  pos = [??]
            // needs to be ORed with the actual number of channels
                
            //case kAudioChannelLayoutTag_Unknown:        pos = [??]
                // needs to be ORed with the actual number of channels

            default:
                break
            }
        }
        return pos
    }
    
    private func channelLayoutTagAACForChannelLabelSet(_ pos : Set<AudioChannelLabel>, _ strict : Bool) -> AudioChannelLayoutTag {
        switch pos {
        case [42]:                  return kAudioChannelLayoutTag_Mono
        case [3]:                   return kAudioChannelLayoutTag_Mono
        case [1,2]:                 return kAudioChannelLayoutTag_Stereo
        case [3,1,2]:               return kAudioChannelLayoutTag_AAC_3_0
        case [1,2,5,6]:             return kAudioChannelLayoutTag_AAC_Quadraphonic
        case [3,1,2,9]:             return kAudioChannelLayoutTag_AAC_4_0
        case [3,1,2,5,6]:           return kAudioChannelLayoutTag_AAC_5_0
        case [3,1,2,5,6,4]:         return kAudioChannelLayoutTag_AAC_5_1
        case [3,1,2,5,6,9]:         return kAudioChannelLayoutTag_AAC_6_0
        case [3,1,2,5,6,9,4]:       return kAudioChannelLayoutTag_AAC_6_1
        case [3,1,2,5,6,33,34]:     return kAudioChannelLayoutTag_AAC_7_0
        case [3,7,8,1,2,5,6,4]:     return kAudioChannelLayoutTag_AAC_7_1
        case [3,1,2,5,6,33,34,4]:   return kAudioChannelLayoutTag_AAC_7_1_B
        case [3,1,2,5,6,4,13,15]:   return kAudioChannelLayoutTag_AAC_7_1_C // vertical
        case [3,1,2,5,6,33,34,9]:   return kAudioChannelLayoutTag_AAC_Octagonal
        default:
            break
        }
        if strict {
            return kAudioChannelLayoutTag_Unknown
        } else {
            return channelLayoutTagAACForChannelLabelSetFallback(pos)
        }
    }
    
    private func channelLayoutTagAACForChannelLabelSetFallback(_ pos : Set<AudioChannelLabel>) -> AudioChannelLayoutTag {
        switch pos {
        case [301,302]:                 return kAudioChannelLayoutTag_Stereo
        case [38,39]:                   return kAudioChannelLayoutTag_Stereo
        case [204,205]:                 return kAudioChannelLayoutTag_Stereo
        case [206,207]:                 return kAudioChannelLayoutTag_Stereo
        case [208,209]:                 return kAudioChannelLayoutTag_Stereo
        case [200,201,202,203]:         return kAudioChannelLayoutTag_AAC_7_1_C // vertical
        case [1,2,5,6,3,9,35,36]:       return kAudioChannelLayoutTag_AAC_Octagonal // horizontal
        case [1,2,33,34,13,15,16,18]:   return kAudioChannelLayoutTag_AAC_7_1_C // vertical
        
        case [1,2,3,4,5,6,38,39]:       return kAudioChannelLayoutTag_AAC_Octagonal // horizontal
        
        case [1,2,9]:                   return kAudioChannelLayoutTag_AAC_4_0
        
        case [1,2,4]:                   return kAudioChannelLayoutTag_AAC_5_1
        case [1,2,4,9]:                 return kAudioChannelLayoutTag_AAC_6_1
        case [1,2,4,5,6]:               return kAudioChannelLayoutTag_AAC_5_1
        case [1,2,3,4]:                 return kAudioChannelLayoutTag_AAC_5_1
        case [1,2,3,4,9]:               return kAudioChannelLayoutTag_AAC_6_1
        
        case [1,2,5,6,3,7,8]:           return kAudioChannelLayoutTag_AAC_Octagonal // horizontal
        
        default:
            let verticalSet = Set<AudioChannelLabel>(12...18)
            let hasVertical : Bool = (pos.intersection(verticalSet).count > 0)
            if hasVertical {
                return kAudioChannelLayoutTag_AAC_7_1_C // vertical
            } else {
                return kAudioChannelLayoutTag_AAC_Octagonal // horizontal
            }
        }
    }
    
    private func channelLayoutTagLPCMForChannelLabelSet(_ pos : Set<AudioChannelLabel>) -> AudioChannelLayoutTag {
        switch pos {
        case [42]:                      return kAudioChannelLayoutTag_Mono
        case [3]:                       return kAudioChannelLayoutTag_Mono
        case [1,2]:                     return kAudioChannelLayoutTag_Stereo
        case [301,302]:                 return kAudioChannelLayoutTag_StereoHeadphones
        case [38,39]:                   return kAudioChannelLayoutTag_MatrixStereo
        case [204,205]:                 return kAudioChannelLayoutTag_MidSide
        case [206,207]:                 return kAudioChannelLayoutTag_XY
        case [208,209]:                 return kAudioChannelLayoutTag_Binaural
        case [200,201,202,203]:         return kAudioChannelLayoutTag_Ambisonic_B_Format
        case [1,2,5,6]:                 return kAudioChannelLayoutTag_Quadraphonic
        case [1,2,5,6,3]:               return kAudioChannelLayoutTag_Pentagonal
        case [1,2,5,6,3,9]:             return kAudioChannelLayoutTag_Hexagonal
        case [1,2,5,6,3,9,35,36]:       return kAudioChannelLayoutTag_Octagonal
        case [1,2,33,34,13,15,16,18]:   return kAudioChannelLayoutTag_Cube
            
        case [1,2,3]:                   return kAudioChannelLayoutTag_MPEG_3_0_A
        case [3,1,2]:                   return kAudioChannelLayoutTag_MPEG_3_0_B
        case [1,2,3,9]:                 return kAudioChannelLayoutTag_MPEG_4_0_A
        case [3,1,2,9]:                 return kAudioChannelLayoutTag_MPEG_4_0_B
        case [1,2,3,5,6]:               return kAudioChannelLayoutTag_MPEG_5_0_A
        case [1,2,5,6,3]:               return kAudioChannelLayoutTag_MPEG_5_0_B
        case [1,3,2,5,6]:               return kAudioChannelLayoutTag_MPEG_5_0_C
        case [3,1,2,5,6]:               return kAudioChannelLayoutTag_MPEG_5_0_D
        case [1,2,3,4,5,6]:             return kAudioChannelLayoutTag_MPEG_5_1_A
        case [1,2,5,6,3,4]:             return kAudioChannelLayoutTag_MPEG_5_1_B
        case [1,3,2,5,6,4]:             return kAudioChannelLayoutTag_MPEG_5_1_C
        case [3,1,2,5,6,4]:             return kAudioChannelLayoutTag_MPEG_5_1_D
        case [1,2,3,4,5,6,9]:           return kAudioChannelLayoutTag_MPEG_6_1_A
        case [1,2,3,4,5,6,7,8]:         return kAudioChannelLayoutTag_MPEG_7_1_A
        case [3,7,8,1,2,5,6,4]:         return kAudioChannelLayoutTag_MPEG_7_1_B
        case [1,2,3,4,5,6,33,34]:       return kAudioChannelLayoutTag_MPEG_7_1_C
        case [1,2,5,6,3,4,7,8]:         return kAudioChannelLayoutTag_Emagic_Default_7_1
        case [1,2,3,4,5,6,38,39]:       return kAudioChannelLayoutTag_SMPTE_DTV
            
        case [1,2,9]:                   return kAudioChannelLayoutTag_ITU_2_1
        case [1,2,5,6]:                 return kAudioChannelLayoutTag_ITU_2_2
            
        case [1,2,4]:                   return kAudioChannelLayoutTag_DVD_4
        case [1,2,4,9]:                 return kAudioChannelLayoutTag_DVD_5
        case [1,2,4,5,6]:               return kAudioChannelLayoutTag_DVD_6
        case [1,2,3,4]:                 return kAudioChannelLayoutTag_DVD_10
        case [1,2,3,4,9]:               return kAudioChannelLayoutTag_DVD_11
        case [1,2,5,6,4]:               return kAudioChannelLayoutTag_DVD_18
            
        case [1,2,5,6,3,9]:             return kAudioChannelLayoutTag_AudioUnit_6_0
        case [1,2,5,6,3,33,34]:         return kAudioChannelLayoutTag_AudioUnit_7_0
        case [1,2,5,6,3,7,8]:           return kAudioChannelLayoutTag_AudioUnit_7_0_Front
            
        case [3,1,2,5,6,9]:             return kAudioChannelLayoutTag_AAC_6_0
        case [3,1,2,5,6,9,4]:           return kAudioChannelLayoutTag_AAC_6_1
        case [3,1,2,5,6,33,34]:         return kAudioChannelLayoutTag_AAC_7_0
        case [3,1,2,5,6,33,34,4]:       return kAudioChannelLayoutTag_AAC_7_1_B
        case [3,1,2,5,6,4,13,15]:       return kAudioChannelLayoutTag_AAC_7_1_C
        case [3,1,2,5,6,33,34,9]:       return kAudioChannelLayoutTag_AAC_Octagonal
            
        // kAudioChannelLayoutTag_TMH_10_2_std
        // kAudioChannelLayoutTag_TMH_10_2_full
        // NOTE: Missing value: LFE1. LFE1 is LFELeft, and LFE2 is LFERight
        //       Missing value: VI.

        case [3,4]:                     return kAudioChannelLayoutTag_AC3_1_0_1
        case [1,3,2]:                   return kAudioChannelLayoutTag_AC3_3_0
        case [1,3,2,9]:                 return kAudioChannelLayoutTag_AC3_3_1
        case [1,3,2,4]:                 return kAudioChannelLayoutTag_AC3_3_0_1
        case [1,2,9,4]:                 return kAudioChannelLayoutTag_AC3_2_1_1
        case [1,3,2,9,4]:               return kAudioChannelLayoutTag_AC3_3_1_1
            
        case [1,3,2,5,6,9]:             return kAudioChannelLayoutTag_EAC_6_0_A
        case [1,3,2,5,6,33,34]:         return kAudioChannelLayoutTag_EAC_7_0_A
        case [1,3,2,5,6,4,9]:           return kAudioChannelLayoutTag_EAC3_6_1_A
        case [1,3,2,5,6,4,12]:          return kAudioChannelLayoutTag_EAC3_6_1_B
        case [1,3,2,5,6,4,14]:          return kAudioChannelLayoutTag_EAC3_6_1_C
        case [1,3,2,5,6,4,33,34]:       return kAudioChannelLayoutTag_EAC3_7_1_A
        case [1,3,2,5,6,4,7,8]:         return kAudioChannelLayoutTag_EAC3_7_1_B
        case [1,3,2,5,6,4,10,11]:       return kAudioChannelLayoutTag_EAC3_7_1_C
        case [1,3,2,5,6,4,35,36]:       return kAudioChannelLayoutTag_EAC3_7_1_D
        case [1,3,2,5,6,4,13,15]:       return kAudioChannelLayoutTag_EAC3_7_1_E
        case [1,3,2,5,6,4,9,12]:        return kAudioChannelLayoutTag_EAC3_7_1_F
        case [1,3,2,5,6,4,9,14]:        return kAudioChannelLayoutTag_EAC3_7_1_G
        case [1,3,2,5,6,4,12,14]:       return kAudioChannelLayoutTag_EAC3_7_1_H
            
        case [3,1,2,4]:                 return kAudioChannelLayoutTag_DTS_3_1
        case [3,1,2,9,4]:               return kAudioChannelLayoutTag_DTS_4_1
        case [7,8,1,2,5,6]:             return kAudioChannelLayoutTag_DTS_6_0_A
        case [3,1,2,33,34,12]:          return kAudioChannelLayoutTag_DTS_6_0_B
        case [3,9,1,2,33,34]:           return kAudioChannelLayoutTag_DTS_6_0_C
        case [7,8,1,2,5,6,4]:           return kAudioChannelLayoutTag_DTS_6_1_A
        case [3,1,2,33,34,12,4]:        return kAudioChannelLayoutTag_DTS_6_1_B
        case [3,9,1,2,33,34,4]:         return kAudioChannelLayoutTag_DTS_6_1_C
        case [7,3,8,1,2,5,6]:           return kAudioChannelLayoutTag_DTS_7_0
        case [7,3,8,1,2,5,6,4]:         return kAudioChannelLayoutTag_DTS_7_1
        case [7,8,1,2,5,6,33,34]:       return kAudioChannelLayoutTag_DTS_8_0_A
        case [7,3,8,1,2,5,9,6]:         return kAudioChannelLayoutTag_DTS_8_0_B
        case [7,8,1,2,5,6,33,34,4]:     return kAudioChannelLayoutTag_DTS_8_1_A
        case [7,3,8,1,2,5,9,6,4]:       return kAudioChannelLayoutTag_DTS_8_1_B
        case [3,1,2,5,6,4,9]:           return kAudioChannelLayoutTag_DTS_6_1_D
        case [1,2,33,34]:               return kAudioChannelLayoutTag_WAVE_4_0_B
        case [1,2,3,33,34]:             return kAudioChannelLayoutTag_WAVE_5_0_B
        case [1,2,3,4,33,34]:           return kAudioChannelLayoutTag_WAVE_5_1_B
        case [1,2,3,4,9,5,6]:           return kAudioChannelLayoutTag_WAVE_6_1
        case [1,2,3,4,33,34,5,6]:       return kAudioChannelLayoutTag_WAVE_7_1
            
        // kAudioChannelLayoutTag_HOA_ACN_SN3D
        // needs to be ORed with the actual number of channels (not the HOA order)
        // kAudioChannelLayoutTag_HOA_ACN_N3D
        // needs to be ORed with the actual number of channels (not the HOA order)

        case [1,2,3,4,5,6,33,34,13,15,52,54]:   return kAudioChannelLayoutTag_Atmos_7_1_4
        case [1,2,3,4,5,6,33,34,35,36,13,15,49,51,52,54]:   return kAudioChannelLayoutTag_Atmos_9_1_6
        case [1,2,3,4,5,6,52,54]:       return kAudioChannelLayoutTag_Atmos_5_1_2
            
        //kAudioChannelLayoutTag_DiscreteInOrder
        // needs to be ORed with the actual number of channels

        default:                        return kAudioChannelLayoutTag_Unknown
        // needs to be ORed with the actual number of channels
        }
    }
    
    private func channelBitmapForChannelLabelSet(_ pos : Set<AudioChannelLabel>) -> AudioChannelBitmap {
        var bitmap : AudioChannelBitmap = []
        if pos.contains(kAudioChannelLabel_Left)                {bitmap.insert(.bit_Left)}
        if pos.contains(kAudioChannelLabel_Right)               {bitmap.insert(.bit_Right)}
        if pos.contains(kAudioChannelLabel_Center)              {bitmap.insert(.bit_Center)}
        if pos.contains(kAudioChannelLabel_LFEScreen)           {bitmap.insert(.bit_LFEScreen)}
        if pos.contains(kAudioChannelLabel_LeftSurround)        {bitmap.insert(.bit_LeftSurround)}
        if pos.contains(kAudioChannelLabel_RightSurround)       {bitmap.insert(.bit_RightSurround)}
        if pos.contains(kAudioChannelLabel_LeftCenter)          {bitmap.insert(.bit_LeftCenter)}
        if pos.contains(kAudioChannelLabel_RightCenter)         {bitmap.insert(.bit_RightCenter)}
        if pos.contains(kAudioChannelLabel_CenterSurround)      {bitmap.insert(.bit_CenterSurround)}
        if pos.contains(kAudioChannelLabel_LeftSurroundDirect)  {bitmap.insert(.bit_LeftSurroundDirect)}
        if pos.contains(kAudioChannelLabel_RightSurroundDirect) {bitmap.insert(.bit_RightSurroundDirect)}
        if pos.contains(kAudioChannelLabel_TopCenterSurround)   {bitmap.insert(.bit_TopCenterSurround)}
        if pos.contains(kAudioChannelLabel_VerticalHeightLeft)  {bitmap.insert(.bit_VerticalHeightLeft)}
        if pos.contains(kAudioChannelLabel_VerticalHeightCenter)    {bitmap.insert(.bit_VerticalHeightCenter)}
        if pos.contains(kAudioChannelLabel_VerticalHeightRight) {bitmap.insert(.bit_VerticalHeightRight)}
        if pos.contains(kAudioChannelLabel_TopBackLeft)         {bitmap.insert(.bit_TopBackLeft)}
        if pos.contains(kAudioChannelLabel_TopBackCenter)       {bitmap.insert(.bit_TopBackCenter)}
        if pos.contains(kAudioChannelLabel_TopBackRight)        {bitmap.insert(.bit_TopBackRight)}
        
        if pos.contains(kAudioChannelLabel_LeftTopMiddle)       {bitmap.insert(.bit_LeftTopMiddle)}
        if pos.contains(kAudioChannelLabel_RightTopMiddle)      {bitmap.insert(.bit_RightTopMiddle)}
        if pos.contains(kAudioChannelLabel_LeftTopRear)         {bitmap.insert(.bit_LeftTopRear)}
        if pos.contains(kAudioChannelLabel_CenterTopRear)       {bitmap.insert(.bit_CenterTopRear)}
        if pos.contains(kAudioChannelLabel_RightTopRear)        {bitmap.insert(.bit_RightTopRear)}
        return bitmap
    }
    
    private func channelDescriptionsForChannelLabelSet(_ pos : Set<AudioChannelLabel>) -> [AudioChannelDescription] {
        var descArray : [AudioChannelDescription] = []
        for label in pos {
            let desc = AudioChannelDescription(mChannelLabel: label,
                                               mChannelFlags: [],
                                               mCoordinates: (0.0,0.0,0.0))
            descArray.append(desc)
        }
        return descArray
    }
}
