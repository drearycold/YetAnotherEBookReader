//
//  PDFMarginCropController.swift
//  YetAnotherEBookReader
//

import ImageIO
import PDFKit
import UIKit

class PDFMarginCropController {
    private(set) var visibleContentBounds: [PageVisibleContentKey: PageVisibleContentValue] = [:]

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

    func preAnalyzeAdjacentPages(
        currentPageNumber: Int,
        document: PDFDocument?,
        readingDirection: PDFReadDirection,
        hMarginDetectStrength: Double,
        vMarginDetectStrength: Double
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
        guard needsNext || needsPrevious else { return }

        DispatchQueue.global(qos: .utility).async { [weak self, weak document] in
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

        guard let cgimage = imageMediaBox.cgImage else {
            return PageVisibleContentValue(bounds: boundsForMediaBox, thumbImage: nil)
        }

        let numberOfComponents = 4
        var top = (0, 0)
        var bottom = (0, 0)
        var leading = (0, 0)
        var trailing = (0, 0)

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
                    ratio: boundsForMediaBox.width / boundsForCropBox.width,
                    hMarginDetectStrength: hMarginDetectStrength,
                    extendsAcrossLineGaps: true
                )
                leading = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .right,
                    data: data,
                    ratio: 3 * imageMediaBox.size.height / Double(Int(imageMediaBox.size.height) - top.1 - bottom.1 + 1),
                    hMarginDetectStrength: vMarginDetectStrength
                )
                trailing = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .left,
                    data: data,
                    ratio: 3 * imageMediaBox.size.height / Double(Int(imageMediaBox.size.height) - top.1 - bottom.1 + 1),
                    hMarginDetectStrength: vMarginDetectStrength
                )
            case .TtB_RtL:
                leading = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .right,
                    data: data,
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
                    ratio: boundsForMediaBox.height / boundsForCropBox.height,
                    hMarginDetectStrength: vMarginDetectStrength,
                    extendsAcrossLineGaps: true
                )
                top = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .up,
                    data: data,
                    ratio: 3 * imageMediaBox.size.width / Double(Int(imageMediaBox.size.width) - leading.1 - trailing.1 + 1),
                    hMarginDetectStrength: hMarginDetectStrength
                )
                bottom = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .down,
                    data: data,
                    ratio: 3 * imageMediaBox.size.width / Double(Int(imageMediaBox.size.width) - leading.1 - trailing.1 + 1),
                    hMarginDetectStrength: hMarginDetectStrength
                )
            }
        }

        print("\(#function) white border page=\(pdfPage.pageRef!.pageNumber) \(top) \(bottom) \(leading) \(trailing)")

        UIGraphicsBeginImageContextWithOptions(imageMediaBox.size, false, CGFloat.zero)
        imageMediaBox.draw(at: CGPoint.zero)

        let rectangle = CGRect(
            x: leading.0,
            y: top.0,
            width: trailing.0 - leading.0 + 2,
            height: bottom.0 - top.0 + 1
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
                x: CGFloat(leading.0) / thumbnailScale - boundsForCropBox.minX,
                y: CGFloat(top.0) / thumbnailScale - (boundsForMediaBox.maxY - boundsForCropBox.maxY),
                width: rectangle.width / thumbnailScale,
                height: rectangle.height / thumbnailScale
            ),
            thumbImage: newImage
        )
    }

    /// Scans from one edge of the page image towards the center and returns the
    /// line index where content starts, plus the number of white lines in the outer
    /// quarter (used to scale the perpendicular pass).
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
        ratio: Double = 1.0,
        hMarginDetectStrength: Double,
        extendsAcrossLineGaps: Bool = false
    ) -> (Int, Int) {
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
        let scanLimit = lineNumMax / 2
        let whiteLineSampleLimit = lineNumMax / 4

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
                nonWhiteDensity += pixelGreyLevel(pixelIndex: pixelIndex, data: data)
            }
            return nonWhiteDensity
        }

        var border: Int?
        var nonWhiteLineFirst = 0
        var nonWhiteLines = 0
        var whiteLines = 0
        var line = 1
        while line < scanLimit && (border == nil || line < whiteLineSampleLimit) {
            let nonWhiteDensity = density(ofLine: line)
            if nonWhiteDensity > 0,
               nonWhiteDensity / Double(pixelNumMax) * ratio * 20.0 > hMarginDetectStrength {
                nonWhiteLines += 1
                if nonWhiteLineFirst == 0 {
                    nonWhiteLineFirst = line
                }
            } else {
                if line < whiteLineSampleLimit {
                    whiteLines += 1
                }
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
            return (result, whiteLines)
        case .down, .downMirrored, .left, .leftMirrored:
            return (lineNumMax - result - 1, whiteLines)
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

    private func pixelGreyLevel(pixelIndex: Int, data: UnsafePointer<UInt8>) -> Double {
        let r = data[pixelIndex]
        let g = data[pixelIndex + 1]
        let b = data[pixelIndex + 2]

        if r < 200 && g < 200 && b < 200 {
            return Double(UInt(255 - r) + UInt(255 - g) + UInt(255 - b)) / 3 / 255.0
        } else {
            return 0.0
        }
    }
}
