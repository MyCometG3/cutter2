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

#### Advanced feature
- Save as reference movie (AVFoundation based)
- Transcoding to ProRes422+LPCM.mov
- Custom Export can preserve original audio's layout.
- Custom Export can preserve original video's colr/fiel/pasp/clap atom.
- Custom Export can use H264/HEVC/ProRes422/ProRes422LT/ProRes422Proxy.
- Custom Export can use AAC-LC/LPCM-16/-24/-32.
- Customize CleanApreture/PixelAspectRatio (macOS 10.13 or later)

#### Known issue about CleanApreture/PixelAspectRatio customization
- This feature requires macOS 10.13 or later.
- Customized CleanApreture/PixelAspectRatio are "temporal" (= volatile).
- Custom export supports customized CleanApreture/PixelAspectRatio.
- They will be lost on next edit operation (cut/copy/paste/delete).
- You can not save customized CleanApreture/PixelAspectRatio as CMVideoFormatDescription inside QuickTime File format.
- These restriction is confirmed at 10.13.4 High Sierra.

#### Development environment
- MacOS X 10.13.4 High Sierra
- Xcode 9.3.0
- Swift 4.1.0

#### License
- The MIT License

Copyright © 2018年 MyCometG3. All rights reserved.
