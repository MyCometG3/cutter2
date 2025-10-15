#!/usr/bin/env swift

import Foundation

// Test localization strings
let strings = [
    "error.document.incompatible_file_type",
    "error.writer.compatibility",
    "ui.button.cancel",
    "progress.exporting.title",
    "menu.file",
    "inspector.current_time"
]

print("Testing Localization Strings:")
print("=============================\n")

for key in strings {
    let localized = NSLocalizedString(key, comment: "")
    let isLocalized = localized != key
    let status = isLocalized ? "✅" : "❌"
    print("\(status) \(key)")
    print("   → \(localized)")
    print()
}

print("Summary:")
print("--------")
let count = strings.count
print("Total strings tested: \(count)")
print("\nNote: This test requires the app bundle to be built with Localizable.xcstrings")
