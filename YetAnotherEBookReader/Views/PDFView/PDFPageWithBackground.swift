//
//  PDFPageWithBackground.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/10.
//

import Foundation
import PDFKit

/// Per-document page rendering state. PDFKit renders page tiles on background
/// threads, so access is lock-protected.
@available(iOS 16.0, macCatalyst 16.0, *)
final class PDFPageRenderTheme: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDrawsInverted = false

    /// Last finished draw per page and resolution bucket (see `drawKey`).
    private var lastDrawEnd: [Int: [Int: CFTimeInterval]] = [:]

    var drawsInverted: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedDrawsInverted
        }
        set {
            lock.lock()
            storedDrawsInverted = newValue
            lock.unlock()
        }
    }

    /// Records that a page finished drawing at `pixelsPerPoint` (a PDFKit tile, or
    /// a thumbnail). PDFKit renders a newly shown page twice: quickly at 100% zoom,
    /// then at the view's own resolution, which is what it finally shows.
    func noteDraw(ofPage pageNumber: Int, pixelsPerPoint: CGFloat) {
        let now = CACurrentMediaTime()
        lock.lock()
        lastDrawEnd[pageNumber, default: [:]][Self.drawKey(pixelsPerPoint)] = now
        lock.unlock()
    }

    /// When the page last finished drawing at about `pixelsPerPoint`
    /// (`CACurrentMediaTime`), if ever.
    func lastDrawEnd(ofPage pageNumber: Int, pixelsPerPoint: CGFloat) -> CFTimeInterval? {
        let key = Self.drawKey(pixelsPerPoint)
        lock.lock()
        defer { lock.unlock() }
        guard let draws = lastDrawEnd[pageNumber] else { return nil }
        return [key - 1, key, key + 1].compactMap { draws[$0] }.max()
    }

    /// 2% buckets.
    private static func drawKey(_ pixelsPerPoint: CGFloat) -> Int {
        Int((log(max(pixelsPerPoint, 0.01)) / log(1.02)).rounded())
    }
}

/// Implemented by the `PDFDocument.delegate` that owns the pages.
@available(iOS 16.0, macCatalyst 16.0, *)
protocol PDFPageRenderThemeProviding: AnyObject {
    var pageRenderTheme: PDFPageRenderTheme { get }
}

/// Draws the dark theme (inverted page, text at 70% gray). Light tints are an
/// overlay on `YabrPDFView`; see `PDFThemePalette`.
@available(iOS 16.0, macCatalyst 16.0, *)
class PDFPageWithBackground: PDFPage {
    private var drawsInverted: Bool {
        (document?.delegate as? PDFPageRenderThemeProviding)?.pageRenderTheme.drawsInverted == true
    }

    private var renderTheme: PDFPageRenderTheme? {
        (document?.delegate as? PDFPageRenderThemeProviding)?.pageRenderTheme
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        defer {
            if let pageNumber = pageRef?.pageNumber {
                let ctm = context.ctm
                renderTheme?.noteDraw(ofPage: pageNumber, pixelsPerPoint: hypot(ctm.a, ctm.b))
            }
        }

        guard drawsInverted else { return }

        let rect = bounds(for: box)
        Self.invert(CGRect(origin: .zero, size: rect.size), in: context)
    }

    /// Draws the page the way PDFView shows it, for snapshots that stand in for the
    /// page (jump mask, dark page-turn cover). PDFView draws annotations over the
    /// page tile after `draw(with:to:)`, markup annotations (highlight, underline,
    /// strike-out) with multiply; `draw(with:to:)` would include them in the dark
    /// inversion and draws highlights paler than PDFView does.
    func drawAsDisplayed(with box: PDFDisplayBox, to context: CGContext) {
        guard let pageRef else {
            draw(with: box, to: context)
            return
        }

        let rect = bounds(for: box)
        context.saveGState()
        // Draw in page space, as `draw(with:to:)` does.
        context.concatenate(transform(for: box))
        context.clip(to: rect)
        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(rect)
        // The page content alone; PDFKit's annotations are drawn below.
        context.drawPDFPage(pageRef)
        if drawsInverted {
            Self.invert(rect, in: context)
        }
        for annotation in annotations where annotation.shouldDisplay {
            context.saveGState()
            switch annotation.type {
            case "Highlight":
                context.setBlendMode(.multiply)
                context.setFillColor(annotation.color.withAlphaComponent(1).cgColor)
                context.fill(annotation.bounds)
            case "Underline", "StrikeOut", "Squiggly":
                context.setBlendMode(.multiply)
                annotation.draw(with: box, in: context)
            default:
                annotation.draw(with: box, in: context)
            }
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// Inverts to black, then caps text at 70% gray.
    private static func invert(_ rect: CGRect, in context: CGContext) {
        UIGraphicsPushContext(context)
        context.saveGState()

        context.setBlendMode(.exclusion)
        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(rect)

        context.setBlendMode(.darken)
        context.setFillColor(gray: 0.7, alpha: 1.0)
        context.fill(rect)

        context.restoreGState()
        UIGraphicsPopContext()
    }
}
