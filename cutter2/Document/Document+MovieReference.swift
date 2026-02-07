//
//  Document+MovieReference.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: -  Movie Reference utility
/* ============================================ */

extension Document {
    
    public func validateIfSelfContained(for url: URL) -> Bool {
        
        /*
         If a movie refers to one file path only and it is same as the movie's filePath,
         - the URL is the only one source of the movie
         - movie file is self-containd - no referencing track is included
         
         In case of in-memory movie (no-file-backed) it should be a reference movie.
         In case of multiple url found it should be a reference movie.
         */
        let refURLs: [URL] = self.movieMutator?.queryMediaDataURLs() ?? []
        if refURLs.count == 1 && refURLs[0] == url {
            return true
        }
        //
        if refURLs.count < 1 {
            LoggingSystem.video.error("Unable to get track reference URLs")
        }
        if refURLs.count == 1 {
            LoggingSystem.video.info("Different track reference URL found")
        }
        if refURLs.count > 1 {
            LoggingSystem.video.info("Multiple track reference URLs found")
        }
        return false
    }
}
