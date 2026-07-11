//
//  CAPARViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/22.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

/* ============================================ */

private final class ObserverTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol? = nil
    
    func store(_ token: NSObjectProtocol?) {
        lock.lock()
        self.token = token
        lock.unlock()
    }
    
    func take() -> NSObjectProtocol? {
        lock.lock()
        defer { lock.unlock() }
        let token = self.token
        self.token = nil
        return token
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
    private let textObserver = ObserverTokenBox()
    
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
        
        guard initialContent.count > 0 else { NSSound.beep(); return }
        
        // Prepare sheet
        modifyClapPasp(self)
        
        self.parentWindow = parent
        guard let sheet = self.view.window else { return }
        parent.beginSheet(sheet) { [weak self] response in
            self?.removeTextObserver()
            handler(response)
        }
        
        let textHandler: @Sendable (Notification) -> Void = { [weak self] notification in
            
            guard let self else { return }
            guard
                let sheetWindow = ActorUtilities.performSyncOnMainActor({ self.view.window }),
                let control = notification.object as? NSControl,
                let controlWindow = ActorUtilities.performSyncOnMainActor({ control.window }),
                sheetWindow == controlWindow
            else { return }
            
            ActorUtilities.performSyncOnMainActor {
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
            self.textObserver.store(observer)
        }
    }
    
    //
    public func endSheet(_ response: NSApplication.ModalResponse) {
        
        guard let parent = self.parentWindow else { return }
        guard let sheet = self.view.window else { return }
        parent.endSheet(sheet, returnCode: response)
        
        removeTextObserver()
    }
    
    private nonisolated func removeTextObserver() {
        guard let observer = self.textObserver.take() else { return }
        NotificationCenter.default.removeObserver(observer,
                                                  name: NSControl.textDidChangeNotification,
                                                  object: nil)
    }
    
    deinit {
        guard let observer = textObserver.take() else { return }
        NotificationCenter.default.removeObserver(observer,
                                                  name: NSControl.textDidChangeNotification,
                                                  object: nil)
    }
    
    /* ============================================ */
    // MARK: - NSControl related
    /* ============================================ */
    
    // Button handler - OK
    @IBAction func ok(_ sender: Any) {
        
        updateUserDefaults()
        endSheet(.continue)
    }
    
    // Button handler - Cancel
    @IBAction func cancel(_ sender: Any) {
        
        endSheet(.cancel)
    }
    
    // update ObjectController.content using initialContent
    @IBAction func resetValues(_ sender: Any) {
        
        loadSourceSettings()
    }
    
    // update ObjectController.content according to checkBox state
    @IBAction func modifyClapPasp(_ sender: Any) {
        
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
        
        guard let content = objectController.content as? NSMutableDictionary else { return false }
        var valid: Bool = true
        guard let encSize = content[dimensionsKey] as? NSSize else { content[validKey] = false; return false }
        guard let clapSize = content[clapSizeKey] as? NSSize else { content[validKey] = false; return false }
        guard let clapOffset = content[clapOffsetKey] as? NSPoint else { content[validKey] = false; return false }
        guard let pasp = content[paspRatioKey] as? NSSize else { content[validKey] = false; return false }
        
        do {
            // Verify dimension is not changed
            guard let encSizeSrc = initialContent[dimensionsKey] as? NSSize else { content[validKey] = false; return false }
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
        
        guard let content = objectController.content as? NSMutableDictionary else { return }
        
        // NSSize/NSPoint -> CGFloat values
        do {
            guard let size = content[clapSizeKey] as? CGSize else { return }
            content[clapSizeWidthKey] = size.width
            content[clapSizeHeightKey] = size.height
        }
        do {
            guard let point = content[clapOffsetKey] as? CGPoint else { return }
            content[clapOffsetXKey] = point.x
            content[clapOffsetYKey] = point.y
        }
        do {
            guard let size = content[paspRatioKey] as? CGSize else { return }
            content[paspRatioWidthKey] = size.width
            content[paspRatioHeightKey] = size.height
        }
    }
    
    // Update label strings according to Struct values
    private func updateLabels(_ sender: Any) {
        
        // NSSize/NSPoint -> label string
        guard let content = objectController.content as? NSMutableDictionary else { return }
        
        let valid: Bool = validate()
        guard let par = content[paspRatioKey] as? NSSize else { return }
        let ratio: CGFloat = (par.width / par.height)
        do {
            if let size: NSSize = content[dimensionsKey] as? NSSize {
                let str = String(format: "%.2f x %.2f", size.width, size.height)
                content[labelEncodedKey] = str
            }
        }
        if valid {
            do {
                guard let size = content[clapSizeKey] as? NSSize else { return }
                let str = String(format: "%.2f x %.2f", size.width * ratio, size.height)
                content[labelCleanKey] = str
            }
            do {
                guard let size = content[dimensionsKey] as? NSSize else { return }
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
        
        // CGFloat values -> NSSize/NSPoint
        guard let content = objectController.content as? NSMutableDictionary else { return }
        
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
        
        guard checkDict(initialContent) else { NSSound.beep(); return }
        
        objectController.content = NSMutableDictionary.init(dictionary: initialContent,
                                                            copyItems: true)
        
        // synchronize
        self.updateFloat()
        self.updateLabels(self)
    }
    
    // update ObjectController.content using UserDefaults
    private func loadLastSettings() {
        
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
        
        let def: UserDefaults = UserDefaults.standard
        let customFlag = def.bool(forKey: modClapPaspKey)
        guard customFlag else { return }
        
        // Synchronize
        self.updateStruct()
        
        //
        let dict = objectController.content as? [AnyHashable:Any]
        if let dict = dict, checkDict(dict) {
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
        } else {
            NSSound.beep(); return
        }
    }
}
