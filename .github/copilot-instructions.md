# cutter2 - QuickTime Movie Editor

cutter2 is a simple yet powerful QuickTime movie editor for macOS with advanced keyboard shortcuts. It's built with Swift 6.0, AVFoundation, and requires Xcode for development.

**ALWAYS reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## CRITICAL: macOS Development Environment Only

**THIS PROJECT CANNOT BE BUILT OR RUN ON LINUX/WINDOWS**
- Requires macOS 11 or later
- Requires Xcode 16.4 or later
- Uses AVFoundation framework (macOS-only)
- No cross-platform build system available

## Working Effectively

### Prerequisites - REQUIRED
- macOS 11+ (Sequoia 15.5+ recommended)
- Xcode 16.4+ with Swift 6.1.2+
- Sufficient disk space for video files during testing

### Build Process
- **NEVER CANCEL**: Build takes 2-5 minutes depending on machine. Set timeout to 10+ minutes.
- Open project: `open cutter2.xcodeproj` in Finder or Xcode
- Build for testing: `xcodebuild -project cutter2.xcodeproj -scheme cutter2 -configuration Debug build`
- Build for release: `xcodebuild -project cutter2.xcodeproj -scheme cutter2 -configuration Release build`
- Clean build: `xcodebuild -project cutter2.xcodeproj -scheme cutter2 clean`

### Running the Application
- **Development**: Run directly from Xcode (⌘R)
- **Built app**: Launch from `DerivedData/cutter2/Build/Products/Debug/cutter2.app` or equivalent Release path
- **Alternative**: Archive and export from Xcode for distribution
- **NEVER CANCEL**: App startup may take 10-30 seconds depending on system permissions

### Project Structure - NO EXTERNAL DEPENDENCIES
- Pure Xcode project (.xcodeproj) - no Swift Package Manager, no CocoaPods, no Carthage
- Single target: cutter2 (Universal binary: x86_64 + arm64)
- Swift 6.0 with strict concurrency enabled
- Current version: 0.8.9 (build 20250611)

## Validation and Testing

### Manual Testing Requirements
**CRITICAL**: There are NO automated tests. All validation must be manual.

**ALWAYS perform these validation steps after making changes:**

1. **Basic App Launch**:
   - Launch app and verify it opens without crashes
   - Check console for errors or warnings

2. **Video File Handling**:
   - Test with .mov, .mp4, .m4v, .m4a files
   - Verify file opening through File > Open or drag-and-drop
   - Test supported formats: H264, HEVC, various audio codecs

3. **Core Editing Operations**:
   - Load a test video file
   - Test timeline scrubbing and playback controls
   - Test selection/trimming operations
   - Verify keyboard shortcuts work (especially JKL mode)

4. **Export/Transcode Testing**:
   - Test reference movie saving
   - Test transcode to H264+AAC
   - Test transcode to HEVC+AAC  
   - Test ProRes422+LPCM export (advanced feature)

### Required Test Files
- Keep sample video files in multiple formats for testing
- Test files should include: .mov, .mp4, .m4v, .m4a
- Include files with different codecs: H264, HEVC, ProRes

### Performance Expectations
- **NEVER CANCEL**: Video processing may take 5-60+ minutes depending on file size and transcode settings
- **Export operations**: Can take 30+ minutes for large files. Set timeout to 90+ minutes.
- **NEVER CANCEL**: Reference movie operations may appear to hang but are processing in background

## Navigation and Code Structure

### Key Source Files (by importance)
- `Document.swift` (1,023 lines) - Core document model, file operations
- `ViewController.swift` (988 lines) - Main window controller, playback UI
- `MovieWriter.swift` (1,273 lines) - Export/transcode engine
- `MovieMutator.swift` (990 lines) - Edit operations, undo/redo
- `MovieMutatorBase.swift` (910 lines) - Base editing functionality  
- `TimelineView.swift` (719 lines) - Timeline UI and scrubbing
- `Document+Utilities.swift` (778 lines) - Helper methods for Document
- `Document+Delegate.swift` (688 lines) - Document delegate methods

### UI Controllers
- `TranscodeViewController.swift` - Export settings panel
- `InspectorViewController.swift` - Media property inspector
- `CAPARViewController.swift` - Clean Aperture/Pixel Aspect Ratio editor
- `AccessoryViewController.swift` - Additional UI accessories
- `WindowController.swift` - Window management

