//
//  PDFReaderSurface.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

extension Notification.Name {
    /// The active page view's `PDFViewPageChanged`, relayed with the surface as object.
    static let readerSurfacePageChanged = Notification.Name("YabrPDFReaderSurfacePageChanged")
    /// The active page view's `PDFViewScaleChanged`, relayed with the surface as object.
    static let readerSurfaceScaleChanged = Notification.Name("YabrPDFReaderSurfaceScaleChanged")
    /// The active page view's `PDFViewDisplayBoxChanged`, relayed with the surface as object.
    static let readerSurfaceDisplayBoxChanged = Notification.Name("YabrPDFReaderSurfaceDisplayBoxChanged")
}

/// Hosts the reader's page views and owns what they share: the active page view
/// and the buffers rendering its neighbours (issues #54 / #55). A turn onto a
/// rendered buffer makes it the active view.
///
/// Read `activeView` at the point of use and never keep a reference to it, and
/// observe the surface's notifications rather than a page view's.
@available(iOS 16.0, macCatalyst 16.0, *)
final class PDFReaderSurface: UIView {
    private(set) var activeView = YabrPDFView()

    private var relayObservers: [NSObjectProtocol] = []

    /// Light theme tint (see `PDFThemePalette`), above the pages.
    let themeOverlayView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }()

    /// Opaque preview of the destination page shown briefly after a jump, while
    /// PDFKit renders the new page's tiles. Sits below the theme overlay.
    let jumpMaskView: UIImageView = {
        let view = UIImageView()
        view.isUserInteractionEnabled = false
        view.contentMode = .scaleToFill
        view.alpha = 0
        return view
    }()
    /// Incremented each time the jump mask is shown.
    private(set) var jumpMaskGeneration = 0
    private var loadingCoverGeneration = -1

    // Page-turn tap zones: double tap along the sides, single tap in the bottom
    // corners. The labels show the zones briefly, then stay nearly transparent.
    let doubleTapLeftLabel = UILabel()
    let doubleTapRightLabel = UILabel()
    let singleTapLeftLabel = UILabel()
    let singleTapRightLabel = UILabel()
    let labelTextColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.9)
    let labelDoubleBackgroundColor = UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.9).cgColor
    let labelSingleBackgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.9).cgColor
    let labelHiddenColor = UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.01)
    let labelDisabledColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    private var tapZoneLabels: [UILabel] {
        [doubleTapLeftLabel, doubleTapRightLabel, singleTapLeftLabel, singleTapRightLabel]
    }

    var doubleTapGestureRecognizer: UITapGestureRecognizer?
    var singleTapGestureRecognizer: UITapGestureRecognizer?
    /// A tap off any highlight: dismisses the highlight menu, clears the
    /// selection, follows links.
    var highlightTapGestureRecognizer: UITapGestureRecognizer?
    /// Only begins on a highlight; PDFKit's taps wait for it to fail, so tapping a
    /// highlight shows the app's persisted menu instead of PDFKit's markup menu
    /// (whose Remove / colour / Add Note would bypass the app's storage).
    var highlightMenuTapGestureRecognizer: UITapGestureRecognizer?

    var pageNextButton: UIButton?
    var pagePrevButton: UIButton?

    /// Highlight annotations by highlight id. They live on the document's pages,
    /// which every page view of the document shows.
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

    /// Off-screen page views rendering the neighbours of the page on screen,
    /// behind the active view (PDFKit renders views that are covered, not hidden
    /// ones). A page change onto a buffered page brings its buffer to the front
    /// until the active view has drawn the page: PDFKit renders a page only once
    /// it is current, so without it the new page shows a blurry placeholder for
    /// a few hundred milliseconds. Both are PDFKit renderings at the same viewport,
    /// so the handover is pixel-identical.
    private(set) var bufferViews: [YabrPDFView] = []
    static let bufferCount = 2
    /// The buffer currently in front of the active view.
    private(set) weak var coveringView: YabrPDFView?
    /// Where pages report finished draws; tells when the active view has drawn.
    weak var drawLog: PDFPageRenderTheme?
    private var coverStart: CFTimeInterval = 0
    /// Tiles the covering buffer had not drawn yet when it came in front. It draws
    /// them too, so the active view has drawn them only on their second draw.
    private(set) var coverOwedTiles: Set<PDFPageTile> = []
    private var coverTimer: Timer?
    /// Called when a cover is removed; the buffer is free for another page. It may
    /// run during a page change, so defer heavy work.
    var onCoverEnded: (() -> Void)?
    /// When each buffer was given its page or scale; it is ready once it has drawn
    /// the tiles it shows since.
    private var bufferShownAt: [ObjectIdentifier: CFTimeInterval] = [:]
    /// The page a takeover made current, until `handlePageChange` consumes it.
    private weak var takenOverPage: PDFPage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        install(activeView)
        relayNotifications(of: activeView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        arrangeOverlayViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        relayObservers.forEach(NotificationCenter.default.removeObserver)
        coverTimer?.invalidate()
    }

    private func install(_ pageView: YabrPDFView) {
        pageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: topAnchor),
            pageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageView.leftAnchor.constraint(equalTo: leftAnchor),
            pageView.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    private func relayNotifications(of pageView: YabrPDFView) {
        relayObservers.forEach(NotificationCenter.default.removeObserver)
        let relays: [(Notification.Name, Notification.Name)] = [
            (.PDFViewPageChanged, .readerSurfacePageChanged),
            (.PDFViewScaleChanged, .readerSurfaceScaleChanged),
            (.PDFViewDisplayBoxChanged, .readerSurfaceDisplayBoxChanged),
        ]
        relayObservers = relays.map { source, relayed in
            // No queue: delivered synchronously, as PDFKit posts them.
            NotificationCenter.default.addObserver(forName: source, object: pageView, queue: nil) { [weak self] _ in
                guard let self else { return }
                NotificationCenter.default.post(name: relayed, object: self)
            }
        }
    }
}

