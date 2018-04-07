//
//  TranscodeViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/07.
//  Copyright © 2018年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import VideoToolbox

class TranscodeViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        UserDefaults.standard.set(checkHEVCEncoder(), forKey:"hevcReady")
    }
    
    public var parentWindow : NSWindow? = nil
    
    public func beginSheetModal(for parentWindow: NSWindow, handler : @escaping (NSApplication.ModalResponse) -> Void) {
        self.parentWindow = parentWindow
        guard let sheet = self.view.window else { return }
        
        parentWindow.beginSheet(sheet, completionHandler: handler)
    }
    
    public func endSheet(_ response : NSApplication.ModalResponse) {
        guard let parent = self.parentWindow else { return }
        guard let sheet = self.view.window else { return }
        
        parent.endSheet(sheet, returnCode: response)
    }
    
    @IBAction func start(_ sender: Any?) {
        Swift.print(#function, #line)
        
        endSheet(.continue)
        updateUserDefaults()
    }
    
    @IBAction func cancel(_ sender: Any?) {
        Swift.print(#function, #line)
        
        endSheet(.cancel)
    }
    
    private func checkHEVCEncoder() -> Bool {
        if #available(OSX 10.13, *) {
            let encoderSpecification: [CFString: Any] = [ kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true ]
            let error = VTCopySupportedPropertyDictionaryForEncoder(3840, 2160,
                                                                    kCMVideoCodecType_HEVC,
                                                                    encoderSpecification as CFDictionary,
                                                                    nil,
                                                                    nil)
            return error == kVTCouldNotFindVideoEncoderErr ? false : true
        }
        return false
    }
    
    private func updateUserDefaults() {
        Swift.print(#function, #line)
        
        let type : Int = UserDefaults.standard.integer(forKey: "transcodeType")
        var preset : String = AVAssetExportPresetPassthrough
        var fileType : AVFileType = AVFileType.mov
        switch type {
        case 0:
            let preset0 : Int = UserDefaults.standard.integer(forKey: "transcode0")
            var name : [String] = [AVAssetExportPreset640x480,
                                   AVAssetExportPreset960x540,
                                   AVAssetExportPreset1280x720,
                                   AVAssetExportPreset1920x1080,
                                   AVAssetExportPreset3840x2160]
            if #available(OSX 10.13, *) {
                name = name + [AVAssetExportPresetHEVC1920x1080,
                               AVAssetExportPresetHEVC3840x2160]
            }
            preset = name[preset0]
            fileType = .mov
        case 1:
            let preset1 : Int = UserDefaults.standard.integer(forKey: "transcode1")
            var name : [String] = [AVAssetExportPresetLowQuality,
                                   AVAssetExportPresetMediumQuality,
                                   AVAssetExportPresetHighestQuality]
            if #available(OSX 10.13, *) {
                name = name + [AVAssetExportPresetHEVCHighestQuality]
            }
            preset = name[preset1]
            fileType = .mov
        case 2:
            //let preset2 : Int = UserDefaults.standard.integer(forKey: "transcode2")
            preset = AVAssetExportPresetAppleProRes422LPCM
            fileType = .mov
        case 3:
            let preset3 : Int = UserDefaults.standard.integer(forKey: "transcode3")
            let name : [String] = [AVAssetExportPresetAppleM4VCellular,
                                   AVAssetExportPresetAppleM4ViPod,
                                   AVAssetExportPresetAppleM4V480pSD,
                                   AVAssetExportPresetAppleM4VAppleTV,
                                   AVAssetExportPresetAppleM4VWiFi,
                                   AVAssetExportPresetAppleM4V720pHD,
                                   AVAssetExportPresetAppleM4V1080pHD]
            preset = name[preset3]
            fileType = .m4v
        default:
            break
        }
        Swift.print("preset name:", preset)
        
        UserDefaults.standard.set(preset, forKey:"transcodePreset")
        UserDefaults.standard.set(fileType.rawValue, forKey:"avFileType")
    }
}
