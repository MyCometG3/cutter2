# Track Offset Storyboard Integration Guide

This document provides step-by-step instructions for integrating the Track Offset UI into the Main.storyboard file using Xcode on macOS.

## Prerequisites
- macOS with Xcode 16.0 or later
- cutter2 project open in Xcode

## Part 1: Add Track Offset Scene to Main.storyboard

### 1. Create Window Controller Scene

1. Open `Main.storyboard` in Xcode
2. From the Object Library, drag a **Window Controller** onto the canvas
3. Select the Window Controller and set the following in the Identity Inspector:
   - Storyboard ID: `TrackOffsetSheet Controller`
4. Set the following in the Attributes Inspector:
   - Window → Title: `Track Offset`
   - Window → Initial Position: Center Parent Window

### 2. Create View Controller

1. The Window Controller should already have a connected View Controller
2. Select the View Controller and set the following in the Identity Inspector:
   - Class: `TrackOffsetViewController`
   - Storyboard ID: `TrackOffsetSheet ViewController`

### 3. Design the View Controller's View

Add the following UI elements to the View Controller's view:

#### Main Container (NSBox or NSStackView)
- Use Vertical Stack View for easy layout

#### Table View Section
1. Add **Scroll View** containing **NSTableView**
   - Table View → Columns: 6
   - Configure columns:
     1. **Track ID** (identifier: `trackID`)
        - Title: Use localization key `track.offset.column.trackID`
        - Width: 80pt
        - Editable: NO
     2. **Media Type** (identifier: `mediaType`)
        - Title: Use localization key `track.offset.column.mediaType`
        - Width: 100pt
        - Editable: NO
     3. **Duration** (identifier: `duration`)
        - Title: Use localization key `track.offset.column.duration`
        - Width: 100pt
        - Editable: NO
     4. **Current Offset** (identifier: `currentOffset`)
        - Title: Use localization key `track.offset.column.current`
        - Width: 120pt
        - Editable: NO
     5. **New Offset** (identifier: `newOffset`)
        - Title: Use localization key `track.offset.column.new`
        - Width: 120pt
        - Editable: YES (this is the only editable column)
     6. **Type** (identifier: `reference`)
        - Title: Use localization key `track.offset.column.reference`
        - Width: 60pt
        - Editable: NO

   - Set constraints:
     - Leading: 20pt to superview
     - Trailing: 20pt to superview
     - Top: 20pt to superview
     - Height: 300pt (or flexible with minimum)

#### Status Label
1. Add **NSTextField** (Label)
   - Identifier: `statusLabel`
   - Text: (empty)
   - Alignment: Left
   - Text Color: System Red (for errors) or System Gray (for info)
   - Set constraints:
     - Leading: 20pt to superview
     - Trailing: 20pt to superview
     - Top: 8pt to table view
     - Height: 20pt (fixed)

#### Button Container
1. Add **Horizontal Stack View** for buttons
   - Distribution: Fill Equally or Fill Proportionally
   - Spacing: 8pt

2. Add three buttons to the stack:
   1. **Reset Button**
      - Title: Use localization key `track.offset.reset`
      - Action: Connect to `reset:` in TrackOffsetViewController
      - Key Equivalent: None
   
   2. **Cancel Button**
      - Title: Use localization key `track.offset.cancel`
      - Action: Connect to `cancel:` in TrackOffsetViewController
      - Key Equivalent: Escape (ESC)
   
   3. **Apply Button**
      - Title: Use localization key `track.offset.apply`
      - Action: Connect to `apply:` in TrackOffsetViewController
      - Key Equivalent: Return/Enter
      - Initial State: Disabled (will be enabled when changes are detected)

   - Set stack view constraints:
     - Trailing: 20pt to superview
     - Bottom: 20pt to superview
     - Top: 12pt to status label
     - Height: 32pt (or standard button height)

### 4. Connect Outlets

Select the TrackOffsetViewController scene and connect the following outlets:

1. **tableView** → Connect to the NSTableView
2. **statusLabel** → Connect to the status NSTextField
3. **applyButton** → Connect to the Apply button

### 5. Set Table View Delegates

1. Select the NSTableView
2. In the Connections Inspector, connect:
   - **dataSource** → TrackOffsetViewController
   - **delegate** → TrackOffsetViewController

## Part 2: Add Menu Item to Configure Menu

### 1. Locate Configure Menu

1. In Main.storyboard, find the **Configure** menu in the menu bar
   - If there is no Configure menu, create one:
     1. Find the main menu bar
     2. Add a new **Menu** item
     3. Set title to "Configure"

