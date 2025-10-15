# Localization Implementation Plan

**Version**: 1.0  
**Date**: October 14, 2025  
**Target**: Phase 2.1 - Internationalization Support (Weeks 1-2)

---

## Overview

This document outlines the implementation plan for adding comprehensive localization support to cutter2 using modern String Catalogs (.xcstrings format) introduced in Xcode 15.

### Goals

- Implement full localization for English (base) and Japanese
- Use modern String Catalog approach (.xcstrings)
- Maintain code readability and maintainability
- Enable easy addition of future languages
- Ensure all user-facing strings are localized

---

## Current Status

### Existing Localization
- **Base.lproj**: Contains Main.storyboard only
- **NSLocalizedString usage**: 1 instance found in `Document+Utilities.swift`
- **Hardcoded strings**: Extensive use throughout the codebase

### String Categories Identified

1. **Error Messages** (High Priority)
   - DocumentError descriptions
   - MovieWriter error messages
   - File I/O errors
   - Export/save errors

2. **UI Labels** (High Priority)
   - Window titles
   - Button labels
   - Menu items
   - Inspector labels
   - Timeline markers

3. **Alert Messages** (High Priority)
   - Confirmation dialogs
   - Warning messages
   - Progress indicators

4. **Status Messages** (Medium Priority)
   - Export progress messages
   - Operation status updates
   - Debug/log messages (consider keeping in English)

5. **File Type Names** (Low Priority)
   - File format descriptions
   - Codec names

---

## Implementation Plan

### Week 1: Setup and Foundation

#### Day 1-2: Create String Catalog Infrastructure

**Task 1.1: Create String Catalog**
- Create `Localizable.xcstrings` in `cutter2/Resources/`
- Add to Xcode project with proper target membership
- Configure base language (English) and add Japanese

**Task 1.2: Configure Project Settings**
- Set project localization settings
- Verify Info.plist localization configuration
- Set development language to English

**Task 1.3: Create Localization Helper**
- Create `LocalizationHelper.swift` utility for common localization patterns
- Implement helper methods for formatted strings

#### Day 3-5: Localize Error Messages

**Priority Files:**
1. `Document/Document.swift` - DocumentError enum
2. `Models/MovieWriter.swift` - MovieWriterError enum
3. `Utilities/ErrorUtilities.swift` - Error handling

**Steps:**
- Extract all error message strings
- Add to String Catalog with proper keys and comments
- Replace hardcoded strings with localized versions
- Add Japanese translations

**Example Keys:**
```
error.incompatible_file_type
error.unable_to_open_file
error.empty_movie
error.invalid_time_range
error.export_session_incompatible
error.reader_writer_unavailable
error.export_in_progress
error.operation_cancelled
```

### Week 2: Core Localization

#### Day 1-2: Localize ViewControllers

**Priority Files:**
1. `ViewControllers/ViewController.swift`
2. `ViewControllers/WindowController.swift`
3. `ViewControllers/InspectorViewController.swift`
4. `ViewControllers/TranscodeViewController.swift`
5. `ViewControllers/CAPARViewController.swift`
6. `ViewControllers/AccessoryViewController.swift`

**Focus Areas:**
- Window titles
- Button labels
- Alert messages
- Status messages
- Menu items (if any)

#### Day 3: Localize Document Layer

**Files:**
1. `Document/Document.swift`
2. `Document/Document+Utilities.swift`
3. `Document/Document+Delegate.swift`

**Focus Areas:**
- Save/export dialogs
- Progress messages
- Confirmation dialogs

#### Day 4: Localize Storyboard

**Steps:**
- Open Main.storyboard
- Enable localization for storyboard
- Extract strings to String Catalog
- Translate UI elements
- Verify layout with both languages

#### Day 5: Testing and Refinement

**Testing:**
- Test application in English
- Test application in Japanese
- Verify string lengths don't break layouts
- Test pseudo-localization for edge cases
- Verify all strings are properly localized

---

## Implementation Guidelines

### String Key Naming Convention

Use hierarchical naming with dots as separators:

```
<category>.<context>.<specific>
```

Examples:
```swift
// Error messages
error.file.incompatible_type
error.file.unable_to_open
error.export.session_incompatible
error.export.in_progress

// UI labels
ui.window.main_title
ui.button.cancel
ui.button.export
ui.timeline.current_marker
ui.timeline.start_marker
ui.timeline.end_marker

// Alert messages
alert.save.title
alert.save.message
alert.export.title
alert.export.message

// Progress messages
progress.exporting
progress.saving
progress.loading
```

### Localization Methods

#### For Simple Strings
```swift
// Modern Swift approach (preferred)
let message = String(localized: "error.file.incompatible_type",
                     comment: "Error when file type is incompatible")

// Traditional approach (also supported)
let message = NSLocalizedString("error.file.incompatible_type",
                                comment: "Error when file type is incompatible")
```

#### For Formatted Strings
```swift
// With String interpolation
let message = String(localized: "progress.exporting_percent \(percent)",
                     comment: "Export progress message with percentage")

// With format specifiers
let message = String(format: NSLocalizedString("progress.exporting_percent",
                                               comment: "Export progress with %"),
                     progress * 100)
```

#### For Plural Rules
```swift
// String Catalog supports plural variations automatically
let message = String(localized: "files.selected.count \(count)",
                     comment: "Number of files selected")
```

### Adding Comments

Always include meaningful comments for translators:

