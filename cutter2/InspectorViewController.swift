//
//  InspectorViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/05/19.
//  Copyright © 2018-2023年 MyCometG3. All rights reserved.
//

import Cocoa

class InspectorViewController: NSViewController {
    
    /* ============================================ */
    // MARK: - Public properties
    /* ============================================ */
    
    public var refreshInterval: TimeInterval = 1.0/10
    
    @IBOutlet var objectController: NSObjectController!
    
    /* ============================================ */
    // MARK: - Private properties
    /* ============================================ */
    
    private var timer: Timer? = nil
    
    private var visible: Bool {
        if let win = self.window {
            return win.isVisible
        }
        return false
    }
    
    private var window: NSWindow? {
        return self.view.window
    }
    
    /* ============================================ */
    // MARK: - NSViewController
    /* ============================================ */
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear() {
        // Swift.print(#function, #line, #file)
        
        startTimer()
    }
    
    override func viewWillDisappear() {
        // Swift.print(#function, #line, #file)
        
        stopTimer()
    }
    
    /* ============================================ */
    // MARK: - Public/Private functions
    /* ============================================ */
    
    private func startTimer() {
        // Swift.print(#function, #line, #file)
        
        timer = Timer.scheduledTimer(timeInterval: refreshInterval,
                                     target: self, selector: #selector(timerFireMethod),
                                     userInfo: nil, repeats: true)
    }
    
    private func stopTimer() {
        // Swift.print(#function, #line, #file)
        
        timer?.invalidate()
        timer = nil
    }
    
    @objc dynamic func timerFireMethod(_ timer: Timer) {
        // Swift.print(#function, #line, #file)
        
        guard self.visible else {
            stopTimer()
            return
        }
        
        let document: Document? = NSApp.orderedDocuments.first as? Document
        guard let doc = document else { return }
        let dict: [String:Any] = doc.inspecterDictionary()
        let content: NSMutableDictionary = objectController.content as! NSMutableDictionary
        for key in dict.keys {
            let dictValue: String = dict[key] as! String
            let contValue: String? = content[key] as? String
            if let contValue = contValue, contValue == dictValue {
                // same value - no update
            } else {
                // trigger KVO
                content.setValue(dictValue, forKey: key)
            }
        }
    }
}