// MARK: - Theme, jump mask and loading cover

@available(iOS 16.0, macCatalyst 16.0, *)
extension PDFReaderSurface {
    func applyTheme(_ palette: PDFThemePalette) {
        activeView.applyTheme(palette)
        activeView.invertsPagePlaceholders = palette.drawsInverted
        for buffer in bufferViews {
            buffer.applyTheme(palette)
            buffer.invertsPagePlaceholders = palette.drawsInverted
        }
        if let overlay = palette.overlay {
            themeOverlayView.backgroundColor = UIColor(red: overlay.red, green: overlay.green, blue: overlay.blue, alpha: overlay.alpha)
            themeOverlayView.isHidden = false
        } else {
            themeOverlayView.backgroundColor = nil
            themeOverlayView.isHidden = true
        }
        jumpMaskView.backgroundColor = palette.canvas.alpha > 0 ? UIColor(cgColor: palette.canvas) : .white
        arrangeOverlayViews()
    }

    var isJumpMaskVisible: Bool {
        jumpMaskView.alpha > 0
    }

    /// Covers the view with `page` rendered at the current viewport, then fades out.
    /// Call after the viewport is applied so both land in the same frame.
    func showJumpMask(for page: PDFPage) {
        showJumpMask(image: activeView.viewportSnapshot(of: page))
    }

    /// Covers the view with what it shows now, then fades out like a jump mask.
    /// Copies the screen instead of drawing `page` again; a mask still showing
    /// stays (the page under it may not have rendered yet).
    func freezeWithJumpMask(showing page: PDFPage) {
        if isJumpMaskVisible {
            jumpMaskGeneration += 1
            jumpMaskView.layer.removeAllAnimations()
            jumpMaskView.alpha = 1
            scheduleJumpMaskFade(generation: jumpMaskGeneration)
            return
        }
        guard let snapshot = (coveringView ?? activeView).snapshotView(afterScreenUpdates: false) else {
            showJumpMask(for: page)
            return
        }
        showJumpMask(image: nil)
        snapshot.frame = jumpMaskView.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        jumpMaskView.addSubview(snapshot)
    }

