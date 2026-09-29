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
    let doubleTapLeftLabel = UILabel()
    let doubleTapRightLabel = UILabel()
    let singleTapLeftLabel = UILabel()
    let singleTapRightLabel = UILabel()
    let labelTextColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.9)
    let labelDoubleBackgroundColor = UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.9).cgColor
    let labelSingleBackgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.9).cgColor
    let labelHiddenColor = UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.01)
    let labelDisabledColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

    var doubleTapGestureRecognizer: UITapGestureRecognizer?
    var singleTapGestureRecognizer: UITapGestureRecognizer?
    var highlightTapGestureRecognizer: UITapGestureRecognizer?
    /// Only begins on a highlight; PDFKit's taps wait for it to fail, so tapping a
    /// highlight shows the app's persisted menu instead of PDFKit's markup menu
    /// (whose Remove / colour / Add Note would bypass the app's storage).
    var highlightMenuTapGestureRecognizer: UITapGestureRecognizer?

    var yabrPDFViewController: YabrPDFViewController? {
        delegate?.pdfViewParentViewController?() as? YabrPDFViewController
    }
    var yabrPDFMetaSource: YabrPDFMetaSource? {
        yabrPDFViewController?.yabrPDFMetaSource
    }
    
    var pageNextButton: UIButton?
    var pagePrevButton: UIButton?
    
    var highlights = [UUID: [HighlightValue]]()
    /// Highlight whose edit menu is showing.
    var highlightTapped: UUID?

    /// Content inset added on top of PDFKit's own so a viewport anchor outside the
    /// normally scrollable range (e.g. top-aligning a page shorter than the view)
    /// can be reached.
    private var viewportExtraInset = UIEdgeInsets.zero
    /// PDFKit's own page break margins, before `padPageBreakMargins(for:)`.
    private var defaultPageBreakMargins: UIEdgeInsets?

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

    override func layoutSubviews() {
        super.layoutSubviews()
        arrangeOverlayViews()
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

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == singleTapGestureRecognizer || gestureRecognizer == doubleTapGestureRecognizer {
            if otherGestureRecognizer is UILongPressGestureRecognizer { return false }
            if otherGestureRecognizer is UIPanGestureRecognizer { return false }

            if gestureRecognizer == doubleTapGestureRecognizer && otherGestureRecognizer == singleTapGestureRecognizer { return false }
            if gestureRecognizer == singleTapGestureRecognizer && otherGestureRecognizer == doubleTapGestureRecognizer { return false }
            return true
        }
        
        if gestureRecognizer == highlightTapGestureRecognizer {
            return true
        }
        
        return super.gestureRecognizer(gestureRecognizer, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer)
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === highlightMenuTapGestureRecognizer {
            return highlight(at: gestureRecognizer.location(in: self)) != nil
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === highlightMenuTapGestureRecognizer {
            return otherGestureRecognizer is UITapGestureRecognizer
                && otherGestureRecognizer !== highlightTapGestureRecognizer
                && otherGestureRecognizer.view?.isDescendant(of: self) == true
        }
        // PDFView declares but does not implement this optional delegate method, so
        // calling super crashes; `false` is UIKit's default when it is absent.
        return false
    }

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: self)
        if singleTapGestureRecognizer == gestureRecognizer {
            return touch.tapCount == 1 && (singleTapLeftLabel.frame.contains(location) || singleTapRightLabel.frame.contains(location))
        }
        if doubleTapGestureRecognizer == gestureRecognizer {
            return doubleTapLeftLabel.frame.contains(location) ||
            doubleTapRightLabel.frame.contains(location) ||
            singleTapLeftLabel.frame.contains(location) ||
            singleTapRightLabel.frame.contains(location)
        }
        if gestureRecognizer is UITapGestureRecognizer {
            return doubleTapLeftLabel.frame.contains(location) == false
            && doubleTapRightLabel.frame.contains(location) == false
            && singleTapLeftLabel.frame.contains(location) == false
            && singleTapRightLabel.frame.contains(location) == false
        }
        return super.gestureRecognizer(gestureRecognizer, shouldReceive: touch)
    }
    
    func prepareActions(pageNextButton: UIButton, pagePrevButton: UIButton) {
        self.pageNextButton = pageNextButton
        self.pagePrevButton = pagePrevButton
        
        doubleTapLeftLabel.text = "Double Tap\nThis Region\nto Turn Page"
        doubleTapLeftLabel.textAlignment = .center
        doubleTapLeftLabel.numberOfLines = 0
        doubleTapLeftLabel.layer.cornerRadius = 8
        doubleTapLeftLabel.layer.masksToBounds = true
        
        doubleTapRightLabel.text = "Double Tap\nThis Region\nto Turn Page"
        doubleTapRightLabel.textAlignment = .center
        doubleTapRightLabel.numberOfLines = 0
        doubleTapRightLabel.layer.cornerRadius = 8
        doubleTapRightLabel.layer.masksToBounds = true
        
        singleTapLeftLabel.text = "Tap to Turn"
        singleTapLeftLabel.textAlignment = .center
        singleTapLeftLabel.numberOfLines = 0
        singleTapLeftLabel.layer.cornerRadius = 8
        singleTapLeftLabel.layer.masksToBounds = true
        
        singleTapRightLabel.text = "Tap to Turn"
        singleTapRightLabel.textAlignment = .center
        singleTapRightLabel.numberOfLines = 0
        singleTapRightLabel.layer.cornerRadius = 8
        singleTapRightLabel.layer.masksToBounds = true
        
        self.addSubview(doubleTapLeftLabel)
        self.addSubview(doubleTapRightLabel)
        self.addSubview(singleTapLeftLabel)
        self.addSubview(singleTapRightLabel)
        
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
    }
    
    func pageTapPreview(hMarginAutoScaler: Double) {
        pageTapResize(hMarginAutoScaler: hMarginAutoScaler)
        
        let textFont = UIFont.systemFont(ofSize: UITraitCollection.current.horizontalSizeClass == .regular ? 16 : 12, weight: .regular)
        UIView.animate(withDuration: TimeInterval(0.5)) { [self] in
//            doubleTapLeftLabel.becomeFirstResponder()
            doubleTapLeftLabel.font = textFont
//            doubleTapLeftLabel.isUserInteractionEnabled = true
            doubleTapLeftLabel.textColor = labelTextColor
            doubleTapLeftLabel.layer.backgroundColor = labelDoubleBackgroundColor

//            doubleTapRightLabel.becomeFirstResponder()
            doubleTapRightLabel.font = textFont
//            doubleTapRightLabel.isUserInteractionEnabled = true
            doubleTapRightLabel.textColor = labelTextColor
            doubleTapRightLabel.layer.backgroundColor = labelDoubleBackgroundColor

//            singleTapLeftLabel.becomeFirstResponder()
            singleTapLeftLabel.font = textFont
//            singleTapLeftLabel.isUserInteractionEnabled = true
            singleTapLeftLabel.textColor = labelTextColor
            singleTapLeftLabel.layer.backgroundColor = labelSingleBackgroundColor

//            singleTapRightLabel.becomeFirstResponder()
            singleTapRightLabel.font = textFont
//            singleTapRightLabel.isUserInteractionEnabled = true
            singleTapRightLabel.textColor = labelTextColor
            singleTapRightLabel.layer.backgroundColor = labelSingleBackgroundColor
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .seconds(3))) { [self] in
            UIView.animate(withDuration: TimeInterval(0.5)) { [self] in
                doubleTapLeftLabel.textColor = labelHiddenColor
                doubleTapLeftLabel.layer.backgroundColor = labelHiddenColor.cgColor
                doubleTapRightLabel.textColor = labelHiddenColor
                doubleTapRightLabel.layer.backgroundColor = labelHiddenColor.cgColor
                singleTapLeftLabel.textColor = labelHiddenColor
                singleTapLeftLabel.layer.backgroundColor = labelHiddenColor.cgColor
                singleTapRightLabel.textColor = labelHiddenColor
                singleTapRightLabel.layer.backgroundColor = labelHiddenColor.cgColor
            }
        }
    }
    
    func pageTapResize(hMarginAutoScaler: Double) {
        let pdfViewHeight = self.frame.height
        var doubleTapWidth = self.frame.width * (hMarginAutoScaler - 5) / 100.0
        if doubleTapWidth < 50.0 {
            doubleTapWidth = 50.0
        }
        if doubleTapWidth > 100.0 {
            doubleTapWidth = 100.0
        }
        var singleTapWidth = self.frame.width * (hMarginAutoScaler - 5) / 50.0
        if singleTapWidth < doubleTapWidth * 2 {
            singleTapWidth = doubleTapWidth * 2
        }
        if singleTapWidth > doubleTapWidth * 2 {
            singleTapWidth = doubleTapWidth * 2
        }
        let singleTapHeight = self.frame.height * 0.15
        doubleTapLeftLabel.frame = CGRect(
            origin: CGPoint(x: 0, y: pdfViewHeight * 0.1),
            size: CGSize(width: doubleTapWidth, height: pdfViewHeight * 0.9 - singleTapHeight)
        )
        
        doubleTapRightLabel.frame = CGRect(
            origin: CGPoint(x: self.frame.width - doubleTapWidth, y: pdfViewHeight * 0.1),
            size: CGSize(width: doubleTapWidth, height: pdfViewHeight * 0.9 - singleTapHeight)
        )
        
        singleTapLeftLabel.frame = CGRect(
            origin: CGPoint(x: 0, y: pdfViewHeight - singleTapHeight),
            size: CGSize(width: singleTapWidth, height: singleTapHeight)
        )
        
        singleTapRightLabel.frame = CGRect(
            origin: CGPoint(x: self.frame.width - singleTapWidth, y: pdfViewHeight - singleTapHeight),
            size: CGSize(width: singleTapWidth, height: singleTapHeight)
        )
        
    }
    
    func pageTapDisable() {
        doubleTapLeftLabel.textColor = labelDisabledColor
        doubleTapLeftLabel.layer.backgroundColor = labelDisabledColor.cgColor
        doubleTapRightLabel.textColor = labelDisabledColor
        doubleTapRightLabel.layer.backgroundColor = labelDisabledColor.cgColor
        singleTapLeftLabel.textColor = labelDisabledColor
        singleTapLeftLabel.layer.backgroundColor = labelDisabledColor.cgColor
        singleTapRightLabel.textColor = labelDisabledColor
        singleTapRightLabel.layer.backgroundColor = labelDisabledColor.cgColor
    }
    
    @objc private func doubleTappedGesture(sender: UITapGestureRecognizer) {
        guard doubleTapLeftLabel.layer.backgroundColor != labelDisabledColor.cgColor else { return }

        print("\(#function) \(sender.state.rawValue) \(sender.view)")
        
        if sender.state == .ended {
            print("tappedGesture \(sender.location(in: self)) in \(self.frame)")
            
            if sender.view == doubleTapLeftLabel || doubleTapLeftLabel.frame.contains(sender.location(in: self)) {
                pagePrevButton?.sendActions(for: .primaryActionTriggered)
                return
            }
            if sender.view == doubleTapRightLabel || doubleTapRightLabel.frame.contains(sender.location(in: self)) {
                pageNextButton?.sendActions(for: .primaryActionTriggered)
                return
            }
            if sender.view == singleTapLeftLabel || singleTapLeftLabel.frame.contains(sender.location(in: self))  {
                pagePrevButton?.sendActions(for: .primaryActionTriggered)
                return
            }
            if sender.view == singleTapRightLabel || singleTapRightLabel.frame.contains(sender.location(in: self))  {
                pageNextButton?.sendActions(for: .primaryActionTriggered)
                return
            }
        }
    }
    
    @objc private func singleTappedGesture(sender: UITapGestureRecognizer) {
        guard doubleTapLeftLabel.layer.backgroundColor != labelDisabledColor.cgColor else { return }

        print("\(#function) \(sender.state.rawValue) \(sender.view)")
        
        if sender.state == .ended {
            print("tappedGesture \(sender.location(in: self)) in \(self.frame)")
            
            if sender.view == singleTapLeftLabel || singleTapLeftLabel.frame.contains(sender.location(in: self))  {
                pagePrevButton?.sendActions(for: .primaryActionTriggered)
                return
            }
            if sender.view == singleTapRightLabel || singleTapRightLabel.frame.contains(sender.location(in: self))  {
                pageNextButton?.sendActions(for: .primaryActionTriggered)
                return
            }
        }
    }
    
    @objc private func highlightTappedGesture(sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        let location = sender.location(in: self)
        // Taps on a highlight belong to `highlightMenuTapGestureRecognizer`.
        guard highlight(at: location) == nil else { return }
        handleTap(at: location)
    }

    @objc private func highlightMenuTappedGesture(sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        handleHighlightTap(at: sender.location(in: self))
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
    func injectHighlight(highlight: PDFHighlight) {
        highlight.pos.forEach { highlightPageLocation in
            guard let highlightPage = self.document?.page(at: highlightPageLocation.page - 1),
                  let highlightSubtype = BookHighlightStyle(rawValue: highlight.type)?.pdfAnnotationSubtype
            else { return }
            
            if highlights[highlight.uuid] == nil {
                highlights[highlight.uuid] = []
            }
            
            highlightPageLocation.ranges.forEach { highlightPageRange in
                guard let highlightSelection = self.document?.selection(from: highlightPage, atCharacterIndex: highlightPageRange.lowerBound, to: highlightPage, atCharacterIndex: highlightPageRange.upperBound)
                else { return }
                
                var highlightValue = HighlightValue(selection: highlightSelection)
                
                highlightSelection.selectionsByLine().forEach { hightlightSelectionByLine in
                    let annotation = PDFAnnotation(
                        bounds: hightlightSelectionByLine.bounds(for: highlightPage),
                        forType: highlightSubtype.0,
                        withProperties: [PDFAnnotationKey.highlightId: highlight.uuid.uuidString]
                    )
                    annotation.color = highlightSubtype.1
                    
                    highlightPage.addAnnotation(annotation)
                    highlightValue.annotations.append(annotation)
                }
                highlights[highlight.uuid]?.append(highlightValue)
            }
            
        }
        addNote(of: highlight, highlightColor: BookHighlightStyle(rawValue: highlight.type)?.pdfAnnotationSubtype.1)
    }

    /// Puts the note on the highlight's first line annotation, where an exported PDF
    /// shows it as the highlight's comment, and marks the last line.
    private func addNote(of highlight: PDFHighlight, highlightColor: UIColor?) {
        guard let note = highlight.note, !note.isEmpty,
              var values = highlights[highlight.uuid],
              let lastIndex = values.indices.last,
              let lastLine = values[lastIndex].annotations.last,
              let page = lastLine.page,
              let highlightColor
        else { return }

        values.first?.annotations.first?.contents = note

        let marker = PDFNoteMarker.make(lineBounds: lastLine.bounds, color: highlightColor, highlightId: highlight.uuid)
        page.addAnnotation(marker)
        values[lastIndex].annotations.append(marker)
        highlights[highlight.uuid] = values
    }

    /// Takes the note markers off their pages while `body` runs, so an annotated
    /// export holds only standard highlight annotations.
    func withoutNoteMarkers<T>(_ body: () -> T) -> T {
        let markers = highlights.values.flatMap { $0.flatMap(\.annotations) }.compactMap { annotation -> (PDFAnnotation, PDFPage)? in
            guard annotation.isNoteMarker, let page = annotation.page else { return nil }
            return (annotation, page)
        }
        markers.forEach { $0.1.removeAnnotation($0.0) }
        defer { markers.forEach { $0.1.addAnnotation($0.0) } }
        return body()
    }
    
    func modifyHighlightStyle(highlightId: UUID, type: BookHighlightStyle) {
        self.yabrPDFViewController?.annotationManager.modifyHighlightStyle(uuid: highlightId, type: type)
    }
    
    func removeHighlight(highlight: PDFHighlight) {
        guard let highlightValue = highlights.removeValue(forKey: highlight.uuid) else { return }
        
        highlightValue.flatMap { $0.annotations }.forEach { annotation in
            annotation.page?.removeAnnotation(annotation)
        }
    }
    
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFView {
    // MARK: Theme and jump mask

    func applyTheme(_ palette: PDFThemePalette) {
        backgroundColor = UIColor(cgColor: palette.canvas)
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
        showJumpMask(image: viewportSnapshot(of: page))
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
            page.draw(with: displayBox, to: context)
        }
    }

    private func arrangeOverlayViews() {
        for overlay in [jumpMaskView, themeOverlayView] as [UIView] {
            if overlay.superview !== self {
                addSubview(overlay)
            }
            overlay.frame = bounds
            bringSubviewToFront(overlay)
        }
        for label in [doubleTapLeftLabel, doubleTapRightLabel, singleTapLeftLabel, singleTapRightLabel] where label.superview === self {
            bringSubviewToFront(label)
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

/// Marks a highlight that has a note: a small square in the top-right corner of
/// its last line. It is itself a highlight annotation in the highlight's colour,
/// so PDFKit renders it inside the page like the highlight: stacked, it reads as
/// a darker patch of the same hue, text under it stays readable, and margin crop
/// never cuts it off. In dark mode highlights show only as tinted text, so the
/// marker is not visible there. (A `draw(with:in:)` override is composited in a
/// separate layer instead: opaque, and not inverted in dark mode.)
@available(iOS 16.0, macCatalyst 16.0, *)
enum PDFNoteMarker {
    static let maxSide: CGFloat = 8

    static func make(lineBounds: CGRect, color: UIColor, highlightId: UUID) -> PDFAnnotation {
        let side = min(lineBounds.height / 2, lineBounds.width, maxSide)
        let marker = PDFAnnotation(
            bounds: CGRect(x: lineBounds.maxX - side, y: lineBounds.maxY - side, width: side, height: side),
            forType: .highlight,
            withProperties: [
                PDFAnnotationKey.highlightId: highlightId.uuidString,
                PDFAnnotationKey.noteMarker: "1",
            ]
        )
        marker.color = color
        marker.isReadOnly = true
        return marker
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