### Core Components
- `AppDelegate.swift` - App lifecycle, bookmarks management
- `DocumentController.swift` - Document creation/management
- `LayoutConverter.swift` - Video layout conversions
- `SampleBufferChannel.swift` - Audio/video pipeline
- `MyPlayerView.swift` - AVKit player view wrapper
- `Constants.swift` - User defaults keys and constants

### Important Configuration Files
- `Info.plist` - App metadata, supported file types
- `cutter2.entitlements` - Sandboxing permissions (file bookmarks)
- `Assets.xcassets` - App icons and resources
- `Main.storyboard` - UI layout (in Base.lproj/)

## Common Development Tasks

### Adding New Features
- **UI Changes**: Modify `Main.storyboard` and corresponding view controllers
- **Video Processing**: Extend `MovieWriter.swift` or `MovieMutator.swift`
- **File Format Support**: Update `Info.plist` CFBundleDocumentTypes
- **Keyboard Shortcuts**: Check `ViewController.swift` key handling methods

### Debugging Video Issues
- Enable detailed logging in `AppDelegate.swift` (set `useLog = true`)
- Check AVFoundation error codes in console
- Verify video codec compatibility in `MovieWriter.swift`
- **Known Issue**: Rate change warning in `Document+Utilities.swift` line 542 with "FIXME!"
- **Note**: Swift Concurrency incompatibility mentioned in `Document.swift` line 369
- **Audio Channel Mapping**: Check `LayoutConverter.swift` for LFE channel handling notes

### Code Quality Guidelines
- Swift 6.0 strict concurrency is enabled - respect @MainActor annotations
- Use `performSyncOnMainActor()` helper methods for cross-actor calls
- Follow existing error handling patterns (DocumentError, MovieWriterError)
- Maintain Universal Binary compatibility (x86_64 + arm64)

## Features and Capabilities

### Basic Features
- Standard JKL keyboard shortcuts (like QuickTime Player Pro 7)
- Step mode for fine editing
- Support for mov/mp4/m4v/m4a remuxing
- H264+AAC and HEVC+AAC transcoding

### Advanced Features
- Reference movie saving (AVFoundation-based)
- ProRes422+LPCM transcoding
- Multi-channel audio layout preservation
- Video metadata preservation (colr/fiel/pasp/clap atoms)
- Custom Clean Aperture/PixelAspectRatio editing
- Support for H264/HEVC/ProRes422/ProRes422LT/ProRes422Proxy
- Audio codec support: AAC-LC/LPCM-16/-24/-32

### Keyboard Shortcuts
- Refer to `Keyboard Shortcut.pdf` for complete reference (72KB PDF file in repo root)
- JKL mode: J (reverse), K (pause), L (forward) - like QuickTime Player Pro 7
- Step mode: Precise frame-by-frame editing
- See `ViewController.swift` for implementation details
- **Note**: Most key event handlers are in `ViewController.swift`, not `TimelineView.swift`

## Limitations and Restrictions
- **No autosave support** (documented restriction)
- **macOS 11+ only** - no backwards compatibility
- **No automated tests** - manual validation required
- **No CI/CD pipeline** - manual builds only
- **AVFoundation dependency** - macOS native framework only

## Common Commands Reference

### Repository Structure
```
.
├── README.md
├── LICENSE.txt
├── Keyboard Shortcut.pdf
├── .gitignore
├── cutter2.xcodeproj/
│   └── project.pbxproj
└── cutter2/                    # Main source directory
    ├── Info.plist
    ├── cutter2.entitlements
    ├── Assets.xcassets
    ├── Base.lproj/
    │   └── Main.storyboard
    └── [20 Swift source files]
```

### Xcode Project Info
- **Project**: cutter2.xcodeproj
- **Target**: cutter2
- **Bundle ID**: com.mycometg3.cutter2
- **Swift Version**: 6.0
- **Deployment Target**: macOS 11+
- **Architecture**: Universal (x86_64 + arm64)

### Build Configurations
- **Debug**: Development builds with debug symbols
- **Release**: Optimized builds for distribution
- **Code Signing**: Apple Development (automatic)
- **Hardened Runtime**: Enabled
- **Entitlements**: File bookmarks app-scope only

Remember: This is a macOS-native application that cannot be developed or tested outside of a macOS environment with Xcode. All validation must be performed manually with real video files.