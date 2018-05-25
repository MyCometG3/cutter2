//
//  CAPARViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/22.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

class CAPARViewController: NSViewController {
    var initialContent : [AnyHashable : Any] = [:] // 4 Keys for source video
    var resultContent : [AnyHashable : Any] = [:] // 4 Keys for target video
    
    @IBOutlet weak var objectController: NSObjectController!
    
    let modClapPaspKey : String = "modClapPasp" // Modify Aperture
    
    let labelEncodedKey : String = "labelEncoded"
    let labelCleanKey : String = "labelClean"
    let labelProductionKey : String = "labelProduction"
    
    let clapSizeWidthKey : String = "clapSizeWidth" // CGFloat
    let clapSizeHeightKey : String = "clapSizeHeight" // CGFloat
    let clapOffsetXKey : String = "clapOffsetX" // CGFloat
    let clapOffsetYKey : String = "clapOffsetY" // CGFloat
    let paspRatioWidthKey : String = "paspRatioWidth" // CGFloat
    let paspRatioHeightKey : String = "paspRatioHeight" // CGFloat
    
    let validKey : String = "valid"
    
    /* ============================================ */
    // MARK: - Sheet control
    /* ============================================ */
    
    private var parentWindow : NSWindow? = nil
    
    //
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        let def = UserDefaults.standard
        def.register(defaults: [
            modClapPaspKey:false,
            labelEncodedKey:"n/a",
            labelCleanKey:"n/a",
            labelProductionKey:"n/a",
            clapSizeWidthKey:1920.0,
            clapSizeHeightKey:1080.0,
            clapOffsetXKey:0.0,
            clapOffsetYKey:0.0,
            paspRatioWidthKey:1.0,
            paspRatioHeightKey:1.0,
            validKey:true,
            ])
    }
    
    //
    public func beginSheetModal(for parent: NSWindow, handler : @escaping (NSApplication.ModalResponse) -> Void) {
        // Swift.print(#function, #line, #file)

        guard initialContent.count > 0 else { NSSound.beep(); return }
        
        // Prepare sheet
        modifyClapPasp(self)
        
        self.parentWindow = parent
        guard let sheet = self.view.window else { return }
        parent.beginSheet(sheet, completionHandler: handler)
    }
    
    //
    public func endSheet(_ response : NSApplication.ModalResponse) {
        // Swift.print(#function, #line, #file)
        guard let parent = self.parentWindow else { return }
        guard let sheet = self.view.window else { return }
        parent.endSheet(sheet, returnCode: response)
    }

    /* ============================================ */
    // MARK: - NSControl related
    /* ============================================ */
    
    // Button handler - OK
    @IBAction func ok(_ sender: Any) {
        // Swift.print(#function, #line, #file)

        updateUserDefaults()
        endSheet(.continue)
    }
    
    // Button handler - Cancel
    @IBAction func cancel(_ sender: Any) {
        // Swift.print(#function, #line, #file)

        endSheet(.cancel)
    }
    
    // update ObjectController.content using initialContent
    @IBAction func resetValues(_ sender: Any) {
        // Swift.print(#function, #line, #file)
        
        loadSourceSettings()
        
        //dump()
    }
    
    // update ObjectController.content according to checkBox state
    @IBAction func modifyClapPasp(_ sender: Any) {
        // Swift.print(#function, #line, #file)

        let def : UserDefaults = UserDefaults.standard
        
        if #available(OSX 10.13, *) {
            // AVMutableMovieTrack.replaceFormatDescription(_:with:) is supported
        } else {
            NSSound.beep()
            def.set(false, forKey: modClapPaspKey)
        }
        
        let customFlag = def.bool(forKey: modClapPaspKey)
        if customFlag {
            loadLastSettings()
        } else {
            loadSourceSettings()
        }
        
        //dump()
    }
    
    // NSControl - Control Editing Notification
    override func controlTextDidChange(_ obj: Notification) {
        // Swift.print(#function, #line, #file)
        
        self.updateStruct()
        self.updateLabels(self)
    }
    
    /* ============================================ */
    // MARK: - synchronize
    /* ============================================ */
    
    //
    private func dump() {
        // Swift.print(#function, #line, #file)
        
        let content : NSMutableDictionary = objectController.content as! NSMutableDictionary
        Swift.print("#####", content)
    }
    
    // Update CGFloat Values according to Struct Values
    private func updateFloat() {
        // Swift.print(#function, #line, #file)
        
        let content : NSMutableDictionary = objectController.content as! NSMutableDictionary
        
        // NSSize/NSPoint -> CGFloat values
        do {
            let size = content[clapSizeKey] as! CGSize
            content[clapSizeWidthKey] = size.width
            content[clapSizeHeightKey] = size.height
        }
        do {
            let point = content[clapOffsetKey] as! CGPoint
            content[clapOffsetXKey] = point.x
            content[clapOffsetYKey] = point.y
        }
        do {
            let size = content[paspRatioKey] as! CGSize
            content[paspRatioWidthKey] = size.width
            content[paspRatioHeightKey] = size.height
        }
    }
    
    // Validate ObjectController.content values
    private func validate() -> Bool {
        // Swift.print(#function, #line, #file)
        
        let content : NSMutableDictionary = objectController.content as! NSMutableDictionary
        var result : Bool = true
        
        // Check clapSize
        let encSize : NSSize = content[dimensionsKey] as! NSSize
        let size : NSSize = content[clapSizeKey] as! NSSize
        if size.width.isNaN || size.height.isNaN { result = false }
        if !(size.width <= encSize.width && size.height <= encSize.height) { result = false }
        
        // Check clapOffset
        let offset : NSPoint = content[clapOffsetKey] as! NSPoint
        if offset.x.isNaN || offset.y.isNaN { result = false }
        let checkX : Bool = abs(offset.x) <= (encSize.width - size.width) / 2.0
        let checkY : Bool = abs(offset.y) <= (encSize.height - size.height) / 2.0
        if !(checkX && checkY) { result = false }
        
        // Check paspRatio
        let par = content[paspRatioKey] as! NSSize
        if par.width.isNaN || par.height.isNaN { result = false }
        let ratio : CGFloat = (par.width / par.height)
        if ratio > 3.0 || ratio < (1.0/3.0) { result = false }
        
        // Trigger KVO
        content[validKey] = result
        return result
    }
    
    // Update label strings according to Struct values
    private func updateLabels(_ sender: Any) {
        // Swift.print(#function, #line, #file)
        
        // NSSize/NSPoint -> label string
        let content : NSMutableDictionary = objectController.content as! NSMutableDictionary
        
        let valid : Bool = validate()
        let par = content[paspRatioKey] as! NSSize
        let ratio : CGFloat = (par.width / par.height)
        do {
            let size : NSSize = content[dimensionsKey] as! NSSize
            let str = String(format: "%.2f x %.2f", size.width, size.height)
            content[labelEncodedKey] = str
        }
        if valid {
            do {
                let size : NSSize = content[clapSizeKey] as! NSSize
                let str = String(format: "%.2f x %.2f", size.width * ratio, size.height)
                content[labelCleanKey] = str
            }
            do {
                let size : NSSize = content[dimensionsKey] as! NSSize
                let str = String(format: "%.2f x %.2f", size.width * ratio, size.height)
                content[labelProductionKey] = str
            }
        } else {
            content[labelCleanKey] = "n/a"
            content[labelProductionKey] = "n/a"
        }
    }
    
    // Update struct values according to CGFloat values
    private func updateStruct() {
        // Swift.print(#function, #line, #file)
        
        // CGFloat values -> NSSize/NSPoint
        let content : NSMutableDictionary = objectController.content as! NSMutableDictionary
        
        do {
            let width = content[clapSizeWidthKey] as? CGFloat ?? CGFloat.nan
            let height = content[clapSizeHeightKey] as? CGFloat ?? CGFloat.nan
            let size = CGSize(width: width, height: height)
            content[clapSizeKey] = size
        }
        do {
            let x = content[clapOffsetXKey] as? CGFloat ?? CGFloat.nan
            let y = content[clapOffsetYKey] as? CGFloat ?? CGFloat.nan
            let point = CGPoint(x: x, y: y)
            content[clapOffsetKey] = point
        }
        do {
            let width = content[paspRatioWidthKey] as? CGFloat ?? CGFloat.nan
            let height = content[paspRatioHeightKey] as? CGFloat ?? CGFloat.nan
            let size = CGSize(width: width, height: height)
            content[paspRatioKey] = size
        }
    }
    
    /* ============================================ */
    // MARK: - opening
    /* ============================================ */

    // Refresh movie source settings - Should be called prior to beginSheet()
    public func applySource(_ dict : [AnyHashable : Any]) -> Bool {
        // Swift.print(#function, #line, #file)
        
        guard let _ = dict[dimensionsKey] else { return false }
        guard let _ = dict[clapSizeKey] else { return false }
        guard let _ = dict[clapOffsetKey] else { return false }
        guard let _ = dict[paspRatioKey] else { return false }
        
        // 4 Keys for source video
        initialContent = dict
        
        //
        loadSourceSettings()
        
        // Clear result
        resultContent = [:]
        
        return true
    }
    
    /* ============================================ */
    // MARK: - editting
    /* ============================================ */
    
    // Update ObjectController's content using initialContent
    private func loadSourceSettings() {
        // Swift.print(#function, #line, #file)
        
        guard initialContent.count > 0 else { NSSound.beep(); return }
        
        objectController.content = NSMutableDictionary.init(dictionary: initialContent,
                                                            copyItems: true)
        
        // synchronize
        self.updateFloat()
        self.updateLabels(self)
    }
    
    // update ObjectController.content using UserDefaults
    private func loadLastSettings() {
        // Swift.print(#function, #line, #file)
        
        //
        let def : UserDefaults = UserDefaults.standard
        guard let clapOffsetStr = def.string(forKey: clapOffsetKey) else { return }
        guard let clapSizeStr = def.string(forKey: clapSizeKey) else { return }
        guard let paspRatioStr = def.string(forKey: paspRatioKey) else { return }
        guard let dimensionsStr = def.string(forKey: dimensionsKey) else { return }
        
        guard let dict = objectController.content as? NSMutableDictionary else { NSSound.beep(); return }
        dict[clapOffsetKey] = NSPointFromString(clapOffsetStr)
        dict[clapSizeKey] = NSSizeFromString(clapSizeStr)
        dict[paspRatioKey] = NSSizeFromString(paspRatioStr)
        dict[dimensionsKey] = NSSizeFromString(dimensionsStr)
        
        // Synchronize
        self.updateFloat()
        self.updateLabels(self)
    }
    
    /* ============================================ */
    // MARK: - closing
    /* ============================================ */
    
    // update UserDefaults using ObjectController.content
    private func updateUserDefaults() {
        // Swift.print(#function, #line, #file)
        
        let def : UserDefaults = UserDefaults.standard
        let customFlag = def.bool(forKey: modClapPaspKey)
        guard customFlag else { return }
        
        // Synchronize
        self.updateStruct()
        
        //
        guard let dict = objectController.content as? NSMutableDictionary else { NSSound.beep(); return }
        guard let clapOffset = dict[clapOffsetKey] as? NSPoint else { return }
        guard let clapSize = dict[clapSizeKey] as? NSSize else { return }
        guard let paspRatio = dict[paspRatioKey] as? NSSize else { return }
        guard let dimensions = dict[dimensionsKey] as? NSSize else { return }

        def.set(NSStringFromSize(clapSize), forKey: clapSizeKey)
        def.set(NSStringFromPoint(clapOffset), forKey: clapOffsetKey)
        def.set(NSStringFromSize(paspRatio), forKey: paspRatioKey)
        def.set(NSStringFromSize(dimensions), forKey: dimensionsKey)
        
        // Fill resultContent
        resultContent[clapSizeKey] = clapSize
        resultContent[clapOffsetKey] = clapOffset
        resultContent[paspRatioKey] = paspRatio
        resultContent[dimensionsKey] = dimensions
    }
}