    /// A plain page-coloured cover while the reader appears, before the first page
    /// is positioned. Replaced by the first jump mask, or faded by
    /// `finishLoadingCover()`.
    func showLoadingCover() {
        clearJumpMask()
        jumpMaskView.layer.removeAllAnimations()
        jumpMaskView.alpha = 1
        jumpMaskGeneration += 1
        loadingCoverGeneration = jumpMaskGeneration
        arrangeOverlayViews()
    }

    func finishLoadingCover() {
        guard loadingCoverGeneration == jumpMaskGeneration, jumpMaskView.alpha > 0 else { return }
        scheduleJumpMaskFade(generation: jumpMaskGeneration)
    }

    private func showJumpMask(image: UIImage?) {
        clearJumpMask()
        jumpMaskView.image = image
        jumpMaskView.layer.removeAllAnimations()
        jumpMaskView.alpha = 1
        arrangeOverlayViews()

        jumpMaskGeneration += 1
        scheduleJumpMaskFade(generation: jumpMaskGeneration)
    }

    private func scheduleJumpMaskFade(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self] in
            guard let self, self.jumpMaskGeneration == generation else { return }
            UIView.animate(withDuration: 0.15) {
                self.jumpMaskView.alpha = 0
            } completion: { _ in
                if self.jumpMaskGeneration == generation {
                    self.clearJumpMask()
                }
            }
        }
    }

    private func clearJumpMask() {
        jumpMaskView.image = nil
        jumpMaskView.subviews.forEach { $0.removeFromSuperview() }
    }

    /// Page view < jump mask < theme overlay < tap zone labels.
    private func arrangeOverlayViews() {
        for overlay in [jumpMaskView, themeOverlayView] as [UIView] {
            if overlay.superview !== self {
                addSubview(overlay)
            }
            overlay.frame = bounds
            bringSubviewToFront(overlay)
        }
        for label in tapZoneLabels where label.superview === self {
            bringSubviewToFront(label)
        }
    }
}

// MARK: - Page-turn tap zones and the app's taps

@available(iOS 16.0, macCatalyst 16.0, *)
extension PDFReaderSurface: UIGestureRecognizerDelegate {
    func prepareActions(pageNextButton: UIButton, pagePrevButton: UIButton) {
        self.pageNextButton = pageNextButton
        self.pagePrevButton = pagePrevButton

        for label in [doubleTapLeftLabel, doubleTapRightLabel] {
            label.text = "Double Tap\nThis Region\nto Turn Page"
        }
        for label in [singleTapLeftLabel, singleTapRightLabel] {
            label.text = "Tap to Turn"
        }
        for label in tapZoneLabels {
            label.textAlignment = .center
            label.numberOfLines = 0
            label.layer.cornerRadius = 8
            label.layer.masksToBounds = true
            addSubview(label)
        }

        let doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(doubleTappedGesture(sender:)))
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        doubleTapGestureRecognizer.delegate = self
        addGestureRecognizer(doubleTapGestureRecognizer)
        self.doubleTapGestureRecognizer = doubleTapGestureRecognizer

