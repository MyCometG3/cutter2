//
//  AccessoryViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/03/04.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

protocol AccessoryViewDelegate : class {
    func didUpdateFileType(_ fileType : AVFileType, selfContained : Bool)
}

class AccessoryViewController: NSViewController {
    public weak var delegate : AccessoryViewDelegate? = nil
    
    @IBOutlet weak var fileTypePopUp: NSPopUpButton!
    @IBOutlet weak var dataSizeTextField: NSTextField!
    
    private var decimalFormatter : NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter
    }()
    
    override func viewDidLoad() {
        // Swift.print(#function, #line, #file)
        
        super.viewDidLoad()
        // Do view setup here.
    }
    
    //
    @IBAction func selectFileType(_ sender: Any) {
        guard let document = delegate else { return }
        
        document.didUpdateFileType(fileType, selfContained: selfContained)
    }
    
    public var selfContained : Bool {
        get {
            if fileTypePopUp.selectedTag() == -1 {
                return false
            }
            return true
        }
        set(newValue) {
            if newValue == false {
                fileTypePopUp.selectItem(withTag: -1)
            } else {
                if fileTypePopUp.selectedTag() == -1 {
                    fileTypePopUp.selectItem(withTag: 1)
                }
            }
        }
    }
    public var fileType : AVFileType {
        get {
            let tag = fileTypePopUp.selectedTag()
            switch tag {
            case -1:
                return AVFileType.mov
            case 1:
                return AVFileType.mov
            case 2:
                return AVFileType.mp4
            case 3:
                return AVFileType.m4v
            case 4:
                return AVFileType.m4a
            default:
                return AVFileType.mov
            }
        }
        set(newFileType) {
            var tag : Int = 1
            switch newFileType {
            case AVFileType.mov:
                tag = 1
            case AVFileType.mp4:
                tag = 2
            case AVFileType.m4v:
                tag = 3
            case AVFileType.m4a:
                tag = 4
            default:
                tag = 1
            }
            fileTypePopUp.selectItem(withTag: tag)
        }
    }

    public func updateDataSizeText(_ size : boxSize) throws {
        let headerSize : Int64 = size.headerSize
        let videoSize : Int64 = size.videoSize, videoCount : Int64 = size.videoCount
        let audioSize : Int64 = size.audioSize, audioCount : Int64 = size.audioCount
        let otherSize : Int64 = size.otherSize, otherCount : Int64 = size.otherCount
        
        let text = "Movie header size: \(format(headerSize/1000)) KB\n"
            + "Video tracks (\(format(videoCount))): \(format(videoSize/1000)) KB\n"
            + "Audio tracks (\(format(audioCount))): \(format(audioSize/1000)) KB\n"
            + "Other tracks (\(format(otherCount))): \(format(otherSize/1000)) KB"
        
        dataSizeTextField.stringValue = text
    }
    
    private func format(_ num : Int64) -> String {
        let df = self.decimalFormatter
        let number = NSNumber.init(value: num)
        guard let str = df.string(from: number) else { return String(num) }
        return str
    }
}
