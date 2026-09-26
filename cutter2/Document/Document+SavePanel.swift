//
//  Document+SavePanel.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2025/10/13.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import UniformTypeIdentifiers
import os.log

/* ============================================ */
// MARK: - Save Panel Operations
/* ============================================ */

extension Document {
    
    /* ============================================ */
    // MARK: - Save panel
    /* ============================================ */
    
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        
        guard let mutator = self.movieMutator else { return false }
        
        // prepare accessory view controller
        if self.accessoryVC == nil {
            let storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)
            let sid: NSStoryboard.SceneIdentifier = "Accessory View Controller"
            guard let accessoryVC = storyboard.instantiateController(withIdentifier: sid) as? AccessoryViewController else {
                NSSound.beep()
                return false
            }
            self.accessoryVC = accessoryVC
            accessoryVC.loadView()
            accessoryVC.delegate = self
        }
        guard let accessoryVC = self.accessoryVC else { return false }
        
        // prepare file types same as current source
        var uti: String = self.fileType ?? AVFileType.mov.rawValue
        if self.transcoding {
            let avFileTypeRaw: String? = UserDefaults.standard.string(forKey: kAVFileTypeKey)
            if let avFileTypeRaw = avFileTypeRaw {
                uti = AVFileType.init(avFileTypeRaw).rawValue
            }
        }
        
        // prepare accessory view
        do {
            try accessoryVC.updateDataSizeText(mutator.headerSize())
            
            accessoryVC.fileType = AVFileType.init(uti)
            if accessoryVC.fileType == .mov && self.transcoding == false {
                if let url = self.fileURL {
                    accessoryVC.selfContained = validateIfSelfContained(for: url)
                } else {
                    accessoryVC.selfContained = false
                }
            } else {
                accessoryVC.selfContained = true
            }
        } catch {
            return false
        }
        
        // prepare NSSavePanel
        savePanel.canSelectHiddenExtension = true
        savePanel.isExtensionHidden = false
        savePanel.delegate = self
        guard let ut = UTType(uti) else {
            LoggingSystem.document.error("Invalid save-panel UTI: \(uti, privacy: .public)")
            return false
        }
        savePanel.allowedContentTypes = [ut]
        savePanel.accessoryView = accessoryVC.view
        self.savePanel = savePanel
        
        return true
    }
    
    override var shouldRunSavePanelWithAccessoryView: Bool {
        return false
    }
    
    override nonisolated var fileTypeFromLastRunSavePanel: String? {
        
        return ActorUtilities.performSyncOnMainActor {
            if let accessoryVC = self.accessoryVC {
                let type: String = accessoryVC.fileType.rawValue
                return type
            } else {
                return AVFileType.mov.rawValue
            }
        }
    }
    
    /* ============================================ */
    // MARK: - NSOpenSavePanelDelegate protocol
    /* ============================================ */
    
    /// Validates the selected save URL against the accessory view's file type.
    ///
    /// The selected self-contained state is cached for the subsequent save operation.
    ///
    /// - Parameters:
    ///   - sender: The save-panel delegate sender.
    ///   - url: The URL being validated.
    /// - Throws: An error when the accessory view is unavailable, the extension is unsupported,
    ///   or the URL extension does not match the selected file type.
    public func panel(_ sender: Any, validate url: URL) throws {
        
        guard let accessoryVC = self.accessoryVC else {
            let reason = "Unexpected nil accessoryVC detected."
            try throwError(.internalError, reason: reason)
        }
        
        guard let fileType = fileTypeForURL(url) else {
            let reason = "(" + url.pathExtension + ")"
            try throwError(.unsupportedFileExtension, reason: reason)
        }
        
        if accessoryVC.fileType != fileType {
            let reason = "URL(" + fileType.rawValue + ") vs Popup(" + accessoryVC.fileType.rawValue + ")"
            try throwError(.fileTypeAndExtensionMismatch, reason: reason)
        }
        
        // Cache last selection state in MainThread here
        self.accessoryVCselfContained = accessoryVC.selfContained
    }
    
    /// Returns the filename entered in the save panel.
    ///
    /// - Parameters:
    ///   - sender: The save-panel delegate sender.
    ///   - filename: The filename entered by the user.
    ///   - okFlag: Whether the user confirmed the save operation.
    /// - Returns: The entered filename unchanged.
    public func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? {
        
        return filename
    }
    
    /// Get AVFileType from specified URL
    private func fileTypeForURL(_ url: URL) -> AVFileType? {
        
        let pathExt: String = url.pathExtension.lowercased()
        let dict: [String:AVFileType] = [
            "mov":AVFileType.mov,
            "mp4":AVFileType.mp4,
            "m4v":AVFileType.m4v,
            "m4a":AVFileType.m4a
        ]
        if let fileType = dict[pathExt] {
            return fileType
        }
        return nil
    }
    
    /* ============================================ */
    // MARK: - AccessoryViewDelegate protocol
    /* ============================================ */
    
    /// Updates the save panel's allowed content type after the accessory selection changes.
    ///
    /// - Parameters:
    ///   - fileType: The newly selected output file type.
    ///   - selfContained: Whether the output should include sample data.
    public func didUpdateFileType(_ fileType: AVFileType, selfContained: Bool) {
        
        guard let savePanel = self.savePanel else { return }
        guard let ut = UTType(fileType.rawValue) else {
            LoggingSystem.document.error("Invalid file type rawValue for save panel: \(fileType.rawValue, privacy: .public)")
            return
        }
        savePanel.allowedContentTypes = [ut]
    }
}
