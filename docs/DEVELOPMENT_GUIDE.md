# Development Guide for cutter2

**Last Updated**: February 5, 2026  
**Status**: ✅ Active and Maintained

**Recent Updates**:
- ✅ Phase 2.1: Internationalization Support (Complete)
- ✅ Phase 2.2: Performance Optimization (Complete)
- ✅ Phase 2.3: Logging System (Complete)
- ✅ LocalizationTests added
- ✅ PerformanceTests added
- ✅ LoggingSystemTests added
- ✅ String Catalog integration
- ✅ Console.app integration for logging

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Development Environment](#development-environment)
3. [Building the Project](#building-the-project)
4. [Running Tests](#running-tests)
5. [Code Style and Conventions](#code-style-and-conventions)
6. [Making Changes](#making-changes)
7. [Debugging](#debugging)
8. [Logging](#logging)
9. [Common Tasks](#common-tasks)
10. [Localization](#localization)
11. [Troubleshooting](#troubleshooting)

---

## Getting Started

### Prerequisites

- **macOS**: 14.0 or later (currently using 26.1)
- **Xcode**: 15.0 or later (currently using 26.1.1)
- **Swift**: 6.0 or later (currently using 6.2.1)
- **Git**: For version control
- **Command Line Tools**: Install via `xcode-select --install`

### Clone the Repository

```bash
git clone <repository-url>
cd cutter2
```

### Open the Project

```bash
open cutter2.xcodeproj
```

Or double-click `cutter2.xcodeproj` in Finder.

---

## Development Environment

### Xcode Configuration

1. **Select the cutter2 scheme**
   - In Xcode toolbar, select "cutter2" scheme
   - Target: "My Mac" or your Mac's name

2. **Enable Code Coverage**
   - Product → Scheme → Edit Scheme (⌘<)
   - Select "Test" tab
   - Check "Code Coverage" under Options
   - Check "Gather coverage for: cutter2"

3. **Set Up Code Signing**
   - Select project in navigator
   - Select "cutter2" target
   - Go to "Signing & Capabilities" tab
   - Select your development team
   - For local testing, you can use "Sign to Run Locally"

### Recommended Xcode Settings

**Editor Settings** (Xcode → Settings → Text Editing):
- ✅ Show line numbers
- ✅ Code folding ribbon
- ✅ Show invisibles (optional but helpful)
- Indent width: 4 spaces
- Tab width: 4 spaces
- ✅ Prefer indent using spaces

**Navigation Settings** (Xcode → Settings → Navigation):
- ✅ Uses Focused Editor
- Command-click: Jumps to Definition

**Key Bindings** (Xcode → Settings → Key Bindings):
- Learn standard shortcuts (⌘B for build, ⌘U for test, ⌘R for run)

---

## Building the Project

### Build from Xcode

1. **Clean Build** (recommended for first build)
   ```
   Product → Clean Build Folder (⌘⇧K)
   ```

2. **Build**
   ```
   Product → Build (⌘B)
   ```

3. **Run**
   ```
   Product → Run (⌘R)
   ```

### Build from Command Line

**Standard Build**:
```bash
xcodebuild build \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS'
```

**Build for Testing**:
```bash
xcodebuild build-for-testing \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS'
```

**Clean Build**:
```bash
xcodebuild clean build \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS'
```

### Build Configuration

- **Debug**: Default for development, includes debug symbols
- **Release**: Optimized build for distribution

To build Release configuration:
```bash
xcodebuild build \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -configuration Release \
  -destination 'platform=macOS'
```

---

## Running Tests

### Test from Xcode

1. **Run All Tests**
   ```
   Product → Test (⌘U)
   ```

2. **Run Specific Test File**
   - Open test file in editor
   - Click diamond icon next to class name
   - Or press ⌘U with test file open

3. **Run Single Test**
   - Click diamond icon next to test method
   - Or use Test Navigator (⌘6)

4. **View Test Results**
   - Open Test Navigator (⌘6)
   - View detailed results and logs

### Test from Command Line

**Run All Tests**:
```bash
xcodebuild test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS'
```

**Run Tests with Coverage**:
```bash
xcodebuild test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES
```

**Using Test Script** (includes coverage report):
```bash
./scripts/test.sh
```

### Test Organization

**Test Files**:
```
cutter2Tests/
├── cutter2Tests.swift              # Base test class
├── DocumentTests.swift             # Document tests
├── LocalizationTests.swift         # Localization tests
├── LoggingSystemTests.swift        # Logging system tests
├── ModelTests.swift                # Model layer tests
├── MovieMutatorTests.swift         # Model layer tests
├── PerformanceTests.swift          # Performance tests
├── UtilitiesTests.swift            # Utility tests
└── ViewControllerTests.swift       # ViewController tests
```

See [TESTING_GUIDE.md](TESTING_GUIDE.md) for detailed testing information.

---

## Code Style and Conventions

### Swift Style Guide

We follow Apple's Swift API Design Guidelines with project-specific conventions.

#### Naming Conventions

**Variables and Functions**:
```swift
// Use camelCase
var playerView: MyPlayerView
func updateTimeline()

// Boolean properties use is/has/should prefix
var isPlaying: Bool
var hasChanges: Bool
var shouldAutoPlay: Bool

// Action methods use verb prefixes
func doMoveLeft()
func updateGUI()
func validateInput()
```

**Types**:
```swift
// Use PascalCase
class DocumentController
struct VideoSettings
enum ExportFormat
```

**Constants**:
```swift
// Use k prefix for string constants
let kTranscodePresetKey = "transcodePreset"
let kVideoCodecKey = "videoCodec"

// Use descriptive names for other constants
let defaultTimescale: Int32 = 600
let maximumZoomLevel: Float = 2.0
```

#### Code Organization

**Use MARK comments for section organization**:
```swift
/* ============================================ */
// MARK: - Section Name
/* ============================================ */

// MARK: Properties
// MARK: Initialization
// MARK: Public Methods
// MARK: Private Methods
// MARK: Protocol Conformance
```

**Property Order**:
1. Public properties
2. Internal properties
3. Private properties
4. Computed properties
5. Lazy properties

**Method Order**:
1. Lifecycle methods (init, deinit, viewDidLoad, etc.)
2. Public methods
3. Internal methods
4. Private methods
5. Protocol conformance methods

#### Error Handling

**Use custom error types**:
```swift
enum DocumentError: Error {
    case invalidFormat(String)
    case exportFailed(String, underlying: Error?)
    
    var localizedDescription: String {
        switch self {
        case .invalidFormat(let msg):
            return "Invalid Format: \(msg)"
        case .exportFailed(let msg, _):
            return "Export Failed: \(msg)"
        }
    }
}
```

**Always handle errors appropriately**:
```swift
// Use do-catch for throwing functions
do {
    try await document.save(to: url)
} catch {
    ErrorUtilities.presentError(error)
}

// Use Result type for asynchronous operations
func loadData() async -> Result<Data, Error> {
    // Implementation
}
```

#### Concurrency

**Use @MainActor for UI code**:
```swift
@MainActor
class ViewController: NSViewController {
    func updateUI() {
        // Automatically runs on main thread
    }
}
```

**Use async/await for I/O operations**:
```swift
func loadMovie(from url: URL) async throws -> AVMutableMovie {
    return try await Task.detached {
        try AVMutableMovie(url: url)
    }.value
}
```

**Synchronize callbacks properly**:
```swift
mutator.updateProgress = { progress in
    performSyncOnMainActor {
        self.progressIndicator.doubleValue = progress
    }
}
```

#### Memory Management

**Use weak references in closures**:
```swift
someOperation { [weak self] result in
    guard let self = self else { return }
    self.handleResult(result)
}
```

**Clean up in deinit**:
```swift
deinit {
    removeObservers()
    player?.pause()
    NotificationCenter.default.removeObserver(self)
}
```

---

## Making Changes

### Creating a Feature Branch

```bash
# Start from work branch
git checkout work
git pull origin work

# Create feature branch
git checkout -b feature/your-feature-name
```

### Making Code Changes

1. **Make focused changes**
   - Keep changes small and focused on one feature/fix
   - Don't mix refactoring with feature changes

2. **Write tests**
   - Add tests for new functionality
   - Update existing tests if behavior changes
   - Ensure tests pass locally

3. **Follow conventions**
   - Match existing code style
   - Add appropriate MARK comments
   - Update documentation if needed

4. **Test your changes**
   ```bash
   # Build
   ⌘B in Xcode or xcodebuild build
   
   # Run tests
   ⌘U in Xcode or ./scripts/test.sh
   
   # Manual testing
   ⌘R in Xcode and test functionality
   ```

### Committing Changes

**Commit Message Format**:
```
<type>: <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Test changes
- `chore`: Build/tooling changes

**Example**:
```bash
git add <files>
git commit -m "feat: Add H.265 export support

Implement HEVC encoding with configurable quality settings.
Update export panel to include codec selection.
Add tests for new export functionality."
```

### Pushing Changes

```bash
# Push feature branch
git push origin feature/your-feature-name

# Create pull request on GitHub
```

---

## Debugging

### Debugging in Xcode

**Set Breakpoints**:
1. Click in gutter next to line number
2. Or use ⌘\ to toggle breakpoint

**Breakpoint Types**:
- **Line breakpoint**: Pause at specific line
- **Conditional breakpoint**: Right-click breakpoint → Edit Breakpoint
- **Exception breakpoint**: Pause on exceptions
- **Symbolic breakpoint**: Pause on method/function call

**Debug Controls**:
- Continue: F6 or ⌘⌃Y
- Step Over: F6
- Step Into: F7
- Step Out: F8

**View Debugging**:
- Debug → View Debugging → Capture View Hierarchy
- Inspect view hierarchy in 3D
- Check constraints and layout issues

**Memory Debugging**:
- Debug → Memory → Profile in Instruments
- Look for leaks and excessive memory usage

### Console Debugging

**Structured Logging** (Preferred):
```swift
// Use LoggingSystem for production-ready logging
LoggingSystem.document.debug("Current time: \(currentTime)")
LoggingSystem.video.info("Processing frame: \(frameNumber)")

// For complex objects in debug builds
#if DEBUG
LoggingSystem.debug.debug("Object state: \(String(describing: object))")
#endif
```

**Quick Debug Prints** (Development only):
```swift
// For quick debugging only - use LoggingSystem in committed code
debugPrint(someObject)
dump(complexObject)
```

**LLDB Commands**:
```lldb
# Print object
po someObject

# Print expression
p someObject.someProperty

# List breakpoints
br list

# Delete breakpoint
br delete 1
```

### Common Debug Scenarios

**AVFoundation Issues**:
```swift
// Enable AVFoundation logging
// Add to scheme: Product → Scheme → Edit Scheme → Run → Arguments
// Environment Variable: AVFOUNDATION_DEBUG_LOG = 1
```

**Actor Isolation Issues**:
```swift
// Check if on main thread
print("On main thread: \(Thread.isMainThread)")

// Verify actor isolation
MainActor.assertIsolated()
```

**Memory Issues**:
```swift
// Check retain cycles
deinit {
    print("\(type(of: self)) deallocated")
}
```

---

## Common Tasks

### Adding a New Feature

1. **Create feature branch**
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. **Add implementation**
   - Create new files or modify existing ones
   - Follow code organization patterns
   - Add appropriate error handling

3. **Add tests**
   - Create test file or add to existing
   - Test happy path and error cases
   - Aim for good coverage

4. **Update documentation**
   - Update relevant .md files
   - Add inline code documentation
   - Update README if user-facing

5. **Test thoroughly**
   - Run automated tests
   - Manual testing
   - Test edge cases

6. **Commit and push**
   ```bash
   git add .
   git commit -m "feat: Description"
   git push origin feature/my-new-feature
   ```

---

## Logging

cutter2 uses Apple's unified logging system (`os.Logger`) for structured logging with Console.app integration.

### Using LoggingSystem

**Available Categories**:
```swift
LoggingSystem.document     // Document operations (open, save, export)
LoggingSystem.video        // Video processing and editing
LoggingSystem.ui           // User interface events
LoggingSystem.performance  // Performance measurements
LoggingSystem.fileIO       // File I/O operations
LoggingSystem.security     // Bookmark and security-scoped resources
LoggingSystem.export       // Export and transcode operations
LoggingSystem.input        // Keyboard and input handling
LoggingSystem.app          // Application lifecycle
```

### Log Levels

**Use appropriate log levels**:

```swift
// Debug: Development debugging (DEBUG builds only)
#if DEBUG
LoggingSystem.video.debug("Processing frame \(frameNumber)")
#endif

// Info: Informational messages
LoggingSystem.document.info("Document saved successfully")

// Notice: Significant events
LoggingSystem.export.notice("Export completed in \(duration)s")

// Error: Error conditions
LoggingSystem.fileIO.error("Failed to read file: \(error.localizedDescription)")

// Fault: Critical failures
LoggingSystem.document.fault("Document state corrupted")
```

### Privacy Annotations

**Protect sensitive data**:

```swift
// Public: Safe for production logs
LoggingSystem.performance.info("Processing \(count, privacy: .public) items")

// Private: Redacted in production (default)
LoggingSystem.fileIO.debug("Opening file: \(url.path)")

// Sensitive: Always redacted
LoggingSystem.security.debug("Bookmark data: \(data, privacy: .sensitive)")
```

### Best Practices

**DO**:
- ✅ Use appropriate log categories
- ✅ Choose correct log levels
- ✅ Add context to log messages
- ✅ Use privacy annotations for sensitive data
- ✅ Wrap debug-only logs in `#if DEBUG`

**DON'T**:
- ❌ Use `print()` statements (use Logger instead)
- ❌ Log in tight loops (performance impact)
- ❌ Log sensitive user data without privacy control
- ❌ Over-log (keep it meaningful)

### Viewing Logs in Console.app

**Open Console.app**:
1. Applications → Utilities → Console.app
2. Select your Mac in sidebar
3. Click "Start" to stream logs

**Filter by subsystem**:
```
subsystem:com.mycometg3.cutter2
```

**Filter by category**:
```
subsystem:com.mycometg3.cutter2 AND category:export
subsystem:com.mycometg3.cutter2 AND category:performance
```

**Filter by log level**:
```
subsystem:com.mycometg3.cutter2 AND level:error
subsystem:com.mycometg3.cutter2 AND level:>=notice
```

**Command line monitoring**:
```bash
# Stream logs
log stream --predicate 'subsystem == "com.mycometg3.cutter2"'

# Export recent logs
log show --predicate 'subsystem == "com.mycometg3.cutter2"' --last 1h > cutter2.log
```

### Examples

**Document operation**:
```swift
func saveDocument(to url: URL) async throws {
    LoggingSystem.document.info("Saving document to: \(url.lastPathComponent)")
    
    do {
        try await performSave(to: url)
        LoggingSystem.document.info("Document saved successfully")
    } catch {
        LoggingSystem.fileIO.error("Save failed: \(error.localizedDescription)")
        throw error
    }
}
```

**Performance measurement**:
```swift
let startTime = CFAbsoluteTimeGetCurrent()
// ... operation ...
let duration = CFAbsoluteTimeGetCurrent() - startTime
LoggingSystem.performance.notice("Export completed in \(String(format: "%.2f", duration))s")
```

**Debug tracing**:
```swift
#if DEBUG
LoggingSystem.video.debug("Frame timing: \(time.seconds)s, valid: \(CMTIME_IS_VALID(time))")
#endif
```

For more details, see [PHASE_2.3_LOGGING_PLAN.md](archive/phase-2.3/PHASE_2.3_LOGGING_PLAN.md).

---

## Common Tasks

1. **Create bug fix branch**
   ```bash
   git checkout -b fix/bug-description
   ```

2. **Write failing test** (if possible)
   - Reproduce the bug in a test
   - Verify test fails

3. **Fix the bug**
   - Make minimal changes
   - Fix root cause, not symptoms

4. **Verify fix**
   - Test passes
   - Manual verification
   - Check for regressions

5. **Commit with clear message**
   ```bash
   git commit -m "fix: Brief description of bug

   Detailed explanation of what was wrong and how it's fixed.
   
   Fixes #123"
   ```

### Refactoring Code

1. **Ensure tests exist**
   - Tests should pass before refactoring
   - Add tests if coverage is insufficient

2. **Make small changes**
   - Refactor in small, testable increments
   - Run tests after each change

3. **Common refactorings**:
   - Extract method
   - Move code to extension
   - Rename for clarity
   - Simplify complex logic

4. **Verify no behavior change**
   ```bash
   ./scripts/test.sh
   # Manual testing
   ```

### Adding a New Export Format

1. **Update MovieWriter.swift**
   - Add codec case to enum
   - Implement export settings
   - Add validation

2. **Update UI**
   - Add option to ExportAccessoryViewController
   - Update storyboard if needed

3. **Add tests**
   - Test export with new format
   - Verify file output

4. **Update documentation**
   - Update README features list
   - Update user documentation

---

## Troubleshooting

### Build Failures

**"Cannot find 'X' in scope"**:
- Clean build folder (⌘⇧K)
- Delete derived data
- Restart Xcode

**Signing Issues**:
- Check signing certificates
- Try "Sign to Run Locally"
- Verify entitlements file

**"Module compiled with Swift X but this compiler is Y"**:
- Clean build folder
- Delete derived data
- Rebuild all targets

### Runtime Issues

**App Crashes on Launch**:
- Check console for error messages
- Verify storyboard connections
- Check for missing resources

**Sandbox Violations**:
- Check entitlements
- Verify security-scoped bookmarks
- Request appropriate permissions

**Performance Issues**:
- Profile with Instruments
- Check for memory leaks
- Optimize heavy operations

### Test Failures

**Tests Pass Individually but Fail Together**:
- Check for shared state
- Verify proper setup/teardown
- Look for timing issues

**Flaky Tests**:
- Add appropriate waits for async operations
- Check for race conditions
- Make tests deterministic

---

## Localization

### Overview

cutter2 supports internationalization using String Catalogs (.xcstrings format).

**Supported Languages**:
- English (base language)
- Japanese (日本語)

### Adding Localized Strings

1. **Add to String Catalog**:
   - Open `cutter2/Resources/Localizable.xcstrings` in Xcode
   - Add new key with English and Japanese translations

2. **Use in Code**:
   ```swift
   // Simple localization
   let message = NSLocalizedString("your.key.name", comment: "Description")
   
   // Using LocalizationHelper
   let message = LocalizationHelper.localized("your.key.name", 
                                             comment: "Description")
   
   // Common UI strings
   let cancelButton = LocalizationHelper.Button.cancel
   ```

3. **Formatted Strings**:
   ```swift
   let format = NSLocalizedString("progress.format.percent", comment: "Progress")
   let text = String(format: format, 75)
   ```

### Testing Localization

1. **Run LocalizationTests**:
   ```bash
   xcodebuild test -only-testing:cutter2Tests/LocalizationTests
   ```

2. **Test in Different Languages**:
   - System Preferences → Language & Region
   - Change preferred language
   - Relaunch cutter2

3. **Verify Translations**:
   - Check all error messages
   - Test all menu items
   - Verify inspector labels
   - Test progress dialogs

### Adding New Languages

1. **Add Language in Xcode**:
   - Select project → Info tab
   - Under "Localizations", click "+"
   - Select language

2. **Translate Strings**:
   - Open Localizable.xcstrings
   - Add translations for new language

3. **Test**:
   - Build and test in new language
   - Verify layout with different string lengths

For detailed localization information, see [LOCALIZATION_PLAN.md](archive/phase-2.1/LOCALIZATION_PLAN.md) and [LOCALIZATION_COMPLETE.md](archive/phase-2.1/LOCALIZATION_COMPLETE.md).

---

## Additional Resources

### Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [TESTING_GUIDE.md](TESTING_GUIDE.md) - Testing guide
- [REFACTORING_PLAN.md](archive/phase-1.2/REFACTORING_PLAN.md) - Code organization
- [CODEBASE_REVIEW.md](archive/reviews/CODEBASE_REVIEW.md) - Codebase analysis
- [LOCALIZATION_PLAN.md](archive/phase-2.1/LOCALIZATION_PLAN.md) - Localization implementation
- [LOCALIZATION_COMPLETE.md](archive/phase-2.1/LOCALIZATION_COMPLETE.md) - Localization summary

### Apple Documentation

- [AVFoundation Programming Guide](https://developer.apple.com/av-foundation/)
- [Document-Based Apps](https://developer.apple.com/documentation/appkit/documents_data_and_pasteboard)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) ✨ NEW

### Tools

- [Instruments](https://help.apple.com/instruments/) - Performance profiling
- [SF Symbols](https://developer.apple.com/sf-symbols/) - System icons
- [SwiftLint](https://github.com/realm/SwiftLint) - Code linting (optional)

---

## Getting Help

If you encounter issues:

1. **Check documentation** in `docs/` directory
2. **Search existing issues** on GitHub
3. **Ask questions** in discussions or issues
4. **Review code** for similar patterns
5. **Debug systematically** using tools above

---

**Document Status**: ✅ Active  
**Last Updated**: February 5, 2026  
**Maintained By**: cutter2 development team