        let singleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(singleTappedGesture(sender:)))
        singleTapGestureRecognizer.numberOfTapsRequired = 1
        singleTapGestureRecognizer.delegate = self
        singleTapGestureRecognizer.delaysTouchesEnded = true
        addGestureRecognizer(singleTapGestureRecognizer)
        self.singleTapGestureRecognizer = singleTapGestureRecognizer

        let highlightTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(highlightTappedGesture(sender:)))
        highlightTapGestureRecognizer.numberOfTapsRequired = 1
        highlightTapGestureRecognizer.delegate = self
        highlightTapGestureRecognizer.delaysTouchesEnded = true
        addGestureRecognizer(highlightTapGestureRecognizer)
        self.highlightTapGestureRecognizer = highlightTapGestureRecognizer

        let highlightMenuTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(highlightMenuTappedGesture(sender:)))
        highlightMenuTapGestureRecognizer.numberOfTapsRequired = 1
        highlightMenuTapGestureRecognizer.delegate = self
        addGestureRecognizer(highlightMenuTapGestureRecognizer)
        self.highlightMenuTapGestureRecognizer = highlightMenuTapGestureRecognizer

        arrangeOverlayViews()
    }

    func pageTapPreview(hMarginAutoScaler: Double) {
        pageTapResize(hMarginAutoScaler: hMarginAutoScaler)

        let textFont = UIFont.systemFont(ofSize: UITraitCollection.current.horizontalSizeClass == .regular ? 16 : 12, weight: .regular)
        UIView.animate(withDuration: TimeInterval(0.5)) { [self] in
            for label in tapZoneLabels {
                label.font = textFont
                label.textColor = labelTextColor
            }
            doubleTapLeftLabel.layer.backgroundColor = labelDoubleBackgroundColor
            doubleTapRightLabel.layer.backgroundColor = labelDoubleBackgroundColor
            singleTapLeftLabel.layer.backgroundColor = labelSingleBackgroundColor
            singleTapRightLabel.layer.backgroundColor = labelSingleBackgroundColor
        }

        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .seconds(3))) { [self] in
            UIView.animate(withDuration: TimeInterval(0.5)) { [self] in
                for label in tapZoneLabels {
                    label.textColor = labelHiddenColor
                    label.layer.backgroundColor = labelHiddenColor.cgColor
                }
            }
        }
    }

    func pageTapResize(hMarginAutoScaler: Double) {
        let height = bounds.height
        let width = bounds.width
        let doubleTapWidth = min(max(width * (hMarginAutoScaler - 5) / 100.0, 50.0), 100.0)
        let singleTapWidth = doubleTapWidth * 2
        let singleTapHeight = height * 0.15
        doubleTapLeftLabel.frame = CGRect(
            origin: CGPoint(x: 0, y: height * 0.1),
            size: CGSize(width: doubleTapWidth, height: height * 0.9 - singleTapHeight)
        )
        doubleTapRightLabel.frame = CGRect(
            origin: CGPoint(x: width - doubleTapWidth, y: height * 0.1),
            size: CGSize(width: doubleTapWidth, height: height * 0.9 - singleTapHeight)
        )
        singleTapLeftLabel.frame = CGRect(
            origin: CGPoint(x: 0, y: height - singleTapHeight),
            size: CGSize(width: singleTapWidth, height: singleTapHeight)
        )
        singleTapRightLabel.frame = CGRect(
            origin: CGPoint(x: width - singleTapWidth, y: height - singleTapHeight),
            size: CGSize(width: singleTapWidth, height: singleTapHeight)
        )
    }

    func pageTapDisable() {
        for label in tapZoneLabels {
            label.textColor = labelDisabledColor
            label.layer.backgroundColor = labelDisabledColor.cgColor
        }
    }

    /// Whether `location` (in the surface) is in a page-turn tap zone.
    func isInTapZone(_ location: CGPoint) -> Bool {
        tapZoneLabels.contains { $0.frame.contains(location) }
    }

    private var tapZonesEnabled: Bool {
        doubleTapLeftLabel.layer.backgroundColor != labelDisabledColor.cgColor
    }

    @objc private func doubleTappedGesture(sender: UITapGestureRecognizer) {
        guard tapZonesEnabled, sender.state == .ended else { return }
        let location = sender.location(in: self)
        if doubleTapLeftLabel.frame.contains(location) || singleTapLeftLabel.frame.contains(location) {
            pagePrevButton?.sendActions(for: .primaryActionTriggered)
        } else if doubleTapRightLabel.frame.contains(location) || singleTapRightLabel.frame.contains(location) {
            pageNextButton?.sendActions(for: .primaryActionTriggered)
        }
    }

    @objc private func singleTappedGesture(sender: UITapGestureRecognizer) {
        guard tapZonesEnabled, sender.state == .ended else { return }
        let location = sender.location(in: self)
        if singleTapLeftLabel.frame.contains(location) {
            pagePrevButton?.sendActions(for: .primaryActionTriggered)
        } else if singleTapRightLabel.frame.contains(location) {
            pageNextButton?.sendActions(for: .primaryActionTriggered)
        }
    }

    @objc private func highlightTappedGesture(sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        // Taps on a highlight belong to `highlightMenuTapGestureRecognizer`.
        guard highlight(at: sender.location(in: self)) == nil else { return }
        activeView.handleTap(at: sender.location(in: activeView))
    }

    @objc private func highlightMenuTappedGesture(sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        handleHighlightTap(at: sender.location(in: self))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == singleTapGestureRecognizer || gestureRecognizer == doubleTapGestureRecognizer {
            if otherGestureRecognizer is UILongPressGestureRecognizer { return false }
            if otherGestureRecognizer is UIPanGestureRecognizer { return false }

            if gestureRecognizer == doubleTapGestureRecognizer && otherGestureRecognizer == singleTapGestureRecognizer { return false }
            if gestureRecognizer == singleTapGestureRecognizer && otherGestureRecognizer == doubleTapGestureRecognizer { return false }
            return true
        }
        return gestureRecognizer == highlightTapGestureRecognizer
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === highlightMenuTapGestureRecognizer {
            return highlight(at: gestureRecognizer.location(in: self)) != nil
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // PDFKit's taps inside the page view, including the text interaction's
        // (double tap selects a word), wait for the highlight menu tap and for the
        // page-turn taps. Only these receive touches in the tap zones, so elsewhere
        // PDFKit's taps are not delayed. PDFKit orders its taps after recognizers
        // on the PDFView itself, but not after the surface's.
        guard gestureRecognizer === highlightMenuTapGestureRecognizer
                || gestureRecognizer === doubleTapGestureRecognizer
                || gestureRecognizer === singleTapGestureRecognizer
        else { return false }
        return otherGestureRecognizer is UITapGestureRecognizer
            && otherGestureRecognizer.view?.isDescendant(of: activeView) == true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: self)
        if gestureRecognizer == singleTapGestureRecognizer {
            return touch.tapCount == 1 && (singleTapLeftLabel.frame.contains(location) || singleTapRightLabel.frame.contains(location))
        }
        if gestureRecognizer == doubleTapGestureRecognizer {
            return isInTapZone(location)
        }
        // The highlight taps stay out of the tap zones.
        return !isInTapZone(location)
    }
}

