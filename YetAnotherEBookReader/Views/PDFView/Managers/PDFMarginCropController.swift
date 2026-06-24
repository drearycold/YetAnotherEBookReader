//
//  PDFMarginCropController.swift
//  YetAnotherEBookReader
//

import ImageIO
import PDFKit
import UIKit

class PDFMarginCropController {
    private weak var pdfView: YabrPDFView?
    private let blankView: UIImageView
    private let blankActivityView: UIActivityIndicatorView

    private(set) var visibleContentBounds: [PageVisibleContentKey: PageVisibleContentValue] = [:]

    init(pdfView: YabrPDFView, blankView: UIImageView, blankActivityView: UIActivityIndicatorView) {
        self.pdfView = pdfView
        self.blankView = blankView
        self.blankActivityView = blankActivityView
    }

    func configureBlankOverlay() {
        guard let pdfView = pdfView else { return }

        blankView.contentMode = .scaleAspectFill
        blankView.addSubview(blankActivityView)
        pdfView.addSubview(blankView)
        blankView.layer.compositingFilter = "darkenBlendMode"
    }

    func clearCache() {
        visibleContentBounds.removeAll()
    }

    func cachedValue(for key: PageVisibleContentKey) -> PageVisibleContentValue? {
        visibleContentBounds[key]
    }

    func visibleBounds(for page: PDFPage, key: PageVisibleContentKey, marginOffset: Double) -> CGRect {
        if visibleContentBounds[key] == nil {
            visibleContentBounds[key] = analyzeVisibleContents(
                pdfPage: page,
                readingDirection: key.readingDirection,
                hMarginDetectStrength: key.hMarginDetectStrength,
                vMarginDetectStrength: key.vMarginDetectStrength,
                marginOffset: marginOffset
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
        vMarginDetectStrength: Double,
        marginOffset: Double
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
                        vMarginDetectStrength: vMarginDetectStrength,
                        marginOffset: marginOffset
                    )
                }
                : nil

            let boundsPrevious = needsPrevious
                ? document?.page(at: previousKey.pageNumber - 1).map {
                    self.analyzeVisibleContents(
                        pdfPage: $0,
                        readingDirection: readingDirection,
                        hMarginDetectStrength: hMarginDetectStrength,
                        vMarginDetectStrength: vMarginDetectStrength,
                        marginOffset: marginOffset
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

    func showBlankOverlay(page: PDFPage?, options: PDFPreferenceValue) {
        guard let pdfView = pdfView else { return }

        let backgroundColor = UIColor(cgColor: PDFPageWithBackground.fillColor ?? CGColor(gray: 1.0, alpha: 1.0))

        if blankView.layer.compositingFilter == nil,
           let page = page as? PDFPageWithBackground {
            let key = PageVisibleContentKey(
                pageNumber: page.pageRef?.pageNumber ?? -1,
                readingDirection: options.readingDirection,
                hMarginDetectStrength: options.hMarginDetectStrength,
                vMarginDetectStrength: options.vMarginDetectStrength
            )
            let bounds = visibleContentBounds[key]?.bounds ?? .zero
            blankView.image = page.thumbnailWithBackground(of: pdfView.frame.size, for: .cropBox, by: bounds)
        }

        blankView.tintColor = backgroundColor
        blankView.backgroundColor = backgroundColor
        blankView.frame.size = pdfView.frame.size

        blankActivityView.frame = CGRect(x: pdfView.frame.width / 2, y: pdfView.frame.height / 2, width: 50, height: 50)
        blankActivityView.style = .large
        blankActivityView.backgroundColor = .clear
        blankActivityView.startAnimating()

        hideBlankOverlay()
    }

    func hideBlankOverlay() {
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(400))) {
            self.blankView.frame.size = .zero
            self.blankActivityView.stopAnimating()
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
        vMarginDetectStrength: Double,
        marginOffset: Double
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
                    hMarginDetectStrength: hMarginDetectStrength
                )
                bottom = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .down,
                    data: data,
                    ratio: boundsForMediaBox.width / boundsForCropBox.width,
                    hMarginDetectStrength: hMarginDetectStrength
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
                leading.0 += Int(marginOffset / 100.0 * imageMediaBox.size.width)
                trailing.0 += Int(marginOffset / 100.0 * imageMediaBox.size.width)
            case .TtB_RtL:
                leading = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .right,
                    data: data,
                    ratio: boundsForMediaBox.height / boundsForCropBox.height,
                    hMarginDetectStrength: vMarginDetectStrength
                )
                trailing = blankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .left,
                    data: data,
                    ratio: boundsForMediaBox.height / boundsForCropBox.height,
                    hMarginDetectStrength: vMarginDetectStrength
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
                top.0 += Int(marginOffset / 100.0 * imageMediaBox.size.height)
                bottom.0 += Int(marginOffset / 100.0 * imageMediaBox.size.height)
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

    private func blankBorderWidth(
        size: CGSize,
        padding: Int,
        numberOfComponents: Int,
        orientation: CGImagePropertyOrientation,
        data: UnsafePointer<UInt8>,
        ratio: Double = 1.0,
        hMarginDetectStrength: Double
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
        var border = lineNumMax / 2
        let pixelNumInRow = Int(size.width) + padding
        var nonWhiteLineFirst = 0
        var nonWhiteLines = 0
        var whiteLines = 0
        for line in 1..<(lineNumMax / 4) {
            var nonWhiteDensity = 0.0
            for pixelInLine in 1..<pixelNumMax {
                let lineIndex = { () -> Int in
                    switch orientation {
                    case .up, .upMirrored, .right, .rightMirrored:
                        return line
                    case .down, .downMirrored, .left, .leftMirrored:
                        return lineNumMax - line - 1
                    }
                }()

                let pixelIndex = { () -> Int in
                    switch orientation {
                    case .up, .down, .upMirrored, .downMirrored:
                        return pixelInLine + pixelNumInRow * lineIndex
                    case .left, .leftMirrored, .right, .rightMirrored:
                        return lineIndex + pixelNumInRow * pixelInLine
                    }
                }() * numberOfComponents

                nonWhiteDensity += pixelGreyLevel(pixelIndex: pixelIndex, data: data)
            }
            if nonWhiteDensity > 0 {
                print("nonWhiteDensity h=\(line) density=\(nonWhiteDensity) orientation=\(orientation.rawValue)")
            }

            if nonWhiteDensity > 0,
               nonWhiteDensity / Double(pixelNumMax) * ratio * 20.0 > hMarginDetectStrength {
                nonWhiteLines += 1
                if nonWhiteLineFirst == 0 {
                    nonWhiteLineFirst = line
                }
            } else {
                whiteLines += 1
                nonWhiteLines = 0
                nonWhiteLineFirst = 0
            }

            if nonWhiteLines > 2,
               nonWhiteLineFirst < lineNumMax / 4,
               border == lineNumMax / 2 {
                border = nonWhiteLineFirst
            }
        }

        if border == lineNumMax / 2 {
            border = 1
        }

        switch orientation {
        case .up, .upMirrored, .right, .rightMirrored:
            return (border, whiteLines)
        case .down, .downMirrored, .left, .leftMirrored:
            return (lineNumMax - border - 1, whiteLines)
        }
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
