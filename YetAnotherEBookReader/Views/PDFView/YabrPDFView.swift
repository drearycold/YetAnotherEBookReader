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
    
    /// Content inset added on top of PDFKit's own so a viewport anchor outside the
    /// normally scrollable range (e.g. top-aligning a page shorter than the view)
    /// can be reached, and the page cannot be dragged away (negative).
    private(set) var viewportExtraInset = UIEdgeInsets.zero
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

    /// PDFKit's internal scroll view, whose drags are reported to the surface.
    private weak var observedScrollView: UIScrollView?

    override func layoutSubviews() {
        super.layoutSubviews()
        observeDocumentDragging()
    }

    /// PDFKit creates its scroll view with the document, so this runs on layout.
    private func observeDocumentDragging() {
        guard observedScrollView?.superview == nil, let scrollView = documentScrollView else { return }
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(documentPanned(_:)))
        observedScrollView = scrollView
    }

    /// The scroll view's own pan: dragging a selection handle does not start it.
    @objc private func documentPanned(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began else { return }
        surface?.pageViewDidBeginDragging(self)
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
        guard surface?.highlightTapped == nil,
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
    
    /// A tap off any highlight: dismisses the highlight menu, clears the selection,
    /// and follows link annotations. Returns whether the tap did any of these.
    @discardableResult
    func handleTap(at tapLocation: CGPoint) -> Bool {
        let dismissedMenu = surface?.highlightTapped != nil
        surface?.highlightTapped = nil
        yabrPDFViewController?.menuManager.dismissHighlightMenu()
        let hadSelection = currentSelection != nil

        let aoi = self.areaOfInterest(for: tapLocation)
        guard aoi.contains(.annotationArea) else {
            self.currentSelection = nil
            return dismissedMenu || hadSelection
        }

        if self.currentSelection != nil {
            self.clearSelection()
        }

        var followedLink = false
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
                // A link within the document lands on the step showing its
                // destination on a page read in steps (#97).
                if let goTo = annotationAction as? PDFActionGoTo, let controller = yabrPDFViewController {
                    controller.jump(to: goTo.destination)
                } else {
                    self.perform(annotationAction)
                }
                followedLink = true
            default:
                break
            }
        }
        return dismissedMenu || hadSelection || followedLink
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
        Self.snapshot(
            of: page,
            displayBox: displayBox,
            pageToView: pageToViewTransform(for: page),
            bounds: bounds,
            canvas: snapshotCanvas,
            format: Self.snapshotFormat()
        )
    }

    /// Page space -> view space, exactly as PDFView lays the page out (scale,
    /// scroll, rotation), measured from three converted points.
    func pageToViewTransform(for page: PDFPage) -> CGAffineTransform {
        let origin = convert(CGPoint.zero, from: page)
        let unitX = convert(CGPoint(x: 100, y: 0), from: page)
        let unitY = convert(CGPoint(x: 0, y: 100), from: page)
        return CGAffineTransform(
            a: (unitX.x - origin.x) / 100, b: (unitX.y - origin.y) / 100,
            c: (unitY.x - origin.x) / 100, d: (unitY.y - origin.y) / 100,
            tx: origin.x, ty: origin.y
        )
    }

    /// The colour around the page in a snapshot.
    var snapshotCanvas: UIColor {
        backgroundColor.cgColor.alpha > 0 ? backgroundColor : .white
    }

    static func snapshotFormat() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        return format
    }

    /// `page` drawn under `pageToView` into an image of `bounds`, as a page view
    /// laid out that way shows it. Any thread: the masks of a page's next steps
    /// are drawn ahead of time in the background (#97).
    nonisolated static func snapshot(
        of page: PDFPage,
        displayBox: PDFDisplayBox,
        pageToView: CGAffineTransform,
        bounds: CGRect,
        canvas: UIColor,
        format: UIGraphicsImageRendererFormat
    ) -> UIImage {
        let box = page.bounds(for: displayBox)
        // PDFPage.draw(with:to:) draws in the box's display space (cropped and
        // rotated); undo that to draw in page space.
        let displayToPage = page.transform(for: displayBox).inverted()

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

    /// Same transform as `PDFPageWithBackground.draw`. Thread-safe (thumbnails
    /// render off the main thread).
    nonisolated static func invertedImage(_ image: CGImage) -> CGImage? {
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
        PDFPageWithBackground.invert(rect, in: context)
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
            guard abs(dx) > 0.25 || abs(dy) > 0.25 else { break }

            let target = CGPoint(x: scrollView.contentOffset.x + dx, y: scrollView.contentOffset.y + dy)
            extendInsetIfNeeded(scrollView, toReach: target)
            scrollView.setContentOffset(target, animated: false)
            layoutIfNeeded()
        }
        confineScrollRange(scrollView, to: page)
    }

    /// Moves to exactly `other`'s scroll position when both lay the page out the
    /// same way (scale, margins, content size). A pixel or two of scrolling keeps
    /// the rendered tiles. Returns whether it moved.
    func alignScrollPosition(to other: YabrPDFView) -> Bool {
        guard abs(scaleFactor - other.scaleFactor) < 0.0005,
              pageBreakMargins == other.pageBreakMargins,
              let scrollView = documentScrollView,
              let otherScrollView = other.documentScrollView,
              abs(scrollView.contentSize.width - otherScrollView.contentSize.width) < 0.01,
              abs(scrollView.contentSize.height - otherScrollView.contentSize.height) < 0.01
        else { return false }
        scrollView.contentInset = otherScrollView.contentInset
        viewportExtraInset = other.viewportExtraInset
        scrollView.contentOffset = otherScrollView.contentOffset
        layoutIfNeeded()
        return true
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

    /// Continuous mode lays pages out with PDFKit's own spacing and scroll range.
    func restoreDefaultPageBreakMargins() {
        if let scrollView = documentScrollView {
            resetViewportExtraInset(scrollView)
        }
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

    /// Limits dragging to where the page belongs: along an axis where it fits the
    /// view it stays inside it, otherwise it keeps covering the view. The padded
    /// page break margins (which PDFKit applies twice per side) would let a page
    /// be dragged almost off screen. The current placement stays reachable.
    private func confineScrollRange(_ scrollView: UIScrollView, to page: PDFPage) {
        let pageRect = scrollView.convert(convert(page.bounds(for: displayBox), from: page), from: self)
        let offset = scrollView.contentOffset
        let size = scrollView.bounds.size
        let adjusted = scrollView.adjustedContentInset

        /// The offsets along one axis that keep the page placed as described.
        func range(pageMin: CGFloat, pageLength: CGFloat, viewLength: CGFloat, current: CGFloat) -> (CGFloat, CGFloat) {
            let slack = viewLength - pageLength
            // Page start in the view = pageMin - offset, between 0 and slack.
            let lower = pageMin - max(0, slack)
            let upper = pageMin - min(0, slack)
            return (min(lower, current), max(upper, current))
        }
        let (minX, maxX) = range(pageMin: pageRect.minX, pageLength: pageRect.width, viewLength: size.width, current: offset.x)
        let (minY, maxY) = range(pageMin: pageRect.minY, pageLength: pageRect.height, viewLength: size.height, current: offset.y)

        // The scroll range is -adjusted.left ... contentSize + adjusted.right - size.
        let change = UIEdgeInsets(
            top: -minY - adjusted.top,
            left: -minX - adjusted.left,
            bottom: maxY + size.height - scrollView.contentSize.height - adjusted.bottom,
            right: maxX + size.width - scrollView.contentSize.width - adjusted.right
        )
        guard change != .zero else { return }
        var inset = scrollView.contentInset
        inset.top += change.top
        inset.left += change.left
        inset.bottom += change.bottom
        inset.right += change.right
        scrollView.contentInset = inset
        viewportExtraInset.top += change.top
        viewportExtraInset.left += change.left
        viewportExtraInset.bottom += change.bottom
        viewportExtraInset.right += change.right
        scrollView.contentOffset = offset
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
    /// The text line of each line annotation, in page space, in the same order.
    /// Taps are tested against these: a dark underline bar is only the bottom
    /// of its line.
    var lineBounds: [CGRect] = []
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

    /// How a dark page shows `style`: a dim fill (an underline is opaque), so
    /// light text over it stays readable.
    static func darkColor(for style: BookHighlightStyle) -> UIColor {
        let color = darkColor(style.pdfAnnotationSubtype.1)
        return style == .underline ? color : color.withAlphaComponent(darkFillAlpha)
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