// MARK: - Highlights

@available(iOS 16.0, macCatalyst 16.0, *)
extension PDFReaderSurface {
    /// Adds (or redraws) a highlight's annotations in the current appearance.
    func injectHighlight(highlight: PDFHighlight) {
        guard let document = activeView.document else { return }
        removeAnnotations(of: highlight.uuid)
        highlightSources[highlight.uuid] = highlight
        let values = Self.addAnnotations(for: highlight, to: document, appearance: highlightAppearance)
        if !values.isEmpty {
            highlights[highlight.uuid] = values
        }
    }

    func removeHighlight(highlight: PDFHighlight) {
        highlightSources.removeValue(forKey: highlight.uuid)
        removeAnnotations(of: highlight.uuid)
    }

    /// The highlight under `location` (in the surface) and the rect (in the
    /// surface) of the annotation hit, so a multi-line highlight's menu points at
    /// the line that was tapped.
    func highlight(at location: CGPoint) -> (UUID, CGRect)? {
        let pageView = activeView
        let locationInPageView = convert(location, to: pageView)
        for (highlightId, values) in highlights {
            for annotation in values.flatMap(\.annotations) {
                guard let page = annotation.page,
                      annotation.bounds.contains(pageView.convert(locationInPageView, to: page))
                else { continue }
                return (highlightId, pageView.convert(pageView.convert(annotation.bounds, from: page), to: self))
            }
        }
        return nil
    }

    /// Shows the edit menu of the highlight at `location` (in the surface); returns
    /// whether one was hit.
    @discardableResult
    func handleHighlightTap(at location: CGPoint) -> Bool {
        guard let (highlightId, rect) = highlight(at: location) else { return false }
        activeView.yabrPDFViewController?.menuManager.presentHighlightMenu(for: highlightId, rect: rect)
        return true
    }

    func copyHighlight(_ highlightId: UUID) {
        guard let values = highlights[highlightId] else { return }
        UIPasteboard.general.string = values.compactMap { $0.selection.string }.joined(separator: " ")
    }

    func selectHighlight(_ highlightId: UUID) {
        guard let values = highlights[highlightId], let document = activeView.document else { return }
        let selection = PDFSelection(document: document)
        selection.add(values.map { $0.selection })
        activeView.setCurrentSelection(selection, animate: false)
    }

