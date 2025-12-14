//
//  TrackOffsetViewController.swift
//  cutter2
//
//  Created on 2025-12-07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Track Offset Row Data
/* ============================================ */

/// Data model for a table row representing a track
@MainActor
class TrackOffsetRow: NSObject {
    @objc dynamic var trackID: String
    @objc dynamic var mediaType: String
    @objc dynamic var duration: String
    @objc dynamic var currentOffset: String
    @objc dynamic var newOffsetString: String
    @objc dynamic var isReference: String
    
    var trackDescriptor: TrackDescriptor
    var newOffset: CMTime?
    var validationError: String?
    
    init(descriptor: TrackDescriptor, mutator: MovieMutator) {
        self.trackDescriptor = descriptor
        self.trackID = "\(descriptor.id)"
        self.mediaType = descriptor.mediaType.rawValue
        self.duration = mutator.shortTimeString(descriptor.duration, withDecimals: true)
        self.currentOffset = mutator.shortTimeString(descriptor.currentOffset, withDecimals: true)
        self.newOffsetString = mutator.shortTimeString(descriptor.currentOffset, withDecimals: true)
        
        // Check if track is reference or self-contained
        if let track = mutator.internalMovie.track(withTrackID: descriptor.id) {
            self.isReference = track.isSelfContained ? "Self" : "Ref"
        } else {
            self.isReference = "?"
        }
        
        self.newOffset = descriptor.currentOffset
        self.validationError = nil
        
        super.init()
    }
}

/* ============================================ */
// MARK: - Track Offset View Controller
/* ============================================ */

