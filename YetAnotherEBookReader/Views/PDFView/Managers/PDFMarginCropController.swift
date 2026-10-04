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
        readingLayout(for: page, key: key).bounds
    }

    /// The page's content bounds and the regions it is read in (#97), detected
    /// once per key.
    func readingLayout(for page: PDFPage, key: PageVisibleContentKey) -> PDFPageReadingLayout {
        if visibleContentBounds[key] == nil {
            visibleContentBounds[key] = analyzeVisibleContents(pdfPage: page, key: key)
        }

        visibleContentBounds[key]?.lastUsed = Date()
        pruneCache()
        guard let value = visibleContentBounds[key] else {
            return PDFPageReadingLayout(bounds: page.bounds(for: .cropBox), regions: [])
        }
        return PDFPageReadingLayout(bounds: value.bounds, regions: value.regions)
    }

    /// Detects the neighbours of `currentPageNumber` in the background, under the
    /// keys `key` gives for their page numbers. `completion` runs on the main
    /// queue once both are cached.
    func preAnalyzeAdjacentPages(
        currentPageNumber: Int,
        document: PDFDocument?,
        key: (Int) -> PageVisibleContentKey,
        completion: (() -> Void)? = nil
    ) {
        let nextKey = key(currentPageNumber + 1)
        let previousKey = key(currentPageNumber - 1)

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
                    self.analyzeVisibleContents(pdfPage: $0, key: nextKey)
                }
                : nil

            let boundsPrevious = needsPrevious
                ? document?.page(at: previousKey.pageNumber - 1).map {
                    self.analyzeVisibleContents(pdfPage: $0, key: previousKey)
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

    /// A page as detection reads it: its media box as displayed (turned by the
    /// page's rotation), rendered at `pixelsPerPoint`.
    struct Thumbnail {
        let image: CGImage
        /// Raster pixels per page point.
        let pixelsPerPoint: CGFloat
        /// The media box, as displayed.
        let mediaDisplay: PDFPageDisplaySpace
        /// The crop box, page space.
        let cropBox: CGRect
    }

    private func analyzeVisibleContents(pdfPage: PDFPage, key: PageVisibleContentKey) -> PageVisibleContentValue {
        // Points of Interest in Instruments: the detection, and its render,
        // edge and region stages.
        let detection = AppPerformanceSignpost.begin("PDFMarginDetection", "page \(key.pageNumber)")
        defer { AppPerformanceSignpost.end("PDFMarginDetection", detection) }

        let render = AppPerformanceSignpost.begin("PDFMarginRender")
        let thumbnail = thumbnail(of: pdfPage)
        AppPerformanceSignpost.end("PDFMarginRender", render)
        guard let thumbnail, let value = analyze(thumbnail, key: key) else {
            return PageVisibleContentValue(bounds: pdfPage.bounds(for: .mediaBox))
        }
        return value
    }

    /// Renders `page` for detection, without the reader's own highlights.
    func thumbnail(of page: PDFPage) -> Thumbnail? {
        let page = Self.pageWithoutReaderAnnotations(page)
        let cropBox = page.bounds(for: .cropBox)
        let scale = thumbnailImageSize(boundsForCropBox: cropBox).width / cropBox.width
        // Thumbnails show the page turned by its rotation, fitted into the requested
        // size, so ask for the turned size and detect in display space: the passes
        // then find the top, line gaps and ragged edges the reader sees.
        let mediaDisplay = PDFPageDisplaySpace(box: page.bounds(for: .mediaBox), rotation: page.rotation)
        let image = page.thumbnail(
            of: CGSize(width: mediaDisplay.size.width * scale, height: mediaDisplay.size.height * scale),
            for: .mediaBox
        )
        guard let cgImage = image.cgImage else { return nil }
        return Thumbnail(image: cgImage, pixelsPerPoint: scale * image.scale, mediaDisplay: mediaDisplay, cropBox: cropBox)
    }

    /// The content bounds and reading regions detected on `thumbnail` under
    /// `key`; nil when its pixels cannot be read.
    func analyze(_ thumbnail: Thumbnail, key: PageVisibleContentKey) -> PageVisibleContentValue? {
        PageRaster.reading(thumbnail.image) { raster in
            analyze(raster, of: thumbnail, key: key)
        }
    }

    private func analyze(_ raster: PageRaster, of thumbnail: Thumbnail, key: PageVisibleContentKey) -> PageVisibleContentValue {
        let scale = thumbnail.pixelsPerPoint
        let mediaDisplay = thumbnail.mediaDisplay
        let cropDisplaySize = PDFPageDisplaySpace(box: thumbnail.cropBox, rotation: mediaDisplay.rotation).size

        let edgesInterval = AppPerformanceSignpost.begin("PDFMarginEdges")
        let edges = detectContentEdges(
            in: raster,
            readingDirection: key.readingDirection,
            hMarginDetectStrength: key.hMarginDetectStrength,
            vMarginDetectStrength: key.vMarginDetectStrength,
            mediaToCrop: CGSize(
                width: mediaDisplay.size.width / cropDisplaySize.width,
                height: mediaDisplay.size.height / cropDisplaySize.height
            )
        )
        AppPerformanceSignpost.end("PDFMarginEdges", edgesInterval)
        var top = edges.top
        var bottom = edges.bottom
        var leading = edges.leading
        var trailing = edges.trailing
        /// Reading regions, in thumbnail pixels.
        var regionRects: [(rect: CGRect, kind: PDFReadingRegion.Kind)] = []

        let regionsInterval = AppPerformanceSignpost.begin("PDFMarginRegions")
        if key.spreadMode != .Off {
            // The crop box's part of the media-box thumbnail, top-down.
            let crop = mediaDisplay.toDisplay(thumbnail.cropBox)
            let page = raster.cropped(
                columns: Self.pixelRange(crop.minX * scale, crop.maxX * scale, limit: raster.width),
                lines: Self.pixelRange(
                    (mediaDisplay.size.height - crop.maxY) * scale,
                    (mediaDisplay.size.height - crop.minY) * scale,
                    limit: raster.height
                )
            )
            regionRects = spreadHalves(of: page, key: key).map { ($0, .spreadHalf) }
            // One half holds everything (a blank verso): the page reads whole,
            // fitted to that half. Text across half the width is too thin for
            // the whole-page passes to find its top and bottom.
            if regionRects.count == 1, let half = regionRects.first?.rect {
                top = Int(half.minY)
                bottom = Int(half.maxY) - 1
                leading = Int(half.minX)
                trailing = Int(half.maxX) - 2
                regionRects = []
            }
        }

        if key.columnsMode == .Auto {
            // Columns (#19) of each half of a spread, or of the page's content.
            let parts = regionRects.isEmpty
                ? [(rect: CGRect(x: leading, y: top, width: trailing - leading + 2, height: bottom - top + 1), kind: PDFReadingRegion.Kind.spreadHalf)]
                : regionRects
            let columned = parts.flatMap { part -> [(rect: CGRect, kind: PDFReadingRegion.Kind)] in
                let columns = columnRegions(in: raster, rect: part.rect, readingDirection: key.readingDirection)
                return columns.isEmpty && !regionRects.isEmpty ? [part] : columns
            }
            if columned.count >= 2 {
                regionRects = columned
            }
        }
        AppPerformanceSignpost.end("PDFMarginRegions", regionsInterval)

        let bounds = CGRect(x: leading, y: top, width: trailing - leading + 2, height: bottom - top + 1)
        func pageRect(_ rasterRect: CGRect) -> CGRect {
            Self.pageRect(fromRaster: rasterRect, thumbnailScale: scale, mediaDisplay: mediaDisplay, cropBox: thumbnail.cropBox)
        }
        return PageVisibleContentValue(
            bounds: pageRect(bounds),
            regions: regionRects.map { PDFReadingRegion(rect: pageRect($0.rect), kind: $0.kind) }
        )
    }

    /// The halves of a two-page spread (#97) that hold content, in reading order,
    /// each cropped to its own content, in thumbnail pixels. `page` is the crop
    /// box's part of the thumbnail. Empty when the page is not split: Auto splits
    /// only a landscape page that looks like two book pages.
    private func spreadHalves(of page: PageRaster, key: PageVisibleContentKey) -> [CGRect] {
        switch key.spreadMode {
        case .Off:
            return []
        case .Auto:
            guard page.width * 5 >= page.height * 6, page.hasSpreadSpine() else { return [] }
        case .On:
            break
        }

        let middle = page.width / 2
        let halves = [0..<middle, middle..<page.width].compactMap { columns -> CGRect? in
            let half = page.cropped(columns: columns, lines: 0..<page.height)
            // Each half is a page of its own; its inner edge's binding shadow is an
            // edge artifact (#95) and stays out.
            let edges = detectContentEdges(
                in: half,
                readingDirection: key.readingDirection,
                hMarginDetectStrength: key.hMarginDetectStrength,
                vMarginDetectStrength: key.vMarginDetectStrength,
                mediaToCrop: CGSize(width: 1, height: 1)
            )
            guard edges.hasContent else { return nil }
            return CGRect(
                x: half.originX + edges.leading,
                y: half.originY + edges.top,
                width: edges.trailing - edges.leading + 2,
                height: edges.bottom - edges.top + 1
            )
        }
        // Vertical text runs right to left, and so do its spreads.
        return key.readingDirection == .TtB_RtL ? halves.reversed() : halves
    }

    /// The columns (#19), or tiers of vertical text, in `rect` (thumbnail
    /// pixels) as reading regions in reading order, in thumbnail pixels; empty
    /// when it is not set in columns.
    private func columnRegions(in raster: PageRaster, rect: CGRect, readingDirection: PDFReadDirection) -> [(rect: CGRect, kind: PDFReadingRegion.Kind)] {
        let part = raster.cropped(
            columns: Self.pixelRange(rect.minX, rect.maxX, limit: raster.width),
            lines: Self.pixelRange(rect.minY, rect.maxY, limit: raster.height)
        )
        let map = PDFInkMap(part)
        return PDFColumnDetector.regions(in: map, readingDirection: readingDirection).map { region in
            (region.rect.offsetBy(dx: CGFloat(part.originX), dy: CGFloat(part.originY)), region.kind)
        }
    }

    /// Whole pixels from `lower` to `upper`, within `0..<limit`.
    private static func pixelRange(_ lower: CGFloat, _ upper: CGFloat, limit: Int) -> Range<Int> {
        let start = min(max(0, Int(lower.rounded())), limit)
        let end = min(max(start, Int(upper.rounded())), limit)
        return start..<end
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

        /// A pass's edge, or the line it starts on when it found nothing.
        func edge(_ found: Int?, from orientation: CGImagePropertyOrientation, skip: Int) -> Int {
            if let found { return found }
            let firstLine = max(1, skip)
            switch orientation {
            case .up, .upMirrored, .right, .rightMirrored:
                return firstLine
            case .down, .downMirrored, .left, .leftMirrored:
                return raster.lineCount(orientation) - firstLine - 1
            }
        }

        switch readingDirection {
        case .LtR_TtB:
            let topFound = blankBorderWidth(
                raster: raster,
                orientation: .up,
                skip: artifactTop,
                pixels: rowPixels,
                ratio: mediaToCrop.width,
                hMarginDetectStrength: hMarginDetectStrength,
                extendsAcrossLineGaps: true
            )
            let top = edge(topFound, from: .up, skip: artifactTop)
            let bottom = edge(blankBorderWidth(
                raster: raster,
                orientation: .down,
                skip: artifactBottom,
                pixels: rowPixels,
                ratio: mediaToCrop.width,
                hMarginDetectStrength: hMarginDetectStrength,
                extendsAcrossLineGaps: true
            ), from: .down, skip: artifactBottom)
            // The side passes add up a column over the text's height, so short
            // pages (a chapter's last lines) are not diluted by the blank below.
            let sideRatio = 3 * Double(raster.height) / Double(max(bottom - top + 1, 1))
            let leading = edge(blankBorderWidth(
                raster: raster,
                orientation: .right,
                skip: artifactLeft,
                pixels: columnPixels,
                ratio: sideRatio,
                hMarginDetectStrength: vMarginDetectStrength,
                sparseInkSpan: min(top, bottom)...max(top, bottom)
            ), from: .right, skip: artifactLeft)
            let trailing = edge(blankBorderWidth(
                raster: raster,
                orientation: .left,
                skip: artifactRight,
                pixels: columnPixels,
                ratio: sideRatio,
                hMarginDetectStrength: vMarginDetectStrength,
                sparseInkSpan: min(top, bottom)...max(top, bottom)
            ), from: .left, skip: artifactRight)
            return RasterEdges(top: top, bottom: bottom, leading: leading, trailing: trailing, hasContent: topFound != nil)
        case .TtB_RtL:
            let leadingFound = blankBorderWidth(
                raster: raster,
                orientation: .right,
                skip: artifactLeft,
                pixels: columnPixels,
                ratio: mediaToCrop.height,
                hMarginDetectStrength: vMarginDetectStrength,
                extendsAcrossLineGaps: true
            )
            let leading = edge(leadingFound, from: .right, skip: artifactLeft)
            let trailing = edge(blankBorderWidth(
                raster: raster,
                orientation: .left,
                skip: artifactRight,
                pixels: columnPixels,
                ratio: mediaToCrop.height,
                hMarginDetectStrength: vMarginDetectStrength,
                extendsAcrossLineGaps: true
            ), from: .left, skip: artifactRight)
            let sideRatio = 3 * Double(raster.width) / Double(max(trailing - leading + 1, 1))
            let top = edge(blankBorderWidth(
                raster: raster,
                orientation: .up,
                skip: artifactTop,
                pixels: rowPixels,
                ratio: sideRatio,
                hMarginDetectStrength: hMarginDetectStrength,
                sparseInkSpan: min(leading, trailing)...max(leading, trailing)
            ), from: .up, skip: artifactTop)
            let bottom = edge(blankBorderWidth(
                raster: raster,
                orientation: .down,
                skip: artifactBottom,
                pixels: rowPixels,
                ratio: sideRatio,
                hMarginDetectStrength: hMarginDetectStrength,
                sparseInkSpan: min(leading, trailing)...max(leading, trailing)
            ), from: .down, skip: artifactBottom)
            return RasterEdges(top: top, bottom: bottom, leading: leading, trailing: trailing, hasContent: leadingFound != nil)
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
    ) -> Int? {
        let lineNumMax = raster.lineCount(orientation)
        let pixelNumMax = raster.pixelCount(orientation)
        let scanLimit = lineNumMax - 1
        let firstLine = max(1, skip)

        func density(ofLine line: Int, pixels: Range<Int> = pixels) -> Double {
            raster.density(line: line, pixels: pixels, orientation)
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

        guard let border else { return nil }
        var result = border
        if extendsAcrossLineGaps {
            result = extendBorderAcrossLineGaps(from: border, floor: firstLine, scanLimit: scanLimit, lineNumMax: lineNumMax, density: { density(ofLine: $0) })
        } else if let sparseInkSpan {
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
    /// False when the first pass found no content: the edges are then the
    /// raster's own, as the passes leave them.
    var hasContent = true
}

/// The page thumbnail's pixels, read along scan lines from any edge: a line runs
/// across the page parallel to the edge, `line` counts in from that edge and
/// `pixel` runs along it (left to right, or top to bottom).
///
/// A pixel is ink when its perceived luminance (Rec. 601) is below 200, so
/// coloured text counts: red, orange or light blue have a channel above 200
/// but are clearly ink. Its darkness is 255 − luminance, counted in
/// thousandths so a line's darkness is an exact integer sum.
struct PageRaster {
    /// A whole darkness, the darkness of black.
    static let darknessScale = 255_000.0

    let data: UnsafePointer<UInt8>
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let channels: PixelChannelOffsets
    /// Where this raster's top-left pixel sits in the image, when it is a part of
    /// it (`cropped`): one half of a spread, one column.
    var originX = 0
    var originY = 0

    /// Reads `image`, 32 bits a pixel, with its own size and row stride, for
    /// as long as `body` runs; nil when its pixels cannot be read.
    static func reading<Value>(_ image: CGImage, _ body: (PageRaster) throws -> Value) rethrows -> Value? {
        guard let channels = PixelChannelOffsets(cgImage: image),
              let pixels = image.dataProvider?.data,
              let data = CFDataGetBytePtr(pixels)
        else { return nil }
        return try withExtendedLifetime(pixels) {
            try body(PageRaster(data: data, width: image.width, height: image.height, bytesPerRow: image.bytesPerRow, channels: channels))
        }
    }

    /// The part of this raster at `columns` × `lines` (top-down), read in its own
    /// coordinates, so every pass works on it as on a whole page.
    func cropped(columns: Range<Int>, lines: Range<Int>) -> PageRaster {
        PageRaster(
            data: data,
            width: columns.count,
            height: lines.count,
            bytesPerRow: bytesPerRow,
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

    /// A pixel's darkness in thousandths, 0 when it is not ink.
    static func darkness(red: UInt8, green: UInt8, blue: UInt8) -> Int32 {
        let luminance = 299 * Int32(red) + 587 * Int32(green) + 114 * Int32(blue)
        // On the threshold itself, detection has always compared the floating
        // point sum, which rounds 14 colours to just under 200: they are ink.
        guard luminance < 200_000
                || luminance == 200_000 && 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue) < 200
        else { return 0 }
        return 255_000 - luminance
    }

    private func darkness(at pixel: UnsafePointer<UInt8>) -> Int32 {
        Self.darkness(red: pixel[channels.red], green: pixel[channels.green], blue: pixel[channels.blue])
    }

    /// Where `pixels` of `line`, counted in from `edge`, start in memory, and
    /// the bytes from one to the next.
    private func walk(line: Int, pixels: Range<Int>, _ edge: CGImagePropertyOrientation) -> (start: UnsafePointer<UInt8>, step: Int) {
        let index: Int
        switch edge {
        case .up, .upMirrored, .right, .rightMirrored:
            index = line
        case .down, .downMirrored, .left, .leftMirrored:
            index = lineCount(edge) - line - 1
        }
        switch edge {
        case .up, .down, .upMirrored, .downMirrored:
            return (data + (originY + index) * bytesPerRow + (originX + pixels.lowerBound) * 4, 4)
        case .left, .leftMirrored, .right, .rightMirrored:
            return (data + (originY + pixels.lowerBound) * bytesPerRow + (originX + index) * 4, bytesPerRow)
        }
    }

    /// The ink of `pixels` along `line`, counted in from `edge`: each ink
    /// pixel adds its darkness, (255 − luminance) / 255.
    func density(line: Int, pixels: Range<Int>, _ edge: CGImagePropertyOrientation) -> Double {
        var (pixel, step) = walk(line: line, pixels: pixels, edge)
        var darkness: Int64 = 0
        for _ in pixels {
            darkness += Int64(self.darkness(at: pixel))
            pixel += step
        }
        return Double(darkness) / Self.darknessScale
    }

    /// The ink pixels among `pixels` along `line`, counted in from `edge`.
    func inkedPixels(line: Int, pixels: Range<Int>, _ edge: CGImagePropertyOrientation) -> Int {
        var (pixel, step) = walk(line: line, pixels: pixels, edge)
        var inked = 0
        for _ in pixels {
            if darkness(at: pixel) > 0 {
                inked += 1
            }
            pixel += step
        }
        return inked
    }

    /// This raster's ink, counted over every rectangle from its top-left
    /// corner, for the column detector (`PDFInkMap`).
    func inkTable() -> PDFInkTable {
        let stride = width + 1
        let counts = [Int32](unsafeUninitializedCapacity: stride * (height + 1)) { counts, count in
            for x in 0..<stride {
                counts[x] = 0
            }
            for y in 0..<height {
                let above = y * stride
                let here = above + stride
                counts[here] = 0
                var rowInk: Int32 = 0
                var pixel = data + (originY + y) * bytesPerRow + originX * 4
                for x in 0..<width {
                    if darkness(at: pixel) > 0 {
                        rowInk += 1
                    }
                    counts[here + x + 1] = counts[above + x + 1] + rowInk
                    pixel += 4
                }
            }
            count = stride * (height + 1)
        }
        return PDFInkTable(width: width, height: height, counts: counts)
    }

    /// Whether this looks like two book pages side by side (#97): within the
    /// central sixth, a strip at least 2% of the width wide running the full
    /// height that is blank (the gutter between two text blocks, two inner
    /// margins) or dark (a binding shadow), with ink on both sides. A slide or a
    /// chart has text or art across its centre; the spaces between a title's
    /// words are narrower than the strip.
    func hasSpreadSpine() -> Bool {
        guard width >= 20, height >= 20 else { return false }
        func inkedRows(inColumn column: Int) -> Int {
            inkedPixels(line: column, pixels: 0..<height, .right)
        }

        let band = (width / 2 - width * 8 / 100)..<(width / 2 + width * 8 / 100)
        let minimumStrip = max(2, width / 50)
        var strip = 0
        var foundSpine = false
        for column in band {
            let inked = inkedRows(inColumn: column)
            // Blank: at most 2% of rows (specks). Shadow: at least 90%.
            if inked * 50 <= height || inked * 10 >= height * 9 {
                strip += 1
                if strip >= minimumStrip {
                    foundSpine = true
                    break
                }
            } else {
                strip = 0
            }
        }
        guard foundSpine else { return false }

        // Content on both sides: at least 2% of each side's columns inked.
        func hasContent(_ columns: Range<Int>) -> Bool {
            let inked = columns.filter { inkedRows(inColumn: $0) > 2 }.count
            return inked * 50 >= columns.count
        }
        return hasContent(0..<band.lowerBound) && hasContent(band.upperBound..<width)
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
            inkedPixels(line: line, pixels: 0..<pixels, edge) * 2 >= pixels
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
