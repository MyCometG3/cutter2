//
//  DocumentController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/07.
//  Copyright © 2018-2020年 MyCometG3. All rights reserved.
//

import Cocoa

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
}