@MainActor
class TrackOffsetViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    /* ============================================ */
    // MARK: - Outlets
    /* ============================================ */
    
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var applyButton: NSButton!
    
    /* ============================================ */
    // MARK: - Properties
    /* ============================================ */
    
    private var parentWindow: NSWindow?
    private weak var document: Document?
    private weak var mutator: MovieMutator?
    private var rows: [TrackOffsetRow] = []
    private var referenceFrameRate: Float = 0.0
    
    /* ============================================ */
    // MARK: - Lifecycle
    /* ============================================ */
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.dataSource = self
        tableView.delegate = self
        
        updateStatusLabel("")
        applyButton.isEnabled = false
    }
    
    /* ============================================ */
    // MARK: - Public Methods
    /* ============================================ */
    
    /// Begin sheet modal for track offset editing
    ///
    /// - Parameters:
    ///   - parentWindow: Parent window
    ///   - document: Document instance
    ///   - handler: Completion handler
    public func beginSheetModal(for parentWindow: NSWindow, document: Document, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        self.parentWindow = parentWindow
        self.document = document
        self.mutator = document.movieMutator
        
        guard let mutator = self.mutator else {
            NSSound.beep()
            return
        }
        
        // Load track descriptors
        let descriptors = mutator.trackDescriptors()
        rows = descriptors.map { TrackOffsetRow(descriptor: $0, mutator: mutator) }
        
        // Find reference frame rate from first video track
        referenceFrameRate = descriptors.first(where: { $0.mediaType == .video && $0.nominalFrameRate > 0 })?.nominalFrameRate ?? 0.0
        
        tableView.reloadData()
        
        guard let sheet = self.view.window else { return }
        parentWindow.beginSheet(sheet, completionHandler: handler)
    }
    
    /// End sheet with response
    ///
    /// - Parameter response: Modal response
    private func endSheet(_ response: NSApplication.ModalResponse) {
        guard let parent = self.parentWindow else { return }
        guard let sheet = self.view.window else { return }
        
        parent.endSheet(sheet, returnCode: response)
    }
    
    /* ============================================ */
    // MARK: - Actions
    /* ============================================ */
    
    @IBAction func apply(_ sender: Any?) {
        guard let mutator = self.mutator else {
            NSSound.beep()
            return
        }
        
        guard let document = self.document else {
            NSSound.beep()
            return
        }
        
        // Validate all offsets
        var hasErrors = false
        for row in rows {
            if let error = row.validationError {
                updateStatusLabel("Validation error: \(error)")
                hasErrors = true
                break
            }
        }
        
        if hasErrors {
            NSSound.beep()
            return
        }
        
        // Build offsets dictionary
        var offsets: [CMPersistentTrackID: CMTime] = [:]
        for row in rows {
            if let newOffset = row.newOffset {
                offsets[row.trackDescriptor.id] = newOffset
            }
        }
        
        // Disable UI during operation
        applyButton.isEnabled = false
        tableView.isEnabled = false
        updateStatusLabel(NSLocalizedString("track.offset.applying", comment: "Applying offsets..."))
        
        // Apply offsets
        do {
            try mutator.applyTrackOffsets(offsets, undoManager: document.undoManagerWrapper)
            
            // Success - close sheet
            endSheet(.continue)
        } catch {
            // Show error
            let errorToShow: NSError
            if let docError = error as? DocumentError {
                errorToShow = docError.nsError
            } else {
                errorToShow = error as NSError
            }
            
            updateStatusLabel("Error: \(errorToShow.localizedDescription)")
            applyButton.isEnabled = true
            tableView.isEnabled = true
            
            // Show error sheet
            document.showErrorSheet(errorToShow)
        }
    }
    
    @IBAction func cancel(_ sender: Any?) {
        endSheet(.cancel)
    }
    
    @IBAction func reset(_ sender: Any?) {
        guard let mutator = self.mutator else { return }
        
        // Reset all rows to current offsets
        for row in rows {
            row.newOffsetString = mutator.shortTimeString(row.trackDescriptor.currentOffset, withDecimals: true)
            row.newOffset = row.trackDescriptor.currentOffset
            row.validationError = nil
        }
        
        tableView.reloadData()
        updateStatusLabel("")
        applyButton.isEnabled = false
    }
    
    /* ============================================ */
    // MARK: - NSTableViewDataSource
    /* ============================================ */
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }
    
    /* ============================================ */
    // MARK: - NSTableViewDelegate
    /* ============================================ */
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        guard let tableColumn = tableColumn else { return nil }
        
        let rowData = rows[row]
        let columnID = tableColumn.identifier.rawValue
        
        // Get or create cell view
        let cellView = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        
        switch columnID {
        case "trackID":
            cellView.textField?.stringValue = rowData.trackID
            cellView.textField?.isEditable = false
        case "mediaType":
            cellView.textField?.stringValue = rowData.mediaType
            cellView.textField?.isEditable = false
        case "duration":
            cellView.textField?.stringValue = rowData.duration
            cellView.textField?.isEditable = false
        case "currentOffset":
            cellView.textField?.stringValue = rowData.currentOffset
            cellView.textField?.isEditable = false
        case "newOffset":
            cellView.textField?.stringValue = rowData.newOffsetString
            cellView.textField?.isEditable = true
            cellView.textField?.delegate = self
            cellView.textField?.tag = row
            
            // Set placeholder hint for frame format
            // Use track's own frame rate if video, or reference frame rate from first video track
            let fps: Float
            if rowData.trackDescriptor.mediaType == .video && rowData.trackDescriptor.nominalFrameRate > 0 {
                fps = rowData.trackDescriptor.nominalFrameRate
            } else {
                fps = referenceFrameRate
            }
            
            if fps > 0 {
                cellView.textField?.placeholderString = String(format: "e.g., 30f@%.2f", fps)
            } else {
                cellView.textField?.placeholderString = nil
            }
        case "reference":
            cellView.textField?.stringValue = rowData.isReference
            cellView.textField?.isEditable = false
        default:
            cellView.textField?.stringValue = ""
        }
        
        return cellView
    }
    
    /* ============================================ */
    // MARK: - Helper Methods
    /* ============================================ */
    
    /// Update status label text
    ///
    /// - Parameter text: Status text
    private func updateStatusLabel(_ text: String) {
        statusLabel.stringValue = text
    }
    
    /// Validate input text in real-time (during typing)
    /// Shows error but doesn't modify values
    ///
    /// - Parameters:
    ///   - text: Input text
    ///   - row: Row index
    ///   - textField: The text field being edited
    private func validateInputRealtime(_ text: String, for row: Int, textField: NSTextField) {
        guard row < rows.count else { return }
        guard let mutator = self.mutator else { return }
        
        let rowData = rows[row]
        
        do {
            // Parse the offset
            let parsedTime = try mutator.parseTimeOffset(text)
            
            // Validate the offset
            guard CMTIME_IS_VALID(parsedTime) else {
                throw DocumentError.invalidTimeFormat
            }
            
            // Calculate delta
            let delta = parsedTime - rowData.trackDescriptor.currentOffset
            
            // Validate offset magnitude doesn't exceed track duration
            let absOffset = abs(delta.seconds)
            let trackDuration = rowData.trackDescriptor.duration.seconds
            
            if absOffset > trackDuration {
                throw DocumentError.trackOffsetExceedsDuration
            }
            
            // Valid - clear error and reset text color to default
            rowData.validationError = nil
            textField.textColor = nil  // Reset to default (allows system to handle selection color)
            updateStatusLabel("")
            
        } catch {
            // Invalid - set error and change text color
            let errorMessage: String
            if let docError = error as? DocumentError {
                errorMessage = docError.nsError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
            
            rowData.validationError = errorMessage
            textField.textColor = NSColor.systemRed
            
            let format = NSLocalizedString("track.offset.validation_error_format",
                                          comment: "Track offset validation error message format")
            updateStatusLabel(String(format: format, rowData.trackID, errorMessage))
        }
    }
    
    /// Validate and commit new offset for a row (when editing ends)
    ///
    /// - Parameters:
    ///   - text: Input text
    ///   - row: Row index
    private func validateAndCommitOffset(_ text: String, for row: Int) {
        guard row < rows.count else { return }
        guard let mutator = self.mutator else { return }
        
        let rowData = rows[row]
        
        do {
            // Parse the offset
            let parsedTime = try mutator.parseTimeOffset(text)
            
            // Validate the offset
            guard CMTIME_IS_VALID(parsedTime) else {
                throw DocumentError.invalidTimeFormat
            }
            
            // Calculate delta
            let delta = parsedTime - rowData.trackDescriptor.currentOffset
            
            // Validate offset magnitude doesn't exceed track duration
            let absOffset = abs(delta.seconds)
            let trackDuration = rowData.trackDescriptor.duration.seconds
            
            if absOffset > trackDuration {
                throw DocumentError.trackOffsetExceedsDuration
            }
            
            // Valid - commit the value
            rowData.newOffset = parsedTime
            rowData.newOffsetString = text
            rowData.validationError = nil
            
            updateStatusLabel("")
            applyButton.isEnabled = hasChanges()
            
        } catch {
            // Invalid - reset to current offset
            let errorMessage: String
            if let docError = error as? DocumentError {
                errorMessage = docError.nsError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
            
            // Reset to original value
            rowData.newOffsetString = mutator.shortTimeString(rowData.trackDescriptor.currentOffset, withDecimals: true)
            rowData.newOffset = rowData.trackDescriptor.currentOffset
            rowData.validationError = nil
            
            let format = NSLocalizedString("track.offset.validation_error_format",
                                          comment: "Track offset validation error message format")
            updateStatusLabel(String(format: format, rowData.trackID, errorMessage))
            applyButton.isEnabled = hasChanges()
        }
        
        // Reset text color before reloading
        if let cellView = tableView.view(atColumn: tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("newOffset")), 
                                          row: row, 
                                          makeIfNecessary: false) as? NSTableCellView {
            cellView.textField?.textColor = nil
        }
        
        // Reload to update display
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }
    
    /// Check if any rows have changes
    ///
    /// - Returns: True if there are changes
    private func hasChanges() -> Bool {
        for row in rows {
            if let newOffset = row.newOffset,
               newOffset != row.trackDescriptor.currentOffset {
                return true
            }
        }
        return false
    }
}

/* ============================================ */
// MARK: - NSTextFieldDelegate
/* ============================================ */

extension TrackOffsetViewController: NSTextFieldDelegate {
    
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        
        let row = textField.tag
        let text = textField.stringValue
        
        // Validate and commit (reset to original if invalid)
        validateAndCommitOffset(text, for: row)
    }
    
    func controlTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        
        let row = textField.tag
        let text = textField.stringValue
        
        // Real-time validation for visual feedback (don't reload to avoid interrupting input)
        validateInputRealtime(text, for: row, textField: textField)
    }
}
