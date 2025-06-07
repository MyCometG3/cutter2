//
//  DocumentController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/07.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa

@MainActor
class DocumentController: NSDocumentController {
    
    /* ============================================ */
    // MARK: - NSDocumentController
    /* ============================================ */
    
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        // Swift.print(#function, #line, #file)
        
        // Add extensionHidden button on OpenPanel
        openPanel.canSelectHiddenExtension = true
        openPanel.isExtensionHidden = false
        
        // Show OpenPanel with the button
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }
    
    private func makeDocumentAsync(withContentsOf url: URL, ofType typeName: String) async throws -> NSDocument {
        // Swift.print(#function, #line, #file)
        
        // Create a new document
        let document = Document()
        
        // Read the document data
        try await document.readAsync(from: url, ofType: typeName)
        
        // Set the document properties
        document.fileURL = url
        document.fileType = typeName
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let modificationDate = attributes[.modificationDate] as? Date {
            document.fileModificationDate = modificationDate
        }
        document.updateChangeCount(.changeCleared)
        return document
    }
    
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool) async throws -> (NSDocument, Bool) {
        // Swift.print(#function, #line, #file)
        
        // Check if the document is already open
        if let existingDocument = document(for: url) {
            if displayDocument {
                existingDocument.showWindows()
            }
            return (existingDocument, false)
        }
        
        // Check file type
        let typeName: String = try self.typeForContents(of: url)
        
        // Open the document
        let document = try await makeDocumentAsync(withContentsOf: url, ofType: typeName)
        self.addDocument(document)
        
        // Display the document if requested
        if displayDocument {
            document.makeWindowControllers()
            document.showWindows()
        }
        return (document, true)
    }
    
    private func makeDocumentAsync(for urlOrNil: URL?, withContentsOf contentsURL: URL, ofType typeName: String) async throws -> NSDocument {
        // Swift.print(#function, #line, #file)
        
        // Create a new document
        let document = Document()
        
        // Read the document data
        try await document.readAsync(from: contentsURL, ofType: typeName)
        
        // Set the document properties
        document.fileURL = urlOrNil
        document.fileType = typeName
        let attributes = try FileManager.default.attributesOfItem(atPath: contentsURL.path)
        if let modificationDate = attributes[.modificationDate] as? Date {
            document.fileModificationDate = modificationDate
        }
        document.updateChangeCount(.changeReadOtherContents)
        return document
    }
    
    override func reopenDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool) async throws -> (NSDocument, Bool) {
        // Swift.print(#function, #line, #file)
        
        // Check if the document is already open
        if let url = urlOrNil, let existingDocument = document(for: url) {
            if displayDocument {
                existingDocument.showWindows()
            }
            return (existingDocument, false)
        }
        
        // Check file type
        let typeName: String = try self.typeForContents(of: contentsURL)
        
        // Open the document
        let document = try await makeDocumentAsync(for: urlOrNil, withContentsOf: contentsURL, ofType: typeName)
        self.addDocument(document)
        
        // Display the document if requested
        if displayDocument {
            document.makeWindowControllers()
            document.showWindows()
        }
        return (document, true)
    }
}
