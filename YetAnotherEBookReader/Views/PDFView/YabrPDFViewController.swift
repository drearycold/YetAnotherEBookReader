//
//  PDFViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import Foundation
import RealmSwift
import UIKit
import PDFKit
import OSLog
import SwiftUI
import FolioReaderKit

@available(macCatalyst 14.0, *)
class YabrPDFViewController: UIViewController, PDFViewDelegate {
    var modelData: ModelData?
    var pdfView = PDFView()
    var blankView = UIImageView()
    var mDictView = MDictViewContainer()
    
    let logger = Logger()
    
    var historyMenu = UIMenu(title: "History", children: [])
    
    var stackView = UIStackView()
    
    var pageSlider = UISlider()
    var pageIndicator = UIButton()
    var pageNextButton = UIButton()
    var pagePrevButton = UIButton()
    
    let titleInfoButton = UIButton()
    var tocList = [(String, Int)]()
    
    let thumbImageView = UIImageView()
    let thumbController = UIViewController()
    
    var pdfOptions = PDFOptions() {
        didSet {
            var isDark = false
            switch (pdfOptions.themeMode) {
            case .none:
                PDFPageWithBackground.fillColor = nil
            case .serpia:   //#FBF0D9
                PDFPageWithBackground.fillColor = CGColor(red: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
            case .forest:   //#BAD5C1
                PDFPageWithBackground.fillColor = CGColor(
                    red: CGFloat(Int("BA", radix: 16) ?? 255) / 255.0,
                    green: CGFloat(Int("D5", radix: 16) ?? 255) / 255.0,
                    blue: CGFloat(Int("C1", radix: 16) ?? 255) / 255.0,
                    alpha: 1.0)
            case .dark:
                PDFPageWithBackground.fillColor = .init(gray: 0.0, alpha: 1.0)
                isDark = true
            }
            let backgroundColor = UIColor(cgColor: PDFPageWithBackground.fillColor ?? CGColor.init(gray: 1.0, alpha: 1.0))
            self.navigationController?.navigationBar.barTintColor = backgroundColor
            self.navigationController?.navigationBar.backgroundColor = backgroundColor
            self.navigationController?.toolbar.barTintColor = backgroundColor
            self.navigationController?.toolbar.backgroundColor = backgroundColor

            self.tabBarController?.tabBar.barTintColor = backgroundColor
            self.tabBarController?.tabBar.backgroundColor = backgroundColor
            
            let tintColor: UIColor = isDark ? .lightText : .darkText
            pageIndicator.setTitleColor(tintColor, for: .normal)
            titleInfoButton.setTitleColor(tintColor, for: .normal)
            
            self.pdfView.backgroundColor = backgroundColor
            //self.pdfView.pageShadowsEnabled
//            pageSlider.backgroundColor = backgroundColor
//            pageIndicator.backgroundColor = backgroundColor
//            self.view.backgroundColor = backgroundColor
        }
    }
        
    var bookTitle: String!
    
    var pageViewPositionHistory = [Int: PageViewPosition]() //key is 1-based (pdfView.currentPage?.pageRef?.pageNumber)
    
    var realm: Realm?
    
    func open(pdfURL: URL, position: BookDeviceReadingPosition) -> Int {
        self.bookTitle = modelData?.readingBook?.title
        
        logger.info("pdfURL: \(pdfURL.absoluteString)")
        logger.info("Exist: \(FileManager.default.fileExists(atPath: pdfURL.path))")
        
        guard let pdfDoc = PDFDocument(url: pdfURL) else { return -1 }
        
        pdfDoc.delegate = self
        logger.info("pdfDoc: \(pdfDoc.majorVersion) \(pdfDoc.minorVersion)")
        pdfView.document = pdfDoc

        let intialPageNum = position.lastPosition[0] > 0 ? position.lastPosition[0] : 1
        
        pageViewPositionHistory[intialPageNum] = PageViewPosition(
            scaler: pdfOptions.lastScale,
            point: CGPoint(x: position.lastPosition[1], y: position.lastPosition[2])
        )
        
        if let config = getBookPreferenceConfig(bookFileURL: pdfURL) {
            realm = try? Realm(configuration: config)
            if let pdfOptionsRealm = realm?.objects(PDFOptionsRealm.self).first {
                var pdfOptions = PDFOptions()
                pdfOptions.themeMode = PDFThemeMode.init(rawValue: pdfOptionsRealm.themeMode) ?? .serpia
                pdfOptions.selectedAutoScaler = PDFAutoScaler.init(rawValue: pdfOptionsRealm.selectedAutoScaler) ?? .Width
                pdfOptions.readingDirection = PDFReadDirection.init(rawValue: pdfOptionsRealm.readingDirection) ?? .LtR_TtB
                pdfOptions.hMarginAutoScaler = CGFloat(pdfOptionsRealm.hMarginAutoScaler)
                pdfOptions.vMarginAutoScaler = CGFloat(pdfOptionsRealm.vMarginAutoScaler)
                pdfOptions.hMarginDetectStrength = CGFloat(pdfOptionsRealm.hMarginDetectStrength)
                pdfOptions.vMarginDetectStrength = CGFloat(pdfOptionsRealm.vMarginDetectStrength)
                pdfOptions.lastScale = CGFloat(pdfOptionsRealm.lastScale)
                pdfOptions.rememberInPagePosition = pdfOptionsRealm.rememberInPagePosition
                self.pdfOptions = pdfOptions
            }
        }
        
        
        return 0
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        pdfView.displayMode = PDFDisplayMode.singlePage
        pdfView.displayDirection = PDFDisplayDirection.horizontal
        pdfView.interpolationQuality = PDFInterpolationQuality.high
        
        // pdfView.usePageViewController(true, withViewOptions: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageChange(notification:)), name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScaleChange(_:)), name: .PDFViewScaleChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDisplayBoxChange(_:)), name: .PDFViewDisplayBoxChanged, object: pdfView)
        
        pdfView.autoScales = false

        pageIndicator.setTitle("0 / 0", for: .normal)
        pageIndicator.addAction(UIAction(handler: { (action) in
            self.present(self.thumbController, animated: true, completion: nil)
        }), for: .primaryActionTriggered)
        
        pageSlider.minimumValue = 1
        pageSlider.maximumValue = Float(pdfView.document!.pageCount)
        pageSlider.isContinuous = true
        pageSlider.addAction(UIAction(handler: { (action) in
            if let destPage = self.pdfView.document?.page(at: Int(self.pageSlider.value.rounded())) {
                self.addBlankSubView(page: destPage)
                self.pdfView.go(to: destPage)
            }
        }), for: .valueChanged)

        pagePrevButton.setImage(UIImage(systemName: "arrow.left"), for: .normal)
        pagePrevButton.addAction(UIAction(handler: { (action) in
            self.updatePageViewPositionHistory()
            self.addBlankSubView(page: self.pdfView.currentPage)    //FIXME get actual page

            if self.pdfView.displaysRTL {
                self.pdfView.goToNextPage(self.pagePrevButton)
            } else {
                self.pdfView.goToPreviousPage(self.pagePrevButton)
            }
        }), for: .primaryActionTriggered)
        
        pageNextButton.setImage(UIImage(systemName: "arrow.right"), for: .normal)
        pageNextButton.addAction(UIAction(handler: { (action) in
            self.updatePageViewPositionHistory()
            self.addBlankSubView(page: self.pdfView.currentPage)    //FIXME get actual page

            if self.pdfView.displaysRTL {
                self.pdfView.goToPreviousPage(self.pagePrevButton)
            } else {
                self.pdfView.goToNextPage(self.pagePrevButton)
            }
        }), for: .primaryActionTriggered)
        
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.axis = .horizontal
        stackView.spacing = 16.0
        
        stackView.addArrangedSubview(pagePrevButton)
        stackView.addArrangedSubview(pageSlider)
        stackView.addArrangedSubview(pageIndicator)
        stackView.addArrangedSubview(pageNextButton)
        
        let toolbarView = UIBarButtonItem(customView: stackView)
        setToolbarItems([toolbarView], animated: false)
        
        navigationItem.setLeftBarButtonItems([
            UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), style: .done, target: self, action: #selector(finishReading(sender:))),
            UIBarButtonItem(title: "Zoom Out", image: UIImage(systemName: "minus.magnifyingglass"), primaryAction: UIAction(handler: { (UIAction) in
                self.pdfView.scaleFactor = (self.pdfView.scaleFactor ) / 1.1
            })),
            UIBarButtonItem(title: "Zoom In", image: UIImage(systemName: "plus.magnifyingglass"), primaryAction: UIAction(handler: { (UIAction) in
                self.pdfView.scaleFactor = (self.pdfView.scaleFactor ) * 1.1
            })),
        ], animated: true)
        
        navigationItem.setRightBarButtonItems([
            UIBarButtonItem(image: UIImage(systemName: "clock"), menu: historyMenu),
            UIBarButtonItem(
                title: "Options",
                image: UIImage(systemName: "doc.badge.gearshape"),
                primaryAction: UIAction { (UIAction) in
                    //self.present(self.optionMenu, animated: true, completion: nil)
                    let optionView = PDFOptionView(pdfViewController: self)
                    
                    let optionViewController = UIHostingController(rootView: optionView.fixedSize())
                    optionViewController.preferredContentSize = CGSize(width:340, height:600)
                    optionViewController.modalPresentationStyle = .popover
                    optionViewController.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItems?[1]
                    
                    self.present(optionViewController, animated: true, completion: nil)
                }
            ),
        ], animated: true)
        self.navigationItem.rightBarButtonItems?.first?.isEnabled = false
        
        var tableOfContents = [UIMenuElement]()
        
        if let pdfDoc = pdfView.document, var outlineRoot = pdfDoc.outlineRoot {
            while outlineRoot.numberOfChildren == 1 {
                outlineRoot = outlineRoot.child(at: 0)!
            }
            for i in (0..<outlineRoot.numberOfChildren) {
                tocList.append((outlineRoot.child(at: i)?.label ?? "Label at \(i)", outlineRoot.child(at: i)?.destination?.page?.pageRef?.pageNumber ?? 1))
                tableOfContents.append(UIAction(title: outlineRoot.child(at: i)?.label ?? "Label at \(i)") { (action) in
                    guard let dest = outlineRoot.child(at: i)?.destination,
                          let curPage = self.pdfView.currentPage
                    else { return }
                    
                    var lastHistoryLabel = "Page \(curPage.pageRef!.pageNumber)"
                    if let curPageSelection = curPage.selection(for: curPage.bounds(for: .mediaBox)),
                       let curPageSelectionText = curPageSelection.string,
                       curPageSelectionText.count > 5,
                       var curPageOutlineItem = pdfDoc.outlineItem(for: curPageSelection) {
                        
                        print("\(curPageSelectionText)")
                        while( curPageOutlineItem.parent != nil && curPageOutlineItem.parent != outlineRoot) {
                            curPageOutlineItem = curPageOutlineItem.parent!
                        }
                        lastHistoryLabel += " of \(curPageOutlineItem.label!)"
                    }
                    
                    var historyItems = self.historyMenu.children
                    historyItems.append(UIAction(title: lastHistoryLabel) { (action) in
                        var children = self.historyMenu.children
                        if let index = children.firstIndex(of: action) {
                            children.removeLast(children.count - index)
                            self.historyMenu = self.historyMenu.replacingChildren(children)
                            let newMenu = self.navigationItem.rightBarButtonItems?.first?.menu?.replacingChildren(children)
                            self.navigationItem.rightBarButtonItems?.first?.menu = nil  //MUST HAVE, otherwise no effect
                            self.navigationItem.rightBarButtonItems?.first?.menu = newMenu
                            if children.isEmpty {
                                self.navigationItem.rightBarButtonItems?.first?.isEnabled = false
                            }
                        }
                        if curPage.pageRef?.pageNumber != self.pdfView.currentPage?.pageRef?.pageNumber {
                            self.addBlankSubView(page: curPage)
                        }
                        self.pdfView.go(to: curPage)
                    })
                    
                    self.historyMenu = self.historyMenu.replacingChildren(historyItems)
                    let newMenu = self.navigationItem.rightBarButtonItems?.first?.menu?.replacingChildren(historyItems)
                    self.navigationItem.rightBarButtonItems?.first?.menu = nil  //MUST HAVE, otherwise no effect
                    self.navigationItem.rightBarButtonItems?.first?.menu = newMenu
                    self.navigationItem.rightBarButtonItems?.first?.isEnabled = true
                        
                    if dest.page?.pageRef?.pageNumber != self.pdfView.currentPage?.pageRef?.pageNumber {
                        self.addBlankSubView(page: dest.page)
                    }
                    self.pdfView.go(to: dest)
                })
                
            }
        }
        
        let navContentsMenu = UIMenu(title: "Contents", children: tableOfContents)
        
        titleInfoButton.setTitle("Title", for: .normal)
        titleInfoButton.contentHorizontalAlignment = .center
        titleInfoButton.showsMenuAsPrimaryAction = true
        titleInfoButton.menu = navContentsMenu
        titleInfoButton.frame = CGRect(x:0, y:0, width: navigationController?.navigationBar.frame.width ?? 600 / 2, height: 40)
        
        navigationItem.titleView = titleInfoButton
        
        thumbController.view = thumbImageView
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tappedGesture(sender:)))
        tapGestureRecognizer.numberOfTapsRequired = 2
        
        pdfView.addGestureRecognizer(tapGestureRecognizer)
        pdfView.delegate = self
        
        self.view = pdfView

        if modelData?.getCustomDictViewer().0 ?? false {     // if enabled
            UIMenuController.shared.menuItems = [UIMenuItem(title: "MDict", action: #selector(lookupMDict))]
            mDictView.loadViewIfNeeded()
        } else {
            UIMenuController.shared.menuItems = []
        }
        
        let destPageIndex = (pageViewPositionHistory.first?.key ?? 1) - 1 //convert from 1-based to 0-based
        
        if let page = pdfView.document?.page(at: destPageIndex) {
            if page.pageRef?.pageNumber != self.pdfView.currentPage?.pageRef?.pageNumber {
                self.addBlankSubView(page: page)
            }
            pdfView.go(to: page)
        }
        
        if destPageIndex == 0 {
            self.handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
        }
        
        print("stackView \(self.navigationController?.view.frame ?? .zero) \(self.navigationController?.toolbar.frame ?? .zero)")
        stackView.frame = self.navigationController?.toolbar.frame ?? .zero
    }
    
    override func viewDidAppear(_ animated: Bool) {
//        self.viewSafeAreaInsetsDidChange()
//        self.viewLayoutMarginsDidChange()
        
//        UIMenuController.shared.menuItems = [UIMenuItem(title: "StarDict", action: #selector(lookupStarDict))]
//        starDictView.loadViewIfNeeded()
        blankView.contentMode = .scaleAspectFill
        pdfView.addSubview(blankView)

        self.handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
    }

    override func viewDidDisappear(_ animated: Bool) {
        updatePageViewPositionHistory()
        updateReadingProgress()
        
        super.viewDidDisappear(animated)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        updatePageViewPositionHistory()
        
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in
            
        } completion: { _ in
            self.handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
        }
    }
    
    @objc private func tappedGesture(sender: UITapGestureRecognizer) {
        print("tappedGesture \(sender.state.rawValue)")
        
        if sender.state == .ended {
            let frameRect = self.pdfView.frame
            let tapRect = sender.location(in: self.pdfView)
            print("tappedGesture \(tapRect) in \(frameRect)")
            
            if( tapRect.y < frameRect.height * 0.9 && tapRect.y > frameRect.height * 0.1 ) {
                if tapRect.x < frameRect.width * 0.2 {
                    pagePrevButton.sendActions(for: .primaryActionTriggered)
                    return
                }
                if tapRect.x > frameRect.width * 0.8 {
                    pageNextButton.sendActions(for: .primaryActionTriggered)
                    return
                }
                
                self.pdfView.scaleFactor = self.pdfView.scaleFactor * 1.2
            }
        }
    }
    
    @objc private func handlePageChange(notification: Notification) {
        var titleLabel = self.bookTitle
        guard let curPage = pdfView.currentPage else { return }

        addBlankSubView(page: curPage)
        
        defer {
            clearBlankSubView()
        }
        
        if var outlineRoot = pdfView.document?.outlineRoot {
            while outlineRoot.numberOfChildren == 1 {
                outlineRoot = outlineRoot.child(at: 0)!
            }
            if let curPageSelection = curPage.selection(for: curPage.bounds(for: .mediaBox)),
               !curPageSelection.selectionsByLine().isEmpty,
               var curPageOutlineItem = pdfView.document?.outlineItem(for: curPageSelection) {
                while( curPageOutlineItem.parent != nil && curPageOutlineItem.parent != outlineRoot) {
                    curPageOutlineItem = curPageOutlineItem.parent!
                }
                if curPageOutlineItem.label != nil && !curPageOutlineItem.label!.isEmpty {
                    titleLabel = curPageOutlineItem.label
                }
            }
        }
        self.titleInfoButton.setTitle(titleLabel, for: .normal)
        
        let curPageNum = pdfView.currentPage?.pageRef?.pageNumber ?? 1
        pageIndicator.setTitle("\(curPageNum) / \(pdfView.document?.pageCount ?? 1)", for: .normal)
        pageSlider.setValue(Float(curPageNum), animated: true)
        
        if pdfOptions.readingDirection.rawValue.contains("LtR") {
            pageSlider.semanticContentAttribute = .forceLeftToRight
            pdfView.displaysRTL = false
        }
        if pdfOptions.readingDirection.rawValue.contains("RtL") {
            pageSlider.semanticContentAttribute = .forceRightToLeft
            pdfView.displaysRTL = true
        }
        
        print("handlePageChange \(pageIndicator.title(for: .normal) ?? "Untitled") \(pageSlider.value)")
        
        if pdfView.frame.width < 1.0 {
            // have not been populated, cannot fit content
            return
        }
        let boundsForCropBox = curPage.bounds(for: .cropBox)
        let boundForVisibleContent = getVisibleContentsBound(pdfPage: curPage)
        
        if let pageViewPosition = pageViewPositionHistory[curPageNum],
           pageViewPosition.scaler > 0,
           pageViewPosition.viewSize == pdfView.frame.size {
            let lastDest = PDFDestination(
                page: curPage,
                at: pageViewPosition.point
            )
            lastDest.zoom = pageViewPosition.scaler
            print("BEFORE POINT lastDestPoint=\(lastDest.point)")
            
            let bottomRight = PDFDestination(
                page: curPage,
                at: CGPoint(x: lastDest.point.x + boundsForCropBox.width, y: lastDest.point.y + boundsForCropBox.height)
            )
            bottomRight.zoom = 1.0
            
            pdfView.scaleFactor = pageViewPosition.scaler
            
            pdfView.go(to: bottomRight)
            pdfView.go(to: lastDest)
            return
        }
        
        guard pdfView.scaleFactor > 0 else { return }

        let visibleWidthRatio = 1.0 * (boundForVisibleContent.width + 1) / boundsForCropBox.width
        let visibleHeightRatio = 1.0 * (boundForVisibleContent.height + 1) / boundsForCropBox.height
        print("curScale \(pdfView.scaleFactor) \(visibleWidthRatio) \(visibleHeightRatio) \(pdfView.scaleFactorForSizeToFit)")
        
        let newDestX = boundForVisibleContent.minX + 4
        let newDestY = boundsForCropBox.height - boundForVisibleContent.minY
        
        let visibleRectInView = pdfView.convert(
            CGRect(x: newDestX,
                   y: newDestY,
                   width: boundsForCropBox.width * visibleWidthRatio,
                   height: boundsForCropBox.height * visibleHeightRatio),
            from: curPage)
        
        print("pdfView frame \(pdfView.frame)")
        
        print("initialRect \(visibleRectInView)")
        
        // let insetsScaleFactor = 0.9
        let insetsHorizontalScaleFactor = 1.0 - (pdfOptions.hMarginAutoScaler * 2.0) / 100.0
        let insetsVerticalScaleFactor = 1.0 - (pdfOptions.vMarginAutoScaler * 2.0) / 100.0
        let scaleFactor = { () -> CGFloat in
            if pdfOptions.lastScale < 0 || pdfOptions.selectedAutoScaler != PDFAutoScaler.Custom {
                switch pdfOptions.selectedAutoScaler {
                case .Width:
                    return pdfView.scaleFactor * pdfView.frame.width / visibleRectInView.width * CGFloat(insetsHorizontalScaleFactor)
                case .Height:
                    return pdfView.scaleFactor * (pdfView.frame.height - self.navigationController!.navigationBar.frame.height) / visibleRectInView.height * CGFloat(insetsVerticalScaleFactor)
                default:    // including .Page
                    return min(
                        pdfView.scaleFactor * pdfView.frame.width / visibleRectInView.width * CGFloat(insetsHorizontalScaleFactor),
                        pdfView.scaleFactor * pdfView.frame.height / visibleRectInView.height * CGFloat(insetsVerticalScaleFactor)
                    )
                }
            } else {
                return pdfOptions.lastScale
            }
        }()
        
        //pdfView.scaleFactor = self.lastScale
        print("scaleFactor \(pdfOptions.lastScale)")
        
        pdfView.scaleFactor = scaleFactor

        let navBarFrame = self.navigationController!.navigationBar.frame
        let navBarFrameInPDF = pdfView.convert(navBarFrame, to:curPage)
        let viewFrameInPDF = pdfView.convert(pdfView.frame, to: curPage)
        
        let newDest = PDFDestination(
            page: curPage,
            at: CGPoint(
                x: pageViewPositionHistory[curPageNum]?.point.x ??
                    newDestX - (1.0 - insetsHorizontalScaleFactor) / 2 * boundsForCropBox.width + boundsForCropBox.minX,
                y: pageViewPositionHistory[curPageNum]?.point.y ??
                    newDestY + navBarFrameInPDF.height + boundsForCropBox.minY + (1.0 - insetsVerticalScaleFactor) / 2 * viewFrameInPDF.height
            )
        )
        
        print("BEFORE POINT curDestPoint=\(pdfView.currentDestination!.point) newDestPoint=\(newDest.point) \(boundsForCropBox)")
        //            let bottomRight = PDFDestination(
        //                page: curPage,
        //                at: CGPoint(x: newDestX + boundsForCropBox.width, y: newDestY + boundsForCropBox.height))
        
        let bottomRight = PDFDestination(
            page: curPage,
            at: CGPoint(x: newDestX + boundsForCropBox.width, y: newDestY - boundsForCropBox.height))
        
        pdfView.go(to: bottomRight)
        
        print("BEFORE POINT curDestPoint=\(pdfView.currentDestination!.point) newDestPoint=\(newDest.point) \(boundsForCropBox)")
        
        pdfView.go(to: newDest)
        
        var afterPointX = pdfView.currentDestination!.point.x
        var afterPointY = pdfView.currentDestination!.point.y + navBarFrameInPDF.height + viewFrameInPDF.height
        
        print("AFTER POINT scale=\(scaleFactor) curDestPoint=\(pdfView.currentDestination!.point) curDestPointInPDF=\(afterPointX),\(afterPointY) newDestPoint=\(newDest.point) \(boundsForCropBox)")
        
        let newDestForCompensation = PDFDestination(
            page: curPage,
            at: CGPoint(
                x: newDest.point.x - (afterPointX - newDest.point.x),
                y: newDest.point.y - (afterPointY - newDest.point.y)
            )
        )
        
        pdfView.go(to: bottomRight)
        pdfView.go(to: newDestForCompensation)
        afterPointX = pdfView.currentDestination!.point.x
        afterPointY = pdfView.currentDestination!.point.y + navBarFrameInPDF.height + viewFrameInPDF.height
        print("AFTER POINT COMPENSATION scale=\(scaleFactor) curDestPoint=\(pdfView.currentDestination!.point) curDestPointInPDF=\(afterPointX),\(afterPointY) newDestPoint=\(newDestForCompensation.point) \(boundsForCropBox)")

    }
    
    func getThumbnailImageSize(boundsForCropBox: CGRect) -> CGSize {
        // return CGSize(width: boundsForCropBox.width / 4, height: boundsForCropBox.height / 4)
        if boundsForCropBox.width < 1024 && boundsForCropBox.height < 1024 {
            return CGSize(width: boundsForCropBox.width, height: boundsForCropBox.height)
        } else {
            var width = boundsForCropBox.width
            var height = boundsForCropBox.height
            repeat {
                width /= 2
                height /= 2
            } while( width > 1024 || height > 1024)
            return CGSize(width: width, height: height)
        }
    }
    
    func getVisibleContentsBound(pdfPage: PDFPage) -> CGRect{
        let boundsForCropBox = pdfPage.bounds(for: .cropBox)
        let sizeForThumbnailImage = getThumbnailImageSize(boundsForCropBox: boundsForCropBox)
        
        let image = pdfPage.thumbnail(of: sizeForThumbnailImage, for: .cropBox)
        
        guard let cgimage = image.cgImage else { return boundsForCropBox }
        
        let numberOfComponents = 4
        
        var top = 0
        var bottom = 0
        var leading = 0
        var trailing = 0
        
        print("bounds cropBox=\(boundsForCropBox) mediaBox=\(pdfPage.bounds(for: .mediaBox)) artBox=\(pdfPage.bounds(for: .artBox)) bleedBox=\(pdfPage.bounds(for: .bleedBox)) trimBox=\(pdfPage.bounds(for: .trimBox))")
        print("sizeForThumbnailImage \(sizeForThumbnailImage)")
        print("image width=\(image.size.width) height=\(image.size.height)")
        
        let align = 8
        let padding = (align - Int(image.size.width) % align) % align
        print("CGIMAGE PADDING \(padding)")
        
        //TOP
        if let provider = cgimage.dataProvider,
              let providerData = provider.data,
              let data = CFDataGetBytePtr(providerData) {
            top      = getBlankBorderWidth(size: image.size, padding: padding, numberOfComponents: numberOfComponents, orientation: .up, data: data)
            bottom   = getBlankBorderWidth(size: image.size, padding: padding, numberOfComponents: numberOfComponents, orientation: .down, data: data)
            leading  = getBlankBorderWidth(size: image.size, padding: padding, numberOfComponents: numberOfComponents, orientation: .right, data: data)
            trailing = getBlankBorderWidth(size: image.size, padding: padding, numberOfComponents: numberOfComponents, orientation: .left, data: data)
        }
        print("white border \(top) \(bottom) \(leading) \(trailing)")
        
        let imageSize = image.size
        UIGraphicsBeginImageContextWithOptions(imageSize, false, CGFloat.zero)
        image.draw(at: CGPoint.zero)
        let rectangle = CGRect(x: leading, y: top, width: trailing - leading + 2, height: bottom - top + 1)
        UIColor.black.setFill()
        UIRectFrame(rectangle)
        
        let thumbnailScale = sizeForThumbnailImage.width / boundsForCropBox.width

        #if DEBUG
        UIColor.red.setStroke()
        let drawBounds = CGRect(x: boundsForCropBox.minX * thumbnailScale,
                                y: boundsForCropBox.minY * thumbnailScale,
                                width: sizeForThumbnailImage.width,
                                height: sizeForThumbnailImage.height)
        UIRectFrame(drawBounds)
        #endif
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        self.thumbImageView.image = newImage
        
        return CGRect(x: rectangle.minX / thumbnailScale, y: rectangle.minY / thumbnailScale, width: rectangle.width / thumbnailScale, height: rectangle.height / thumbnailScale)
    }
    
    /*
     from top to bottom
     */
    func getBlankBorderWidth(size: CGSize, padding: Int, numberOfComponents: Int, orientation: CGImagePropertyOrientation, data: UnsafePointer<UInt8>) -> Int {
        var isWhite = true
        let lineNumMax = { () -> Int in
            switch(orientation) {
            case .up, .down, .upMirrored, .downMirrored:
                return Int(size.height)
            case .left, .leftMirrored, .right, .rightMirrored:
                return Int(size.width)
            }
        }()
        let pixelNumMax = { () -> Int in
            switch(orientation) {
            case .up, .down, .upMirrored, .downMirrored:
                return Int(size.width)
            case .left, .leftMirrored, .right, .rightMirrored:
                return Int(size.height)
            }
        }()
        var border = lineNumMax/4
        let pixelNumInRow = Int(size.width) + padding
        for line in (1 ..< (lineNumMax/4)) {    //bypassing first line due to noises
            var nonWhiteDensity = 0.0
            for pixelInLine in (1 ..< pixelNumMax) {    //bypassing first line due to noises
                let lineIndex = { () -> Int in
                    switch(orientation) {
                    case .up, .upMirrored, .right, .rightMirrored:
                        return line     //top to bottom & left to right
                    case .down, .downMirrored, .left, .leftMirrored:
                        return lineNumMax - line - 1
                    }
                }()
                
                let pixelIndex = { () -> Int in
                    switch(orientation) {
                    case .up, .down, .upMirrored, .downMirrored:
                        return pixelInLine + pixelNumInRow * lineIndex
                    case .left, .leftMirrored, .right, .rightMirrored:
                        return lineIndex + pixelNumInRow * pixelInLine  //pixelInLine is row number of data
                    }
                }() * numberOfComponents
                
                
//                let pixelIndex = (
//                    ( Int(size.width) + padding ) * lineIndex   //locating target line in data
//                        + pixelInLine                           //moving to pixel
//                ) * numberOfComponents
                
                nonWhiteDensity += getPixelGreyLevel(pixelIndex: pixelIndex, data: data)
            }
            if nonWhiteDensity > 0 {
                print("nonWhiteDensity h=\(line) density=\(nonWhiteDensity)")
                if CGFloat(nonWhiteDensity) / CGFloat(pixelNumMax) > pdfOptions.hMarginDetectStrength / 20.0 {
                    isWhite = false
                }
            }
            //print("isWhite h=\(h) \(isWhite)")
            if !isWhite {
                border = line
                break
            }
        }
        
        switch(orientation) {
        case .up, .upMirrored, .right, .rightMirrored:
            return border     //top to bottom & left to right
        case .down, .downMirrored, .left, .leftMirrored:
            return lineNumMax - border - 1
        }
        
//        if bottomUp {
//            border = Int(size.height) - border - 1
//        }
        
//        return border
        
    }
    
    func getPixelGreyLevel(pixelIndex: Int, data: UnsafePointer<UInt8>) -> Double {
        let r = data[pixelIndex]
        let g = data[pixelIndex + 1]
        let b = data[pixelIndex + 2]
        // let a = data[pixelIndex + 3]
        // print("\(h) \(w) \(r) \(g) \(b) \(a)")
        
        if r < 200 && g < 200 && b < 200 {
            return Double(UInt(255-r) + UInt(255-g) + UInt(255-b) / 3) / 255.0
            //print("top=\(h) w=\(w) \(r) \(g) \(b) \(a)")
            //isWhite = false
            //break
        } else {
            return 0.0
        }
    }
    
    func addBlankSubView(page: PDFPage?) {
        let backgroundColor = UIColor(cgColor: PDFPageWithBackground.fillColor ?? CGColor.init(gray: 1.0, alpha: 1.0))
        
        if let page = page as? PDFPageWithBackground {
            let thumbImage = page.thumbnailWithBackground(of: pdfView.frame.size, for: .cropBox)
            blankView.image = thumbImage
        }
        
        blankView.tintColor = backgroundColor
        blankView.backgroundColor = backgroundColor
        blankView.frame.size = pdfView.frame.size
    }
    
    func clearBlankSubView() {
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(200))) {
            self.blankView.frame.size = .zero
        }
    }
    
    func handleOptionsChange(pdfOptions: PDFOptions) {
        print(pdfOptions)
        if self.pdfOptions != pdfOptions {
            var needRedraw = false
            if self.pdfOptions.themeMode != pdfOptions.themeMode {
                needRedraw = true
            }
            self.pdfOptions = pdfOptions
            if needRedraw {
//                self.pdfView.layoutDocumentView()
                //self.pdfView.invalidateIntrinsicContentSize()
            }
            if let pageNum = pdfView.currentPage?.pageRef?.pageNumber {
                self.pageViewPositionHistory[pageNum]?.scaler = 0
            }
            handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
        }
    }
    
    func handleAutoScalerChange(autoScaler: PDFAutoScaler, hMarginAutoScaler: Double, vMarginAutoScaler: Double) {
        
    }
    
    @objc func handleScaleChange(_ sender: Any?)
    {
        pdfOptions.lastScale = pdfView.scaleFactor
        print("handleScaleChange: \(pdfOptions.lastScale)")
    }
    
    @objc func handleDisplayBoxChange(_ sender: Any?)
    {
        print("handleDisplayBoxChange: \(self.pdfView.currentDestination!)")
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        updateReadingProgress()
        
        self.dismiss(animated: true, completion: nil)
    }
    
    func updateReadingProgress() {
        var position = [String : Any]()
        
        guard let curDest = pdfView.currentDestination,
              let pageNum = curDest.page?.pageRef?.pageNumber
        else { return }
        
        position["pageNumber"] = pageNum
        position["pageOffsetX"] = curDest.point.x
        let viewFrameInPDF = pdfView.convert(pdfView.frame, to: curDest.page!)
        let navFrameInPDF = pdfView.convert(navigationController!.navigationBar.frame, to: curDest.page!)
        print("viewFrameInPDF=\(viewFrameInPDF) navFrameInPDF=\(navFrameInPDF) curDestY=\(curDest.point.y)")
        position["pageOffsetY"] = curDest.point.y + viewFrameInPDF.height + navFrameInPDF.height
        
        let bookProgress = 100.0 * Double(position["pageNumber"]! as! Int) / Double(pdfView.document!.pageCount)
        
        var chapterProgress = 0.0
        let chapterName = titleInfoButton.currentTitle ?? "Unknown Title"
        if let firstIndex = tocList.lastIndex(where: { $0.0 == chapterName && $0.1 <= pageNum }) {
            let curIndex = firstIndex.advanced(by: 0)
            let nextIndex = firstIndex.advanced(by: 1)
            let chapterStartPageNum = tocList[curIndex].1
            let chapterEndPageNum = nextIndex < tocList.count ?
                tocList[nextIndex].1 + 1 : pdfView.document!.pageCount + 1
            if chapterEndPageNum > chapterStartPageNum {
                chapterProgress = 100.0 * Double(pageNum - chapterStartPageNum) / Double(chapterEndPageNum - chapterStartPageNum)
            }
        }
        
        modelData?.updatedReadingPosition.lastPosition[0] = pageNum
        modelData?.updatedReadingPosition.lastPosition[1] = Int(curDest.point.x.rounded())
        modelData?.updatedReadingPosition.lastPosition[2] = Int((curDest.point.y + viewFrameInPDF.height + navFrameInPDF.height).rounded())
        modelData?.updatedReadingPosition.lastReadPage = pageNum
        modelData?.updatedReadingPosition.lastChapterProgress = chapterProgress
        modelData?.updatedReadingPosition.lastProgress = bookProgress
        modelData?.updatedReadingPosition.lastReadChapter = chapterName
        modelData?.updatedReadingPosition.readerName = ReaderType.YabrPDF.rawValue
            
//            modelData?.updateCurrentPosition(progress: progress, position: position)
        
        if let pdfOptionsRealm = realm?.objects(PDFOptionsRealm.self).filter(
            NSPredicate(format: "id = %@ AND libraryName = %@", NSNumber(value: modelData!.readingBook!.id), modelData!.readingBook!.library.name)
        ).first {
            try? realm?.write {
                pdfOptionsRealm.themeMode = pdfOptions.themeMode.rawValue
                pdfOptionsRealm.selectedAutoScaler = pdfOptions.selectedAutoScaler.rawValue
                pdfOptionsRealm.readingDirection = pdfOptions.readingDirection.rawValue
                pdfOptionsRealm.hMarginAutoScaler = Double(pdfOptions.hMarginAutoScaler)
                pdfOptionsRealm.vMarginAutoScaler = Double(pdfOptions.vMarginAutoScaler)
                pdfOptionsRealm.hMarginDetectStrength = Double(pdfOptions.hMarginDetectStrength)
                pdfOptionsRealm.vMarginDetectStrength = Double(pdfOptions.vMarginDetectStrength)
                pdfOptionsRealm.lastScale = Double(pdfOptions.lastScale)
                pdfOptionsRealm.rememberInPagePosition = pdfOptions.rememberInPagePosition
            }
        } else {
            let pdfOptionsRealm = PDFOptionsRealm()
            pdfOptionsRealm.id = modelData!.readingBook!.id
            pdfOptionsRealm.libraryName = modelData!.readingBook!.library.name
            pdfOptionsRealm.themeMode = pdfOptions.themeMode.rawValue
            pdfOptionsRealm.selectedAutoScaler = pdfOptions.selectedAutoScaler.rawValue
            pdfOptionsRealm.readingDirection = pdfOptions.readingDirection.rawValue
            pdfOptionsRealm.hMarginAutoScaler = Double(pdfOptions.hMarginAutoScaler)
            pdfOptionsRealm.vMarginAutoScaler = Double(pdfOptions.vMarginAutoScaler)
            pdfOptionsRealm.hMarginDetectStrength = Double(pdfOptions.hMarginDetectStrength)
            pdfOptionsRealm.vMarginDetectStrength = Double(pdfOptions.vMarginDetectStrength)
            pdfOptionsRealm.lastScale = Double(pdfOptions.lastScale)
            pdfOptionsRealm.rememberInPagePosition = pdfOptions.rememberInPagePosition
            try? realm?.write {
                realm?.add(pdfOptionsRealm)
            }
        }
        
    }
    
