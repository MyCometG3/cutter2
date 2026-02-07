//
//  MovieHeaderValidator.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import AVFoundation

struct MovieHeaderValidator {
    static func isValid(_ movie: AVMutableMovie) -> Bool {
        return movie.tracks.isEmpty == false
            && CMTIME_IS_VALID(movie.duration)
            && CMTIME_IS_NUMERIC(movie.duration)
    }
}
