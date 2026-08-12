//
//  AVMutableMovie+Extensions.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/04.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation
import AVFoundation

extension AVMutableMovie {
    /// Movie timeRange (union of all track range)
    ///
    /// NOTE: See MovieMutator.refreshMovie()
    public var range: CMTimeRange {
        var range: CMTimeRange = CMTimeRange.zero
        for track: AVMutableMovieTrack in self.tracks {
            range = CMTimeRangeGetUnion(range, otherRange: track.timeRange)
        }
        return range
    }
    
    /// Get movie Header in mov format. nil returned in case of any error.
    public var movHeader: Data? {
        let headerData: Data? = try? self.makeMovieHeader(fileType: .mov)
        return headerData
    }
    
    /// Analyze movHeader bytes for embedded 'url ' atoms and return any referenced URLs. Returns nil if no URLs can be parsed.
    public func findReferenceURLs() -> [URL]? {
        if let data = self.movHeader {
            // Two-stage size guard:
            //   Stage 1 (header): pattern match + atom-size header (4 bytes) needs data.count >= 12.
            //   Stage 2 (full):   url body needs data.count >= 8 + 5 + 0 (atomSize >= 13).
            let pattern: [UInt8] = [0x75, 0x72, 0x6C, 0x20, 0x00, 0x00, 0x00, 0x00] // 'url ', 0x00 * 4
            let headerSize: Int = pattern.count + 4 // pattern(8) + atomSizeHeader(4)
            guard data.count >= headerSize + 5 else { return nil }
            let start: Int = 4 // ptr[n-4..n-1] needs n >= 4
            let end: Int = data.count - pattern.count
            var set: Set<URL> = []
            data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                for n in start..<end {
                    // search pattern
                    if ptr[n] != pattern[0] {
                        continue
                    }
                    // validate pattern
                    var valid: Bool = true
                    for offset in 0..<(pattern.count) {
                        if ptr[n + offset] != pattern[offset] {
                            valid = false
                            break
                        }
                    }
                    if valid { // found file url
                        // get atom size
                        let s4 = Int(ptr[n - 4])
                        let s3 = Int(ptr[n - 3])
                        let s2 = Int(ptr[n - 2])
                        let s1 = Int(ptr[n - 1])
                        let atomSize: Int = (s4 << 24) | (s3 << 16) | (s2 << 8) | s1
                        guard atomSize >= 13 else { continue }
                        let urlStart = n + 8
                        let urlEnd = n + atomSize - 5
                        guard urlEnd <= data.count, urlStart <= urlEnd else { continue }
                        // let atomPtr = ptr.advanced(by: n)
                        
                        // heading(8):0x75726C20,0x00000000; trailing(5):0x00????????
                        let urlData: Data = data.subdata(in: urlStart..<urlEnd)
                        guard let urlPath = String(data: urlData, encoding: String.Encoding.utf8) else { continue }
                        if let url = URL(string: urlPath) {
                            set.insert(url)
                        }
                    }
                }
            }
            
            if set.count > 0 {
                return Array(set)
            }
        }
        return nil
    }
}
