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
        // Thumbnails show the page turned by its rotation, fitted into the requested
        // size, so ask for the turned size and detect in display space: the passes
        // then find the top, line gaps and ragged edges the reader sees.
        let mediaDisplay = PDFPageDisplaySpace(box: boundsForMediaBox, rotation: pdfPage.rotation)
        let cropDisplaySize = PDFPageDisplaySpace(box: boundsForCropBox, rotation: pdfPage.rotation).size

        let imageMediaBox = pdfPage.thumbnail(
            of: CGSize(
                width: mediaDisplay.size.width * thumbnailScale,
                height: mediaDisplay.size.height * thumbnailScale
            ),
            for: .mediaBox
        )
        let imageCropBox = pdfPage.thumbnail(of: sizeForThumbnailImage, for: .cropBox)

        guard let cgimage = imageMediaBox.cgImage,
              let channels = PixelChannelOffsets(cgImage: cgimage) else {
            return PageVisibleContentValue(bounds: boundsForMediaBox, thumbImage: nil)
        }

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
            let raster = PageRaster(
                data: data,
                width: Int(imageMediaBox.size.width),
                height: Int(imageMediaBox.size.height),
                pixelsPerRow: Int(imageMediaBox.size.width) + padding,
                channels: channels
            )
            let edges = detectContentEdges(
                in: raster,
                readingDirection: readingDirection,
                hMarginDetectStrength: hMarginDetectStrength,
                vMarginDetectStrength: vMarginDetectStrength,
                mediaToCrop: CGSize(
                    width: mediaDisplay.size.width / cropDisplaySize.width,
                    height: mediaDisplay.size.height / cropDisplaySize.height
                )
            )
            top = edges.top
            bottom = edges.bottom
            leading = edges.leading
            trailing = edges.trailing
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
            bounds: Self.pageRect(
                fromRaster: rectangle,
                thumbnailScale: thumbnailScale,
                mediaDisplay: mediaDisplay,
                cropBox: boundsForCropBox
            ),
            thumbImage: newImage
        )
    }

    /// Finds the content edges in `raster`, in its own lines: `top`/`bottom` are
    /// rows and `leading`/`trailing` columns, counted from its top-left.
    /// `mediaToCrop` scales the first passes' density, which is measured across
    /// the media box, to the crop box the reader sees.
    private func detectContentEdges(
        in raster: PageRaster,
        readingDirection: PDFReadDirection,
        hMarginDetectStrength: Double,
        vMarginDetectStrength: Double,
        mediaToCrop: CGSize
    ) -> RasterEdges {
        // Scanner borders and binding shadows (#95): each pass starts inside the
        // one on its own edge, and leaves those either side out of its lines.
        let artifactTop = raster.edgeArtifactWidth(from: .up)
        let artifactBottom = raster.edgeArtifactWidth(from: .down)
        let artifactLeft = raster.edgeArtifactWidth(from: .right)
        let artifactRight = raster.edgeArtifactWidth(from: .left)
        let rowPixels = max(1, artifactLeft)..<(raster.width - artifactRight)
        let columnPixels = max(1, artifactTop)..<(raster.height - artifactBottom)

        switch readingDirection {
        case .LtR_TtB:
            let top = blankBorderWidth(
                raster: raster,
                orientation: .up,
                skip: artifactTop,
                pixels: rowPixels,
                ratio: mediaToCrop.width,
                hMarginDetectStrength: hMarginDetectStrength,
                extendsAcrossLineGaps: true
            )
            let bottom = blankBorderWidth(
                raster: raster,
                orientation: .down,
                skip: artifactBottom,
                pixels: rowPixels,
                ratio: mediaToCrop.width,
                hMarginDetectStrength: hMarginDetectStrength,
                extendsAcrossLineGaps: true
            )
            // The side passes add up a column over the text's height, so short
            // pages (a chapter's last lines) are not diluted by the blank below.
            let sideRatio = 3 * Double(raster.height) / Double(max(bottom - top + 1, 1))
            let leading = blankBorderWidth(
                raster: raster,
                orientation: .right,
                skip: artifactLeft,
                pixels: columnPixels,
                ratio: sideRatio,
                hMarginDetectStrength: vMarginDetectStrength,
                sparseInkSpan: min(top, bottom)...max(top, bottom)
            )
            let trailing = blankBorderWidth(
                raster: raster,
                orientation: .left,
                skip: artifactRight,
                pixels: columnPixels,
                ratio: sideRatio,
                hMarginDetectStrength: vMarginDetectStrength,
                sparseInkSpan: min(top, bottom)...max(top, bottom)
            )
            return RasterEdges(top: top, bottom: bottom, leading: leading, trailing: trailing)
        case .TtB_RtL:
            let leading = blankBorderWidth(
                raster: raster,
                orientation: .right,
                skip: artifactLeft,
                pixels: columnPixels,
                ratio: mediaToCrop.height,
                hMarginDetectStrength: vMarginDetectStrength,
                extendsAcrossLineGaps: true
            )
            let trailing = blankBorderWidth(
                raster: raster,
                orientation: .left,
                skip: artifactRight,
                pixels: columnPixels,
                ratio: mediaToCrop.height,
                hMarginDetectStrength: vMarginDetectStrength,
                extendsAcrossLineGaps: true
            )
            let sideRatio = 3 * Double(raster.width) / Double(max(trailing - leading + 1, 1))
            let top = blankBorderWidth(
                raster: raster,
                orientation: .up,
                skip: artifactTop,
                pixels: rowPixels,
                ratio: sideRatio,
                hMarginDetectStrength: hMarginDetectStrength,
                sparseInkSpan: min(leading, trailing)...max(leading, trailing)
            )
            let bottom = blankBorderWidth(
                raster: raster,
                orientation: .down,
                skip: artifactBottom,
                pixels: rowPixels,
                ratio: sideRatio,
                hMarginDetectStrength: hMarginDetectStrength,
                sparseInkSpan: min(leading, trailing)...max(leading, trailing)
            )
            return RasterEdges(top: top, bottom: bottom, leading: leading, trailing: trailing)
        }
    }

    /// A rect in the media-box thumbnail's pixels (top-down, display space) as a
    /// crop-relative, top-down page-space rect, the form `visibleBounds` returns.
    static func pageRect(
        fromRaster rect: CGRect,
        thumbnailScale: CGFloat,
        mediaDisplay: PDFPageDisplaySpace,
        cropBox: CGRect
    ) -> CGRect {
        // Display space is bottom-up; map back through the page's rotation.
        let page = mediaDisplay.toPage(CGRect(
            x: rect.minX / thumbnailScale,
            y: mediaDisplay.size.height - rect.maxY / thumbnailScale,
            width: rect.width / thumbnailScale,
            height: rect.height / thumbnailScale
        ))
        return CGRect(
            x: page.minX - cropBox.minX,
            y: cropBox.maxY - page.maxY,
            width: page.width,
            height: page.height
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
    /// lines set off from the body: a short first line (paragraph tail), ascenders,
    /// or a heading after extra space, but not a running head or folio at the page
    /// edge (`extendBorderAcrossLineGaps`). With `sparseInkSpan`, it walks outward over
    /// any ink within those perpendicular lines instead, so the few long lines of
    /// ragged text are kept (`extendBorderOverSparseInk`).
    ///
    /// `skip` is the scanner border or binding shadow on the scanned edge, and
    /// `pixels` leaves out those on the edges either side of it (#95).
    private func blankBorderWidth(
        raster: PageRaster,
        orientation: CGImagePropertyOrientation,
        skip: Int,
        pixels: Range<Int>,
        ratio: Double = 1.0,
        hMarginDetectStrength: Double,
        extendsAcrossLineGaps: Bool = false,
        sparseInkSpan: ClosedRange<Int>? = nil
    ) -> Int {
        let lineNumMax = raster.lineCount(orientation)
        let pixelNumMax = raster.pixelCount(orientation)
        let scanLimit = lineNumMax - 1
        let firstLine = max(1, skip)

        func density(ofLine line: Int, pixels: Range<Int> = pixels) -> Double {
            var nonWhiteDensity = 0.0
            for pixelInLine in pixels {
                nonWhiteDensity += raster.darkness(line: line, pixel: pixelInLine, orientation)
            }
            return nonWhiteDensity
        }

        var border: Int?
        var nonWhiteLineFirst = 0
        var nonWhiteLines = 0
        var line = firstLine
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

        var result = border ?? firstLine
        if let border, extendsAcrossLineGaps {
            result = extendBorderAcrossLineGaps(from: border, floor: firstLine, scanLimit: scanLimit, lineNumMax: lineNumMax, density: { density(ofLine: $0) })
        } else if let border, let sparseInkSpan {
            let span = max(sparseInkSpan.lowerBound, pixels.lowerBound)..<min(sparseInkSpan.upperBound + 1, pixels.upperBound)
            if !span.isEmpty {
                result = extendBorderOverSparseInk(from: border, floor: firstLine, lineNumMax: lineNumMax, density: { density(ofLine: $0, pixels: span) })
            }
        }

        switch orientation {
        case .up, .upMirrored, .right, .rightMirrored:
            return result
        case .down, .downMirrored, .left, .leftMirrored:
            return lineNumMax - result - 1
        }
    }

    /// The side passes need several columns that are dense over the whole text
    /// height, so where only a few lines run long (ragged right, a long word, a
    /// trailing dash) the edge lands at the common line length and clips them.
    /// Walks outward over any ink within the text's lines, across gaps up to about
    /// a word space; a marginal note or folio further out is not reached.
    private func extendBorderOverSparseInk(
        from border: Int,
        floor: Int,
        lineNumMax: Int,
        density: (Int) -> Double
    ) -> Int {
        // Any ink at all: a thin dash at thumbnail scale is a few faint pixels,
        // and the gap limit, not a floor, keeps stray specks out.
        let maxGap = max(4, lineNumMax / 100)
        var extended = border
        var whiteRun = 0
        var probe = border - 1
        while probe >= floor {
            if density(probe) > 0 {
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

    private func extendBorderAcrossLineGaps(
        from border: Int,
        floor: Int,
        scanLimit: Int,
        lineNumMax: Int,
        density: (Int) -> Double
    ) -> Int {
        // A couple of dark pixels; ignores anti-aliasing dust.
        let inkFloor = 2.0

        // Measure the body's first line and the inter-line gap after it.
        var cursor = border
        var lineInk = 0
        while cursor < scanLimit, density(cursor) >= inkFloor {
            lineInk += 1
            cursor += 1
        }
        var lineGap = 0
        while cursor < scanLimit, density(cursor) < inkFloor {
            lineGap += 1
            cursor += 1
        }
        guard lineGap > 0, cursor < scanLimit, lineGap <= lineNumMax / 20 else { return border }

        // Ink within ~1.5x the line gap continues the text: a paragraph tail, ascenders.
        let maxGap = lineGap + lineGap / 2 + 1
        // Ink across a wider gap (extra space before a heading, or after a short
        // line) is text when it is a line, not a speck, within a few lines' pitch,
        // and clear of the band at the page edge that holds running heads and
        // folios. The gap alone cannot tell them apart: a running head is often
        // closer to the body than a section heading is.
        let maxBlockGap = 4 * (lineInk + lineGap)
        let minBlockInk = max(3, lineInk / 2)
        let edgeZone = lineNumMax / 10

        var extended = border
        var whiteRun = 0
        var probe = border - 1
        while probe >= floor {
            if density(probe) >= inkFloor {
                if whiteRun > maxGap {
                    var runStart = probe
                    while runStart > floor, density(runStart - 1) >= inkFloor {
                        runStart -= 1
                    }
                    guard probe - runStart + 1 >= minBlockInk, runStart > edgeZone else { break }
                    extended = runStart
                    whiteRun = 0
                    probe = runStart - 1
                    continue
                }
                extended = probe
                whiteRun = 0
            } else {
                whiteRun += 1
                if whiteRun > maxBlockGap { break }
            }
            probe -= 1
        }
        return extended
    }
}

/// Content edges in a `PageRaster`'s own pixels, top-down: rows for `top` and
/// `bottom`, columns for `leading` and `trailing`.
struct RasterEdges: Equatable {
    var top: Int
    var bottom: Int
    var leading: Int
    var trailing: Int
}

/// The page thumbnail's pixels, read along scan lines from any edge: a line runs
/// across the page parallel to the edge, `line` counts in from that edge and
/// `pixel` runs along it (left to right, or top to bottom).
struct PageRaster {
    let data: UnsafePointer<UInt8>
    let width: Int
    let height: Int
    let pixelsPerRow: Int
    let channels: PixelChannelOffsets
    /// Where this raster's top-left pixel sits in the image, when it is a part of
    /// it (`cropped`): one half of a spread, one column.
    var originX = 0
    var originY = 0

    /// The part of this raster at `columns` × `lines` (top-down), read in its own
    /// coordinates, so every pass works on it as on a whole page.
    func cropped(columns: Range<Int>, lines: Range<Int>) -> PageRaster {
        PageRaster(
            data: data,
            width: columns.count,
            height: lines.count,
            pixelsPerRow: pixelsPerRow,
            channels: channels,
            originX: originX + columns.lowerBound,
            originY: originY + lines.lowerBound
        )
    }

    func lineCount(_ edge: CGImagePropertyOrientation) -> Int {
        switch edge {
        case .up, .down, .upMirrored, .downMirrored:
            return height
        case .left, .leftMirrored, .right, .rightMirrored:
            return width
        }
    }

    func pixelCount(_ edge: CGImagePropertyOrientation) -> Int {
        switch edge {
        case .up, .down, .upMirrored, .downMirrored:
            return width
        case .left, .leftMirrored, .right, .rightMirrored:
            return height
        }
    }

    /// Ink darkness by perceived luminance (Rec. 601), so coloured text counts:
    /// red, orange or light blue have a channel above 200 but are clearly ink.
    /// Greys get the same value as the old per-channel average.
    func darkness(line: Int, pixel: Int, _ edge: CGImagePropertyOrientation) -> Double {
        let lineIndex: Int
        switch edge {
        case .up, .upMirrored, .right, .rightMirrored:
            lineIndex = line
        case .down, .downMirrored, .left, .leftMirrored:
            lineIndex = lineCount(edge) - line - 1
        }
        let x: Int
        let y: Int
        switch edge {
        case .up, .down, .upMirrored, .downMirrored:
            (x, y) = (pixel, lineIndex)
        case .left, .leftMirrored, .right, .rightMirrored:
            (x, y) = (lineIndex, pixel)
        }
        let pixelIndex = ((originY + y) * pixelsPerRow + originX + x) * 4
        let r = Double(data[pixelIndex + channels.red])
        let g = Double(data[pixelIndex + channels.green])
        let b = Double(data[pixelIndex + channels.blue])

        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 200 ? (255 - luminance) / 255 : 0
    }

    /// Lines at `edge` taken by a scanner border or a binding shadow: a run of
    /// lines that are mostly ink along their length, from the edge (past a thin
    /// light strip) to within the outer tenth. Text never inks most of a line. A
    /// dark run that goes on is a full-bleed picture or a tinted page, not an
    /// artifact, and gives 0.
    func edgeArtifactWidth(from edge: CGImagePropertyOrientation) -> Int {
        let lines = lineCount(edge)
        let pixels = pixelCount(edge)
        func isArtifactLine(_ line: Int) -> Bool {
            var inked = 0
            for pixel in 0..<pixels where darkness(line: line, pixel: pixel, edge) > 0 {
                inked += 1
            }
            return inked * 2 >= pixels
        }

        var line = 0
        let lightStrip = max(2, lines / 100)
        while line < lightStrip, !isArtifactLine(line) {
            line += 1
        }
        guard line < lightStrip else { return 0 }
        while line < lines, isArtifactLine(line) {
            line += 1
        }
        return line <= lines / 10 ? line : 0
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
