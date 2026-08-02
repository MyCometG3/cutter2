//
//  MovieMutatorBase+Formatting.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/04.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation
import AVFoundation

@MainActor
extension MovieMutatorBase {
    /// Timestamp generator for debug
    ///
    /// - Returns: timestamp string of local timezone
    public func ts() -> String {
        return timestampFormatter.string(from: Date())
    }
    
    /// Return string representation of CMTime
    ///
    /// - Parameters:
    ///   - time: source time
    ///   - flag: includes 3rd decimals of second.
    /// - Returns: Format in "01:02:03" or "01:02:03.004"
    public func shortTimeString(_ time: CMTime, withDecimals flag: Bool) -> String {
        var string: String = ""
        let timeInSec: Float64 = CMTimeGetSeconds(time)
        let timeInt: Int = Int(floor(timeInSec))
        let hInt: Int = Int(timeInt / 3600)
        let mInt: Int = Int(timeInt % 3600 / 60)
        let sInt: Int = Int(timeInt % 3600 % 60)
        
        if flag { // 01:02:03.004
            let fInt: Int = Int(1000.0 * (timeInSec - Float64(timeInt)))
            string = String(format:"%02i:%02i:%02i.%03i", hInt, mInt, sInt, fInt)
        } else { // 01:02:03
            string = String(format:"%02i:%02i:%02i", hInt, mInt, sInt)
        }
        return string
    }
    
    /// Return string representation of fraction from CMTime
    ///
    /// - Parameter time: source time
    /// - Returns: Format in "123456789/600"
    public func rawTimeString(_ time: CMTime) -> String {
        let value: Int = Int(time.value)
        let scale: Int = Int(time.timescale)
        let rawTimeString: String = String(format:"%9i/%i", value, scale)
        return rawTimeString
    }
    
    /// Inspector support - String representation for single CGSize
    /// - Parameter size1: CGSize
    /// - Returns: w1xh1
    @inline(__always) public func stringForOne(_ size1: CGSize) -> String {
        return String(format: "%dx%d",
                      Int(size1.width), Int(size1.height))
    }
    
    /// Inspector support - String representation for two CGSize
    /// - Parameters:
    ///   - size1: CGSize
    ///   - size2: CGSize
    /// - Returns: w1:h1(w2:h2)
    @inline(__always) public func stringForTwo(_ size1: CGSize, _ size2: CGSize) -> String {
        return String(format: "%d:%d(%d:%d)",
                      Int(size1.width), Int(size1.height),
                      Int(size2.width), Int(size2.height))
    }
    
    /// Inspector support - String representation for three CGSize
    /// - Parameters:
    ///   - size1: CGSize
    ///   - size2: CGSize
    ///   - size3: CGSize
    /// - Returns: w1:h1(w2:h2/w3:h3)
    @inline(__always) public func stringForThree(_ size1: CGSize, _ size2: CGSize, _ size3: CGSize) -> String {
        return String(format: "%d:%d(%d:%d/%d:%d)",
                      Int(size1.width), Int(size1.height),
                      Int(size2.width), Int(size2.height),
                      Int(size3.width), Int(size3.height))
    }
}
