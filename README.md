# cutter2

cutter2 is simple QuickTime movie editor - with powerful key shortcuts.

- __Requirement__: MacOS X 10.11 or later.
- __Framework__: AVFoundation (macOS native)
- __Restriction__: No autosave support.

#### Basic feature
- Mimic key shortcuts from legacy QuickTime Player Pro 7
- Powerful key shortcuts - Step mode - for fine editing
- Support remux b/w mov/mp4/m4v/m4a
- Transcoding to H264+AAC.mov/.mp4/m4v
- Transcoding to HEVC+AAC.mov/.mp4/m4v (macOS 10.13 or later)
- Dark mode (macOS 10.14 or later)

#### Advanced feature
- Save as reference movie (AVFoundation based)
- Transcoding to ProRes422+LPCM.mov
- Custom Export can preserve original audio's channel layout.
- Custom Export can preserve original video's colr/fiel/pasp/clap atom.
- Custom Export can use H264/HEVC/ProRes422/ProRes422LT/ProRes422Proxy.
- Custom Export can use AAC-LC/LPCM-16/-24/-32.
- Customize Clean Aperture/PixelAspectRatio (macOS 10.13 or later)

#### Note: Clean Aperture/PixelAspectRatio customization
- This feature requires macOS 10.13 or later.
- It will update Video Track dimension and Media sample description.
- Customizing CleanAperture/PixelAspectRatio does not modify media data.
- Custom export keeps customized CleanAperture/PixelAspectRatio.

#### Development environment
- MacOS X 10.14.5 Mojave
- Xcode 10.2.1
- Swift 5.0.1

#### License
- The MIT License

Copyright © 2018-2019年 MyCometG3. All rights reserved.
