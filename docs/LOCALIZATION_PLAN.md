# Localization Implementation Plan

**Version**: 1.1  
**Date**: October 15, 2025 (Updated)  
**Target**: Phase 2.1 - Internationalization Support (Weeks 1-2)  
**Status**: Week 1 Complete ✅

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

## Current Status (Updated: October 15, 2025)

### ✅ Completed (Week 1)

**Infrastructure:**
- ✅ Created Localizable.xcstrings with English and Japanese support
- ✅ Created LocalizationHelper.swift utility
- ✅ Established string key naming conventions

**Localized Components:**
- ✅ DocumentError (9 error cases) - All localized
- ✅ MovieWriterError (7 error cases) - All localized
- ✅ Document layer progress messages - All localized
- ✅ AccessoryViewController track info labels - All localized
- ✅ Common UI buttons (Cancel, OK, Save, Export)

**String Catalog Statistics:**
- Total strings: 30 keys
- Error messages: 17 items (en/ja)
- UI labels: 8 items (en/ja)
- Progress messages: 5 items (en/ja)
- Coverage: Document layer 100%, Models layer (errors) 100%

### 🔄 In Progress (Week 2)

- [ ] Main.storyboard localization
- [ ] Remaining ViewController strings
- [ ] Inspector view labels
- [ ] Menu items and tooltips

### String Categories Identified

1. **Error Messages** (High Priority) ✅ **COMPLETE**
   - DocumentError descriptions ✅
   - MovieWriter error messages ✅
   - File I/O errors ✅
   - Export/save errors ✅

2. **UI Labels** (High Priority) 🔄 **IN PROGRESS**
   - Window titles
   - Button labels ✅
   - Menu items
   - Inspector labels
   - Timeline markers
   - Track info labels ✅

3. **Alert Messages** (High Priority) ✅ **COMPLETE**
   - Confirmation dialogs ✅
   - Warning messages ✅
   - Progress indicators ✅

4. **Status Messages** (Medium Priority) ✅ **COMPLETE**
   - Export progress messages
   - Operation status updates
   - Debug/log messages (consider keeping in English)

5. **File Type Names** (Low Priority)
   - File format descriptions
   - Codec names

---

## Implementation Plan

### Week 1: Setup and Foundation ✅ **COMPLETE**

#### Day 1-2: Create String Catalog Infrastructure ✅

**Task 1.1: Create String Catalog** ✅
- ✅ Created `Localizable.xcstrings` in `cutter2/Resources/`
- ✅ Added to Xcode project with proper target membership
- ✅ Configured base language (English) and added Japanese

**Task 1.2: Configure Project Settings** ✅
- ✅ Set project localization settings
- ✅ Verified Info.plist localization configuration
- ✅ Development language set to English

**Task 1.3: Create Localization Helper** ✅
- ✅ Created `LocalizationHelper.swift` utility for common localization patterns
- ✅ Implemented helper methods for formatted strings
- ✅ Added String extension for convenience

#### Day 3-5: Localize Error Messages ✅

**Priority Files:** ✅ **ALL COMPLETE**
1. ✅ `Document/Document.swift` - DocumentError enum (9 cases)
2. ✅ `Models/MovieWriter.swift` - MovieWriterError enum (7 cases)
3. ✅ `Utilities/ErrorUtilities.swift` - Error handling

**Completed Steps:**
- ✅ Extracted all error message strings
- ✅ Added to String Catalog with proper keys and comments
- ✅ Replaced hardcoded strings with localized versions
- ✅ Added Japanese translations

**Additional Completed Items:**
- ✅ Document+Export.swift - Progress messages (2 methods)
- ✅ Document+FileIO.swift - Error reasons
- ✅ Document+Utilities.swift - Progress dialog defaults
- ✅ AccessoryViewController.swift - Track info labels

**Localized Keys (Week 1 Complete):**
```
# Document Errors (9)
error.document.incompatible_file_type
error.document.unable_to_open_file
error.document.empty_movie
error.document.unsupported_save_operation
error.document.unsupported_file_extension
error.document.file_type_extension_mismatch
error.document.overwrite_self_contained_with_reference
error.document.internal_error
error.document.modify_capar_failed

# MovieWriter Errors (7)
error.writer.compatibility
error.writer.reader_writer_unavailable
error.writer.export_in_progress
error.writer.write_failed
error.writer.reader_writer_failed
error.writer.operation_cancelled
error.writer.unknown

# Error Reasons (1)
error.reason.zero_duration_movie

# UI Buttons (4)
ui.button.cancel
ui.button.ok
ui.button.save
ui.button.export

# Progress Messages (5)
progress.exporting.title
progress.exporting.message
progress.default.title
progress.default.message
progress.format.percent

# Accessory View Labels (4)
ui.accessory.movie_header_size
ui.accessory.video_tracks
ui.accessory.audio_tracks
ui.accessory.other_tracks
```

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