### 2. Add Track Offset Menu Item

1. Add a new **Menu Item** to the Configure menu
2. Set the following properties:
   - Title: `Track Offset…`
   - Key Equivalent: None (or assign a keyboard shortcut like ⌘⇧T if desired)
   - Action: `showTrackOffsetPanel:` (connect to **First Responder**)

3. Position the menu item logically (recommended: after CAPAR-related items)

### 3. Connect Action to First Responder

1. Right-click (or control-click) on the menu item
2. Drag from the **Sent Actions → selector** connector to **First Responder**
3. Select `showTrackOffsetPanel:` from the list

## Part 3: Verify Connections

### Check List

- [ ] Window Controller has Storyboard ID: `TrackOffsetSheet Controller`
- [ ] View Controller has Class: `TrackOffsetViewController`
- [ ] Table View has 6 columns with correct identifiers
- [ ] Table View dataSource and delegate are connected to view controller
- [ ] All three buttons (Reset, Cancel, Apply) have actions connected
- [ ] Status label outlet is connected
- [ ] Table view outlet is connected
- [ ] Apply button outlet is connected
- [ ] Menu item action is connected to First Responder

## Part 4: Build and Test

1. Build the project (⌘B)
2. Fix any build errors related to missing outlets or actions
3. Run the application
4. Open a movie file
5. Select **Configure → Track Offset…** from the menu
6. Verify the sheet appears with the table showing all tracks
7. Test editing offset values
8. Test validation (try invalid formats, negative offsets exceeding duration)
9. Test Apply, Cancel, and Reset buttons
10. Test undo/redo after applying offsets

## Troubleshooting

### Sheet doesn't appear
- Check that the Storyboard ID is exactly `TrackOffsetSheet Controller`
- Verify the scene identifier in `Document+UI.swift` matches

### Table is empty
- Check that dataSource is connected
- Verify `trackDescriptors()` is returning data
- Check console for any error messages

### Buttons don't work
- Verify action connections to the view controller
- Check that selectors match method names exactly (including colon)

### Validation not working
- Check that NSTextField delegate is set to view controller
- Verify `controlTextDidChange:` and `controlTextDidEndEditing:` are implemented

### Apply button always disabled
- Check that `applyButton` outlet is connected
- Verify `hasChanges()` logic in view controller

## Accessibility

Ensure all UI elements have proper accessibility labels:

1. Select each table column and set **Accessibility → Label**:
   - Column 1: "Track ID"
   - Column 2: "Media Type"
   - Column 3: "Duration"
   - Column 4: "Current Offset"
   - Column 5: "New Offset"
   - Column 6: "Type"

2. Set button accessibility labels:
   - Reset button: "Reset all offsets"
   - Cancel button: "Cancel changes"
   - Apply button: "Apply offsets"

3. Enable **VoiceOver** testing to verify proper navigation

## Localization

The UI uses the following localization keys (already added to `Localizable.xcstrings`):

- `track.offset.title` - Window title
- `track.offset.column.trackID` - Track ID column header
- `track.offset.column.mediaType` - Media Type column header
- `track.offset.column.duration` - Duration column header
- `track.offset.column.current` - Current Offset column header
- `track.offset.column.new` - New Offset column header
- `track.offset.column.reference` - Type column header
- `track.offset.apply` - Apply button
- `track.offset.cancel` - Cancel button
- `track.offset.reset` - Reset button
- `track.offset.applying` - Status message during application
- `track.offset.invalid` - Invalid format error
- `track.offset.exceedsDuration` - Exceeds duration error

All strings are available in English and Japanese.

## Notes

- The table view uses cell-based layout for simplicity
- Editable column uses NSTextField with delegate for real-time validation
- Error highlighting is done by changing background color in `tableView(_:viewFor:row:)`
- The sheet modal pattern follows the existing CAPAR sheet implementation
- Window position is set to center on parent for consistency

## Screenshots

After implementation, take screenshots showing:
1. Empty table (no movie loaded)
2. Table with multiple tracks (video, audio)
3. Editing an offset value
4. Validation error (red highlighting)
5. Success state
6. Menu item location

## Future Enhancements

Potential improvements for future versions:

1. Add tooltips explaining time format options
2. Add preset offset buttons (e.g., "+1s", "-1s", "+30f", "-30f")
3. Add visual preview of offset changes
4. Add batch operations (apply same offset to all tracks)
5. Add offset history/favorites
6. Support for additional time formats (SMPTE timecode)
