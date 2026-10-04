//
//  PDFMarginCropController.swift
//  YetAnotherEBookReader
//

import ImageIO
import PDFKit
import UIKit

class PDFMarginCropController {
    private(set) var visibleContentBounds: [PageVisibleContentKey: PageVisibleContentValue] = [:]
    /// Its own serial queue: a private queue still gets a thread when the global
    /// pool is saturated (PDFKit's per-document page analysis can fill it), and
    /// detections do not run concurrently.
    private let analysisQueue = DispatchQueue(label: "YabrPDF.marginDetection", qos: .utility)

    func clearCache() {
        visibleContentBounds.removeAll()
    }

    func cachedValue(for key: PageVisibleContentKey) -> PageVisibleContentValue? {
        visibleContentBounds[key]
    }

    /// Detected content bounds, relative to the crop box with a top-down y axis.
    /// `marginOffset` is applied by `PDFPageViewportFitter`, not here, so the cache
    /// stays valid when it changes.
    func visibleBounds(for page: PDFPage, key: PageVisibleContentKey) -> CGRect {
        if visibleContentBounds[key] == nil {
            visibleContentBounds[key] = analyzeVisibleContents(
                pdfPage: page,
                readingDirection: key.readingDirection,
                hMarginDetectStrength: key.hMarginDetectStrength,
                vMarginDetectStrength: key.vMarginDetectStrength
            )
        }

        visibleContentBounds[key]?.lastUsed = Date()
        pruneCache()
        return visibleContentBounds[key]?.bounds ?? page.bounds(for: .cropBox)
    }

    /// Detects the neighbours of `currentPageNumber` in the background.
    /// `completion` runs on the main queue once both are cached.
    func preAnalyzeAdjacentPages(
        currentPageNumber: Int,
        document: PDFDocument?,
        readingDirection: PDFReadDirection,
        hMarginDetectStrength: Double,
        vMarginDetectStrength: Double,
        completion: (() -> Void)? = nil
    ) {
        let nextKey = PageVisibleContentKey(
            pageNumber: currentPageNumber + 1,
            readingDirection: readingDirection,
            hMarginDetectStrength: hMarginDetectStrength,
            vMarginDetectStrength: vMarginDetectStrength
        )
        let previousKey = PageVisibleContentKey(
            pageNumber: currentPageNumber - 1,
            readingDirection: readingDirection,
            hMarginDetectStrength: hMarginDetectStrength,
            vMarginDetectStrength: vMarginDetectStrength
        )

        let needsNext = visibleContentBounds[nextKey] == nil
        let needsPrevious = visibleContentBounds[previousKey] == nil
        guard needsNext || needsPrevious else {
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
            return
        }

        analysisQueue.async { [weak self, weak document] in
            guard let self = self else { return }

            let boundsNext = needsNext
                ? document?.page(at: nextKey.pageNumber - 1).map {
                    self.analyzeVisibleContents(
                        pdfPage: $0,
                        readingDirection: readingDirection,
                        hMarginDetectStrength: hMarginDetectStrength,
                        vMarginDetectStrength: vMarginDetectStrength
                    )
                }
                : nil

            let boundsPrevious = needsPrevious
                ? document?.page(at: previousKey.pageNumber - 1).map {
                    self.analyzeVisibleContents(
                        pdfPage: $0,
                        readingDirection: readingDirection,
                        hMarginDetectStrength: hMarginDetectStrength,
                        vMarginDetectStrength: vMarginDetectStrength
                    )
                }
                : nil

            DispatchQueue.main.async {
                if let boundsNext = boundsNext {
                    self.visibleContentBounds[nextKey] = boundsNext
                }
                if let boundsPrevious = boundsPrevious {
                    self.visibleContentBounds[previousKey] = boundsPrevious
                }
                completion?()
            }
        }
    }

