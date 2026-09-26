//
//  Document+MovieReference.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import os.log

/* ============================================ */
// MARK: -  Movie Reference utility
/* ============================================ */

extension Document {
    
    /// Determines whether the document's movie is self-contained at the specified URL.
    ///
    /// A movie is considered self-contained when exactly one referenced URL exists and
    /// it matches `url`.
    ///
    /// - Parameter url: The document URL to compare with the movie's referenced URL.
    /// - Returns: `true` when the movie has exactly one matching reference URL.
    public func validateIfSelfContained(for url: URL) -> Bool {
        
        /*
         If a movie refers to one file path only and it is same as the movie's filePath,
         - the URL is the only one source of the movie
         - movie file is self-contained - no referencing track is included
         
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
