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
                preconditionFailure("Failed to instantiate AccessoryViewController")
            }
            self.accessoryVC = accessoryVC
            accessoryVC.loadView()
            accessoryVC.delegate = self
        }
        guard let accessoryVC = self.accessoryVC else { preconditionFailure("Unexpected nil accessoryVC detected.") }
        
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
        savePanel.allowedContentTypes = [UTType(uti)!]
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
    
    // NSOpenSavePanelDelegate protocol
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
    
    // NSOpenSavePanelDelegate protocol
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
    
    // AccessoryViewDelegate protocol
    public func didUpdateFileType(_ fileType: AVFileType, selfContained: Bool) {
        
        guard let savePanel = self.savePanel else { return }
        savePanel.allowedContentTypes = [UTType(fileType.rawValue)!]
    }
}
