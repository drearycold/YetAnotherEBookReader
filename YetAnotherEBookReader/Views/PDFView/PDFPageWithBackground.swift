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
    /// The last finished draws of each PDFKit tile, per page and resolution bucket.
    private var tileDrawEnds: [Int: [Int: [PDFPageTile: [CFTimeInterval]]]] = [:]
    private static let keptDrawsPerTile = 2

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

    /// Records that a page finished drawing with `ctm` (a PDFKit tile, or a
    /// thumbnail). PDFKit renders a newly shown page twice: quickly at 100% zoom,
    /// then at the view's own resolution, which is what it finally shows.
    func noteDraw(ofPage pageNumber: Int, ctm: CGAffineTransform) {
        let now = CACurrentMediaTime()
        let key = Self.drawKey(hypot(ctm.a, ctm.b))
        lock.lock()
        defer { lock.unlock() }
        lastDrawEnd[pageNumber, default: [:]][key] = now
        if let tile = PDFPageTile(drawnWith: ctm) {
            var ends = tileDrawEnds[pageNumber, default: [:]][key, default: [:]][tile, default: []]
            ends.append(now)
            tileDrawEnds[pageNumber, default: [:]][key, default: [:]][tile] = Array(ends.suffix(Self.keptDrawsPerTile))
        }
    }

    /// How many times each PDFKit tile of the page finished drawing at about
    /// `pixelsPerPoint` after `time` (`CACurrentMediaTime`), counting at most the
    /// last two draws of a tile.
    func tileDrawCounts(ofPage pageNumber: Int, pixelsPerPoint: CGFloat, after time: CFTimeInterval) -> [PDFPageTile: Int] {
        let key = Self.drawKey(pixelsPerPoint)
        lock.lock()
        defer { lock.unlock() }
        guard let buckets = tileDrawEnds[pageNumber] else { return [:] }
        var counts = [PDFPageTile: Int]()
        for bucket in [key - 1, key, key + 1] {
            for (tile, ends) in buckets[bucket] ?? [:] {
                let count = ends.filter { $0 > time }.count
                if count > 0 {
                    counts[tile, default: 0] += count
                }
            }
        }
        return counts
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

/// A tile PDFKit renders a page in: 1024 device pixels square with a 1 pixel
/// border, in the displayed box's space (origin at its bottom left). Tile
/// (column, row) is drawn with the box origin at (1 - 1024 column, 1 - 1024 row).
/// The same on iOS 18 and 26.
struct PDFPageTile: Hashable {
    var column: Int
    var row: Int

    private static let size: CGFloat = 1024
    private static let border: CGFloat = 1

    /// The tile a draw with `ctm` renders; nil for other draws (thumbnails).
    init?(drawnWith ctm: CGAffineTransform) {
        let column = ((Self.border - ctm.tx) / Self.size).rounded()
        let row = ((Self.border - ctm.ty) / Self.size).rounded()
        // Within a hundredth of a pixel of the grid.
        guard abs(ctm.b) < 0.0001, abs(ctm.c) < 0.0001, ctm.a > 0, ctm.d > 0,
              abs(Self.border - column * Self.size - ctm.tx) < 0.01,
              abs(Self.border - row * Self.size - ctm.ty) < 0.01
        else { return nil }
        self.column = Int(column)
        self.row = Int(row)
    }

    init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// The tiles that show `rect` (in box space, points) at `pixelsPerPoint`.
    static func tiles(covering rect: CGRect, pixelsPerPoint: CGFloat) -> Set<PDFPageTile> {
        guard !rect.isNull, !rect.isEmpty, pixelsPerPoint > 0 else { return [] }
        // Half a pixel in, so a tile merely touching an edge is not counted.
        func index(_ points: CGFloat, inset: CGFloat) -> Int {
            Int(((points * pixelsPerPoint + inset + border) / size).rounded(.down))
        }
        let columns = index(rect.minX, inset: 0.5)...max(index(rect.minX, inset: 0.5), index(rect.maxX, inset: -0.5))
        let rows = index(rect.minY, inset: 0.5)...max(index(rect.minY, inset: 0.5), index(rect.maxY, inset: -0.5))
        return Set(columns.flatMap { column in rows.map { PDFPageTile(column: column, row: $0) } })
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
                renderTheme?.noteDraw(ofPage: pageNumber, ctm: context.ctm)
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
        // `PDFAnnotation.draw(with:in:)` applies the box transform itself, like
        // `draw(with:to:)`, so it is given box space.
        let boxToPage = transform(for: box).inverted()
        for annotation in annotations where annotation.shouldDisplay {
            context.saveGState()
            switch annotation.type {
            case "Highlight":
                context.setBlendMode(.multiply)
                context.setFillColor(annotation.color.withAlphaComponent(1).cgColor)
                context.fill(annotation.bounds)
            case "Underline", "StrikeOut", "Squiggly":
                context.setBlendMode(.multiply)
                context.concatenate(boxToPage)
                annotation.draw(with: box, in: context)
            default:
                context.concatenate(boxToPage)
                annotation.draw(with: box, in: context)
            }
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// Inverts to black, then caps text at 70% gray. Also used for PDFKit's page
    /// placeholders, which must match the tiles.
    static func invert(_ rect: CGRect, in context: CGContext) {
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
