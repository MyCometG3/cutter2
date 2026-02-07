//
//  DocumentController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/07.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

@MainActor
class DocumentController: NSDocumentController {
    
    /* ============================================ */
    // MARK: - NSDocumentController
    /* ============================================ */
    
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        
        // Add extensionHidden button on OpenPanel
        openPanel.canSelectHiddenExtension = true
        openPanel.isExtensionHidden = false
        
        // Show OpenPanel with the button
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }
    
    private static func prepareOpen(for url: URL) async throws -> OpenPreparation {
        let typeName: String = try NSDocumentController.shared.typeForContents(of: url)
        return try await Task.detached(priority: .userInitiated) { @Sendable in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let modificationDate = attributes[.modificationDate] as? Date
            let movie: AVMutableMovie = AVMutableMovie(url: url, options: nil)
            guard MovieHeaderValidator.isValid(movie) else {
                try ErrorUtilities.throwError(DocumentError.unableToOpenFile,
                                              reason: "Invalid movie header.")
            }
            return OpenPreparation(typeName: typeName,
                                   modificationDate: modificationDate,
                                   movHeader: movie.movHeader)
        }.value
    }
    
    private func makeDocumentAsync(withContentsOf url: URL) async throws -> NSDocument {
        
        // Create a new document
        let document = Document()
        
        // Read the document data
        let openPreparation = try await Self.prepareOpen(for: url)
        try await document.readAsync(from: url, openPreparation: openPreparation)
        
        // Set the document properties
        document.fileURL = url
        document.fileType = openPreparation.typeName
        document.fileModificationDate = openPreparation.modificationDate
        document.updateChangeCount(.changeCleared)
        return document
    }
    
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool) async throws -> (NSDocument, Bool) {
        
        // Check if the document is already open
        if let existingDocument = document(for: url) {
            if displayDocument {
                existingDocument.showWindows()
            }
            return (existingDocument, false)
        }
        
        // Open the document
        let document = try await makeDocumentAsync(withContentsOf: url)
        self.addDocument(document)
        
        // Display the document if requested
        if displayDocument {
            document.makeWindowControllers()
            document.showWindows()
        }
        return (document, true)
    }
    
    private func makeDocumentAsync(for urlOrNil: URL?, withContentsOf contentsURL: URL) async throws -> NSDocument {
        
        // Create a new document
        let document = Document()
        
        // Read the document data
        let openPreparation = try await Self.prepareOpen(for: contentsURL)
        try await document.readAsync(from: contentsURL, openPreparation: openPreparation)
        
        // Set the document properties
        document.fileURL = urlOrNil
        document.fileType = openPreparation.typeName
        document.fileModificationDate = openPreparation.modificationDate
        document.updateChangeCount(.changeReadOtherContents)
        return document
    }
    
    override func reopenDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool) async throws -> (NSDocument, Bool) {
        
        // Check if the document is already open
        if let url = urlOrNil, let existingDocument = document(for: url) {
            if displayDocument {
                existingDocument.showWindows()
            }
            return (existingDocument, false)
        }
        
        // Open the document
        let document = try await makeDocumentAsync(for: urlOrNil, withContentsOf: contentsURL)
        self.addDocument(document)
        
        // Display the document if requested
        if displayDocument {
            document.makeWindowControllers()
            document.showWindows()
        }
        return (document, true)
    }
}
