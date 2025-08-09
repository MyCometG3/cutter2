# cutter2 - macOS Video Editor

cutter2 is a native macOS QuickTime movie editor with powerful keyboard shortcuts, built using Swift and AVFoundation framework. It provides professional video editing capabilities with JKL mode shortcuts and advanced transcoding features.

**ALWAYS reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Platform Requirements & Critical Limitations

**CRITICAL**: This application can ONLY be built and run on macOS. Do not attempt to build on Linux or Windows.

### Required Development Environment
- **macOS 15.5 Sequoia or later** (recommended)
- **Xcode 16.4 or later** 
- **Swift 6.1.2 or later**
- **macOS 11+ deployment target** (minimum runtime requirement)

### Architecture Support
- Universal binary (x86_64 + arm64)
- Native macOS frameworks: Cocoa, AVFoundation, AVKit, VideoToolbox

## Working Effectively

### NEVER CANCEL Build Operations
**CRITICAL**: Build operations may take 10-15 minutes on slower machines. NEVER CANCEL builds or long-running operations. Set timeouts to 30+ minutes for all build commands.

### Building the Application
```bash
# Open project in Xcode (required - no command line alternative)
open cutter2.xcodeproj

# Command line build (if Xcode Command Line Tools installed)
xcodebuild -project cutter2.xcodeproj -scheme cutter2 -configuration Debug build
# Expected time: 5-15 minutes. NEVER CANCEL. Set timeout to 30+ minutes.

# Release build
xcodebuild -project cutter2.xcodeproj -scheme cutter2 -configuration Release build  
# Expected time: 5-15 minutes. NEVER CANCEL. Set timeout to 30+ minutes.

# Clean build (when needed)
xcodebuild -project cutter2.xcodeproj -scheme cutter2 clean
# Expected time: 1-2 minutes.
```

### Running the Application
```bash
# After building, run from Xcode or:
open build/Release/cutter2.app

# Debug build location:
open build/Debug/cutter2.app
```

### Development Workflow
- **ALWAYS build and test** your changes before committing
- **Use Xcode for development** - this is not a command-line application
- **Test with actual video files** - supports .mov, .mp4, .m4v, .m4a formats
- **No autosave support** - users must manually save their work

## Testing & Validation

### Manual Validation Requirements
After making any changes, you MUST test these core scenarios:

1. **File Opening Test**:
   - Open a .mov or .mp4 file
   - Verify the video loads and displays correctly
   - Test playback controls (play/pause/stop)

2. **Keyboard Shortcuts Test**:
   - Test JKL mode shortcuts (J=reverse, K=pause, L=forward)
   - Test Step mode shortcuts for fine editing
   - Verify timeline navigation works

3. **Export Functionality Test**:
   - Open a video file
   - Use "Save As" to export as reference movie
   - Test transcode to H264+AAC format
   - Verify exported file plays correctly

4. **UI Components Test**:
   - Test Inspector panel functionality
   - Test Transcode settings panel
   - Test CAPAR (Clean Aperture/Pixel Aspect Ratio) controls

### No Automated Tests
- This project does not include unit tests or automated test infrastructure
- All validation must be done manually through the application UI
- Focus on real user workflows rather than isolated component testing

## Codebase Navigation

### Core Architecture (9,518 total lines of Swift)

#### Main Application Components
- **AppDelegate.swift** (218 lines) - Application lifecycle, bookmark management
- **Document.swift** (1,023 lines) - Core document model, movie handling
- **DocumentController.swift** (120 lines) - Document management
- **ViewController.swift** (988 lines) - Main window controller, UI coordination

#### Video Processing Engine
- **MovieMutator.swift** (990 lines) - Core video editing operations
- **MovieMutatorBase.swift** (910 lines) - Base video processing functionality  
- **MovieWriter.swift** (1,273 lines) - Video export and transcoding
- **SampleBufferChannel.swift** (103 lines) - Low-level video processing

#### UI Controllers
- **TimelineView.swift** (719 lines) - Video timeline UI component
- **TranscodeViewController.swift** (130 lines) - Export settings UI
- **InspectorViewController.swift** (101 lines) - Properties panel
- **CAPARViewController.swift** (448 lines) - Clean Aperture/Pixel Aspect Ratio settings
- **AccessoryViewController.swift** (139 lines) - Additional UI controls

