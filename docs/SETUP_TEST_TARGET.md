# Setup Test Target in Xcode

**Status**: ✅ **COMPLETED - October 13, 2025**

This document provides historical reference for the test target setup process. The test target has been successfully configured and integrated into the project.

## Current Status

- ✅ Test target `cutter2Tests` created and configured
- ✅ Test files added and organized in `cutter2Tests/` directory
- ✅ Code coverage enabled in scheme settings
- ✅ CI/CD pipeline configured with GitHub Actions
- ✅ Initial test suite implemented and passing

## Test Files Currently in Project

```
cutter2Tests/
├── cutter2Tests.swift              # Base test class and setup
├── MovieMutatorTests.swift         # Model layer tests
├── UtilitiesTests.swift            # Utility class tests
├── ActorUtilitiesTests.swift       # Actor isolation tests
├── ErrorUtilitiesTests.swift       # Error handling tests
└── ViewControllerTests.swift       # ViewController tests
```

---

## Historical Setup Documentation

This document provides step-by-step instructions that were used to add the test target to the cutter2 Xcode project.

## Prerequisites

- Xcode 15.0 or later
- cutter2 project files with `cutter2Tests/` directory already created

## Steps to Add Test Target

### Method 1: Using Xcode UI (Recommended)

1. **Open the Project**
   - Launch Xcode
   - Open `cutter2.xcodeproj`

2. **Add Test Target**
   - Select the project in the Project Navigator (⌘1)
   - Click the `+` button at the bottom of the targets list
   - Select "Unit Testing Bundle" under macOS
   - Click "Next"

3. **Configure Test Target**
   - Product Name: `cutter2Tests`
   - Team: Select your team
   - Organization Name: MyCometG3
   - Organization Identifier: (your identifier)
   - Language: Swift
   - Project: cutter2
   - Target to be Tested: cutter2
   - Click "Finish"

4. **Delete Auto-Generated Test File**
   - Xcode will create a default test file
   - Delete it (it's redundant with our pre-created files)

5. **Add Existing Test Files**
   - Right-click on the `cutter2Tests` group in Project Navigator
   - Select "Add Files to cutter2..."
   - Navigate to `cutter2Tests/` directory
   - Select all `.swift` files:
     - `cutter2Tests.swift`
     - `MovieMutatorTests.swift`
     - `UtilitiesTests.swift`
   - Make sure "Copy items if needed" is **unchecked**
   - Make sure `cutter2Tests` target is **checked**
   - Click "Add"

6. **Configure Test Target Settings**
   - Select `cutter2Tests` target
   - Go to "Build Settings"
   - Search for "Host Application"
   - Set to `cutter2.app`

7. **Enable Code Coverage**
   - Select the scheme "cutter2" from the scheme selector
   - Click "Edit Scheme..." (or press ⌘<)
   - Select "Test" in the left sidebar
   - Check "Code Coverage" checkbox
   - Select `cutter2.app` in the coverage targets
   - Click "Close"

8. **Verify Setup**
   - Press ⌘U to run tests
   - Tests should build and run successfully

### Method 2: Using Command Line (Alternative)

If you prefer command-line setup, you can use the following approach:

```bash
# This requires manual editing of the project.pbxproj file
# Not recommended unless you're familiar with Xcode project structure
```

## Troubleshooting

### "No such module 'cutter2'" Error

**Solution**: Make sure the test target has the main app target as a dependency:
1. Select `cutter2Tests` target
2. Go to "Build Phases"
3. Expand "Dependencies"
4. Click `+` and add `cutter2` app target

### Tests Not Showing in Test Navigator

**Solution**: 
1. Clean build folder (⇧⌘K)
2. Close and reopen Xcode
3. Build the project (⌘B)
4. Open Test Navigator (⌘6)

### Code Coverage Not Available

**Solution**: 
1. Edit Scheme (⌘<)
2. Select "Test" action
3. Ensure "Code Coverage" is checked
4. Run tests again

### "Could not launch app" Error

**Solution**:
1. Ensure the app target builds successfully
2. Check that Host Application is set correctly
3. Try resetting simulators/devices

## Verification

After setup, verify everything works:

```bash
# Run from command line
xcodebuild test \
  -project cutter2.xcodeproj \
  -scheme cutter2 \
  -destination 'platform=macOS'
```

Expected output should show:
```
Test Suite 'All tests' passed
```

## Next Steps

The test infrastructure is now fully operational:

1. ✅ Test target is set up and running
2. ✅ Initial test suite implemented
3. ✅ Code coverage tracking enabled
4. ✅ CI/CD pipeline configured and active

For information on writing and running tests, see [TESTING_GUIDE.md](TESTING_GUIDE.md).

For ongoing testing strategy, see the Phase 1 completion notes in [CODEBASE_REVIEW.md](CODEBASE_REVIEW.md).

---

**Last Updated**: October 13, 2025  
**Status**: ✅ Setup Complete - Test Infrastructure Operational
