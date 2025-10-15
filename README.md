# cutter2

cutter2 is simple QuickTime movie editor - with powerful key shortcuts.

- __Requirement__: macOS 11 or later.
- __Framework__: AVFoundation (macOS native)
- __Restriction__: No autosave support.
- __Architecture__: Universal binary (x86_64 + arm64)
- __Languages__: English, Japanese (日本語) ✨ **NEW**

#### Basic feature
- Standard key shortcuts - JKL mode - like legacy QuickTime Player Pro 7
- Powerful key shortcuts - Step mode - for fine editing
- Support remux b/w mov/mp4/m4v/m4a
- Transcode to H264+AAC.mov/.mp4/m4v
- Transcode to HEVC+AAC.mov/.mp4/m4v
- Full internationalization support (English/Japanese) ✨ **NEW**

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

**Development environment**
- macOS 26.0.1 Tahoe
- Xcode 26.0.1
- Swift 6.2.0

**Internationalization** ✨ **COMPLETE (Phase 2.1)**:
- **String Catalogs (.xcstrings)**: 229 localized keys (55 code + 174 storyboard)
- **Supported languages**: English, Japanese (日本語)
- **LocalizationHelper** utility for easy localization
- **All user-facing strings localized**: Error messages, UI labels, menus, dialogs
- **Storyboard localization**: All menu items and UI elements in Japanese ✨ **NEW**
- **Comprehensive tests**: 11 localization tests (100% pass rate)
- See [LOCALIZATION_COMPLETE.md](docs/LOCALIZATION_COMPLETE.md) for details

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

The project includes comprehensive test coverage with 7 test files and 60 tests:
- `cutter2Tests.swift` - Base test class
- `MovieMutatorTests.swift` - Model layer tests
- `ModelTests.swift` - Additional model tests
- `DocumentTests.swift` - Document tests
- `UtilitiesTests.swift` - Utility tests
- `ViewControllerTests.swift` - ViewController tests
- `LocalizationTests.swift` - Localization tests (11 tests) ✨ **NEW**

**Test Results**: ✅ 60/60 tests passing (100%)

To run tests:

```bash
# Run all tests
xcodebuild test -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS'

# Run specific test class
xcodebuild test -project cutter2.xcodeproj -scheme cutter2 -destination 'platform=macOS' -only-testing:cutter2Tests/LocalizationTests

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

**Localization** ✅ **Phase 2.1 Complete**:
- [LOCALIZATION_PLAN.md](docs/LOCALIZATION_PLAN.md) - Localization implementation plan
- [LOCALIZATION_COMPLETE.md](docs/LOCALIZATION_COMPLETE.md) - Phase 2.1 completion summary

**Performance** 📋 **Phase 2.2 Planning**:
- [PERFORMANCE_ANALYSIS.md](docs/PERFORMANCE_ANALYSIS.md) - Performance analysis and optimization opportunities
- [PERFORMANCE_OPTIMIZATION_PLAN.md](docs/PERFORMANCE_OPTIMIZATION_PLAN.md) - Detailed implementation plan for Phase 2.2

#### License
- The MIT License

Copyright © 2018-2025年 MyCometG3. All rights reserved.
