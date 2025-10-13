# Contributing to cutter2

Thank you for your interest in contributing to cutter2! This document provides guidelines and instructions for contributing to the project.

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [How to Contribute](#how-to-contribute)
4. [Development Workflow](#development-workflow)
5. [Coding Standards](#coding-standards)
6. [Testing Requirements](#testing-requirements)
7. [Pull Request Process](#pull-request-process)
8. [Reporting Issues](#reporting-issues)

---

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inspiring community for all. Please be respectful and constructive in all interactions.

### Expected Behavior

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on what is best for the project
- Show empathy towards other community members

### Unacceptable Behavior

- Harassment, discrimination, or offensive comments
- Publishing others' private information
- Trolling, insulting, or derogatory comments
- Unprofessional or inappropriate conduct

---

## Getting Started

### Prerequisites

Before contributing, ensure you have:

1. **macOS** 14.0 (Sonoma) or later
2. **Xcode** 15.0 or later
3. **Git** installed and configured
4. **GitHub account** for submitting contributions

### Fork and Clone

1. **Fork the repository** on GitHub
   - Click "Fork" button on the repository page

2. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR-USERNAME/cutter2.git
   cd cutter2
   ```

3. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/ORIGINAL-OWNER/cutter2.git
   ```

4. **Verify remotes**
   ```bash
   git remote -v
   # origin    https://github.com/YOUR-USERNAME/cutter2.git (fetch)
   # origin    https://github.com/YOUR-USERNAME/cutter2.git (push)
   # upstream  https://github.com/ORIGINAL-OWNER/cutter2.git (fetch)
   # upstream  https://github.com/ORIGINAL-OWNER/cutter2.git (push)
   ```

### Set Up Development Environment

1. **Open project in Xcode**
   ```bash
   open cutter2.xcodeproj
   ```

2. **Build the project**
   - Press ⌘B or Product → Build

3. **Run tests**
   - Press ⌘U or Product → Test

4. **Read documentation**
   - [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) - Development setup and workflows
   - [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
   - [TESTING_GUIDE.md](TESTING_GUIDE.md) - Testing practices

---

## How to Contribute

### Types of Contributions

We welcome various types of contributions:

#### 🐛 Bug Fixes
- Fix reported issues
- Improve error handling
- Address edge cases

#### ✨ New Features
- Implement requested features
- Add new export formats
- Enhance user interface
- Improve keyboard shortcuts

#### 📚 Documentation
- Improve existing documentation
- Add code comments
- Create tutorials or guides
- Translate documentation

#### 🧪 Tests
- Add missing test coverage
- Improve existing tests
- Add integration tests
- Performance benchmarks

#### 🎨 Code Quality
- Refactor complex code
- Improve code organization
- Remove code smells
- Optimize performance

---

## Development Workflow

### 1. Sync with Upstream

Before starting work, sync your fork:

```bash
git checkout work
git fetch upstream
git merge upstream/work
git push origin work
```

### 2. Create a Branch

Create a descriptive branch name:

```bash
# For features
git checkout -b feature/short-description

# For bug fixes
git checkout -b fix/short-description

# For documentation
git checkout -b docs/short-description

# Examples:
git checkout -b feature/add-hevc-export
git checkout -b fix/timeline-rendering-bug
git checkout -b docs/update-api-reference
```

### 3. Make Changes

- Write clean, focused code
- Follow coding standards (see below)
- Add tests for new functionality
- Update documentation as needed

### 4. Test Your Changes

**Run all tests**:
```bash
./scripts/test.sh
```

**Manual testing**:
- Build and run the app (⌘R)
- Test the specific functionality
- Verify no regressions in other features

### 5. Commit Changes

Use clear, descriptive commit messages:

```bash
git add <files>
git commit -m "type: brief description

Detailed explanation of what changed and why.

Fixes #issue-number (if applicable)"
```

**Commit types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `test`: Adding or updating tests
- `refactor`: Code refactoring
- `perf`: Performance improvement
- `chore`: Build/tooling changes

**Examples**:
```
feat: Add HEVC export support

Implement H.265 encoding with quality settings.
Add UI controls for codec selection.
Include tests for new export functionality.

Fixes #123
```

```
fix: Correct timeline marker positioning

Timeline markers were offset by 1 frame due to rounding error.
Use CMTimeClampToRange for proper boundary checking.

Fixes #456
```

### 6. Push to Your Fork

```bash
git push origin your-branch-name
```

### 7. Create Pull Request

1. Go to your fork on GitHub
2. Click "New pull request"
3. Select base: `work` and compare: `your-branch-name`
4. Fill in the PR template (see below)
5. Submit the pull request

---

## Coding Standards

### Swift Style Guide

Follow Apple's Swift API Design Guidelines and project conventions.

#### Naming

```swift
// Variables and functions: camelCase
var playerView: MyPlayerView
func updateTimeline()

// Types: PascalCase
class MovieMutator
struct ExportSettings
enum CodecType

// Booleans: descriptive with is/has/should prefix
var isPlaying: Bool
var hasUnsavedChanges: Bool
var shouldAutoSave: Bool

// Constants: k prefix for string keys
let kExportPresetKey = "exportPreset"
```

#### Code Organization

```swift
/* ============================================ */
// MARK: - Section Name
/* ============================================ */

class MyClass {
    // MARK: Properties
    // Public properties first
    var publicProperty: String
    
    // Then private properties
    private var privateProperty: Int
    
    // MARK: Initialization
    init() { }
    
    // MARK: Public Methods
    func publicMethod() { }
    
    // MARK: Private Methods
    private func privateMethod() { }
    
    // MARK: Protocol Conformance
}

// MARK: - Protocol Extension
extension MyClass: SomeProtocol {
    // Protocol methods
}
```

#### Error Handling

```swift
// Use custom error types
enum MyError: Error {
    case invalidInput(String)
    case operationFailed(underlying: Error)
}

// Handle errors appropriately
do {
    try performOperation()
} catch {
    ErrorUtilities.presentError(error)
}
```

#### Concurrency

```swift
// Use @MainActor for UI code
@MainActor
class ViewController: NSViewController {
    func updateUI() {
        // Runs on main thread
    }
}

// Use async/await for I/O
func loadData() async throws -> Data {
    return try await Task.detached {
        // Background work
    }.value
}
```

#### Memory Management

```swift
// Use weak references in closures
someObject.completion = { [weak self] result in
    guard let self = self else { return }
    self.handleResult(result)
}

// Clean up in deinit
deinit {
    removeObservers()
    cleanup()
}
```

### File Organization

- Place files in appropriate directories
- Follow existing project structure
- Use extensions for grouping related functionality
- Keep files focused and under 500 lines when possible

### Documentation

```swift
/// Brief description of the function
///
/// More detailed explanation if needed.
///
/// - Parameters:
///   - param1: Description of parameter 1
///   - param2: Description of parameter 2
/// - Returns: Description of return value
/// - Throws: Description of errors that can be thrown
func myFunction(param1: String, param2: Int) throws -> Bool {
    // Implementation
}
```

---

## Testing Requirements

### Test Coverage

- Add tests for all new functionality
- Maintain or improve code coverage
- Test both success and failure cases
- Include edge cases

### Test Organization

```swift
import XCTest
@testable import cutter2

class MyFeatureTests: XCTestCase {
    // MARK: - Setup
    override func setUp() {
        super.setUp()
        // Test setup
    }
    
    override func tearDown() {
        // Test cleanup
        super.tearDown()
    }
    
    // MARK: - Tests
    func testFeatureWorks() {
        // Arrange
        let input = setupInput()
        
        // Act
        let result = performOperation(input)
        
        // Assert
        XCTAssertEqual(result, expected)
    }
    
    func testFeatureHandlesError() {
        // Test error case
    }
}
```

### Running Tests

**Before submitting PR**:
```bash
# Run all tests with coverage
./scripts/test.sh

# Or use Xcode
# Press ⌘U
```

**Tests must pass** before PR can be merged.

---

## Pull Request Process

### PR Template

When creating a PR, include:

```markdown
## Description
Brief description of the changes

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Manual testing performed
- [ ] All tests pass locally

## Related Issues
Fixes #(issue number)

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review of code performed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings generated
- [ ] Tests added for new features
- [ ] All tests pass
```

### Review Process

1. **Automated checks run**
   - Build verification
   - Test execution
   - Code coverage analysis

2. **Code review by maintainers**
   - Review code quality
   - Check for issues
   - Provide feedback

3. **Address feedback**
   - Make requested changes
   - Update PR
   - Re-request review

4. **Approval and merge**
   - At least one approval required
   - All checks must pass
   - Maintainer merges PR

### After Merge

- Delete your branch
- Sync your fork with upstream
- Thank reviewers for their time!

---

## Reporting Issues

### Before Reporting

1. **Search existing issues** - Check if already reported
2. **Try latest version** - Verify issue still exists
3. **Gather information** - Prepare relevant details

### Issue Template

```markdown
## Description
Clear description of the issue

## Steps to Reproduce
1. Open app
2. Click on...
3. See error

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Environment
- macOS version: 14.0
- Xcode version: 15.0
- App version: 1.0.0

## Additional Context
- Screenshots if applicable
- Error messages
- Crash logs

## Possible Solution
(Optional) Suggest a fix
```

### Issue Types

**Bug Report** - Something isn't working
**Feature Request** - Suggest a new feature
**Documentation** - Improve or clarify docs
**Question** - Ask for help or clarification

---

## Communication

### Where to Ask Questions

- **GitHub Discussions** - General questions and discussions
- **GitHub Issues** - Bug reports and feature requests
- **Pull Requests** - Code review discussions

### Response Time

- We aim to respond to issues within 1-2 weeks
- PR reviews typically within 1 week
- Please be patient, this is a volunteer project

---

## License

By contributing to cutter2, you agree that your contributions will be licensed under the MIT License.

---

## Recognition

Contributors are recognized in:
- Git commit history
- Release notes
- Special recognition for significant contributions

---

## Questions?

If you have questions about contributing:

1. Check [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)
2. Search existing issues and discussions
3. Open a new discussion on GitHub
4. Tag maintainers if urgent

---

**Thank you for contributing to cutter2!** 🎉

Your contributions help make video editing on macOS better for everyone.

---

**Document Status**: ✅ Active  
**Last Updated**: October 13, 2025  
**Maintained By**: cutter2 project maintainers
