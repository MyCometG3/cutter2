//
//  DocumentController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/07.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa

class DocumentController: NSDocumentController {
    // Add extensionHidden button on OpenPanel
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        // Swift.print(#function, #line, #file)
        
        openPanel.canSelectHiddenExtension = true
        openPanel.isExtensionHidden = false
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }
}
