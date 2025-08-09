//
//  DocumentSession.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/01/27.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Foundation
import AVFoundation

/// Actor that manages document operations to ensure proper sequencing
/// and prevent race conditions during save/export operations
@MainActor
public class DocumentSession {
    
    /// The document this session manages
    private weak var document: Document?
    
    /// Current operation task for sequential execution
    private var currentOperation: Task<Void, Never>?
    
    /// Initialize with the document to manage
    public init(document: Document) {
        self.document = document
    }
    
    /// Execute a document operation with proper sequencing
    /// - Parameter operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: Any error from the operation or if document is deallocated
    public func executeOperation<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        guard let document = document else {
            throw NSError(domain: "DocumentSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Document was deallocated"])
        }
        
        // Wait for any current operation to complete
        await currentOperation?.value
        
        // Execute the new operation
        return try await withCheckedThrowingContinuation { continuation in
            currentOperation = Task {
                do {
                    let result = try await operation()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute a write operation with the document
    /// - Parameters:
    ///   - url: The URL to write to
    ///   - typeName: The type name for the operation
    ///   - saveOperation: The save operation type
    /// - Throws: Any error from the write operation
    public func executeWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) async throws {
        guard let document = document else {
            throw NSError(domain: "DocumentSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Document was deallocated"])
        }
        
        try await executeOperation {
            switch saveOperation {
            case .saveToOperation:
                // Export...
                let transcodePreset: String? = UserDefaults.standard.string(forKey: kTranscodePresetKey)
                let preset = transcodePreset ?? kTranscodePresetCustom
                if preset == kTranscodePresetCustom {
                    try await document.exportCustom(to: url, ofType: typeName)
                } else {
                    try await document.export(to: url, ofType: typeName, preset: preset)
                }
            case .saveOperation, .saveAsOperation:
                // Save.../Save as...
                try await document.writeAsync(to: url, ofType: typeName)
            default:
                let reason = "No autoSave feature is implemented yet."
                try document.throwError(.unsupportedSaveOperation, reason: reason)
            }
        }
    }
}