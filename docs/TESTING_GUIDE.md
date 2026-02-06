# Testing Guide for cutter2

**Status**: ✅ **Active - Test Infrastructure Operational** *(Updated: February 5, 2026)*

This guide provides instructions for running and writing tests for the cutter2 application.

## Quick Start

The test infrastructure is fully configured and operational:
- ✅ Test suite covers Models, ViewControllers, Utilities, Localization, Performance, and Logging
- ✅ XCTest framework integrated
- ✅ Code coverage enabled
- ✅ CI/CD pipeline active (GitHub Actions)

To run tests: Press `⌘U` in Xcode or run `xcodebuild test` from command line.

## Table of Contents

1. [Test Environment Setup](#test-environment-setup)
2. [Running Tests](#running-tests)
3. [Writing Tests](#writing-tests)
4. [Code Coverage](#code-coverage)
5. [CI/CD Integration](#cicd-integration)
6. [Best Practices](#best-practices)

---

## Test Environment Setup

### Prerequisites

- Xcode 15.0 or later (currently using 26.1.1)
- macOS 11.0 or later (currently using 26.1)
- Swift 6.0 or later (currently using 6.2.1)

### Initial Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd cutter2
   ```

2. **Open the project in Xcode**
   ```bash
   open cutter2.xcodeproj
   ```

3. **Verify test target exists**
   - In Xcode, select the project in the navigator
   - Verify that `cutter2Tests` target is listed

### Test Structure

```
cutter2Tests/
├── cutter2Tests.swift              # Base test class and setup ✅
├── DocumentTests.swift             # Document tests ✅
├── LocalizationTests.swift         # Localization tests ✅ (Phase 2.1)
├── LoggingSystemTests.swift        # Logging tests ✅ (Phase 2.3)
├── ModelTests.swift                # Additional model tests ✅
├── MovieMutatorTests.swift         # Model layer tests ✅
├── PerformanceTests.swift          # Performance tests ✅ (Phase 2.2)
├── UtilitiesTests.swift            # Utility class tests ✅
└── ViewControllerTests.swift       # ViewController tests ✅
```

**Current Status**:
- Full test suite implemented covering core functionality, localization, logging, and performance
- Run `./scripts/test.sh` or `xcodebuild test` for current results

**Phase 2.1 - Localization**:
- ✅ LocalizationTests.swift - localization coverage
- Tests all error messages (DocumentError, MovieWriterError)
- Tests UI strings (buttons, menus, inspector labels)
- Tests LocalizationHelper utility methods
- Tests formatted string localization

**Phase 2.2 - Performance**:
- ✅ PerformanceTests.swift - performance coverage
- Tests CMTime operations performance
- Tests movie loading and preparation
- Tests export progress reporting
- Baseline performance measurements for regression detection

---

## Running Tests

### From Xcode

1. **Run all tests**
   - Press `⌘U` (Command-U)
   - Or: Product → Test

2. **Run specific test class**
   - Click the diamond icon next to the test class
   - Or right-click the test class and select "Run tests"

3. **Run specific test method**
   - Click the diamond icon next to the test method
   - Or place cursor in the test method and press `⌃⌥⌘U`

### From Command Line

1. **Build and run all tests**
   ```bash
   xcodebuild test \
     -project cutter2.xcodeproj \
     -scheme cutter2 \
     -destination 'platform=macOS'
   ```

2. **Build for testing only**
   ```bash
   xcodebuild build-for-testing \
     -project cutter2.xcodeproj \
     -scheme cutter2 \
     -destination 'platform=macOS'
   ```

3. **Run tests without building**
   ```bash
   xcodebuild test-without-building \
     -project cutter2.xcodeproj \
     -scheme cutter2 \
     -destination 'platform=macOS'
   ```

### Quick Test Script

Use the existing test script (includes coverage report):

```bash
./scripts/test.sh
```

---

## Writing Tests

### Test File Template

```swift
import XCTest
@testable import cutter2

final class MyFeatureTests: XCTestCase {
    
    var sut: MyFeatureClass?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = MyFeatureClass()
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        sut = nil
        try super.tearDownWithError()
    }
    
    func testFeatureBehavior() throws {
        // Given
        let input = "test"
        
        // When
        let result = sut?.processInput(input)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "expected")
    }
}
```

### Testing Async Code

```swift
func testAsyncOperation() async throws {
    // Given
    let document = Document()
    
    // When
    try await document.readAsync(from: testURL, ofType: "mov")
    
    // Then
    XCTAssertNotNil(document.movieMutator)
}
```

### Testing Main Actor Code

```swift
func testMainActorOperation() throws {
    let expectation = self.expectation(description: "Main actor operation")
    
    Task { @MainActor in
        // Test main actor code
        let viewController = ViewController()
        XCTAssertTrue(Thread.isMainThread)
        expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 1.0)
}
```

### Performance Testing

```swift
func testPerformance() throws {
    self.measure {
        // Code to measure
        for _ in 0..<1000 {
            _ = CMTime(seconds: 1.0, preferredTimescale: 600)
        }
    }
}
```

### Test Organization

Follow this structure for test methods:

```swift
// MARK: - Initialization Tests
func testInitialization() { }

// MARK: - Business Logic Tests  
func testFeatureA() { }
func testFeatureB() { }

// MARK: - Error Handling Tests
func testErrorCondition() { }

// MARK: - Edge Case Tests
func testEdgeCaseA() { }

// MARK: - Performance Tests
func testPerformanceOfCriticalPath() { }
```

---

## Code Coverage

### Enable Code Coverage

1. **In Xcode**
   - Edit Scheme (⌘<)
   - Select "Test" action
   - Check "Code Coverage" checkbox
   - Select "cutter2.app" target for coverage

2. **View Coverage Report**
   - Run tests
   - Open Report Navigator (⌘9)
   - Select latest test report
   - Click "Coverage" tab

### Coverage Targets

**Current Status**: Coverage goals are tracked in CI and updated as the suite evolves.

Run tests with coverage enabled to track progress toward current goals.

### Generate Coverage Report (CLI)

```bash
xcodebuild test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES

xcrun llvm-cov export \
  -format="lcov" \
  -instr-profile=$(find ~/Library/Developer/Xcode/DerivedData -name "Coverage.profdata" | head -1) \
  $(find ~/Library/Developer/Xcode/DerivedData -name "cutter2" -type f | head -1) \
  > coverage.lcov
```

---

## CI/CD Integration

### GitHub Actions

✅ **Active**: Tests run automatically on:
- Push to `main`, `work`, or `develop` branches
- Pull requests to these branches

Workflow file: `.github/workflows/test.yml`

**Status**: CI/CD pipeline configured and operational as of October 13, 2025.

### Local Pre-commit Testing

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
echo "Running tests before commit..."
xcodebuild test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
  -quiet

if [ $? -ne 0 ]; then
  echo "Tests failed. Commit aborted."
  exit 1
fi
```

Make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

---

## Best Practices

### General Testing Guidelines

1. **Test Names**: Use descriptive names that explain what is being tested
   - Good: `testInsertTimeRangeWithValidInput`
   - Bad: `testInsert`

2. **Test Structure**: Follow Given-When-Then pattern
   ```swift
   // Given - Setup
   // When - Execute
   // Then - Assert
   ```

3. **One Assertion Per Test**: Focus each test on a single behavior
   - Exception: Related assertions on the same result

4. **Test Independence**: Tests should not depend on each other
   - Use `setUp()` and `tearDown()` for clean state

5. **Use Meaningful Assertions**
   - Prefer specific assertions: `XCTAssertEqual` over `XCTAssertTrue`
   - Add descriptive failure messages

### Testing Swift Concurrency

1. **Async Tests**: Use `async throws` for async code
2. **Main Actor**: Test UI code with proper actor isolation
3. **Expectations**: Use XCTestExpectation for async callbacks

### Mock Objects

When needed, create mock objects in test files:

```swift
class MockMovieMutator: MovieMutatorProtocol {
    var didCallMethod = false
    
    func someMethod() {
        didCallMethod = true
    }
}
```

### Test Data

Store test resources in `cutter2Tests/TestResources/`:
- Sample video files (small, < 1MB)
- Configuration files
- Mock data files

---

## Troubleshooting

### Tests Won't Run

1. Check scheme settings (Edit Scheme → Test)
2. Verify test target membership for test files
3. Clean build folder (⇧⌘K) and rebuild

### Code Coverage Not Showing

1. Enable coverage in scheme settings
2. Run tests (not just build)
3. Check Report Navigator for coverage tab

### Tests Timeout

1. Increase timeout in expectations
2. Check for main actor deadlocks
3. Verify async operations complete

---

## Future Enhancements

Based on Phase 2-3 of the improvement plan:

- [ ] Expand test coverage to reach 70%+ overall
- [ ] UI Testing with XCUITest
- [ ] Integration testing framework
- [ ] Mocking framework (e.g., Mockingbird, Cuckoo)
- [ ] Snapshot testing for UI
- [ ] Property-based testing
- [ ] Performance benchmarking suite

---

## Resources

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Testing Swift Concurrency](https://developer.apple.com/documentation/swift/concurrency)
- [Writing Tests in Swift](https://developer.apple.com/videos/play/wwdc2021/10192/)

---

**Last Updated**: February 5, 2026  
**Version**: 1.2  
**Status**: ✅ Test Infrastructure Operational - Phase 2.1 & 2.2 Complete
