//
//  PDFPageViewportFitter.swift
//  YetAnotherEBookReader
//

import CoreGraphics

/// Where a single-page PDF viewport should land: `pageAnchor` (page space,
/// bottom-left origin) must appear at `viewAnchor` (PDFView bounds, top-left
/// origin) at `scale`. Each axis is anchored independently.
struct PDFPageViewportFit: Equatable {
    var scale: CGFloat
    var pageAnchor: CGPoint
    var viewAnchor: CGPoint
}

/// Pure viewport math for the YabrPDF single-page auto-crop mode.
enum PDFPageViewportFitter {
    struct Input: Equatable {
        /// Detected content, page space.
        var contentBounds: CGRect
        /// Page crop box, page space.
        var pageBounds: CGRect
        /// PDFView bounds minus the bars / safe area, view space.
        var readableRect: CGRect
        var autoScaler: PDFAutoScaler
        var hMarginPercent: Double
        var vMarginPercent: Double
        /// Used by `.Custom`; falls back to `.Page` when not positive.
        var customScale: CGFloat
        var readingDirection: PDFReadDirection
        var marginOffsetPercent: Double
    }

    static func fit(_ input: Input) -> PDFPageViewportFit {
        let content = input.contentBounds.width > 0 && input.contentBounds.height > 0
            ? input.contentBounds
            : input.pageBounds
        let readable = input.readableRect
        let hMargin = readable.width * CGFloat(input.hMarginPercent) / 100
        let vMargin = readable.height * CGFloat(input.vMarginPercent) / 100
        let availableWidth = max(readable.width - 2 * hMargin, 1)
        let availableHeight = max(readable.height - 2 * vMargin, 1)

        let widthScale = availableWidth / content.width
        let heightScale = availableHeight / content.height
        let scale: CGFloat
        switch input.autoScaler {
        case .Width:
            scale = widthScale
        case .Height:
            scale = heightScale
        case .Page:
            scale = min(widthScale, heightScale)
        case .Custom:
            scale = input.customScale > 0 ? input.customScale : min(widthScale, heightScale)
        }

        let fitsWidth = content.width * scale <= availableWidth + 0.5
        let fitsHeight = content.height * scale <= availableHeight + 0.5
        var pageAnchor = CGPoint.zero
        var viewAnchor = CGPoint.zero

        switch input.readingDirection {
        case .LtR_TtB:
            // Centered when it fits, otherwise start at the leading (left) edge.
            if fitsWidth {
                pageAnchor.x = content.midX
                viewAnchor.x = readable.midX
            } else {
                pageAnchor.x = content.minX
                viewAnchor.x = readable.minX + hMargin
            }
            // Text always starts at the same place below the top bar.
            pageAnchor.y = content.maxY
            viewAnchor.y = readable.minY + vMargin
            pageAnchor.x += input.pageBounds.width * CGFloat(input.marginOffsetPercent) / 100
        case .TtB_RtL:
            // Centered when it fits, otherwise vertical text starts at the
            // leading (right) edge.
            if fitsWidth {
                pageAnchor.x = content.midX
                viewAnchor.x = readable.midX
            } else {
                pageAnchor.x = content.maxX
                viewAnchor.x = readable.maxX - hMargin
            }
            if fitsHeight {
                pageAnchor.y = content.midY
                viewAnchor.y = readable.midY
            } else {
                pageAnchor.y = content.maxY
                viewAnchor.y = readable.minY + vMargin
            }
            pageAnchor.y -= input.pageBounds.height * CGFloat(input.marginOffsetPercent) / 100
        }

        return PDFPageViewportFit(scale: scale, pageAnchor: pageAnchor, viewAnchor: viewAnchor)
    }

    /// Anchors the page point that was at the view's top-left corner, for restoring
    /// a saved in-page position (`PageViewPosition.point`).
    static func restore(scale: CGFloat, upperLeft: CGPoint, viewBounds: CGRect) -> PDFPageViewportFit {
        PDFPageViewportFit(scale: scale, pageAnchor: upperLeft, viewAnchor: CGPoint(x: viewBounds.minX, y: viewBounds.minY))
    }

    /// Converts `PDFMarginCropController.visibleBounds` output (crop-box relative,
    /// top-down y) into page space.
    static func pageSpaceRect(detected: CGRect, pageBounds: CGRect) -> CGRect {
        CGRect(
            x: pageBounds.minX + detected.minX,
            y: pageBounds.maxY - detected.minY - detected.height,
            width: detected.width,
            height: detected.height
        )
    }
}

/// A page box as displayed: PDFKit turns the page clockwise by its `rotation`.
/// Display space has its origin at the bottom-left of the turned box and y up,
/// like page space, so detection and the fit work on what the reader sees and
/// only the result is mapped back to page space.
struct PDFPageDisplaySpace: Equatable {
    /// The box in page space (crop or media box).
    let box: CGRect
    /// 0, 90, 180 or 270.
    let rotation: Int

    init(box: CGRect, rotation: Int) {
        self.box = box
        let quarterTurns = ((rotation / 90) % 4 + 4) % 4
        self.rotation = quarterTurns * 90
    }

    /// The box's size as displayed.
    var size: CGSize {
        rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    func toDisplay(_ point: CGPoint) -> CGPoint {
        let u = point.x - box.minX
        let v = point.y - box.minY
        switch rotation {
        case 90: return CGPoint(x: v, y: box.width - u)
        case 180: return CGPoint(x: box.width - u, y: box.height - v)
        case 270: return CGPoint(x: box.height - v, y: u)
        default: return CGPoint(x: u, y: v)
        }
    }

    func toPage(_ point: CGPoint) -> CGPoint {
        let u: CGFloat
        let v: CGFloat
        switch rotation {
        case 90: (u, v) = (box.width - point.y, point.x)
        case 180: (u, v) = (box.width - point.x, box.height - point.y)
        case 270: (u, v) = (point.y, box.height - point.x)
        default: (u, v) = (point.x, point.y)
        }
        return CGPoint(x: box.minX + u, y: box.minY + v)
    }

    func toDisplay(_ rect: CGRect) -> CGRect {
        Self.rect(toDisplay(CGPoint(x: rect.minX, y: rect.minY)), toDisplay(CGPoint(x: rect.maxX, y: rect.maxY)))
    }

    func toPage(_ rect: CGRect) -> CGRect {
        Self.rect(toPage(CGPoint(x: rect.minX, y: rect.minY)), toPage(CGPoint(x: rect.maxX, y: rect.maxY)))
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
