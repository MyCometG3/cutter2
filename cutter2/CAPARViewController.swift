//
//  CAPARViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/22.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */
// MARK: - Actor isolation
/* ============================================ */

extension CAPARViewController {
    
    /// Runs a throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A closure isolated to the main actor that may throw an error.
    /// - Returns: The result of the closure's operation.
    /// - Throws: Any error thrown by the closure.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try block()
            }
        } else {
            return try DispatchQueue.main.sync {
                return try MainActor.assumeIsolated {
                    try block()
                }
            }
        }
    }
    
    /// Runs a non-throwing `@MainActor`-isolated closure synchronously.
    /// - Parameter block: A non-throwing closure isolated to the main actor.
    /// - Returns: The result of the closure's operation.
    /// - Warning: Blocks the calling thread if not already on the main thread, potentially causing UI freezes.
    nonisolated func performSyncOnMainActor<T: Sendable>(_ block: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                block()
            }
        } else {
            return DispatchQueue.main.sync {
                return MainActor.assumeIsolated {
                    block()
                }
            }
        }
    }
}

/* ============================================ */

@MainActor
class CAPARViewController: NSViewController {
    
    /* ============================================ */
    // MARK: - Public properties
    /* ============================================ */
    
    public var initialContent: [AnyHashable:Any] = [:] // 4 Keys for source video
    public var resultContent: [AnyHashable:Any] = [:] // 4 Keys for target video
    
    @IBOutlet weak var objectController: NSObjectController!
    
    @IBOutlet weak var encodedPixelLabel: NSTextField!
    
    /* ============================================ */
    // MARK: - Private properties
    /* ============================================ */
    
    private var parentWindow: NSWindow? = nil
    private var textObserver: NSObjectProtocol? = nil
    
    /* ============================================ */
    // MARK: - Sheet control
    /* ============================================ */
    
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
    public func beginSheetModal(for parent: NSWindow, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        // Swift.print(#function, #line, #file)
        
        guard initialContent.count > 0 else { NSSound.beep(); return }
        
        // Prepare sheet
        modifyClapPasp(self)
        
        self.parentWindow = parent
        guard let sheet = self.view.window else { return }
        parent.beginSheet(sheet, completionHandler: handler)
        
        let textHandler: @Sendable (Notification) -> Void = { [weak self] notification in
            // Swift.print(#function, #line, #file)
            
            guard let self else { fatalError("Unexpected nil self detected.") }
            guard
                let sheetWindow = performSyncOnMainActor({ self.view.window }),
                let control = notification.object as? NSControl,
                let controlWindow = performSyncOnMainActor({ control.window }),
                sheetWindow == controlWindow
            else { return }
            
            performSyncOnMainActor {
                updateStruct()
                updateLabels(self)
            }
        }
        do {
            let center = NotificationCenter.default
            var observer: NSObjectProtocol? = nil
            observer = center.addObserver(forName: NSControl.textDidChangeNotification,
                                          object: nil,
                                          queue: OperationQueue.main,
                                          using: textHandler)
            self.textObserver = observer
        }
    }
    
    //
    public func endSheet(_ response: NSApplication.ModalResponse) {
        // Swift.print(#function, #line, #file)
        
        guard let parent = self.parentWindow else { return }
        guard let sheet = self.view.window else { return }
        parent.endSheet(sheet, returnCode: response)
        
        do {
            guard let observer = self.textObserver else { return }
            let center = NotificationCenter.default
            center.removeObserver(observer,
                                  name: NSControl.textDidChangeNotification,
                                  object: nil)
            self.textObserver = nil
        }
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
    }
    
    // update ObjectController.content according to checkBox state
    @IBAction func modifyClapPasp(_ sender: Any) {
        // Swift.print(#function, #line, #file)
        
        let def: UserDefaults = UserDefaults.standard
        let customFlag = def.bool(forKey: modClapPaspKey)
        
        if customFlag {
            loadLastSettings()
        } else {
            loadSourceSettings()
        }
    }
    
    /* ============================================ */
    // MARK: - synchronize
    /* ============================================ */
    
    private func updateTextColor(for valid:Bool) {
        let color: NSColor = (valid ? NSColor.labelColor : NSColor.systemRed)
        encodedPixelLabel.textColor = color
    }
    
