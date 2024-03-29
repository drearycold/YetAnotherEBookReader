//
//  YabrPDFView.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/4/18.
//

import Foundation

import PDFKit

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

    var yabrPDFViewController: YabrPDFViewController? {
        delegate?.pdfViewParentViewController?() as? YabrPDFViewController
    }
    var yabrPDFMetaSource: YabrPDFMetaSource? {
        yabrPDFViewController?.yabrPDFMetaSource
    }
    
    var pageNextButton: UIButton?
    var pagePrevButton: UIButton?
    
    var highlights = [UUID: [HighlightValue]]()
    var highlightTapped: UUID?
    var highlightIsEditing = false
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let could = super.canPerformAction(action, withSender: sender)
        print("\(#function) \(could) \(action.description)")
        
        self.interactions.forEach { interaction in
            print("\(#function) \(interaction)")
        }
        
        if action.description == "selectAll:" {
            return false
        }
        if self.highlightTapped != nil {
            if action.description == "copy:" && highlightIsEditing {
                return false
            }
            if action.description == "deleteHighlightAction"  {
                return true
            }
            if action.description == "_translate:" {
                return false
            }
            if action.description == "_lookup:" {
                return false
            }
            if action.description == "_define:" {
                return false
            }
        } else {
//            if action == #selector(highlightAction(_:)) {
//                return true
//            }
        }
        
        return could
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
        self.highlightTapped = nil
        self.highlightIsEditing = false
        
        print("\(#function) highlighted=\(highlightedSelections?.count)")
        
        if sender.state == .ended {
            let tapLocation = sender.location(in: self)
            
            let aoi = self.areaOfInterest(for: tapLocation)
            print("\(#function) aoi=\(aoi)")
            
            guard aoi.contains(.annotationArea) else {
                self.currentSelection = nil
                return
            }
            
            let tappedHighlightValues = highlights.reduce(into: [HighlightValue]()) { partialResult, entry in
                entry.value.forEach { highlightValue in
                    if highlightValue.annotations.filter ({
                        guard let page = $0.page else { return false }
                        let pageLocation = self.convert(tapLocation, to: page)
                        return $0.bounds.contains(pageLocation)
                    }).isEmpty == false {
                        partialResult.append(highlightValue)
                    }
                }
            }
            
            print("\(#function) tappedHighlightValues=\(tappedHighlightValues)")
            
            if let tappedHighlightValue = tappedHighlightValues.first,
               let tappedAnnotation = tappedHighlightValue.annotations.first,
               let tappedUUIDString = tappedAnnotation.value(forAnnotationKey: .highlightId) as? String,
               let tappedUUID = UUID(uuidString: tappedUUIDString),
               let tappedHighlightValue = highlights[tappedUUID],
               let tappedAnnotationFirst = tappedHighlightValue.first?.annotations.first,
               let page = tappedAnnotationFirst.page {
                self.highlightTapped = tappedUUID
                UIMenuController.shared.menuItems = buildHighlightMenuItems()
                UIMenuController.shared.showMenu(from: self, rect: self.convert(tappedAnnotationFirst.bounds, from: page))
            } else if UIMenuController.shared.isMenuVisible {
                UIMenuController.shared.hideMenu()
            } else if self.currentSelection != nil {
                self.clearSelection()
            }
            
            self.visiblePages.forEach { visiblePage in
                guard let annotation = visiblePage.annotation(at: self.convert(tapLocation, to: visiblePage)),
                      let typeString = annotation.type,
                      let annotationAction = annotation.action
                else {
                    return
                }
                
                print("\(#function) \(typeString) \(annotation.bounds)")
                
                switch typeString {
                case "Link":
                    if let currentPage = currentPage {
                        self.yabrPDFViewController?.updateHistoryMenu(
                            curPage: currentPage,
                            location: self.convert(.zero, to: currentPage)//annotation.bounds
                        )
                    }
                    self.perform(annotationAction)
                default:
                    break
                }
            }
        }
    }
    
    @objc override func copy(_ sender: Any?) {
        if let highlightTapped = highlightTapped,
           let highlightValueArray = highlights[highlightTapped] {
            UIPasteboard.general.string = highlightValueArray.compactMap { $0.selection.string }.joined(separator: " ")
            self.highlightTapped = nil
        } else {
            super.copy(sender)
        }
    }
    
    @objc func selectHighlightAction() {
        guard let highlightTapped = highlightTapped,
              let highlightValueArray = highlights[highlightTapped] else {
            return
        }

        let tappedSelection = PDFSelection(document: self.document!)
        tappedSelection.add(highlightValueArray.map { $0.selection})
        self.setCurrentSelection(tappedSelection, animate: false)
        
        if let page = tappedSelection.pages.first {
            UIMenuController.shared.hideMenu()
            UIMenuController.shared.showMenu(from: self, rect: self.convert(tappedSelection.bounds(for: page), from: page))
        }
    }
    
    @objc func modifyHighlightAction(_ sender: Any?) {
        guard let highlightTapped = highlightTapped,
              let highlightValueArray = highlights[highlightTapped] else {
            return
        }

        if let selection = highlightValueArray.first?.selection,
            let page = selection.pages.first {
            UIMenuController.shared.hideMenu()
            UIMenuController.shared.menuItems = buildHighlightModifyMenuItems()
            highlightIsEditing = true
            UIMenuController.shared.showMenu(from: self, rect: self.convert(selection.bounds(for: page), from: page))
        }
    }
    
    @objc func deleteHighlightAction(_ sender: Any?) {
        guard let highlightTapped = highlightTapped
        else {
            return
        }

        if let pdfHighlight = self.yabrPDFMetaSource?.yabrPDFHighlights(self, getById: highlightTapped) {
            self.yabrPDFMetaSource?.yabrPDFHighlights(self, remove: pdfHighlight)
        }
    }
}

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
    }
    
    func modifyHighlightStyle(highlightId: UUID, type: BookHighlightStyle) {
        guard var highlight = self.yabrPDFMetaSource?.yabrPDFHighlights(self, getById: highlightId)
        else { return }
        
        self.removeHighlight(highlight: highlight)
        
        highlight.type = type.rawValue
        highlight.date = .init()
        
        self.yabrPDFMetaSource?.yabrPDFHighlights(self, update: highlight)
        self.injectHighlight(highlight: highlight)
    }
    
    func removeHighlight(highlight: PDFHighlight) {
        guard let highlightValue = highlights.removeValue(forKey: highlight.uuid) else { return }
        
        highlightValue.flatMap { $0.annotations }.forEach { annotation in
            annotation.page?.removeAnnotation(annotation)
        }
    }
    
    func buildHighlightMenuItems() -> [UIMenuItem] {
        var menuItems = [UIMenuItem]()
        
        menuItems.append(UIMenuItem(title: "Select", action: #selector(selectHighlightAction)))
//        menuItems.append(UIMenuItem(title: "Modify", action: #selector(modifyHighlightAction)))
        menuItems.append(UIMenuItem(title: "Delete", action: #selector(deleteHighlightAction)))
        
        return menuItems
    }
    
    func buildHighlightModifyMenuItems() -> [UIMenuItem] {
        guard let highlightTapped = self.highlightTapped else { return [] }
        
        var menuItems = BookHighlightStyle.allCases.map { style in
            UIMenuItem(
                title: style.description,
                image: nil,
                action: { _ in
                    self.modifyHighlightStyle(highlightId: highlightTapped, type: style)
                }
            )
        }
        
        menuItems.append(UIMenuItem(title: "Delete", image: nil, action: { _ in
            if let pdfHighlight = self.yabrPDFMetaSource?.yabrPDFHighlights(self, getById: highlightTapped) {
                self.yabrPDFMetaSource?.yabrPDFHighlights(self, remove: pdfHighlight)
            }
        }))
        
        return menuItems
    }
}

extension PDFAnnotationKey {
    
    public static let highlightId: PDFAnnotationKey = .init(rawValue: "/HID")
}

struct HighlightValue {
    let selection: PDFSelection
    var annotations: [PDFAnnotation] = []
}
