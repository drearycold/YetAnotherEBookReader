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