    // Validate ObjectController.content values
    private func validate() -> Bool {
        // Swift.print(#function, #line, #file)
        
        let content: NSMutableDictionary = objectController.content as! NSMutableDictionary
        var valid: Bool = true
        let encSize: NSSize = content[dimensionsKey] as! NSSize
        let clapSize: NSSize = content[clapSizeKey] as! NSSize
        let clapOffset: NSPoint = content[clapOffsetKey] as! NSPoint
        let pasp = content[paspRatioKey] as! NSSize
        
        do {
            // Verify dimension is not changed
            let encSizeSrc: NSSize = initialContent[dimensionsKey] as! NSSize
            let encSizeNew: NSSize = encSize
            
            valid = encSizeSrc.equalTo(encSizeNew)
            updateTextColor(for: valid)
        }
        if valid {
            // Check NaN
            let clapSizeNan:Bool = clapSize.width.isNaN || clapSize.height.isNaN
            let clapOffsetNan:Bool = clapOffset.x.isNaN || clapOffset.y.isNaN
            let paspNan:Bool = pasp.width.isNaN || pasp.height.isNaN
            valid = !(clapSizeNan || clapOffsetNan || paspNan)
        }
        if valid {
            // Check clapSize
            let checkWidth:Bool = clapSize.width <= encSize.width
            let checkHeight:Bool = clapSize.height <= encSize.height
            let clapSizeValid:Bool = (checkWidth && checkHeight)
            
            // Check clapOffset
            let checkX: Bool = abs(clapOffset.x) <= (encSize.width - clapSize.width) / 2.0
            let checkY: Bool = abs(clapOffset.y) <= (encSize.height - clapSize.height) / 2.0
            let clapOffsetValid: Bool = (checkX && checkY)
            
            // Check paspRatio
            let ratio: CGFloat = (pasp.width / pasp.height)
            let paspValid:Bool =  0.25 < ratio && ratio < 4.0
            
            valid = clapSizeValid && clapOffsetValid && paspValid
        }
        
        // Trigger KVO
        content[validKey] = valid
        return valid
    }
    
    // Update CGFloat Values according to Struct Values
    private func updateFloat() {
        // Swift.print(#function, #line, #file)
        
        let content: NSMutableDictionary = objectController.content as! NSMutableDictionary
        
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
    
    // Update label strings according to Struct values
    private func updateLabels(_ sender: Any) {
        // Swift.print(#function, #line, #file)
        
        // NSSize/NSPoint -> label string
        let content: NSMutableDictionary = objectController.content as! NSMutableDictionary
        
        let valid: Bool = validate()
        let par = content[paspRatioKey] as! NSSize
        let ratio: CGFloat = (par.width / par.height)
        do {
            let size: NSSize = content[dimensionsKey] as! NSSize
            let str = String(format: "%.2f x %.2f", size.width, size.height)
            content[labelEncodedKey] = str
        }
        if valid {
            do {
                let size: NSSize = content[clapSizeKey] as! NSSize
                let str = String(format: "%.2f x %.2f", size.width * ratio, size.height)
                content[labelCleanKey] = str
            }
            do {
                let size: NSSize = content[dimensionsKey] as! NSSize
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
        let content: NSMutableDictionary = objectController.content as! NSMutableDictionary
        
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
    public func applySource(_ dict: [AnyHashable:Any]) -> Bool {
        // Swift.print(#function, #line, #file)
        
        guard checkDict(dict) else { NSSound.beep(); return false}
        
        // 4 Keys for source video
        initialContent = dict
        
        // Clear result
        resultContent = [:]
        
        return true
    }
    
    private func checkDict(_ dict: [AnyHashable:Any]) -> Bool {
        guard dict[dimensionsKey] != nil else { return false }
        guard dict[clapSizeKey] != nil else { return false }
        guard dict[clapOffsetKey] != nil else { return false }
        guard dict[paspRatioKey] != nil else { return false }
        
        return true
    }
    
    /* ============================================ */
    // MARK: - editting
    /* ============================================ */
    
    // Update ObjectController's content using initialContent
    private func loadSourceSettings() {
        // Swift.print(#function, #line, #file)
        
        guard checkDict(initialContent) else { NSSound.beep(); return }
        
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
        let def: UserDefaults = UserDefaults.standard
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
        
        let def: UserDefaults = UserDefaults.standard
        let customFlag = def.bool(forKey: modClapPaspKey)
        guard customFlag else { return }
        
        // Synchronize
        self.updateStruct()
        
        //
        let dict = objectController.content as? [AnyHashable:Any]
        if let dict = dict, checkDict(dict) {
            let clapOffset = dict[clapOffsetKey] as! NSPoint
            let clapSize = dict[clapSizeKey] as! NSSize
            let paspRatio = dict[paspRatioKey] as! NSSize
            let dimensions = dict[dimensionsKey] as! NSSize
            
            def.set(NSStringFromSize(clapSize), forKey: clapSizeKey)
            def.set(NSStringFromPoint(clapOffset), forKey: clapOffsetKey)
            def.set(NSStringFromSize(paspRatio), forKey: paspRatioKey)
            def.set(NSStringFromSize(dimensions), forKey: dimensionsKey)
            
            // Fill resultContent
            resultContent[clapSizeKey] = clapSize
            resultContent[clapOffsetKey] = clapOffset
            resultContent[paspRatioKey] = paspRatio
            resultContent[dimensionsKey] = dimensions
        } else {
            NSSound.beep(); return
        }
    }
}
