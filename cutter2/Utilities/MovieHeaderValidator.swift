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
    
    /// Pure branch decision for the movie header validation.
    ///
    /// `trackCount == 0` wins over any duration problem, mirroring the
    /// original `validate(_ movie:)` ordering. A duration is rejected as
    /// `.invalidDuration` unless it is both valid and numeric per
    /// `CMTIME_IS_VALID` / `CMTIME_IS_NUMERIC` (i.e. any implied value —
    /// indefinite or ±infinity — is rejected).
    static func validate(trackCount: Int, duration: CMTime) -> ValidationError? {
        if trackCount == 0 {
            return .noTracks
        }
        if !CMTIME_IS_VALID(duration) || !CMTIME_IS_NUMERIC(duration) {
            return .invalidDuration
        }
        return nil
    }

    static func validate(_ movie: AVMutableMovie) -> ValidationError? {
        let tracks = movie.tracks
        if tracks.isEmpty {
            return .noTracks
        }
        return validate(trackCount: tracks.count, duration: movie.duration)
    }
    
    static func isValid(_ movie: AVMutableMovie) -> Bool {
        return validate(movie) == nil
    }
}
