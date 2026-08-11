//
//  AccessoryViewController.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2018/03/04.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Cocoa
import AVFoundation

@MainActor
protocol AccessoryViewDelegate: AnyObject {
    func didUpdateFileType(_ fileType: AVFileType, selfContained: Bool)
}

@MainActor
class AccessoryViewController: NSViewController {
    
    /* ============================================ */
    // MARK: - Public properties
    /* ============================================ */
    
    /// The delegate notified when the selected file type or containment changes.
    public weak var delegate: AccessoryViewDelegate? = nil
    
    @IBOutlet weak var fileTypePopUp: NSPopUpButton!
    @IBOutlet weak var dataSizeTextField: NSTextField!
    
    /* ============================================ */
    // MARK: - Private properties
    /* ============================================ */
    
    private var decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter
    }()
    
    /* ============================================ */
    // MARK: - NSViewController
    /* ============================================ */
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        // Do view setup here.
    }
    
    /* ============================================ */
    // MARK: - Public functions
    /* ============================================ */
    
    //
    @IBAction func selectFileType(_ sender: Any) {
        guard let document = delegate else { return }
        
        document.didUpdateFileType(fileType, selfContained: selfContained)
    }
    
    /// Whether the selected output should include sample data in the movie.
    ///
    /// Returns `false` when the reference-movie item (tag -1) is selected. Setting the
    /// value to `false` selects that item.
    public var selfContained: Bool {
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
    /// The output file type represented by the selected popup item.
    ///
    /// Unsupported or unselected popup tags fall back to `.mov`.
    public var fileType: AVFileType {
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
            var tag: Int = 1
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
    
    /// Updates the accessory view with movie header and track-size information.
    ///
    /// Sizes are displayed in kilobytes and track counts are displayed per media type.
    ///
    /// - Parameter size: The header, sample-data, and track-count information to display.
    public func updateDataSizeText(_ size: boxSize) throws {
        let headerSize: Int64 = size.headerSize
        let videoSize: Int64 = size.videoSize, videoCount: Int64 = size.videoCount
        let audioSize: Int64 = size.audioSize, audioCount: Int64 = size.audioCount
        let otherSize: Int64 = size.otherSize, otherCount: Int64 = size.otherCount
        
        let headerFormat = NSLocalizedString("ui.accessory.movie_header_size", comment: "Movie header size label")
        let videoFormat = NSLocalizedString("ui.accessory.video_tracks", comment: "Video tracks label")
        let audioFormat = NSLocalizedString("ui.accessory.audio_tracks", comment: "Audio tracks label")
        let otherFormat = NSLocalizedString("ui.accessory.other_tracks", comment: "Other tracks label")
        
        let text = (String(format: headerFormat, format(headerSize/1000)) + "\n"
                    + String(format: videoFormat, format(videoCount), format(videoSize/1000)) + "\n"
                    + String(format: audioFormat, format(audioCount), format(audioSize/1000)) + "\n"
                    + String(format: otherFormat, format(otherCount), format(otherSize/1000)))
        
        dataSizeTextField.stringValue = text
    }
    
    /* ============================================ */
    // MARK: - Private functions
    /* ============================================ */
    
    private func format(_ num: Int64) -> String {
        let df = self.decimalFormatter
        let number = NSNumber.init(value: num)
        guard let str = df.string(from: number) else { return String(num) }
        return str
    }
}