    private func pruneCache() {
        while visibleContentBounds.count > 9 {
            if let minPageEntry = visibleContentBounds.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
                visibleContentBounds.removeValue(forKey: minPageEntry.key)
                print("\(#function) visibleContentBounds.removeValue=\(minPageEntry.key.pageNumber)")
            } else {
                break
            }
        }
    }

    private func thumbnailImageSize(boundsForCropBox: CGRect) -> CGSize {
        if boundsForCropBox.width < 1024 && boundsForCropBox.height < 1024 {
            return CGSize(width: boundsForCropBox.width, height: boundsForCropBox.height)
        } else {
            var width = boundsForCropBox.width
            var height = boundsForCropBox.height
            repeat {
                width /= 2
                height /= 2
            } while width > 1024 || height > 1024
            return CGSize(width: width, height: height)
        }
    }

    private func analyzeVisibleContents(
        pdfPage: PDFPage,
        readingDirection: PDFReadDirection,
        hMarginDetectStrength: Double,
        vMarginDetectStrength: Double
    ) -> PageVisibleContentValue {
        let pdfPage = Self.pageWithoutReaderAnnotations(pdfPage)
        let boundsForMediaBox = pdfPage.bounds(for: .mediaBox)
        let boundsForCropBox = pdfPage.bounds(for: .cropBox)
        let sizeForThumbnailImage = thumbnailImageSize(boundsForCropBox: boundsForCropBox)
        let thumbnailScale = sizeForThumbnailImage.width / boundsForCropBox.width

        let imageMediaBox = pdfPage.thumbnail(
            of: CGSize(
                width: boundsForMediaBox.width * thumbnailScale,
                height: boundsForMediaBox.height * thumbnailScale
            ),
            for: .mediaBox
        )
        let imageCropBox = pdfPage.thumbnail(of: sizeForThumbnailImage, for: .cropBox)

        guard let cgimage = imageMediaBox.cgImage,
              let channels = PixelChannelOffsets(cgImage: cgimage) else {
            return PageVisibleContentValue(bounds: boundsForMediaBox, thumbImage: nil)
        }

        let numberOfComponents = 4
        var top = 0
        var bottom = 0
        var leading = 0
        var trailing = 0

        print("\(#function) bounds cropBox=\(boundsForCropBox) mediaBox=\(pdfPage.bounds(for: .mediaBox)) artBox=\(pdfPage.bounds(for: .artBox)) bleedBox=\(pdfPage.bounds(for: .bleedBox)) trimBox=\(pdfPage.bounds(for: .trimBox))")
        print("\(#function) sizeForThumbnailImage \(sizeForThumbnailImage)")
        print("\(#function) imageCropBox width=\(imageCropBox.size.width) height=\(imageCropBox.size.height)")
        print("\(#function) imageMediaBox width=\(imageMediaBox.size.width) height=\(imageMediaBox.size.height)")

        let align = 8
        let padding = (align - Int(imageMediaBox.size.width) % align) % align
        print("\(#function) CGIMAGE PADDING \(padding)")

        if let provider = cgimage.dataProvider,
           let providerData = provider.data,
           let data = CFDataGetBytePtr(providerData) {
            switch readingDirection {
            case .LtR_TtB:
                top = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .up,
                    data: data,
                    channels: channels,
                    ratio: boundsForMediaBox.width / boundsForCropBox.width,
                    hMarginDetectStrength: hMarginDetectStrength,
                    extendsAcrossLineGaps: true
                )
                bottom = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .down,
                    data: data,
                    channels: channels,
                    ratio: boundsForMediaBox.width / boundsForCropBox.width,
                    hMarginDetectStrength: hMarginDetectStrength,
                    extendsAcrossLineGaps: true
                )
                // The side passes add up a column over the text's height, so short
                // pages (a chapter's last lines) are not diluted by the blank below.
                let sideRatio = 3 * imageMediaBox.size.height / Double(max(bottom - top + 1, 1))
                leading = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .right,
                    data: data,
                    channels: channels,
                    ratio: sideRatio,
                    hMarginDetectStrength: vMarginDetectStrength
                )
                trailing = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .left,
                    data: data,
                    channels: channels,
                    ratio: sideRatio,
                    hMarginDetectStrength: vMarginDetectStrength
                )
            case .TtB_RtL:
                leading = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .right,
                    data: data,
                    channels: channels,
                    ratio: boundsForMediaBox.height / boundsForCropBox.height,
                    hMarginDetectStrength: vMarginDetectStrength,
                    extendsAcrossLineGaps: true
                )
                trailing = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .left,
                    data: data,
                    channels: channels,
                    ratio: boundsForMediaBox.height / boundsForCropBox.height,
                    hMarginDetectStrength: vMarginDetectStrength,
                    extendsAcrossLineGaps: true
                )
                let sideRatio = 3 * imageMediaBox.size.width / Double(max(trailing - leading + 1, 1))
                top = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .up,
                    data: data,
                    channels: channels,
                    ratio: sideRatio,
                    hMarginDetectStrength: hMarginDetectStrength
                )
                bottom = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .down,
                    data: data,
                    channels: channels,
                    ratio: sideRatio,
                    hMarginDetectStrength: hMarginDetectStrength
                )
            }
        }

        print("\(#function) white border page=\(pdfPage.pageRef!.pageNumber) \(top) \(bottom) \(leading) \(trailing)")

        UIGraphicsBeginImageContextWithOptions(imageMediaBox.size, false, CGFloat.zero)
        imageMediaBox.draw(at: CGPoint.zero)

        let rectangle = CGRect(
            x: leading,
            y: top,
            width: trailing - leading + 2,
            height: bottom - top + 1
        )
        UIColor.black.setFill()
        UIRectFrame(rectangle)

        #if DEBUG
        UIColor.red.setStroke()
        let drawBounds = CGRect(
            x: boundsForCropBox.minX * thumbnailScale,
            y: boundsForCropBox.minY * thumbnailScale,
            width: sizeForThumbnailImage.width,
            height: sizeForThumbnailImage.height
        )
        UIRectFrame(drawBounds)
        #endif

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return PageVisibleContentValue(
            bounds: CGRect(
                x: CGFloat(leading) / thumbnailScale - boundsForCropBox.minX,
                y: CGFloat(top) / thumbnailScale - (boundsForMediaBox.maxY - boundsForCropBox.maxY),
                width: rectangle.width / thumbnailScale,
                height: rectangle.height / thumbnailScale
            ),
            thumbImage: newImage
        )
    }

    /// Thumbnails draw annotations, so the reader's own highlights and note
    /// markers would read as ink: a highlighted line's box is taller than its
    /// glyphs. Detects on a copy without them, so highlighting never moves the crop.
    private static func pageWithoutReaderAnnotations(_ page: PDFPage) -> PDFPage {
        guard #available(iOS 16.0, macCatalyst 16.0, *) else { return page }
        func isReaderAnnotation(_ annotation: PDFAnnotation) -> Bool {
            annotation.value(forAnnotationKey: .highlightId) != nil
        }
        guard page.annotations.contains(where: isReaderAnnotation),
              let copy = page.copy() as? PDFPage else { return page }
        copy.annotations.filter(isReaderAnnotation).forEach(copy.removeAnnotation)
        return copy
    }

    /// Scans from one edge of the page image towards the other and returns the
    /// line index where content starts. The scan crosses the whole page, so text
    /// that sits entirely in one half (a chapter's last lines, a late chapter
    /// opening) is still found from the far edge.
    ///
    /// Content is the first run of 3+ lines whose ink density passes the detect
    /// strength. With `extendsAcrossLineGaps`, the border then walks outward over
    /// any ink separated from the body by no more than ~1.5x its first inter-line
    /// gap, so a short first line (paragraph tail) and ascenders are kept while a
    /// running head further out is not.
    private func blankBorderWidth(
        size: CGSize,
        padding: Int,
        numberOfComponents: Int,
        orientation: CGImagePropertyOrientation,
        data: UnsafePointer<UInt8>,
        channels: PixelChannelOffsets,
        ratio: Double = 1.0,
        hMarginDetectStrength: Double,
        extendsAcrossLineGaps: Bool = false
    ) -> Int {
        let lineNumMax = { () -> Int in
            switch orientation {
            case .up, .down, .upMirrored, .downMirrored:
                return Int(size.height)
            case .left, .leftMirrored, .right, .rightMirrored:
                return Int(size.width)
            }
        }()
        let pixelNumMax = { () -> Int in
            switch orientation {
            case .up, .down, .upMirrored, .downMirrored:
                return Int(size.width)
            case .left, .leftMirrored, .right, .rightMirrored:
                return Int(size.height)
            }
        }()
        let pixelNumInRow = Int(size.width) + padding
        let scanLimit = lineNumMax - 1

        func density(ofLine line: Int) -> Double {
            let lineIndex: Int
            switch orientation {
            case .up, .upMirrored, .right, .rightMirrored:
                lineIndex = line
            case .down, .downMirrored, .left, .leftMirrored:
                lineIndex = lineNumMax - line - 1
            }
            var nonWhiteDensity = 0.0
            for pixelInLine in 1..<pixelNumMax {
                let pixelIndex: Int
                switch orientation {
                case .up, .down, .upMirrored, .downMirrored:
                    pixelIndex = (pixelInLine + pixelNumInRow * lineIndex) * numberOfComponents
                case .left, .leftMirrored, .right, .rightMirrored:
                    pixelIndex = (lineIndex + pixelNumInRow * pixelInLine) * numberOfComponents
                }
                nonWhiteDensity += pixelGreyLevel(pixelIndex: pixelIndex, data: data, channels: channels)
            }
            return nonWhiteDensity
        }

        var border: Int?
        var nonWhiteLineFirst = 0
        var nonWhiteLines = 0
        var line = 1
        while line < scanLimit && border == nil {
            let nonWhiteDensity = density(ofLine: line)
            if nonWhiteDensity > 0,
               nonWhiteDensity / Double(pixelNumMax) * ratio * 20.0 > hMarginDetectStrength {
                nonWhiteLines += 1
                if nonWhiteLineFirst == 0 {
                    nonWhiteLineFirst = line
                }
            } else {
                nonWhiteLines = 0
                nonWhiteLineFirst = 0
            }

            if nonWhiteLines > 2, border == nil {
                border = nonWhiteLineFirst
            }
            line += 1
        }

        var result = border ?? 1
        if let border, extendsAcrossLineGaps {
            result = extendBorderAcrossLineGaps(from: border, scanLimit: scanLimit, lineNumMax: lineNumMax, density: density(ofLine:))
        }

        switch orientation {
        case .up, .upMirrored, .right, .rightMirrored:
            return result
        case .down, .downMirrored, .left, .leftMirrored:
            return lineNumMax - result - 1
        }
    }

    private func extendBorderAcrossLineGaps(
        from border: Int,
        scanLimit: Int,
        lineNumMax: Int,
        density: (Int) -> Double
    ) -> Int {
        // A couple of dark pixels; ignores anti-aliasing dust.
        let inkFloor = 2.0

        // Measure the first inter-line gap inside the body.
        var cursor = border
        while cursor < scanLimit, density(cursor) >= inkFloor {
            cursor += 1
        }
        var lineGap = 0
        while cursor < scanLimit, density(cursor) < inkFloor {
            lineGap += 1
            cursor += 1
        }
        guard lineGap > 0, cursor < scanLimit, lineGap <= lineNumMax / 20 else { return border }

        let maxGap = lineGap + lineGap / 2 + 1
        var extended = border
        var whiteRun = 0
        var probe = border - 1
        while probe >= 1 {
            if density(probe) >= inkFloor {
                extended = probe
                whiteRun = 0
            } else {
                whiteRun += 1
                if whiteRun > maxGap { break }
            }
            probe -= 1
        }
        return extended
    }

    /// Ink darkness of a pixel by perceived luminance (Rec. 601), so coloured text
    /// counts: red, orange or light blue have a channel above 200 but are clearly ink.
    /// Greys get the same value as the old per-channel average.
    private func pixelGreyLevel(pixelIndex: Int, data: UnsafePointer<UInt8>, channels: PixelChannelOffsets) -> Double {
        let r = Double(data[pixelIndex + channels.red])
        let g = Double(data[pixelIndex + channels.green])
        let b = Double(data[pixelIndex + channels.blue])

        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 200 ? (255 - luminance) / 255 : 0
    }
}

/// Byte offsets of the colour channels within a 32-bit pixel. PDFKit thumbnails
/// are little-endian with alpha first, i.e. B G R A in memory.
struct PixelChannelOffsets: Equatable {
    var red: Int
    var green: Int
    var blue: Int

    init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(cgImage: CGImage) {
        guard cgImage.bitsPerPixel == 32, cgImage.bitsPerComponent == 8 else { return nil }
        let alphaFirst: Bool
        switch cgImage.alphaInfo {
        case .first, .premultipliedFirst, .noneSkipFirst:
            alphaFirst = true
        case .last, .premultipliedLast, .noneSkipLast:
            alphaFirst = false
        default:
            return nil
        }
        // Big-endian order is A R G B or R G B A; little-endian reverses the bytes.
        let bigEndian = alphaFirst ? [1, 2, 3] : [0, 1, 2]
        let offsets = cgImage.byteOrderInfo == .order32Little ? bigEndian.map { 3 - $0 } : bigEndian
        self.init(red: offsets[0], green: offsets[1], blue: offsets[2])
    }
}