//    @objc func lookupStarDict() {
//        if let s = pdfView.currentSelection?.string {
//            print(s)
//            starDictView.word = s
//            self.present(starDictView, animated: true, completion: nil)
//        }
//    }
    @objc func lookupMDict() {
        if let s = pdfView.currentSelection?.string {
            print(s)
            mDictView.title = s
            self.present(mDictView, animated: true, completion: nil)
        }
    }
    
    func updatePageViewPositionHistory() {
        guard let dest = pdfView.currentDestination,
              let curPage = dest.page,
              let pageNum = curPage.pageRef?.pageNumber else { return }
        
        let viewFrameInPDF = pdfView.convert(pdfView.frame, to: curPage)
        let navBarFrame = self.navigationController?.navigationBar.frame ?? CGRect()
        let navBarFrameInPDF = pdfView.convert(navBarFrame, to:curPage)

        let pointUpperLeft = CGPoint(
            x: dest.point.x,
            y: dest.point.y + navBarFrameInPDF.height + viewFrameInPDF.height
        )
        pageViewPositionHistory[pageNum] = PageViewPosition(
            scaler: pdfView.scaleFactor,
            point: pointUpperLeft,
            viewSize: pdfView.frame.size
        )
        print("updatePageViewPositionHistory \(pageViewPositionHistory[pageNum]!)")
    }
}

struct PageViewPosition {
    var scaler = CGFloat()
    var point = CGPoint()
    var viewSize = CGSize()
}

class PDFOptionsRealm: Object {
    @objc dynamic var id: Int32 = 0
    @objc dynamic var libraryName = ""
    @objc dynamic var themeMode = PDFThemeMode.serpia.rawValue
    @objc dynamic var selectedAutoScaler = PDFAutoScaler.Width.rawValue
    @objc dynamic var readingDirection = PDFReadDirection.LtR_TtB.rawValue
    @objc dynamic var hMarginAutoScaler = 5.0
    @objc dynamic var vMarginAutoScaler = 5.0
    @objc dynamic var hMarginDetectStrength = 2.0
    @objc dynamic var vMarginDetectStrength = 2.0
    @objc dynamic var lastScale = -1.0
    @objc dynamic var rememberInPagePosition = true
}

extension YabrPDFViewController: PDFDocumentDelegate {
    func classForPage() -> AnyClass {
        return PDFPageWithBackground.self
    }
    
    
}
