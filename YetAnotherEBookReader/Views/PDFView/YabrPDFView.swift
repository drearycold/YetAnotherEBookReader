//
//  YabrPDFView.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/4/18.
//

import Foundation

import PDFKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFView: PDFView {
    var yabrPDFViewController: YabrPDFViewController? {
        delegate?.pdfViewParentViewController?() as? YabrPDFViewController
    }
    var yabrPDFMetaSource: YabrPDFMetaSource? {
        yabrPDFViewController?.yabrPDFMetaSource
    }
    
    var highlights = [UUID: [HighlightValue]]()
    /// The highlights on the pages, to rebuild their annotations.
    private var highlightSources = [UUID: PDFHighlight]()
    /// How highlight annotations are drawn; switching rebuilds them.
    var highlightAppearance = PDFHighlightAppearance.standard {
        didSet {
            guard highlightAppearance != oldValue else { return }
            highlightSources.values.forEach(injectHighlight(highlight:))
        }
    }
    /// Highlight whose edit menu is showing.
    var highlightTapped: UUID?

    /// Content inset added on top of PDFKit's own so a viewport anchor outside the
    /// normally scrollable range (e.g. top-aligning a page shorter than the view)
    /// can be reached.
    private var viewportExtraInset = UIEdgeInsets.zero
    /// PDFKit's own page break margins, before `padPageBreakMargins(for:)`.
    private var defaultPageBreakMargins: UIEdgeInsets?

    /// PDFKit shows a per-page placeholder layer (white background plus an
    /// unthemed low-resolution preview) until a page's tiles render. Dark pages are
    /// drawn inverted into the tiles, so under dark the placeholder is inverted too,
    /// or every newly shown page flashes white (or blank while scrolling fast).
    var invertsPagePlaceholders = false {
        didSet {
            guard oldValue != invertsPagePlaceholders else { return }
            installPagePlaceholderObserver()
            updateAllPagePlaceholders()
        }
    }
    private var pagePlaceholderProvider: PDFPagePlaceholderOverlayProvider?
    /// Keyed by placeholder layer; re-inverts whenever PDFKit sets new contents.
    private var pagePlaceholderObservations: [ObjectIdentifier: PagePlaceholderObservation] = [:]

    private struct PagePlaceholderObservation {
        weak var layer: CALayer?
        let observations: [NSKeyValueObservation]
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Selecting a whole PDF is slow and never what a reader wants.
        if action == #selector(UIResponderStandardEditActions.selectAll(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Adds the reader actions to the system text-selection edit menu.
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let menu = selectionContextMenu() else { return }
        if builder.menu(for: .standardEdit) != nil {
            builder.insertSibling(menu, afterMenu: .standardEdit)
        } else {
            builder.insertChild(menu, atStartOfMenu: .root)
        }
    }

    /// The reader actions for the current text selection, or `nil` when there is no
    /// selection or a highlight's own menu is showing.
    func selectionContextMenu() -> UIMenu? {
        guard highlightTapped == nil,
              let text = currentSelection?.string, !text.isEmpty,
              let elements = yabrPDFViewController?.menuManager.selectionMenuElements(),
              !elements.isEmpty
        else { return nil }
        return UIMenu(options: .displayInline, children: elements)
    }

    /// The reader surface hosting this page view, if any.
    var surface: PDFReaderSurface? {
        superview as? PDFReaderSurface
    }

    // The app's own taps live on the surface; these delegate methods see PDFKit's.

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // PDFView declares but does not implement this optional delegate method, so
        // calling super crashes; `false` is UIKit's default when it is absent.
        return false
    }

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // PDFKit's taps stay out of the page-turn tap zones.
        if gestureRecognizer is UITapGestureRecognizer, let surface, surface.isInTapZone(touch.location(in: surface)) {
            return false
        }
        return super.gestureRecognizer(gestureRecognizer, shouldReceive: touch)
    }
    
    /// Shows the edit menu of the highlight at `location`; returns whether one was hit.
    @discardableResult
    func handleHighlightTap(at location: CGPoint) -> Bool {
        guard let (highlightId, rect) = highlight(at: location) else { return false }
        yabrPDFViewController?.menuManager.presentHighlightMenu(for: highlightId, rect: rect)
        return true
    }

    /// A tap off any highlight: dismisses the highlight menu, clears the selection,
    /// and follows link annotations.
    func handleTap(at tapLocation: CGPoint) {
        self.highlightTapped = nil
        yabrPDFViewController?.menuManager.dismissHighlightMenu()

        let aoi = self.areaOfInterest(for: tapLocation)
        guard aoi.contains(.annotationArea) else {
            self.currentSelection = nil
            return
        }

        if self.currentSelection != nil {
            self.clearSelection()
        }

        self.visiblePages.forEach { visiblePage in
            guard let annotation = visiblePage.annotation(at: self.convert(tapLocation, to: visiblePage)),
                  let typeString = annotation.type,
                  let annotationAction = annotation.action
            else {
                return
            }

            switch typeString {
            case "Link":
                if let currentPage = currentPage {
                    self.yabrPDFViewController?.updateHistoryMenu(
                        curPage: currentPage,
                        location: self.convert(.zero, to: currentPage)
                    )
                }
                self.perform(annotationAction)
            default:
                break
            }
        }
    }

    /// The highlight under `location` and the view rect of the annotation hit, so a
    /// multi-line highlight's menu points at the line that was tapped.
    func highlight(at location: CGPoint) -> (UUID, CGRect)? {
        for (highlightId, values) in highlights {
            for annotation in values.flatMap(\.annotations) {
                guard let page = annotation.page,
                      annotation.bounds.contains(self.convert(location, to: page))
                else { continue }
                return (highlightId, self.convert(annotation.bounds, from: page))
            }
        }
        return nil
    }

    func copyHighlight(_ highlightId: UUID) {
        guard let values = highlights[highlightId] else { return }
        UIPasteboard.general.string = values.compactMap { $0.selection.string }.joined(separator: " ")
    }

    func selectHighlight(_ highlightId: UUID) {
        guard let values = highlights[highlightId], let document = self.document else { return }
        let selection = PDFSelection(document: document)
        selection.add(values.map { $0.selection })
        self.setCurrentSelection(selection, animate: false)
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension BookHighlightStyle {
    var pdfAnnotationSubtype: (PDFAnnotationSubtype, UIColor) {
        switch self {
        case .underline:
            return (.underline, .systemRed)
        case .yellow:
            return (.highlight, .systemYellow)
        case .green:
            return (.highlight, .systemGreen)
        case .blue:
            return (.highlight, .systemBlue)
        case .pink:
            return (.highlight, .systemPink)
        }
    }
}

// MARK: Highlights
@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFView {
    /// Adds (or redraws) a highlight's annotations in the current appearance.
    func injectHighlight(highlight: PDFHighlight) {
        guard let document else { return }
        removeAnnotations(of: highlight.uuid)
        highlightSources[highlight.uuid] = highlight
        let values = Self.addAnnotations(for: highlight, to: document, appearance: highlightAppearance)
        if !values.isEmpty {
            highlights[highlight.uuid] = values
        }
    }

    /// Adds a highlight's annotations to `document`'s pages: one per line, the note
    /// as the first line's comment (an exported PDF shows it on the highlight), and
    /// a marker on the last line when there is a note.
    private static func addAnnotations(for highlight: PDFHighlight, to document: PDFDocument, appearance: PDFHighlightAppearance) -> [HighlightValue] {
        guard let style = BookHighlightStyle(rawValue: highlight.type) else { return [] }
        var values = [HighlightValue]()
        // Text line of the last annotation; a dark underline bar is only its bottom.
        var lastLineBounds: CGRect?
        for location in highlight.pos {
            guard let page = document.page(at: location.page - 1) else { continue }
            for range in location.ranges {
                guard let selection = document.selection(from: page, atCharacterIndex: range.lowerBound, to: page, atCharacterIndex: range.upperBound)
                else { continue }
                var value = HighlightValue(selection: selection)
                for line in selection.selectionsByLine() {
                    let lineBounds = line.bounds(for: page)
                    let annotation = PDFHighlightAnnotations.line(bounds: lineBounds, style: style, highlightId: highlight.uuid, appearance: appearance)
                    page.addAnnotation(annotation)
                    value.annotations.append(annotation)
                    lastLineBounds = lineBounds
                }
                values.append(value)
            }
        }

        guard let note = highlight.note, !note.isEmpty,
              let lastIndex = values.indices.last,
              let page = values[lastIndex].annotations.last?.page,
              let lastLineBounds
        else { return values }
        values.first?.annotations.first?.contents = note
        if let marker = PDFHighlightAnnotations.noteMarker(lineBounds: lastLineBounds, style: style, highlightId: highlight.uuid, appearance: appearance) {
            page.addAnnotation(marker)
            values[lastIndex].annotations.append(marker)
        }
        return values
    }

    /// A fresh copy of the document with the highlights in their standard form and
    /// the notes as their comments, for sharing. The pages on screen are untouched.
    func annotatedExportDocument() -> PDFDocument? {
        guard let document,
              let copy = document.documentURL.flatMap(PDFDocument.init(url:)) ?? document.dataRepresentation().flatMap(PDFDocument.init(data:))
        else { return nil }
        if document.documentURL == nil {
            // A serialized copy already holds the on-screen annotations.
            for index in 0..<copy.pageCount {
                guard let page = copy.page(at: index) else { continue }
                page.annotations.filter { $0.value(forAnnotationKey: .highlightId) != nil }.forEach(page.removeAnnotation)
            }
        }
        for highlight in highlightSources.values {
            _ = Self.addAnnotations(for: highlight, to: copy, appearance: .export)
        }
        return copy
    }

    private func removeAnnotations(of highlightId: UUID) {
        highlights.removeValue(forKey: highlightId)?.flatMap(\.annotations).forEach { annotation in
            annotation.page?.removeAnnotation(annotation)
        }
    }
    
    func modifyHighlightStyle(highlightId: UUID, type: BookHighlightStyle) {
        self.yabrPDFViewController?.annotationManager.modifyHighlightStyle(uuid: highlightId, type: type)
    }
    
    func removeHighlight(highlight: PDFHighlight) {
        highlightSources.removeValue(forKey: highlight.uuid)
        removeAnnotations(of: highlight.uuid)
    }
    
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFView {
    // MARK: Theme and jump mask

    /// The page canvas colour; the surface owns the tint and the jump mask.
    func applyTheme(_ palette: PDFThemePalette) {
        backgroundColor = UIColor(cgColor: palette.canvas)
    }

    /// `page` as it appears in the view right now. Page drawing is untinted (the
    /// theme overlay sits above the mask) except for dark, which `draw` inverts.
    func viewportSnapshot(of page: PDFPage) -> UIImage {
        let box = page.bounds(for: displayBox)
        // Page space -> view space, exactly as PDFView lays the page out (scale,
        // scroll, rotation), measured from three converted points.
        let origin = convert(CGPoint.zero, from: page)
        let unitX = convert(CGPoint(x: 100, y: 0), from: page)
        let unitY = convert(CGPoint(x: 0, y: 100), from: page)
        let pageToView = CGAffineTransform(
            a: (unitX.x - origin.x) / 100, b: (unitX.y - origin.y) / 100,
            c: (unitY.x - origin.x) / 100, d: (unitY.y - origin.y) / 100,
            tx: origin.x, ty: origin.y
        )
        // PDFPage.draw(with:to:) draws in the box's display space (cropped and
        // rotated); undo that to draw in page space.
        let displayToPage = page.transform(for: displayBox).inverted()

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        let canvas = backgroundColor.cgColor.alpha > 0 ? backgroundColor : .white

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { rendererContext in
            canvas.setFill()
            rendererContext.fill(bounds)

            let context = rendererContext.cgContext
            context.concatenate(pageToView)
            context.setFillColor(gray: 1.0, alpha: 1.0)
            context.fill(box)
            context.concatenate(displayToPage)
            if let page = page as? PDFPageWithBackground {
                page.drawAsDisplayed(with: displayBox, to: context)
            } else {
                page.draw(with: displayBox, to: context)
            }
        }
    }

    // MARK: Page placeholders

    /// Number of PDFKit placeholder layers updated; 0 means PDFKit's layer
    /// structure was not recognised.
    @discardableResult
    func updateAllPagePlaceholders() -> Int {
        guard let scrollView = documentScrollView else { return 0 }
        func pageViews(in view: UIView) -> [UIView] {
            Self.pagePlaceholderLayers(in: view).isEmpty ? view.subviews.flatMap(pageViews) : [view]
        }
        return pageViews(in: scrollView).reduce(0) { $0 + updatePagePlaceholder(in: $1) }
    }

    @discardableResult
    func updatePagePlaceholder(in pageView: UIView) -> Int {
        let layers = Self.pagePlaceholderLayers(in: pageView)
        // PDFKit recycles page views while scrolling; drop entries for freed layers
        // so a reused address is not mistaken for an observed layer.
        pagePlaceholderObservations = pagePlaceholderObservations.filter { $0.value.layer != nil }
        for layer in layers {
            let key = ObjectIdentifier(layer)
            guard invertsPagePlaceholders else {
                pagePlaceholderObservations[key] = nil
                continue
            }
            Self.invertPlaceholder(layer)
            if pagePlaceholderObservations[key]?.layer !== layer {
                // PDFKit fills the preview in later; invert it in the same
                // transaction so the unthemed version is never displayed.
                pagePlaceholderObservations[key] = PagePlaceholderObservation(layer: layer, observations: [
                    layer.observe(\.contents) { layer, _ in Self.invertPlaceholder(layer) },
                    layer.observe(\.backgroundColor) { layer, _ in Self.invertPlaceholder(layer) },
                ])
            }
        }
        return layers.count
    }

    static let invertedPlaceholderKey = "yabr.inverted"

    private static func invertPlaceholder(_ layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if layer.backgroundColor.map({ $0.components?.first ?? 0 }) ?? 0 > 0.01 {
            layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        }
        guard let contents = layer.contents else { return }
        guard CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
            // Unknown preview format: better blank than a white flash.
            layer.contents = nil
            return
        }
        let image = contents as! CGImage
        if layer.value(forKey: invertedPlaceholderKey) as AnyObject? === image { return }
        guard let inverted = invertedImage(image) else {
            layer.contents = nil
            return
        }
        layer.setValue(inverted, forKey: invertedPlaceholderKey)
        layer.contents = inverted
    }

    /// Same transform as `PDFPageWithBackground.draw`: invert, then cap at 70% gray.
    private static func invertedImage(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        context.setBlendMode(.exclusion)
        context.fill(rect)
        context.setBlendMode(.darken)
        context.setFillColor(gray: 0.7, alpha: 1)
        context.fill(rect)
        return context.makeImage()
    }

    /// PDFKit's per-page placeholder: the child of `PDFPageLayer` at the
    /// background z position, named `backgroundLayer` on iOS 26 and unnamed on
    /// iOS 18.
    static func pagePlaceholderLayers(in pageView: UIView) -> [CALayer] {
        (pageView.layer.sublayers ?? [])
            .filter { ($0.name ?? "").hasPrefix("PDFPageLayer") }
            .flatMap { pageLayer in
                (pageLayer.sublayers ?? []).filter { $0.name == "backgroundLayer" || ($0.name == nil && $0.zPosition == -900) }
            }
    }

    private func installPagePlaceholderObserver() {
        guard invertsPagePlaceholders, pagePlaceholderProvider == nil else { return }
        // Called synchronously while a page view is set up, before it is drawn.
        let provider = PDFPagePlaceholderOverlayProvider()
        pagePlaceholderProvider = provider
        pageOverlayViewProvider = provider
    }

    // MARK: Viewport

    var documentScrollView: UIScrollView? {
        func find(in view: UIView) -> UIScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? UIScrollView { return scrollView }
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        return find(in: self)
    }

    /// Places `fit.pageAnchor` of `page` at `fit.viewAnchor` by driving the internal
    /// scroll view directly. `go(to:)` is not used: its result depends on the safe
    /// area and on the previous scroll position, and it resolves out-of-range
    /// targets inconsistently.
    func applyViewport(_ fit: PDFPageViewportFit, on page: PDFPage) {
        scaleFactor = fit.scale
        layoutIfNeeded()
        padPageBreakMargins(for: page)

        guard let scrollView = documentScrollView else {
            // Approximate fallback; PDFKit has always hosted pages in a scroll view.
            go(to: PDFDestination(page: page, at: fit.pageAnchor))
            return
        }

        resetViewportExtraInset(scrollView)

        // Two passes: the second absorbs any relayout caused by the inset change.
        for _ in 0..<2 {
            let current = convert(fit.pageAnchor, from: page)
            let dx = current.x - fit.viewAnchor.x
            let dy = current.y - fit.viewAnchor.y
            guard abs(dx) > 0.25 || abs(dy) > 0.25 else { return }

            let target = CGPoint(x: scrollView.contentOffset.x + dx, y: scrollView.contentOffset.y + dy)
            extendInsetIfNeeded(scrollView, toReach: target)
            scrollView.setContentOffset(target, animated: false)
            layoutIfNeeded()
        }
    }

    /// PDFKit centres a document smaller than the view, and on iOS 18 it does so by
    /// moving the document view during layout, which cancels any scroll offset.
    /// Padding each side of the page by the view's excess keeps the document at
    /// least as large as the view, so every placement is reachable by scrolling.
    private func padPageBreakMargins(for page: PDFPage) {
        let base = defaultPageBreakMargins ?? pageBreakMargins
        defaultPageBreakMargins = base
        guard scaleFactor > 0 else { return }

        let pageSize = page.bounds(for: displayBox).applying(CGAffineTransform(rotationAngle: CGFloat(page.rotation) * .pi / 180)).size
        let extraWidth = max(0, bounds.width / scaleFactor - pageSize.width)
        let extraHeight = max(0, bounds.height / scaleFactor - pageSize.height)
        let margins = UIEdgeInsets(
            top: base.top + extraHeight,
            left: base.left + extraWidth,
            bottom: base.bottom + extraHeight,
            right: base.right + extraWidth
        )
        guard pageBreakMargins != margins else { return }
        pageBreakMargins = margins
        // PDFKit would otherwise relayout (and re-centre) the document later,
        // after the scroll offset has been applied.
        layoutDocumentView()
        layoutIfNeeded()
    }

    /// Continuous mode lays pages out with PDFKit's own spacing.
    func restoreDefaultPageBreakMargins() {
        guard let base = defaultPageBreakMargins, pageBreakMargins != base else { return }
        pageBreakMargins = base
    }

    private func resetViewportExtraInset(_ scrollView: UIScrollView) {
        guard viewportExtraInset != .zero else { return }
        var inset = scrollView.contentInset
        inset.top -= viewportExtraInset.top
        inset.left -= viewportExtraInset.left
        inset.bottom -= viewportExtraInset.bottom
        inset.right -= viewportExtraInset.right
        scrollView.contentInset = inset
        viewportExtraInset = .zero
    }

    private func extendInsetIfNeeded(_ scrollView: UIScrollView, toReach target: CGPoint) {
        let adjusted = scrollView.adjustedContentInset
        let size = scrollView.bounds.size
        var extra = UIEdgeInsets.zero
        extra.top = max(0, -adjusted.top - target.y)
        extra.left = max(0, -adjusted.left - target.x)
        extra.bottom = max(0, target.y - (scrollView.contentSize.height + adjusted.bottom - size.height))
        extra.right = max(0, target.x - (scrollView.contentSize.width + adjusted.right - size.width))
        guard extra != .zero else { return }

        var inset = scrollView.contentInset
        inset.top += extra.top
        inset.left += extra.left
        inset.bottom += extra.bottom
        inset.right += extra.right
        scrollView.contentInset = inset
        viewportExtraInset.top += extra.top
        viewportExtraInset.left += extra.left
        viewportExtraInset.bottom += extra.bottom
        viewportExtraInset.right += extra.right
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension PDFAnnotationKey {
    
    public static let highlightId: PDFAnnotationKey = .init(rawValue: "/HID")
    public static let noteMarker: PDFAnnotationKey = .init(rawValue: "/YNM")
}

@available(iOS 16.0, macCatalyst 16.0, *)
struct HighlightValue {
    let selection: PDFSelection
    var annotations: [PDFAnnotation] = []
}

/// How highlight annotations are drawn.
enum PDFHighlightAppearance {
    /// Markup annotations (highlight / underline), with note markers.
    case standard
    /// PDFKit composites markup annotations over the already-inverted dark page
    /// with multiply, which leaves only tinted text (and no underline at all), so
    /// dark uses filled squares, which it composites normally.
    case dark
    /// Standard annotations without markers, for an exported PDF.
    case export
}

/// Builds highlight annotations for a `PDFHighlightAppearance`.
@available(iOS 16.0, macCatalyst 16.0, *)
enum PDFHighlightAnnotations {
    static let noteMarkerMaxSide: CGFloat = 8
    static let darkFillAlpha: CGFloat = 0.35
    static let darkMarkerAlpha: CGFloat = 0.9

    static func line(bounds: CGRect, style: BookHighlightStyle, highlightId: UUID, appearance: PDFHighlightAppearance) -> PDFAnnotation {
        let (subtype, color) = style.pdfAnnotationSubtype
        let properties = [PDFAnnotationKey.highlightId: highlightId.uuidString]
        switch appearance {
        case .standard, .export:
            let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: properties)
            annotation.color = color
            return annotation
        case .dark:
            if subtype == .underline {
                // PDFKit does not fill a square 1 pt tall.
                let height = max(2, (bounds.height * 0.12).rounded())
                return filledSquare(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height), color: darkColor(color), properties: properties)
            }
            return filledSquare(bounds, color: darkColor(color).withAlphaComponent(darkFillAlpha), properties: properties)
        }
    }

    /// A small square in the top-right corner of the last line, drawn like the
    /// highlight: a stacked highlight annotation reads as a darker patch of the
    /// same hue with the text readable; in dark, a brighter filled square. It stays
    /// inside the line, so margin crop never cuts it off.
    static func noteMarker(lineBounds: CGRect, style: BookHighlightStyle, highlightId: UUID, appearance: PDFHighlightAppearance) -> PDFAnnotation? {
        let side = min(lineBounds.height / 2, lineBounds.width, noteMarkerMaxSide)
        let bounds = CGRect(x: lineBounds.maxX - side, y: lineBounds.maxY - side, width: side, height: side)
        let color = style.pdfAnnotationSubtype.1
        let properties = [
            PDFAnnotationKey.highlightId: highlightId.uuidString,
            PDFAnnotationKey.noteMarker: "1",
        ]
        switch appearance {
        case .standard:
            let marker = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: properties)
            marker.color = color
            marker.isReadOnly = true
            return marker
        case .dark:
            return filledSquare(bounds, color: darkColor(color).withAlphaComponent(darkMarkerAlpha), properties: properties)
        case .export:
            return nil
        }
    }

    private static func filledSquare(_ bounds: CGRect, color: UIColor, properties: [PDFAnnotationKey: Any]) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: properties)
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        annotation.color = .clear
        annotation.interiorColor = color
        annotation.isReadOnly = true
        return annotation
    }

    private static func darkColor(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension PDFAnnotation {
    var isNoteMarker: Bool {
        value(forAnnotationKey: .noteMarker) != nil
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
final class PDFPagePlaceholderOverlayProvider: NSObject, PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let overlay = UIView()
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let pdfView = pdfView as? YabrPDFView else { return }
        var candidate = overlayView.superview
        while let view = candidate, YabrPDFView.pagePlaceholderLayers(in: view).isEmpty {
            candidate = view.superview
        }
        if let pageView = candidate {
            pdfView.updatePagePlaceholder(in: pageView)
        }
    }
}