    /// A fresh copy of the document with the highlights in their standard form and
    /// the notes as their comments, for sharing. The pages on screen are untouched.
    func annotatedExportDocument() -> PDFDocument? {
        guard let document = activeView.document,
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
}

// MARK: - Buffered neighbour pages

@available(iOS 16.0, macCatalyst 16.0, *)
extension PDFReaderSurface {
    /// The pages the buffers hold.
    var bufferedPages: [PDFPage] {
        bufferViews.compactMap { $0.document == nil ? nil : $0.currentPage }
    }

    /// Shows `pages` in the buffers at the viewport `viewport` gives, keeping any
    /// buffer that already holds one of them. The buffer in front stays until its
    /// cover ends.
    func prepareBuffers(showing pages: [PDFPage], viewport: (PDFPage, YabrPDFView) -> PDFPageViewportFit) {
        guard let document = activeView.document else {
            discardBuffers()
            return
        }
        while bufferViews.count < Self.bufferCount {
            let buffer = YabrPDFView()
            setInteractive(false, buffer)
            installBuffer(buffer)
            bufferViews.append(buffer)
        }

        let wanted = Array(pages.prefix(Self.bufferCount))
        var free = bufferViews.filter { $0 !== coveringView }
        var unassigned = [PDFPage]()
        for page in wanted {
            if let index = free.firstIndex(where: { $0.document === document && $0.currentPage === page }) {
                let buffer = free.remove(at: index)
                show(page, in: buffer, viewport: viewport)
            } else if page !== coveringView?.currentPage {
                unassigned.append(page)
            }
        }
        for (page, buffer) in zip(unassigned, free) {
            show(page, in: buffer, viewport: viewport)
        }
    }

    /// Releases the buffers' pages (scroll mode, theme re-render).
    func discardBuffers() {
        endCover(notifies: false)
        for buffer in bufferViews {
            buffer.document = nil
        }
    }

    /// Brings the buffer holding `page` in front of the active view if it shows
    /// the page exactly where the active view does. Call after the active view's
    /// viewport is applied. Returns whether it covers.
    @discardableResult
    func coverWithBuffer(showing page: PDFPage) -> Bool {
        if let coveringView, coveringView.currentPage !== page {
            endCover()
        }
        guard coveringView == nil,
              let buffer = bufferViews.first(where: { $0.currentPage === page && showsLikeActiveView($0) }),
              // The same fit can land a few pixels apart depending on how each view
              // got there (iOS 18 lays pages out asynchronously); take the active
              // view's exact position. A shift this small stays within the
              // buffer's rendered tiles.
              Self.showsSameViewport(buffer, activeView, page: page, pixels: 24),
              buffer.alignScrollPosition(to: activeView),
              Self.showsSameViewport(buffer, activeView, page: page, pixels: 0.03)
        else { return false }

        insertSubview(buffer, aboveSubview: activeView)
        coveringView = buffer
        coverStart = CACurrentMediaTime()
        let drawn = tileDrawCounts(of: buffer, page: page, after: bufferShownAt[ObjectIdentifier(buffer)] ?? 0)
        coverOwedTiles = shownTiles(of: buffer, page: page).filter { drawn[$0] == nil }
        coverTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.checkCoverHandover()
        }
        // Also while a touch is tracking.
        RunLoop.main.add(timer, forMode: .common)
        coverTimer = timer
        return true
    }

