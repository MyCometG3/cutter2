# cutter2

cutter2 is simple QuickTime movie editor - with powerful key shortcuts.

- __Requirement__: MacOS X 10.14 or later.
- __Framework__: AVFoundation (macOS native)
- __Restriction__: No autosave support.
- __Architecture__: Universal binary (x86_64 + arm64)

#### Basic feature
- Standard key shortcuts - JKL mode - like legacy QuickTime Player Pro 7
- Powerful key shortcuts - Step mode - for fine editing
- Support remux b/w mov/mp4/m4v/m4a
- Transcode to H264+AAC.mov/.mp4/m4v
- Transcode to HEVC+AAC.mov/.mp4/m4v
- Dark mode (macOS 10.14 or later)

#### Advanced feature
- Save as reference movie (AVFoundation based)
- Transcoding to ProRes422+LPCM.mov
- Custom Export can preserve original audio's multi-channel layout.
- Custom Export can preserve original video's colr/fiel/pasp/clap atom.
- Custom Export can use H264/HEVC/ProRes422/ProRes422LT/ProRes422Proxy.
- Custom Export can use AAC-LC/LPCM-16/-24/-32.
- Customize Clean Aperture/PixelAspectRatio

#### Note: Clean Aperture/PixelAspectRatio customization
- It will update Video Track dimension and Media sample description.
- Customizing CleanAperture/PixelAspectRatio does not modify media data.
- Custom export keeps customized CleanAperture/PixelAspectRatio.

#### Development environment
- macOS 12.6 Monterey
- Xcode 14.0
- Swift 5.7.0

#### License
- The MIT License

Copyright © 2018-2022年 MyCometG3. All rights reserved.
