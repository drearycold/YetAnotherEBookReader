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

/// Hosts the reader's page views and owns what they share. It holds one page view
/// today; buffered neighbour pages are planned (issues #54 / #55), after which the
/// active view can change.
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

    /// A plain page-coloured cover while the reader appears, before the first page
    /// is positioned. Replaced by the first jump mask, or faded by
    /// `finishLoadingCover()`.
    func showLoadingCover() {
        jumpMaskView.image = nil
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

    private func showJumpMask(image: UIImage) {
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
                    self.jumpMaskView.image = nil
                }
            }
        }
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
        let location = sender.location(in: activeView)
        // Taps on a highlight belong to `highlightMenuTapGestureRecognizer`.
        guard activeView.highlight(at: location) == nil else { return }
        activeView.handleTap(at: location)
    }

    @objc private func highlightMenuTappedGesture(sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        activeView.handleHighlightTap(at: sender.location(in: activeView))
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
            return activeView.highlight(at: gestureRecognizer.location(in: activeView)) != nil
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