    private func installBuffer(_ buffer: YabrPDFView) {
        buffer.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(buffer, belowSubview: activeView)
        NSLayoutConstraint.activate([
            buffer.topAnchor.constraint(equalTo: topAnchor),
            buffer.bottomAnchor.constraint(equalTo: bottomAnchor),
            buffer.leftAnchor.constraint(equalTo: leftAnchor),
            buffer.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    private func show(_ page: PDFPage, in buffer: YabrPDFView, viewport: (PDFPage, YabrPDFView) -> PDFPageViewportFit) {
        let active = activeView
        if buffer.document !== active.document {
            buffer.document = active.document
        }
        buffer.displayMode = .singlePage
        buffer.displayDirection = active.displayDirection
        buffer.displaysRTL = active.displaysRTL
        buffer.displayBox = active.displayBox
        buffer.interpolationQuality = active.interpolationQuality
        buffer.autoScales = false
        buffer.backgroundColor = active.backgroundColor
        buffer.invertsPagePlaceholders = active.invertsPagePlaceholders
        buffer.delegate = active.delegate
        buffer.layoutIfNeeded()
        let scale = buffer.scaleFactor
        if buffer.currentPage !== page {
            buffer.go(to: page)
            bufferShownAt[ObjectIdentifier(buffer)] = CACurrentMediaTime()
        }
        buffer.applyViewport(viewport(page, buffer), on: page)
        if abs(buffer.scaleFactor - scale) > 0.0005 {
            // Tiles of this page at the new scale may be from long ago, or another view.
            bufferShownAt[ObjectIdentifier(buffer)] = CACurrentMediaTime()
        }
    }

    /// Whether a buffer holds `page`, fully rendered.
    func hasRenderedBuffer(showing page: PDFPage) -> Bool {
        bufferViews.contains { $0.currentPage === page && showsLikeActiveView($0) && isRendered($0) }
    }

    /// Whether `buffer` has drawn every tile it shows since it was given its page.
    private func isRendered(_ buffer: YabrPDFView) -> Bool {
        guard let page = buffer.currentPage else { return false }
        return hasDrawn(buffer, page: page, after: bufferShownAt[ObjectIdentifier(buffer)] ?? 0)
    }

    /// Whether every tile `view` shows of `page` finished drawing after `time`, the
    /// `twice` ones twice. The draw log does not know which view drew: another
    /// view drawing the same page at the same scale would count.
    private func hasDrawn(_ view: YabrPDFView, page: PDFPage, after time: CFTimeInterval, twice: Set<PDFPageTile> = []) -> Bool {
        guard let drawLog, let pageNumber = page.pageRef?.pageNumber else { return false }
        let tiles = shownTiles(of: view, page: page)
        // PDFKit hands a drawn tile to its layer a moment later, so the page's
        // draws at this scale must also have gone quiet.
        guard !tiles.isEmpty,
              let lastDraw = drawLog.lastDrawEnd(ofPage: pageNumber, pixelsPerPoint: view.scaleFactor * displayScale),
              lastDraw > time,
              CACurrentMediaTime() - lastDraw > 0.06
        else { return false }
        let counts = tileDrawCounts(of: view, page: page, after: time)
        // Draws that are not PDFKit's usual tiles: settle for the quiet.
        return counts.isEmpty || tiles.allSatisfy { counts[$0, default: 0] >= (twice.contains($0) ? 2 : 1) }
    }

    /// The PDFKit tiles of `page` that `view` shows at its scale.
    func shownTiles(of view: YabrPDFView, page: PDFPage) -> Set<PDFPageTile> {
        let box = view.displayBox
        let boxSize = page.bounds(for: box).applying(CGAffineTransform(rotationAngle: CGFloat(page.rotation) * .pi / 180)).size
        let visible = view.convert(view.bounds, to: page)
            .applying(page.transform(for: box))
            .intersection(CGRect(origin: .zero, size: CGSize(width: abs(boxSize.width), height: abs(boxSize.height))))
        return PDFPageTile.tiles(covering: visible, pixelsPerPoint: view.scaleFactor * displayScale)
    }

    private func tileDrawCounts(of view: YabrPDFView, page: PDFPage, after time: CFTimeInterval) -> [PDFPageTile: Int] {
        guard let drawLog, let pageNumber = page.pageRef?.pageNumber else { return [:] }
        return drawLog.tileDrawCounts(ofPage: pageNumber, pixelsPerPoint: view.scaleFactor * displayScale, after: time)
    }

    private var displayScale: CGFloat {
        traitCollection.displayScale > 0 ? traitCollection.displayScale : UIScreen.main.scale
    }

    private func setInteractive(_ interactive: Bool, _ pageView: YabrPDFView) {
        pageView.isUserInteractionEnabled = interactive
        pageView.accessibilityElementsHidden = !interactive
    }

    /// Makes the buffer holding `page` the active view if it has finished
    /// rendering at `viewport`: no re-render and no cover. The old active view
    /// becomes a buffer; it already shows the new neighbour. Posts the page change.
    /// Returns false (the caller turns the usual way) if no buffer is ready.
    func takeOver(showing page: PDFPage, viewport: (PDFPage, YabrPDFView) -> PDFPageViewportFit) -> Bool {
        guard let index = bufferViews.firstIndex(where: { $0.currentPage === page && $0 !== coveringView && showsLikeActiveView($0) })
        else { return false }
        let buffer = bufferViews[index]
        // Re-apply in case the page's viewport changed since it was prepared (the
        // same viewport is a no-op), then require tiles at that resolution.
        buffer.applyViewport(viewport(page, buffer), on: page)
        guard isRendered(buffer) else { return false }

        endCover(notifies: false)
        let old = activeView
        highlightTapped = nil
        old.yabrPDFViewController?.menuManager.dismissHighlightMenu()
        if old.isFirstResponder {
            old.resignFirstResponder()
        }
        old.clearSelection()

        insertSubview(buffer, aboveSubview: old)
        insertSubview(old, belowSubview: buffer)
        setInteractive(false, old)
        setInteractive(true, buffer)
        bufferViews[index] = old
        // The old active view's tiles are complete; it counts as rendered.
        bufferShownAt[ObjectIdentifier(old)] = 0
        bufferShownAt[ObjectIdentifier(buffer)] = nil
        activeView = buffer
        relayNotifications(of: buffer)

        if abs(buffer.scaleFactor - old.scaleFactor) > 0.0001 {
            NotificationCenter.default.post(name: .readerSurfaceScaleChanged, object: self)
        }
        takenOverPage = page
        NotificationCenter.default.post(name: .readerSurfacePageChanged, object: self)
        return true
    }

    /// Whether `buffer` shows the active view's document laid out the same way.
    /// Options changes reach the buffers only when they are next refreshed.
    private func showsLikeActiveView(_ buffer: YabrPDFView) -> Bool {
        let active = activeView
        return buffer.document != nil
            && buffer.document === active.document
            && active.displayMode == .singlePage
            && buffer.displayDirection == active.displayDirection
            && buffer.displaysRTL == active.displaysRTL
            && buffer.displayBox == active.displayBox
            && buffer.invertsPagePlaceholders == active.invertsPagePlaceholders
    }

    /// Whether the current page change came from `takeOver(showing:)`; clears it.
    func consumeTakeover(of page: PDFPage) -> Bool {
        defer { takenOverPage = nil }
        return takenOverPage === page
    }

    /// Same scale and the same page point at the view's top left, within
    /// `pixels` device pixels.
    private static func showsSameViewport(_ a: YabrPDFView, _ b: YabrPDFView, page: PDFPage, pixels: CGFloat) -> Bool {
        guard abs(a.scaleFactor - b.scaleFactor) < 0.0005 else { return false }
        let pointA = a.convert(a.bounds.origin, to: page)
        let pointB = b.convert(b.bounds.origin, to: page)
        let pixel = 1 / (a.traitCollection.displayScale > 0 ? a.traitCollection.displayScale : UIScreen.main.scale)
        let tolerance = pixels * pixel / max(a.scaleFactor, 0.01)
        return abs(pointA.x - pointB.x) <= tolerance && abs(pointA.y - pointB.y) <= tolerance
    }

    /// Ends the cover once the active view has drawn the tiles it shows, or after
    /// a timeout (tiles still cached from before are not redrawn).
    private func checkCoverHandover() {
        guard let page = coveringView?.currentPage else {
            endCover()
            return
        }
        if CACurrentMediaTime() - coverStart > 1.0 || hasDrawn(activeView, page: page, after: coverStart, twice: coverOwedTiles) {
            endCover()
        }
    }

    private func endCover(notifies: Bool = true) {
        coverTimer?.invalidate()
        coverTimer = nil
        guard let buffer = coveringView else { return }
        insertSubview(buffer, belowSubview: activeView)
        coveringView = nil
        coverOwedTiles = []
        if notifies {
            onCoverEnded?()
        }
    }
}
