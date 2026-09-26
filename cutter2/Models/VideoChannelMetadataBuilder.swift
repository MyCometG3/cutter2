//
//  VideoChannelMetadataBuilder.swift
//  cutter2
//
//  Created by Takashi Mochizuki on 2026/09/25.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import AVFoundation
import CoreMedia
import VideoToolbox

/// Shared metadata assembly for custom export video channels (S-16).
///
/// The helpers here are module-internal pure functions: they turn CoreMedia
/// extension values into `AVVideo*` / VT compression dictionaries without
/// touching `MovieWriter` state. They are exercised directly by
/// `cutter2Tests/MovieWriterVideoChannelMetadataTests.swift` through
/// `@testable import cutter2`.
enum VideoChannelMetadataBuilder {

    // MARK: - CoreMedia extension retrieval gate

    /// Retrieves the ordered `keys` from `description` via CoreMedia and lets
    /// `build` turn the values into a dictionary.
    ///
    /// - When `keys` is empty, no CoreMedia retrieval happens: the builder is
    ///   not invoked and `nil` is returned.
    /// - When any extension is missing, the builder is not invoked and `nil`
    ///   is returned.
    /// - Only when every extension is present are the values passed to `build`
    ///   in `keys` order.
    ///
    /// `build` is synchronous, non-escaping, and must not cross an actor or
    /// queue boundary.
    static func makeExtensionDict(
        from description: CMFormatDescription,
        keys: [CFString],
        build: ([CFPropertyList]) -> NSDictionary?
    ) -> NSDictionary? {
        guard !keys.isEmpty else { return nil }
        var values: [CFPropertyList] = []
        for key in keys {
            guard let value = CMFormatDescriptionGetExtension(description, extensionKey: key) else {
                return nil
            }
            values.append(value)
        }
        return build(values)
    }

    // MARK: - Clean aperture

    /// Builds the `AVVideoCleanApertureKey` dictionary from the
    /// `kCMFormatDescriptionExtension_CleanAperture` extension value.
    ///
    /// All four required values must be present as `NSNumber`; otherwise
    /// `nil` is returned.
    static func makeCleanAperture(from extensionValue: CFPropertyList) -> NSDictionary? {
        guard
            let width = extensionValue[kCMFormatDescriptionKey_CleanApertureWidth] as? NSNumber,
            let height = extensionValue[kCMFormatDescriptionKey_CleanApertureHeight] as? NSNumber,
            let wOffset = extensionValue[kCMFormatDescriptionKey_CleanApertureHorizontalOffset] as? NSNumber,
            let hOffset = extensionValue[kCMFormatDescriptionKey_CleanApertureVerticalOffset] as? NSNumber
        else {
            return nil
        }
        let dict: [AnyHashable: Any] = [
            AVVideoCleanApertureWidthKey: width,
            AVVideoCleanApertureHeightKey: height,
            AVVideoCleanApertureHorizontalOffsetKey: wOffset,
            AVVideoCleanApertureVerticalOffsetKey: hOffset,
        ]
        return dict as NSDictionary
    }

    // MARK: - Pixel aspect ratio

