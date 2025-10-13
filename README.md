# cutter2

cutter2 is simple QuickTime movie editor - with powerful key shortcuts.

- __Requirement__: macOS 11 or later.
- __Framework__: AVFoundation (macOS native)
- __Restriction__: No autosave support.
- __Architecture__: Universal binary (x86_64 + arm64)

#### Basic feature
- Standard key shortcuts - JKL mode - like legacy QuickTime Player Pro 7
- Powerful key shortcuts - Step mode - for fine editing
- Support remux b/w mov/mp4/m4v/m4a
- Transcode to H264+AAC.mov/.mp4/m4v
- Transcode to HEVC+AAC.mov/.mp4/m4v

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
- macOS 26.0.1 Tahoe
- Xcode 26.0.1
- Swift 6.2.0

#### Code Structure

The codebase is organized into focused, maintainable modules:

**Document Layer** (7 files):
- `Document.swift` - Core document class (311 lines)
- `Document+FileIO.swift` - File I/O operations (382 lines)
- `Document+SavePanel.swift` - Save panel UI (156 lines)
- `Document+Export.swift` - Export/Transcode (177 lines)
- `Document+UI.swift` - Window/Transform UI (171 lines)
- `Document+Delegate.swift` - Delegate protocols (688 lines)
- `Document+Utilities.swift` - Utility methods (811 lines)

**Models Layer**:
- `MovieMutator.swift` - Core editing operations
- `MovieMutatorBase.swift` - Base functionality
- `MovieWriter.swift` - Export/Write operations
- `SampleBufferChannel.swift` - Sample buffer handling

**ViewControllers Layer**:
- `ViewController.swift` - Core view controller
- `WindowController.swift` - Window management
- Additional specialized view controllers

See [docs/REFACTORING_PLAN.md](docs/REFACTORING_PLAN.md) for detailed architecture information.

#### Testing

The project includes comprehensive test coverage with 6 test files:
- `cutter2Tests.swift` - Base test class
- `MovieMutatorTests.swift` - Model layer tests
- `UtilitiesTests.swift` - Utility tests
- `ActorUtilitiesTests.swift` - Actor isolation tests
- `ErrorUtilitiesTests.swift` - Error handling tests
- `ViewControllerTests.swift` - ViewController tests

To run tests:

```bash
# Run all tests
xcodebuild test -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS'

# Or use the test script with code coverage
./scripts/test.sh

# Or use Xcode
# Press ⌘U to run all tests
```

See [TESTING_GUIDE.md](docs/TESTING_GUIDE.md) for detailed testing documentation.

#### Documentation

**Architecture & Design**:
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - System architecture, design patterns, and component details
- [REFACTORING_PLAN.md](docs/REFACTORING_PLAN.md) - Code structure and refactoring history
- [CODEBASE_REVIEW.md](docs/CODEBASE_REVIEW.md) - Comprehensive codebase analysis (English)
- [CODEBASE_REVIEW_JP.md](docs/CODEBASE_REVIEW_JP.md) - コードベースレビュー（日本語）

**Development**:
- [DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md) - Development setup, workflows, and best practices
- [API_REFERENCE.md](docs/API_REFERENCE.md) - API documentation and usage examples
- [CONTRIBUTING.md](docs/CONTRIBUTING.md) - Contribution guidelines and code of conduct

**Testing**:
- [TESTING_GUIDE.md](docs/TESTING_GUIDE.md) - Testing practices and automation
- [SETUP_TEST_TARGET.md](docs/SETUP_TEST_TARGET.md) - Test environment setup (historical reference)

#### License
- The MIT License

Copyright © 2018-2025年 MyCometG3. All rights reserved.