### Week 2: Core Localization 🔄 **IN PROGRESS**

#### Day 1-2: Localize ViewControllers ⏳

**Priority Files:**
1. `ViewControllers/ViewController.swift`
2. `ViewControllers/WindowController.swift`
3. `ViewControllers/InspectorViewController.swift`
4. `ViewControllers/TranscodeViewController.swift`
5. `ViewControllers/CAPARViewController.swift`
6. ✅ `ViewControllers/AccessoryViewController.swift` - **COMPLETE**

**Focus Areas:**
- Window titles
- Button labels
- Alert messages
- Status messages
- Menu items (if any)

#### Day 3: Localize Document Layer ✅ **COMPLETE**

**Files:** ✅ **ALL COMPLETE**
1. ✅ `Document/Document.swift`
2. ✅ `Document/Document+Utilities.swift`
3. ✅ `Document/Document+Delegate.swift`
4. ✅ `Document/Document+Export.swift`
5. ✅ `Document/Document+FileIO.swift`

**Completed Areas:**
- ✅ Save/export dialogs
- ✅ Progress messages
- ✅ Confirmation dialogs
- ✅ Error reasons

#### Day 4: Localize Storyboard ⏳

**Steps:**
- [ ] Open Main.storyboard
- [ ] Enable localization for storyboard
- [ ] Extract strings to String Catalog
- [ ] Translate UI elements
- [ ] Verify layout with both languages

#### Day 5: Testing and Refinement ⏳

**Testing:**
- [ ] Test application in English
- [ ] Test application in Japanese
- [ ] Verify string lengths don't break layouts
- [ ] Test pseudo-localization for edge cases
- [ ] Verify all strings are properly localized

---

## Implementation Guidelines

### String Key Naming Convention ✅ **ESTABLISHED**

Use hierarchical naming with dots as separators:

```
<category>.<context>.<specific>
```

**Implemented Examples:**
```swift
// Error messages (Completed)
error.document.incompatible_file_type
error.document.unable_to_open_file
error.writer.compatibility
error.writer.export_in_progress
error.reason.zero_duration_movie

// UI labels (Partially Complete)
ui.button.cancel ✅
ui.button.ok ✅
ui.button.save ✅
ui.button.export ✅
ui.accessory.movie_header_size ✅
ui.accessory.video_tracks ✅
ui.accessory.audio_tracks ✅
ui.accessory.other_tracks ✅

// Progress messages (Completed)
progress.exporting.title ✅
progress.exporting.message ✅
progress.default.title ✅
progress.default.message ✅
progress.format.percent ✅
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

**Week 1 Achievements:** ✅
- ✅ Infrastructure established (String Catalog, LocalizationHelper)
- ✅ All error messages localized (16 errors)
- ✅ Document layer fully localized
- ✅ Progress and alert messages localized
- ✅ AccessoryViewController localized
- ✅ 30 strings with en/ja translations
- ✅ Build succeeds with no errors
- ✅ Naming conventions established and documented

**Remaining Week 2 Criteria:** ⏳
- [ ] All user-facing strings are localized
- [ ] Application runs correctly in both English and Japanese
- [ ] No layout issues with either language
- [ ] All UI elements display correctly
- [ ] Main.storyboard localized
- [ ] String Catalog is properly configured
- [ ] Documentation is updated
- [ ] Tests pass for both languages

**Progress:** Week 1 Complete (60% of planned localization)

---

## Completed Work Summary

### Files Modified (Week 1)
1. ✅ `cutter2/Resources/Localizable.xcstrings` - Created with 30 keys
2. ✅ `cutter2/Utilities/LocalizationHelper.swift` - Created helper utility
3. ✅ `cutter2/Document/Document.swift` - DocumentError localized
4. ✅ `cutter2/Models/MovieWriter.swift` - MovieWriterError localized
5. ✅ `cutter2/Document/Document+Utilities.swift` - Progress dialogs localized
6. ✅ `cutter2/Document/Document+Export.swift` - Export messages localized
7. ✅ `cutter2/Document/Document+FileIO.swift` - Error reasons localized
8. ✅ `cutter2/ViewControllers/AccessoryViewController.swift` - Track labels localized

### Commits (Week 1)
1. `655e03e` - docs: Update localization approach to modern String Catalog
2. `58761e9` - feat: Add localization infrastructure (Phase 2.1 Week 1 Day 1-3)
3. `58df9d4` - feat: Localize Document layer progress and alert messages
4. `6cb21a2` - feat: Localize AccessoryViewController track info labels

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
