//
//  ViewController+Edit.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/01/14.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Edit Actions and Menu Validation
/* ============================================ */

extension ViewController {
    
    /* ============================================ */
    // MARK: - Validate menu
    /* ============================================ */
    
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let document = delegate else { return false }
        if menuItem.action == #selector(ViewController.cut(_:)) {
            return document.hasSelection()
        }
        if menuItem.action == #selector(ViewController.copy(_:)) {
            return document.hasSelection()
        }
        if menuItem.action == #selector(ViewController.paste(_:)) {
            return document.hasClipOnPBoard()
        }
        if menuItem.action == #selector(ViewController.delete(_:)) {
            return document.hasSelection()
        }
        if menuItem.action == #selector(ViewController.selectAll(_:)) {
            return document.hasDuration()
        }
        return false
    }
    
    /* ============================================ */
    // MARK: - cut/copy/paste/delete IBAction
    /* ============================================ */
    
    @IBAction func cut(_ sender: Any) {
        guard let document = delegate else { return }
        do {
            try document.doCut()
        } catch {
            NSSound.beep()
        }
    }
    
    @IBAction func copy(_ sender: Any) {
        guard let document = delegate else { return }
        do {
            try document.doCopy()
        } catch {
            NSSound.beep()
        }
    }
    
    @IBAction func paste(_ sender: Any) {
        guard let document = delegate else { return }
        do {
            try document.doPaste()
        } catch {
            NSSound.beep()
        }
    }
    
    @IBAction func delete(_ sender: Any?) {
        deleteBackward(sender)
    }
}
