# Testing Guide for cutter2

**Status**: Active — test instructions and infrastructure reference *(Updated: August 6, 2026)*

This guide provides instructions for running and writing tests for the cutter2 application.

## Quick Start

The test target is configured with XCTest and currently contains:
- 15 test source files
- 1 test helper file
- 197 statically declared `func test...` methods
- Code coverage support in the command-line and CI workflows

Run the complete suite with:

```bash
xcodebuild test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO
```

The recorded run on August 5, 2026 reported 197 passing tests. A fresh run on August 6, 2026 at commit `78f1d00e140afb2e2ce7ce030781895e0d981e5c` did not reach test execution because the build failed on a duplicate `writeSampleMovie(to:duration:timescale:frameRate:)` declaration in `MovieMutatorTransformExportTests.swift:19` and `TestMovieFixtureWriter.swift:32`.

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

- Xcode 16.0 or later
- macOS 14.0 or later
- Swift language mode 6.0 (`SWIFT_VERSION = 6.0`)

The documentation was verified on August 6, 2026 with macOS 26.6 (build 25G72), Xcode 26.6 (build 17F113), and Swift compiler 6.3.3.

### Initial Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/MyCometG3/cutter2.git
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
├── cutter2Tests.swift                    # Base test class and integration tests (20 tests)
├── DocumentTests.swift                   # Document tests (6 tests)
├── LocalizationTests.swift               # Localization tests (11 tests)
├── LoggingSystemTests.swift              # Logging tests (17 tests)
├── ModelTests.swift                      # Additional model tests (25 tests)
├── MovieMutatorTests.swift               # Model layer tests (22 tests)
├── MovieMutatorEditTests.swift           # Edit operation tests (5 tests)
├── MovieMutatorTransformExportTests.swift # Transform/export tests (8 tests)
├── MovieHeaderValidatorTests.swift       # Header validation tests (3 tests)
├── AsyncBridgeTests.swift                # AsyncBridge tests (4 tests)
├── TimelineViewRenderingTests.swift      # Timeline rendering tests (15 tests)
├── ViewControllerTests.swift             # ViewController tests (15 tests)
├── ViewControllerKeyEventTests.swift     # Key event tests (14 tests)
├── PerformanceTests.swift                # Performance tests (12 tests)
├── UtilitiesTests.swift                  # Utility class tests (20 tests)
└── TestMovieFixtureWriter.swift          # Test helper (0 tests)
```

**Static suite size**: 16 files total (15 test source files + 1 helper), **197 statically declared test methods**.

Runtime results must be taken from the specific `xcodebuild test` or Xcode run being reported.

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
     -destination 'platform=macOS' \
     -enableCodeCoverage YES \
     CODE_SIGN_IDENTITY='' \
     CODE_SIGNING_REQUIRED=NO
   ```

2. **Build for testing and run without rebuilding**

   `test-without-building` requires a successful `build-for-testing` run with the same project, scheme, destination, configuration, and DerivedData path.

   ```bash
   DERIVED_DATA=.build-test

   xcodebuild build-for-testing \
     -project cutter2.xcodeproj \
     -scheme cutter2 \
     -destination 'platform=macOS' \
     -derivedDataPath "$DERIVED_DATA" \
     CODE_SIGN_IDENTITY='' \
     CODE_SIGNING_REQUIRED=NO

   xcodebuild test-without-building \
     -project cutter2.xcodeproj \
     -scheme cutter2 \
     -destination 'platform=macOS' \
     -derivedDataPath "$DERIVED_DATA" \
     -enableCodeCoverage YES \
     CODE_SIGN_IDENTITY='' \
     CODE_SIGNING_REQUIRED=NO
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
// Note: A `Document` instance cannot be constructed in the unit-test environment —
// the `window` computed property force-indexes `windowControllers[0]`, raising
// `NSRangeException` on the empty array during `NSDocument.init()`. Test Document
// logic through extracted helpers instead (e.g. `Document.validateMovieType(_:)`
// and `MovieHeaderValidator`).
func testAsyncOperation() async throws {
    // Given
    let typeName = "com.apple.quicktime-movie"

    // When — UTI validation (shared by readAsync / read) accepts a movie type
    try Document.validateMovieType(typeName)

    // Then — header validation rejects a trackless movie
    let movie = AVMutableMovie()
    XCTAssertFalse(MovieHeaderValidator.isValid(movie))
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

   For command-line runs, pass `-enableCodeCoverage YES` explicitly; the command-line option is independent of the Xcode scheme checkbox.

2. **View Coverage Report**
   - Run tests
   - Open Report Navigator (⌘9)
   - Select latest test report
   - Click "Coverage" tab

### Coverage Targets

**Current Status**: Coverage goals are tracked in CI and updated as the suite evolves.

Run tests with coverage enabled to track progress toward current goals.

### Generate Coverage Report (CLI)

Use the test script which includes coverage report generation:

```bash
./scripts/test.sh
```

---

## CI/CD Integration

### GitHub Actions

**Workflow**: Tests are configured to run on:
- Push to `main`, `work`, or `develop` branches
- Pull requests to these branches

Workflow file: `.github/workflows/test.yml`

The workflow runs Build → Test → Analyze and attempts to publish an LCOV artifact. The current workflow does not pin the Xcode image and treats coverage artifact generation as optional; confirm the result from the specific GitHub Actions run.

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

Test fixtures are created programmatically using `TestMovieFixtureWriter` in `cutter2Tests/TestMovieFixtureWriter.swift`.

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

**Last Updated**: August 6, 2026
**Version**: 1.4
**Status**: Static suite size: 197 test methods; runtime status depends on the specific test run
