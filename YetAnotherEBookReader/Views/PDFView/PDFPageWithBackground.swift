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
final class PDFPageRenderTheme: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDrawsInverted = false

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
}

/// Implemented by the `PDFDocument.delegate` that owns the pages.
protocol PDFPageRenderThemeProviding: AnyObject {
    var pageRenderTheme: PDFPageRenderTheme { get }
}

/// Draws the dark theme (inverted page, text at 70% gray). Light tints are an
/// overlay on `YabrPDFView`; see `PDFThemePalette`.
class PDFPageWithBackground: PDFPage {
    private var drawsInverted: Bool {
        (document?.delegate as? PDFPageRenderThemeProviding)?.pageRenderTheme.drawsInverted == true
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)

        guard drawsInverted else { return }

        let rect = bounds(for: box)
        Self.invert(CGRect(origin: .zero, size: rect.size), in: context)
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
