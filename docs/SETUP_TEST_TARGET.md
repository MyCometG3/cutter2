# Setup Test Target in Xcode

This document provides step-by-step instructions to add the test target to the cutter2 Xcode project.

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

Once the test target is set up:

1. ✅ Run existing tests to ensure setup is correct
2. ✅ Check code coverage report
3. ✅ Start writing additional tests
4. ✅ Configure CI/CD pipeline (already created in `.github/workflows/test.yml`)

See [TESTING_GUIDE.md](TESTING_GUIDE.md) for detailed testing documentation.

---

**Last Updated**: October 13, 2025  
**Status**: Initial Setup Instructions
