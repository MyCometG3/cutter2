//
//  MovieHeaderValidator.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/02/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import AVFoundation

struct MovieHeaderValidator {

    enum ValidationError: LocalizedError {
        case noTracks
        case invalidDuration

        var errorDescription: String? {
            switch self {
            case .noTracks:
                return "This file does not contain any movie tracks."
            case .invalidDuration:
                return "The movie file appears to be corrupted (invalid duration)."
            }
        }
    }

    static func validate(_ movie: AVMutableMovie) -> ValidationError? {
        if movie.tracks.isEmpty {
            return .noTracks
        }
        if !CMTIME_IS_VALID(movie.duration) || !CMTIME_IS_NUMERIC(movie.duration) {
            return .invalidDuration
        }
        return nil
    }

    static func isValid(_ movie: AVMutableMovie) -> Bool {
        return validate(movie) == nil
    }
}
