# cutter2

cutter2 is a simple QuickTime movie editor with powerful keyboard shortcuts.

- **Minimum requirement**: macOS 14.0 or later
- **Framework**: AVFoundation (native macOS)
- **Restriction**: Autosave is not supported
- **Architecture**: Native macOS application; the project does not explicitly pin a universal-binary architecture set
- **Languages**: English and Japanese (日本語)

## Quick Start

1. Clone the repository and open the project:

   ```bash
   git clone https://github.com/MyCometG3/cutter2.git
   cd cutter2
   open cutter2.xcodeproj
   ```

2. In Xcode, select the `cutter2` scheme and run the application with `⌘R`.
3. Open a supported movie from the File menu.
4. Use JKL mode for playback navigation or Step mode for frame-by-frame editing.
5. Save the document or use the Export commands from the File menu.

See [`docs/DEVELOPMENT_GUIDE.md`](docs/DEVELOPMENT_GUIDE.md) for development setup and [`docs/TESTING_GUIDE.md`](docs/TESTING_GUIDE.md) for test commands.

## Basic Features

- Standard key shortcuts with JKL mode, similar to legacy QuickTime Player Pro 7
- Step mode for precise editing
- Remuxing between MOV, MP4, M4V, and M4A where supported by AVFoundation
- H.264 + AAC and HEVC + AAC transcoding to MOV, MP4, or M4V
- English/Japanese localization

## Advanced Features

- Reference movie export based on AVFoundation
- ProRes 422 + LPCM transcoding to MOV
- Custom Export support for preserving the source audio's multichannel layout
- Custom Export support for preserving the source video's `colr`, `fiel`, `pasp`, and `clap` atoms
- H.264, HEVC, ProRes 422, ProRes 422 LT, and ProRes 422 Proxy video options
- AAC-LC and LPCM 16/24/32-bit audio options
- Clean Aperture and Pixel Aspect Ratio customization

The feature list describes the implemented product surface. The current unit-test target contains no complete media-format matrix for every codec, container, and metadata-preservation combination; verify those combinations with representative media before release.

## Clean Aperture and Pixel Aspect Ratio

- Customization updates the video track dimensions and media sample description.
- Customization does not modify the encoded media data.
- Custom Export preserves the customized Clean Aperture and Pixel Aspect Ratio.

## Developer Documentation

For architecture, development, testing, concurrency, and contribution guidance, see [`docs/`](docs/):

- [`CODEBASE_REVIEW.md`](docs/CODEBASE_REVIEW.md) — source-level review and verification record
- [`ConcurrencyGuidelines.md`](docs/ConcurrencyGuidelines.md) — Swift concurrency rules
- [`DEVELOPMENT_GUIDE.md`](docs/DEVELOPMENT_GUIDE.md) — build and development workflow
- [`TESTING_GUIDE.md`](docs/TESTING_GUIDE.md) — test structure and commands
- [`CONTRIBUTING.md`](docs/CONTRIBUTING.md) — contribution workflow

## Development Environment

- **Minimum**: macOS 14.0; Xcode 16.0 or later
- **Swift language mode**: 6.0 (`SWIFT_VERSION = 6.0`)
- **Verified on 2026-08-06**: macOS 26.6 (build 25G72), Xcode 26.6 (build 17F113), Swift compiler 6.3.3

## License

- The MIT License

Copyright © 2018-2026 MyCometG3. All rights reserved.