    /// Builds the `AVVideoPixelAspectRatioKey` dictionary from the
    /// `kCMFormatDescriptionExtension_PixelAspectRatio` extension value.
    ///
    /// Both required values must be present as `NSNumber`; otherwise `nil`
    /// is returned.
    static func makePixelAspectRatio(from extensionValue: CFPropertyList) -> NSDictionary? {
        guard
            let hSpacing = extensionValue[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as? NSNumber,
            let vSpacing = extensionValue[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as? NSNumber
        else {
            return nil
        }
        let dict: [AnyHashable: Any] = [
            AVVideoPixelAspectRatioHorizontalSpacingKey: hSpacing,
            AVVideoPixelAspectRatioVerticalSpacingKey: vSpacing,
        ]
        return dict as NSDictionary
    }

    // MARK: - Color properties (NCLC)

    /// Builds the `AVVideoColorPropertiesKey` dictionary from the ordered
    /// color extension values: primaries, transfer function, YCbCr matrix.
    ///
    /// All three values must be present as `NSString`; otherwise `nil` is
    /// returned.
    static func makeNCLC(from extensions: [CFPropertyList]) -> NSDictionary? {
        guard extensions.count == 3,
              let colorPrimaries = extensions[0] as? NSString,
              let transferFunction = extensions[1] as? NSString,
              let ycbcrMatrix = extensions[2] as? NSString
        else {
            return nil
        }
        let dict: [AnyHashable: Any] = [
            AVVideoColorPrimariesKey: colorPrimaries,
            AVVideoTransferFunctionKey: transferFunction,
            AVVideoYCbCrMatrixKey: ycbcrMatrix,
        ]
        return dict as NSDictionary
    }

    // MARK: - Ordered extension key lists

    /// Returns the ordered CoreMedia color extension keys when `copyNCLC` is
    /// enabled, otherwise an empty list so that no color extension is
    /// retrieved and no color properties dictionary is produced.
    static func nclcExtensionKeys(copyNCLC: Bool) -> [CFString] {
        guard copyNCLC else { return [] }
        return [
            kCMFormatDescriptionExtension_ColorPrimaries,
            kCMFormatDescriptionExtension_TransferFunction,
            kCMFormatDescriptionExtension_YCbCrMatrix,
        ]
    }

    /// Returns the ordered CoreMedia field extension keys when `copyField` is
    /// enabled, otherwise an empty list so that no field extension is
    /// retrieved.
    static func fieldExtensionKeys(copyField: Bool) -> [CFString] {
        guard copyField else { return [] }
        return [
            kCMFormatDescriptionExtension_FieldCount,
            kCMFormatDescriptionExtension_FieldDetail,
        ]
    }

    // MARK: - Field metadata merge

    /// Merges field metadata into the initial video compression properties.
    ///
    /// Mirrors the previous inline behavior in `prepareVideoChannels`:
    /// - each extension value is cast independently, so a partial cast still
    ///   creates a compression dictionary
    /// - `kVTCompressionPropertyKey_FieldCount` / `kVTCompressionPropertyKey_FieldDetail`
    ///   are added only when both casts succeed
    /// - existing compression property entries are preserved
    /// - when neither cast succeeds, `initial` is returned unchanged
    static func mergeFieldCompressionProperties(
        fieldCountExtension: CFPropertyList,
        fieldDetailExtension: CFPropertyList,
        initial: NSDictionary?
    ) -> NSDictionary? {
        let fieldCount = fieldCountExtension as? NSNumber
        let fieldDetail = fieldDetailExtension as? NSString
        guard fieldCount != nil || fieldDetail != nil else {
            return initial
        }

        var dict: [AnyHashable: Any] = [:]
        if let fieldCount, let fieldDetail {
            dict[kVTCompressionPropertyKey_FieldCount] = fieldCount
            dict[kVTCompressionPropertyKey_FieldDetail] = fieldDetail
        }
        if let initial, let entries = initial as? [AnyHashable: Any] {
            for (key, value) in entries {
                dict[key] = value
            }
        }
        return dict as NSDictionary
    }

    // MARK: - Initial compression properties

    /// The initial `AVVideoCompressionPropertiesKey` value for the target
    /// codec.
    ///
    /// The listed ProRes family does not carry a target bitrate; every other
    /// codec receives the average-bitrate entry. The list mirrors the
    /// pre-refactor production list exactly and intentionally does not
    /// include `ap4x` (ProRes 4444 XQ), which keeps the legacy else-branch
    /// (target bitrate) behavior.
    static func makeInitialCompressionProperties(
        forCodec fourCC: String,
        targetBitRate: Int
    ) -> NSDictionary? {
        if ["ap4h", "apch", "apcn", "apcs", "apco"].contains(fourCC) {
            return nil
        }
        return [AVVideoAverageBitRateKey: targetBitRate] as NSDictionary
    }
}