```swift
// Good comments explain context and usage
String(localized: "ui.button.cancel",
       comment: "Cancel button for canceling save/export operations")

// Include format information
String(localized: "progress.time_remaining",
       comment: "Time remaining for export. Format: 'X minutes remaining'")

// Explain plural rules
String(localized: "files.count",
       comment: "Number of files. Supports plural variations: 1 file, 2 files, etc.")
```

---

## String Catalog Structure

### Example Localizable.xcstrings

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "error.file.incompatible_type" : {
      "comment" : "Error message when file type is incompatible with the application",
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Incompatible file type detected."
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "互換性のないファイル形式が検出されました。"
          }
        }
      }
    },
    "ui.button.cancel" : {
      "comment" : "Cancel button for canceling operations",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cancel"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "キャンセル"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

---

## File-by-File Localization Checklist

### Document Layer

- [ ] **Document.swift**
  - [ ] DocumentError descriptions
  - [ ] Save dialog strings
  - [ ] Export progress messages
  - [ ] Alert messages
  - [ ] Window titles

- [ ] **Document+Utilities.swift**
  - [ ] Update existing NSLocalizedString usage
  - [ ] Alert buttons
  - [ ] Confirmation dialogs

- [ ] **Document+Delegate.swift**
  - [ ] Delegate callback messages
  - [ ] Status updates

### Models Layer

- [ ] **MovieWriter.swift**
  - [ ] MovieWriterError descriptions
  - [ ] Export status messages
  - [ ] Progress notifications
  - [ ] Log messages (consider keeping in English)

- [ ] **MovieMutator.swift**
  - [ ] Operation error messages
  - [ ] Validation messages

### ViewControllers Layer

- [ ] **ViewController.swift**
  - [ ] Window titles
  - [ ] Menu items
  - [ ] Keyboard shortcut descriptions
  - [ ] Timeline labels

- [ ] **WindowController.swift**
  - [ ] Window title formatting
  - [ ] Fullscreen messages

- [ ] **InspectorViewController.swift**
  - [ ] Inspector labels
  - [ ] Time format strings
  - [ ] Frame rate strings

- [ ] **TranscodeViewController.swift**
  - [ ] Codec names
  - [ ] Preset names
  - [ ] Quality descriptions

- [ ] **CAPARViewController.swift**
  - [ ] Aspect ratio labels
  - [ ] Aperture descriptions

- [ ] **AccessoryViewController.swift**
  - [ ] Save options
  - [ ] Format descriptions

### Utilities Layer

- [ ] **ErrorUtilities.swift**
  - [ ] Error presentation strings
  - [ ] Alert formatting

### Resources

- [ ] **Main.storyboard**
  - [ ] All UI element labels
  - [ ] Button titles
  - [ ] Menu items
  - [ ] Placeholder text

---

## Testing Strategy

### Manual Testing

1. **English Environment**
   - Launch app in English locale
   - Verify all strings display correctly
   - Test all error conditions
   - Check alert messages
   - Verify export dialogs

2. **Japanese Environment**
   - Launch app in Japanese locale
   - Verify all strings display correctly
   - Check for layout issues with longer strings
   - Verify font rendering
   - Test all error conditions

3. **Pseudo-Localization**
   - Use extended characters
   - Test with extra-long strings
   - Verify layout flexibility

### Automated Testing

Create localization tests:

```swift
// LocalizationTests.swift
import XCTest
@testable import cutter2

final class LocalizationTests: XCTestCase {
    func testAllErrorMessagesLocalized() {
        // Test all DocumentError cases have localized strings
        // Test all MovieWriterError cases have localized strings
    }
    
    func testUIStringsLocalized() {
        // Verify common UI strings are present in catalog
    }
    
    func testStringFormatting() {
        // Test formatted strings work correctly
    }
}
```

---

## Risks and Mitigation

### Risk 1: Breaking Existing Functionality
**Mitigation**: 
- Test thoroughly after each change
- Create unit tests for localized strings
- Review all changes before committing

### Risk 2: Layout Issues with Japanese Text
**Mitigation**:
- Japanese text can be longer or shorter than English
- Test layouts with both languages
- Use Auto Layout properly
- Consider using shorter alternatives for space-constrained UI

### Risk 3: Missing Strings
**Mitigation**:
- Use Xcode's string extraction tools
- Search for hardcoded strings programmatically
- Review all user-facing code paths
- Use fallback language (English) for untranslated strings

### Risk 4: Format String Mismatches
**Mitigation**:
- Document format specifiers in comments
- Test all formatted strings
- Use type-safe string interpolation where possible

---

## Success Criteria

- [ ] All user-facing strings are localized
- [ ] Application runs correctly in both English and Japanese
- [ ] No layout issues with either language
- [ ] All error messages are localized
- [ ] All UI elements display correctly
- [ ] String Catalog is properly configured
- [ ] Documentation is updated
- [ ] Tests pass for both languages

---

## Future Enhancements

### Additional Languages
- German
- French
- Spanish
- Chinese (Simplified/Traditional)
- Korean

### Advanced Features
- Region-specific formatting
- Currency localization
- Date/time format preferences
- Right-to-left language support (Arabic, Hebrew)

### Localization Management
- Integration with translation services
- XLIFF export/import workflow
- Continuous localization updates
- Translation memory

---

## References

- [Apple Localization Guide](https://developer.apple.com/localization/)
- [String Catalogs Documentation](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [NSLocalizedString Documentation](https://developer.apple.com/documentation/foundation/nslocalizedstring)
- [Formatting Strings](https://developer.apple.com/documentation/foundation/strings_and_text)

---

**Document Status**: Draft  
**Last Updated**: October 14, 2025  
**Next Review**: After Week 1 completion
