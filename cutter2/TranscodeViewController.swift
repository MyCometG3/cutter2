//
//  TranscodeViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/04/07.
//  Copyright © 2018-2022年 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation
import VideoToolbox

class TranscodeViewController: NSViewController {
    
    /* ============================================ */
    // MARK: - Properties
    /* ============================================ */
    
    public var parentWindow: NSWindow? = nil
    
    /* ============================================ */
    // MARK: - NSViewController
    /* ============================================ */
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        UserDefaults.standard.set(checkHEVCEncoder(), forKey:kHEVCReadyKey)
    }
    
    /* ============================================ */
    // MARK: - Public functions
    /* ============================================ */
    
    public func beginSheetModal(for parentWindow: NSWindow, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        self.parentWindow = parentWindow
        guard let sheet = self.view.window else { return }
        
        parentWindow.beginSheet(sheet, completionHandler: handler)
    }
    
    public func endSheet(_ response: NSApplication.ModalResponse) {
        guard let parent = self.parentWindow else { return }
        guard let sheet = self.view.window else { return }
        
        parent.endSheet(sheet, returnCode: response)
    }
    
    @IBAction func start(_ sender: Any?) {
        // Swift.print(#function, #line, #file)
        
        endSheet(.continue)
        updateUserDefaults()
    }
    
    @IBAction func cancel(_ sender: Any?) {
        // Swift.print(#function, #line, #file)
        
        endSheet(.cancel)
    }
    
    /* ============================================ */
    // MARK: - Private functions
    /* ============================================ */
    
    private func checkHEVCEncoder() -> Bool {
        let encoderSpecification: [CFString: Any] = [ kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true ]
        let error =
            VTCopySupportedPropertyDictionaryForEncoder(width: 3840, height: 2160,
                                                        codecType: kCMVideoCodecType_HEVC,
                                                        encoderSpecification: encoderSpecification as CFDictionary,
                                                        encoderIDOut: nil,
                                                        supportedPropertiesOut: nil)
        return error == kVTCouldNotFindVideoEncoderErr ? false : true
    }
    
    private func updateUserDefaults() {
        // Swift.print(#function, #line, #file)
        
        let type: Int = UserDefaults.standard.integer(forKey: kTranscodeTypeKey)
        var preset: String = AVAssetExportPresetPassthrough
        var fileType: AVFileType = AVFileType.mov
        switch type {
        case 0:
            let preset0: Int = UserDefaults.standard.integer(forKey: kTrancode0Key)
            let name: [String] = [AVAssetExportPreset640x480,
                                  AVAssetExportPreset960x540,
                                  AVAssetExportPreset1280x720,
                                  AVAssetExportPreset1920x1080,
                                  AVAssetExportPreset3840x2160,
                                  AVAssetExportPresetHEVC1920x1080,
                                  AVAssetExportPresetHEVC3840x2160]
            preset = name[preset0]
            fileType = .mov
        case 1:
            let preset1: Int = UserDefaults.standard.integer(forKey: kTrancode1Key)
            let name: [String] = [AVAssetExportPresetLowQuality,
                                  AVAssetExportPresetMediumQuality,
                                  AVAssetExportPresetHighestQuality,
                                  AVAssetExportPresetHEVCHighestQuality]
            preset = name[preset1]
            fileType = .mov
        case 2:
            //let preset2: Int = UserDefaults.standard.integer(forKey: kTrancode2Key)
            preset = AVAssetExportPresetAppleProRes422LPCM
            fileType = .mov
        case 3:
            let preset3: Int = UserDefaults.standard.integer(forKey: kTrancode3Key)
            let name: [String] = [AVAssetExportPresetAppleM4VCellular,
                                  AVAssetExportPresetAppleM4ViPod,
                                  AVAssetExportPresetAppleM4V480pSD,
                                  AVAssetExportPresetAppleM4VAppleTV,
                                  AVAssetExportPresetAppleM4VWiFi,
                                  AVAssetExportPresetAppleM4V720pHD,
                                  AVAssetExportPresetAppleM4V1080pHD]
            preset = name[preset3]
            fileType = .m4v
        case 4:
            preset = kTranscodePresetCustom
            fileType = .mov
        default:
            break
        }
        
        UserDefaults.standard.set(preset, forKey:kTranscodePresetKey)
        UserDefaults.standard.set(fileType.rawValue, forKey:kAVFileTypeKey)
    }
}