#### Utilities
- **Document+Delegate.swift** (688 lines) - Document delegation patterns
- **Document+Utilities.swift** (778 lines) - Document helper functions
- **LayoutConverter.swift** (641 lines) - Video layout conversion utilities
- **Constants.swift** (123 lines) - Application constants and user defaults keys

#### UI Resources
- **Main.storyboard** - Interface Builder file for UI layout
- **Assets.xcassets** - App icons and image assets
- **Info.plist** - Application configuration and file type associations

### Key Development Patterns

#### Code Organization
- Files use `// MARK:` comments extensively for organization
- Clear separation between public and private methods
- Actor isolation annotations for Swift concurrency

#### Supported File Types
- Input: .mov, .mp4, .m4v, .m4a
- Output: H264+AAC, HEVC+AAC, ProRes422+LPCM variants
- Reference movies (AVFoundation-based, no media duplication)

#### Critical Dependencies
```swift
import Cocoa          // macOS UI framework
import AVFoundation   // Core video/audio processing
import AVKit          // Video player components  
import VideoToolbox   // Hardware video acceleration
```

## Common Development Tasks

### Making Code Changes
1. Open `cutter2.xcodeproj` in Xcode
2. Navigate using the file structure above
3. Key files for common tasks:
   - **Video editing logic**: MovieMutator.swift, MovieMutatorBase.swift
   - **Export functionality**: MovieWriter.swift, TranscodeViewController.swift
   - **UI changes**: ViewController.swift, TimelineView.swift
   - **File handling**: Document.swift, Document+Utilities.swift

### Adding New Features
- **Video effects**: Modify MovieMutator classes
- **Export formats**: Update MovieWriter.swift and TranscodeViewController.swift
- **Keyboard shortcuts**: Update ViewController.swift
- **UI panels**: Create new view controllers following existing patterns

### Debugging Common Issues
- **Build failures**: Usually require Xcode-specific settings or macOS SDKs
- **Video import issues**: Check Document.swift file type handling
- **Export problems**: Examine MovieWriter.swift error handling
- **UI layout issues**: Use Xcode Interface Builder with Main.storyboard

## Project Structure Reference

```
cutter2/
├── .github/
│   └── copilot-instructions.md
├── cutter2/                     # Source code directory
│   ├── *.swift                  # 24 Swift source files
│   ├── Base.lproj/
│   │   └── Main.storyboard     # UI layout
│   ├── Assets.xcassets/        # App icons and images  
│   ├── Info.plist             # App configuration
│   └── cutter2.entitlements   # Sandbox permissions
├── cutter2.xcodeproj/          # Xcode project
│   └── project.pbxproj        # Project configuration
├── README.md                   # Project documentation
├── LICENSE.txt                 # MIT License
├── Keyboard Shortcut.pdf       # User documentation
└── .gitignore                 # Git ignore patterns
```

### Build Configuration
- **Bundle ID**: com.mycometg3.cutter2
- **Development Team**: BV5C4YNA4Z
- **Current Version**: 0.8.9 (build 20250611)
- **Deployment Target**: Latest recommended macOS version
- **Architectures**: Universal (x86_64 + arm64)

## Limitations & Workarounds

### Cannot Build on Non-macOS Systems
- **No Linux/Windows support**: This is a macOS-native application
- **Requires Xcode**: Cannot use Swift Package Manager or other build systems
- **Native framework dependencies**: AVFoundation, Cocoa are macOS-only

### No Automated Testing Infrastructure
- **Manual testing required**: No unit tests or automated test suite
- **UI testing**: Must be done through actual application interaction
- **Regression testing**: Maintain manual test scenarios for core functionality

### Development Environment Constraints
- **Xcode required**: Cannot effectively develop without Xcode IDE
- **macOS SDKs required**: Uses macOS-specific APIs throughout
- **Code signing**: May require Apple Developer account for distribution

Always validate changes through complete user scenarios rather than isolated testing. The application's core value is in its video editing workflow, so focus testing on real-world usage patterns.