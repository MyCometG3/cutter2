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
            updateStatusLabel("Error: \(error.localizedDescription)")
            applyButton.isEnabled = true
            tableView.isEnabled = true
            
            // Show error sheet
            document.showErrorSheet(error as NSError)
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
        
        let rowData = rows[row]
        let columnID = tableColumn?.identifier.rawValue ?? ""
        
        // Get or create cell view
        let cellView = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: self) as? NSTableCellView
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
            
            // Highlight if there's a validation error
            if rowData.validationError != nil {
                cellView.textField?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.2)
            } else {
                cellView.textField?.backgroundColor = NSColor.controlBackgroundColor
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
    
    /// Validate and parse new offset for a row
    ///
    /// - Parameters:
    ///   - text: Input text
    ///   - row: Row index
    private func validateAndParseOffset(_ text: String, for row: Int) {
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
            
            // For negative offsets, check against track duration
            if delta < CMTime.zero {
                let absOffset = CMTime.zero - delta
                if absOffset > rowData.trackDescriptor.duration {
                    throw DocumentError.trackOffsetExceedsDuration
                }
            }
            
            // Valid
            rowData.newOffset = parsedTime
            rowData.newOffsetString = text
            rowData.validationError = nil
            
            updateStatusLabel("")
            applyButton.isEnabled = hasChanges()
            
        } catch {
            // Invalid
            rowData.validationError = error.localizedDescription
            updateStatusLabel("Invalid offset for track \(rowData.trackID): \(error.localizedDescription)")
            applyButton.isEnabled = false
        }
        
        // Reload the row to update highlighting
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
        
        validateAndParseOffset(text, for: row)
    }
    
    func controlTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        
        let row = textField.tag
        let text = textField.stringValue
        
        // Real-time validation
        validateAndParseOffset(text, for: row)
    }
}
