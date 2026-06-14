//
//  LayoutConverter.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/10.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

public typealias AudioChannelLayoutData = Data

/// LayoutConverter uses AudioChannelLabel as primary channel position.
public struct LayoutConverter: Sendable {
    
    public init() {}
    
    typealias LayoutPtr = UnsafePointer<AudioChannelLayout>
    typealias MutableLayoutPtr = UnsafeMutablePointer<AudioChannelLayout>
    typealias DescriptionsPtr = UnsafeBufferPointer<AudioChannelDescription>
    typealias MutableDescriptionsPtr = UnsafeMutableBufferPointer<AudioChannelDescription>
}
