//
//  YabrPDFView.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/4/18.
//

import Foundation

import PDFKit
import FolioReaderKit

class YabrPDFView: PDFView {
    let doubleTapLeftLabel = UILabel()
    let doubleTapRightLabel = UILabel()
    let singleTapLeftLabel = UILabel()
    let singleTapRightLabel = UILabel()
    let labelTextColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.9)
    let labelDoubleBackgroundColor = UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.9).cgColor
    let labelSingleBackgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.9).cgColor
    let labelHiddenColor = UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.02)
    let labelDisabledColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

    var doubleTapGestureRecognizer: UITapGestureRecognizer?
    var singleTapGestureRecognizer: UITapGestureRecognizer?
    
    var pageNextButton: UIButton?
    var pagePrevButton: UIButton?
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        print("\(#function) \(action.description)")
        if action.description == "selectAll:" {
            return false
        }
        
        return super.canPerformAction(action, withSender: sender)
    }
    
    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == singleTapGestureRecognizer || gestureRecognizer == doubleTapGestureRecognizer {
            if otherGestureRecognizer is UILongPressGestureRecognizer { return false }
            if gestureRecognizer == doubleTapGestureRecognizer && otherGestureRecognizer == singleTapGestureRecognizer { return false }
            if gestureRecognizer == singleTapGestureRecognizer && otherGestureRecognizer == doubleTapGestureRecognizer { return false }
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
    }
    
    func pageTapPreview(navBarHeight: CGFloat, hMarginAutoScaler: Double) {
        let pdfViewHeight = self.frame.height
        var doubleTapWidth = self.frame.width * hMarginAutoScaler / 100.0
        if doubleTapWidth < 50.0 {
            doubleTapWidth = 50.0
        }
        if doubleTapWidth > 100.0 {
            doubleTapWidth = 100.0
        }
        var singleTapWidth = self.frame.width * hMarginAutoScaler / 50.0
        if singleTapWidth < doubleTapWidth * 2 {
            singleTapWidth = doubleTapWidth * 2
        }
        if singleTapWidth > doubleTapWidth * 2 {
            singleTapWidth = doubleTapWidth * 2
        }
        let singleTapHeight = self.frame.height * 0.15
        let textFont = UIFont.systemFont(ofSize: UITraitCollection.current.horizontalSizeClass == .regular ? 16 : 12, weight: .regular)
        doubleTapLeftLabel.frame = CGRect(
            origin: CGPoint(x: 0, y: pdfViewHeight * 0.1 - navBarHeight),
            size: CGSize(width: doubleTapWidth, height: pdfViewHeight * 0.9 - singleTapHeight)
        )
        
        doubleTapRightLabel.frame = CGRect(
            origin: CGPoint(x: self.frame.width - doubleTapWidth, y: pdfViewHeight * 0.1 - navBarHeight),
            size: CGSize(width: doubleTapWidth, height: pdfViewHeight * 0.9 - singleTapHeight)
        )
        
        singleTapLeftLabel.frame = CGRect(
            origin: CGPoint(x: 0, y: pdfViewHeight - navBarHeight - singleTapHeight),
            size: CGSize(width: singleTapWidth, height: singleTapHeight)
        )
        
        singleTapRightLabel.frame = CGRect(
            origin: CGPoint(x: self.frame.width - singleTapWidth, y: pdfViewHeight - navBarHeight - singleTapHeight),
            size: CGSize(width: singleTapWidth, height: singleTapHeight)
        )
        
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
    
}
