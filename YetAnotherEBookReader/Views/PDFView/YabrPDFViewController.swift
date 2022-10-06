//
//  PDFViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import Foundation
import UIKit
import PDFKit
import OSLog
import SwiftUI

@available(macCatalyst 14.0, *)
class YabrPDFViewController: UIViewController, PDFViewDelegate, UIGestureRecognizerDelegate {
    let pdfView = YabrPDFView()
    let blankView = UIImageView()
    let blankActivityView = UIActivityIndicatorView()
    
    let logger = Logger()
    
    var historyMenu = UIMenu(title: "History", children: [])
    
    let stackView = UIStackView()
    
    let pageSlider = UISlider()
    let pageIndicator = UIButton()
    let pageNextButton = UIButton()
    let pagePrevButton = UIButton()
    
    let titleInfoButton = UIButton()
    var tocList = [(String, Int)]()
    
    let thumbImageView = UIImageView()
    let thumbController = UIViewController()
    
    var yabrPDFMetaSource: YabrPDFMetaSource?
    
    var pdfOptions = PDFOptions() {
        didSet {
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
            }
            let isDark = pdfOptions.themeMode == .dark
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
            
            guard let curPage = self.pdfView.currentPage,
                  let curPageNum = curPage.pageRef?.pageNumber else { return }
            
            if oldValue.pageMode != pdfOptions.pageMode || oldValue.scrollDirection != pdfOptions.scrollDirection {
                updatePageViewPositionHistory()
            }
            
            switch pdfOptions.pageMode {
            case .Page:
                self.pdfView.displayMode = .singlePage
                switch pdfOptions.readingDirection {
                case .LtR_TtB:
                    pageSlider.semanticContentAttribute = .forceLeftToRight
                    pdfView.displaysRTL = false
                    pdfView.displayDirection = .vertical
                case .TtB_RtL:
                    pageSlider.semanticContentAttribute = .forceRightToLeft
                    pdfView.displaysRTL = true
                    pdfView.displayDirection = .horizontal
                }
            case .Scroll:
                self.pdfView.displayMode = .singlePageContinuous
                pageSlider.semanticContentAttribute = .forceLeftToRight
                pdfView.displaysRTL = false
                switch pdfOptions.scrollDirection {
                case .Vertical:
                    pdfView.displayDirection = .vertical
                case .Horizontal:
                    pdfView.displayDirection = .horizontal
                }
            }
            
            if oldValue.pageMode != pdfOptions.pageMode || oldValue.scrollDirection != pdfOptions.scrollDirection {
                if let firstPage = pdfView.document?.page(at: 1) {
                    pdfView.go(to: PDFDestination(page: firstPage, at: .zero))
                }
                
                let viewPosition = getPageViewPositionHistory(curPageNum)?.point
                if viewPosition != nil {
                    pdfView.go(to: PDFDestination(page: curPage, at: viewPosition!))
                } else {
                    pdfView.go(to: curPage)
                }
            }
            
            if pdfOptions.pageMode == .Page {
                pdfView.pageTapPreview(navBarHeight: navigationController?.navigationBar.frame.height ?? 0, hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
            } else {
                pdfView.pageTapDisable()
            }
        }
    }
        
    var pageViewPositionHistory = [Int: PageViewPosition]() //key is 1-based (pdfView.currentPage?.pageRef?.pageNumber)
    
    var pageVisibleContentBounds: [PageVisibleContentKey: PageVisibleContentValue] = [:]
    
    func open() -> Int {
        guard let pdfURL = yabrPDFMetaSource?.yabrPDFURL(pdfView) else { return -1 }
        
        logger.info("pdfURL: \(pdfURL.absoluteString)")
        logger.info("Exist: \(FileManager.default.fileExists(atPath: pdfURL.path))")
        
        guard let pdfDoc = PDFDocument(url: pdfURL) else { return -1 }
        
        pdfDoc.delegate = self
        logger.info("pdfDoc: \(pdfDoc.majorVersion) \(pdfDoc.minorVersion)")
        pdfView.document = pdfDoc

        pdfView.displayMode = PDFDisplayMode.singlePage
        pdfView.displayDirection = PDFDisplayDirection.horizontal
        pdfView.interpolationQuality = PDFInterpolationQuality.high
        
        if let pdfOptions = yabrPDFMetaSource?.yabrPDFOptions(pdfView) {
            self.pdfOptions = pdfOptions
        }
        
        if let position = yabrPDFMetaSource?.yabrPDFReadPosition(pdfView) {
            let intialPageNum = position.lastPosition[0] > 0 ? position.lastPosition[0] : 1
        
            pageViewPositionHistory.removeAll()
            
            pageViewPositionHistory[intialPageNum] = PageViewPosition(
                scaler: pdfOptions.lastScale,
                point: CGPoint(x: position.lastPosition[1], y: position.lastPosition[2])
            )
        }
        
        return 0
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // pdfView.usePageViewController(true, withViewOptions: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageChange(notification:)), name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScaleChange(_:)), name: .PDFViewScaleChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDisplayBoxChange(_:)), name: .PDFViewDisplayBoxChanged, object: pdfView)
        
        pdfView.autoScales = false

        pageIndicator.setTitle("0 / 0", for: .normal)
        pageIndicator.addAction(UIAction(handler: { [self] (action) in
            guard let curPageNum = pdfView.currentPage?.pageRef?.pageNumber,
                  let bounds = pageVisibleContentBounds[
                    PageVisibleContentKey(
                        pageNumber: curPageNum,
                        readingDirection: pdfOptions.readingDirection,
                        hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
                        vMarginDetectStrength: pdfOptions.vMarginDetectStrength
                    )
                  ],
                  let image = bounds.thumbImage else { return }
            self.thumbImageView.image = image
            self.present(self.thumbController, animated: true, completion: nil)
        }), for: .primaryActionTriggered)
        
        pageSlider.minimumValue = 1
        pageSlider.maximumValue = Float(pdfView.document?.pageCount ?? 1)
        pageSlider.isContinuous = true
        pageSlider.addAction(UIAction(handler: { (action) in
            guard let currentPageNumber = self.pdfView.currentPage?.pageRef?.pageNumber else { return }
            let destPageNumber = Int(self.pageSlider.value.rounded())
            print("\(#function) current=\(currentPageNumber) target=\(destPageNumber)")
            
            guard currentPageNumber != destPageNumber,
                  let destPage = self.pdfView.document?.page(at: destPageNumber - 1) else { return }
            
            self.addBlankSubView(page: destPage)
            self.pdfView.go(to: destPage)
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
            UIBarButtonItem(title: "List", image: UIImage(systemName: "line.3.horizontal"), primaryAction: UIAction(handler: { action in
                let pageController = YabrPDFAnnotationPageVC()
                
                pageController.yabrPDFView = self.pdfView
                pageController.yabrPDFMetaSource = self.yabrPDFMetaSource
                
                let nav = UINavigationController(rootViewController: pageController)
                if let fillColor = PDFPageWithBackground.fillColor {
                    nav.navigationBar.backgroundColor = UIColor(cgColor: fillColor)
                }
                
                self.present(nav, animated: true)
            }))
//            UIBarButtonItem(title: "Zoom Out", image: UIImage(systemName: "minus.magnifyingglass"), primaryAction: UIAction(handler: { (UIAction) in
//                self.pdfView.scaleFactor = (self.pdfView.scaleFactor ) / 1.1
//            })),
//            UIBarButtonItem(title: "Zoom In", image: UIImage(systemName: "plus.magnifyingglass"), primaryAction: UIAction(handler: { (UIAction) in
//                self.pdfView.scaleFactor = (self.pdfView.scaleFactor ) * 1.1
//            })),
        ], animated: true)
        
        navigationItem.setRightBarButtonItems([
            UIBarButtonItem(image: UIImage(systemName: "clock"), menu: historyMenu),
            UIBarButtonItem(
                title: "Options",
                image: UIImage(systemName: "doc.badge.gearshape"),
                primaryAction: UIAction { (UIAction) in
                    //self.present(self.optionMenu, animated: true, completion: nil)
                    let optionView = PDFOptionView(pdfViewController: Binding<YabrPDFViewController>(
                        get: { return self },
                        set: { _ in }
                    ))
                    
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
        
        
//        let doubleTapLeftGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(doubleTappedGesture(sender:)))
//        doubleTapLeftGestureRecognizer.numberOfTapsRequired = 2
//        doubleTapLeftGestureRecognizer.delegate = self
//        doubleTapLeftLabel.addGestureRecognizer(doubleTapLeftGestureRecognizer)
//
//        let doubleTapRightGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(doubleTappedGesture(sender:)))
//        doubleTapRightGestureRecognizer.numberOfTapsRequired = 2
//        doubleTapRightGestureRecognizer.delegate = self
//        doubleTapRightLabel.addGestureRecognizer(doubleTapRightGestureRecognizer)
//
//        let singleTapLeftGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(singleTappedGesture(sender:)))
//        singleTapLeftGestureRecognizer.numberOfTapsRequired = 1
//        singleTapLeftGestureRecognizer.delegate = self
//        singleTapLeftLabel.addGestureRecognizer(singleTapLeftGestureRecognizer)
//
//        let singleTapRightGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(singleTappedGesture(sender:)))
//        singleTapRightGestureRecognizer.numberOfTapsRequired = 1
//        singleTapRightGestureRecognizer.delegate = self
//        singleTapRightLabel.addGestureRecognizer(singleTapRightGestureRecognizer)

        pdfView.delegate = self
        
        self.view = pdfView

        if let dictViewer = yabrPDFMetaSource?.yabrPDFDictViewer(pdfView) {
            UIMenuController.shared.menuItems = [UIMenuItem(title: dictViewer.0, action: #selector(dictViewerAction))]
            dictViewer.1.loadViewIfNeeded()
        } else {
            UIMenuController.shared.menuItems = []
        }
        
        print("stackView \(self.navigationController?.view.frame ?? .zero) \(self.navigationController?.toolbar.frame ?? .zero)")
        stackView.frame = self.navigationController?.toolbar.frame ?? .zero
        
        pdfView.prepareActions(pageNextButton: pageNextButton, pagePrevButton: pagePrevButton)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
//        self.viewSafeAreaInsetsDidChange()
//        self.viewLayoutMarginsDidChange()
        
//        UIMenuController.shared.menuItems = [UIMenuItem(title: "StarDict", action: #selector(lookupStarDict))]
//        starDictView.loadViewIfNeeded()
        blankView.contentMode = .scaleAspectFill
        blankView.addSubview(blankActivityView)
        
        if pdfOptions.pageMode == .Page {
            pdfView.pageTapPreview(navBarHeight: navigationController?.navigationBar.frame.height ?? 0, hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
        }
        pdfView.addSubview(blankView)
        
        let destPageIndex = (pageViewPositionHistory.first?.key ?? 1) - 1 //convert from 1-based to 0-based
        
        if let page = pdfView.document?.page(at: destPageIndex) {
            if page.pageRef?.pageNumber != self.pdfView.currentPage?.pageRef?.pageNumber {
                self.addBlankSubView(page: page)
            }
            self.pdfView.goToFirstPage(self)
            self.pdfView.go(to: page)
            
//                if self.pdfView.currentPage?.pageRef?.pageNumber != destPageIndex {
//                    delay(0.2) {
//                        self.pdfView.go(to: page)
//                    }
//                }
        }
        
        if destPageIndex == 0 {
            self.handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        updatePageViewPositionHistory()
        
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in
            
        } completion: { [self] _ in
            handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
            if pdfOptions.pageMode == .Page {
                pdfView.pageTapPreview(navBarHeight: navigationController?.navigationBar.frame.height ?? 0, hMarginAutoScaler: pdfOptions.hMarginAutoScaler)
            } else {
                pdfView.pageTapDisable()
            }
        }
    }
    
    @objc private func handlePageChange(notification: Notification) {
        var titleLabel = yabrPDFMetaSource?.yabrPDFReadPosition(pdfView)?.lastReadChapter
        guard let curPage = pdfView.currentPage else { return }

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
        
        print("\(#function) curPageNum=\(curPageNum) pageIndicator=\(pageIndicator.title(for: .normal) ?? "Untitled") pageSlider=\(pageSlider.value)")
        
        guard pdfView.frame.width > 1.0 else { return }     // have not been populated, cannot fit content
        
        if pdfView.displayMode != .singlePage {
            pdfView.scaleFactor = pdfOptions.lastScale
            
            if let pageViewPosition = getPageViewPositionHistory(curPageNum),
               pageViewPosition.scaler > 0,
               pageViewPosition.viewSize == pdfView.frame.size || pageViewPosition.viewSize == .zero {
                let lastDest = PDFDestination(
                    page: curPage,
                    at: pageViewPosition.point
                )
                lastDest.zoom = pageViewPosition.scaler
                print("\(#function) displayMode=\(pdfView.displayMode) BEFORE POINT lastDestPoint=\(lastDest.point)")
                
                pdfView.scaleFactor = pageViewPosition.scaler
                
                pageViewPositionHistory.removeValue(forKey: curPageNum)     //prevent further application
                pdfView.go(to: lastDest)
            }
            
            return
        }
        
        addBlankSubView(page: curPage)
        
        [PDFDisplayBox.mediaBox, PDFDisplayBox.cropBox, PDFDisplayBox.trimBox, PDFDisplayBox.bleedBox, PDFDisplayBox.artBox].forEach {
            let bounds = curPage.bounds(for: $0)
            print("\(#function) boundsForBox box=\($0.rawValue) bounds=\(bounds)")
        }
        let boundsForCropBox = curPage.bounds(for: .cropBox)
        let boundsForMediaBox = curPage.bounds(for: .mediaBox)
        let boundForVisibleContentKey = PageVisibleContentKey(
            pageNumber: curPageNum,
            readingDirection: pdfOptions.readingDirection,
            hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
            vMarginDetectStrength: pdfOptions.vMarginDetectStrength
        )
        
        let boundForVisibleContent = pageVisibleContentBounds[boundForVisibleContentKey]?.bounds ?? { () -> CGRect in
            let bounds = getVisibleContentsBound(pdfPage: curPage)
            pageVisibleContentBounds[boundForVisibleContentKey] = bounds
            return bounds.bounds
        }()
        pageVisibleContentBounds[boundForVisibleContentKey]?.lastUsed = Date()
        
        //pre-analyze next page
        while( pageVisibleContentBounds.count > 9 ) {
            if let minPageEntry = pageVisibleContentBounds.min(by: {$0.value.lastUsed < $1.value.lastUsed}) {
                pageVisibleContentBounds.removeValue(forKey: minPageEntry.key)
                print("\(#function) pageVisibleContentBounds.removeValue=\(minPageEntry.key.pageNumber)")
            } else {
                break
            }
        }
        DispatchQueue.global(qos: .utility).async { [self] in
            let boundForVisibleContentKeyNext = PageVisibleContentKey(
                pageNumber: curPageNum + 1,
                readingDirection: pdfOptions.readingDirection,
                hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
                vMarginDetectStrength: pdfOptions.vMarginDetectStrength
            )
            let boundForVisibleContentKeyPrev = PageVisibleContentKey(
                pageNumber: curPageNum - 1,
                readingDirection: pdfOptions.readingDirection,
                hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
                vMarginDetectStrength: pdfOptions.vMarginDetectStrength
            )
            var boundsNext: PageVisibleContentValue? = nil
            var boundsPrev: PageVisibleContentValue? = nil
            defer {
                DispatchQueue.main.async {
                    if boundsNext != nil {
                        pageVisibleContentBounds[boundForVisibleContentKeyNext] = boundsNext!
                    }
                    if boundsPrev != nil {
                        pageVisibleContentBounds[boundForVisibleContentKeyPrev] = boundsPrev!
                    }
                }
            }
            
            if pageVisibleContentBounds[boundForVisibleContentKeyNext] == nil,
               let prePage = pdfView.document?.page(at: boundForVisibleContentKeyNext.pageNumber - 1) {   //page(at:) is 0-based
                boundsNext = getVisibleContentsBound(pdfPage: prePage)
            }
                        
            if pageVisibleContentBounds[boundForVisibleContentKeyPrev] == nil,
               let prePage = pdfView.document?.page(at: boundForVisibleContentKeyPrev.pageNumber - 1) {   //page(at:) is 0-based
                boundsPrev = getVisibleContentsBound(pdfPage: prePage)
            }
        }
        print("\(#function) pageVisibleContentBounds.count=\(pageVisibleContentBounds.count)")
        
        if let pageViewPosition = getPageViewPositionHistory(curPageNum),
           pageViewPosition.scaler > 0,
           pageViewPosition.viewSize == pdfView.frame.size {
            let lastDest = PDFDestination(
                page: curPage,
                at: pageViewPosition.point
            )
            lastDest.zoom = pageViewPosition.scaler
            print("\(#function) displayMode=\(pdfView.displayMode) BEFORE POINT lastDestPoint=\(lastDest.point)")
            
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
        print("\(#function) curScale scaleFactor=\(pdfView.scaleFactor) visibleWidthRatio=\(visibleWidthRatio) visibleHeightRatio=\(visibleHeightRatio) boundsForCropBox=\(boundsForCropBox) boundForVisibleContent=\(boundForVisibleContent)")
        
        let newDestX = boundForVisibleContent.minX + boundsForMediaBox.minX + 2
        let newDestY = boundsForCropBox.height - boundForVisibleContent.minY + 2
        
        let visibleRectInView = pdfView.convert(
            CGRect(x: newDestX,
                   y: newDestY,
                   width: boundsForCropBox.width * visibleWidthRatio,
                   height: boundsForCropBox.height * visibleHeightRatio),
            from: curPage)
        
        print("\(#function) pdfView pdfView.frame=\(pdfView.frame)")
        
        print("\(#function) initialRect visibleRectInView=\(visibleRectInView)")
        
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
        pdfView.scaleFactor = scaleFactor
        //pdfView.scaleFactor = self.lastScale
        let navBarFrame = self.navigationController!.navigationBar.frame
        let navBarFrameInPDF = pdfView.convert(navBarFrame, to: curPage)
        let viewFrameInPDF = pdfView.convert(pdfView.frame, to: curPage)
        let stackViewFrameInPDF = pdfView.convert(stackView.frame, to: curPage)
        
        let pageViewPositionHistory = getPageViewPositionHistory(curPageNum)
        let newDest = PDFDestination(
            page: curPage,
            at: CGPoint(
                x: pageViewPositionHistory?.point.x ??
                (newDestX - (1.0 - insetsHorizontalScaleFactor) / 2 * boundsForCropBox.width + boundsForCropBox.minX),
                y: pageViewPositionHistory?.point.y ??
                (newDestY + navBarFrameInPDF.height + boundsForCropBox.minY + (1.0 - insetsVerticalScaleFactor) / 2 * viewFrameInPDF.height)
            )
        )
        
        print("\(#function) newDest newDestX=\(newDestX) minus=\((1.0 - insetsHorizontalScaleFactor) / 2 * boundsForCropBox.width) plus=\(boundsForCropBox.minX) history=\(pageViewPositionHistory?.point.x)")
        
        print("\(#function) newDest newDestY=\(newDestX) plus1=\(navBarFrameInPDF.height) plus2=\(boundsForCropBox.minY) plus3=\((1.0 - insetsVerticalScaleFactor) / 2 * viewFrameInPDF.height) history=\(pageViewPositionHistory?.point.y)")
        
        let initialDestPoint = pdfView.currentDestination!.point
        
        print("\(#function) BEFORE POINT curDestPoint=\(pdfView.currentDestination!.point) newDestPoint=\(newDest.point) boundsForCropBox=\(boundsForCropBox)")
        //            let bottomRight = PDFDestination(
        //                page: curPage,
        //                at: CGPoint(x: newDestX + boundsForCropBox.width, y: newDestY + boundsForCropBox.height))
        
        let bottomRight = PDFDestination(
            page: curPage,
            at: CGPoint(x: boundsForMediaBox.width, y: 0))
        
        pdfView.go(to: bottomRight)
        
        print("\(#function) BEFORE POINT BOTTOM RIGHT curDestPoint=\(pdfView.currentDestination!.point) newDestPoint=\(newDest.point) boundsForCropBox=\(boundsForCropBox)")
        
        pdfView.go(to: newDest)
        
        var afterPointX = pdfView.currentDestination!.point.x
        var afterPointY = pdfView.currentDestination!.point.y + navBarFrameInPDF.height + viewFrameInPDF.height
        
        print("\(#function) AFTER POINT scale=\(scaleFactor) curDestPoint=\(pdfView.currentDestination!.point) curDestPointInPDF=\(afterPointX),\(afterPointY) gotoDestPoint=\(newDest.point) boundsForCropBox=\(boundsForCropBox)")
        
        let newDestForCompensation = PDFDestination(
            page: curPage,
            at: CGPoint(
                x: newDest.point.x - (afterPointX - newDest.point.x),
                y: newDest.point.y - (afterPointY - newDest.point.y) - (initialDestPoint.y < 0 ? initialDestPoint.y : 0)
            )
        )
        
        pdfView.go(to: bottomRight)
        pdfView.go(to: newDestForCompensation)
        afterPointX = pdfView.currentDestination!.point.x
        afterPointY = pdfView.currentDestination!.point.y + navBarFrameInPDF.height + viewFrameInPDF.height
        print("\(#function) AFTER POINT COMPENSATION scale=\(scaleFactor) curDestPoint=\(pdfView.currentDestination!.point) curDestPointInPDF=\(afterPointX),\(afterPointY) gotoDestPoint=\(newDestForCompensation.point) boundsForCropBox=\(boundsForCropBox)")

        print("\(#function) scaleFactor=\(pdfOptions.lastScale)")
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
    
    func getVisibleContentsBound(pdfPage: PDFPage) -> PageVisibleContentValue {
        let boundsForMediaBox = pdfPage.bounds(for: .mediaBox)
        let boundsForCropBox = pdfPage.bounds(for: .cropBox)
        let sizeForThumbnailImage = getThumbnailImageSize(boundsForCropBox: boundsForCropBox)
        let thumbnailScale = sizeForThumbnailImage.width / boundsForCropBox.width

        let imageMediaBox = pdfPage.thumbnail(
            of: CGSize(
                width: boundsForMediaBox.width * thumbnailScale,
                height: boundsForMediaBox.height * thumbnailScale),
            for: .mediaBox
        )
        let imageCropBox = pdfPage.thumbnail(of: sizeForThumbnailImage, for: .cropBox)
        
        guard let cgimage = imageMediaBox.cgImage else { return PageVisibleContentValue(bounds: boundsForMediaBox, thumbImage: nil) }
        
        let numberOfComponents = 4
        
        var top = (0, 0)
        var bottom = (0, 0)
        var leading = (0, 0)
        var trailing = (0, 0)
        
        print("\(#function) bounds cropBox=\(boundsForCropBox) mediaBox=\(pdfPage.bounds(for: .mediaBox)) artBox=\(pdfPage.bounds(for: .artBox)) bleedBox=\(pdfPage.bounds(for: .bleedBox)) trimBox=\(pdfPage.bounds(for: .trimBox))")
        print("\(#function) sizeForThumbnailImage \(sizeForThumbnailImage)")
        print("\(#function) imageCropBox width=\(imageCropBox.size.width) height=\(imageCropBox.size.height)")
        print("\(#function) imageMediaBox width=\(imageMediaBox.size.width) height=\(imageMediaBox.size.height)")

        let align = 8
        let padding = (align - Int(imageMediaBox.size.width) % align) % align
        print("\(#function) CGIMAGE PADDING \(padding)")
        
        if let provider = cgimage.dataProvider,
              let providerData = provider.data,
              let data = CFDataGetBytePtr(providerData) {
            switch pdfOptions.readingDirection {
            case .LtR_TtB:
                top      = getBlankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .up,
                    data: data,
                    ratio: boundsForMediaBox.width / boundsForCropBox.width
                )
                bottom   = getBlankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .down,
                    data: data,
                    ratio: boundsForMediaBox.width / boundsForCropBox.width
                )
                leading  = getBlankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .right,
                    data: data,
                    ratio: 3 * imageMediaBox.size.height / Double(Int(imageMediaBox.size.height) - top.1 - bottom.1 + 1)
                )
                trailing = getBlankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .left,
                    data: data,
                    ratio: 3 * imageMediaBox.size.height / Double(Int(imageMediaBox.size.height) - top.1 - bottom.1 + 1)
                )
                break
            case .TtB_RtL:
                leading  = getBlankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .right,
                    data: data,
                    ratio: boundsForMediaBox.height / boundsForCropBox.height
                )
                trailing = getBlankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .left,
                    data: data,
                    ratio: boundsForMediaBox.height / boundsForCropBox.height
                )
                top      = getBlankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .up,
                    data: data,
                    ratio: 3 * imageMediaBox.size.width / Double(Int(imageMediaBox.size.width) - leading.1 - trailing.1 + 1)
                )
                bottom   = getBlankBorderWidth(
                    size: imageMediaBox.size,
                    padding: padding,
                    numberOfComponents: numberOfComponents,
                    orientation: .down,
                    data: data,
                    ratio: 3 * imageMediaBox.size.width / Double(Int(imageMediaBox.size.width) - leading.1 - trailing.1 + 1)
                )
                break
            }
            
        }
        
        print("\(#function) white border \(top) \(bottom) \(leading) \(trailing)")
        
        UIGraphicsBeginImageContextWithOptions(imageMediaBox.size, false, CGFloat.zero)
        imageMediaBox.draw(at: CGPoint.zero)
        
        //imageCropBox.draw(at: CGPoint(x: boundsForCropBox.minX, y: boundsForMediaBox.maxY - boundsForCropBox.maxY), blendMode: .darken, alpha: 0.8)
        
        let rectangle = CGRect(
            x: leading.0,
            y: top.0,
            width: trailing.0 - leading.0 + 2,
            height: bottom.0 - top.0 + 1
        )
        UIColor.black.setFill()
        UIRectFrame(rectangle)
        
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
        
//        return CGRect(x: rectangle.minX / thumbnailScale, y: rectangle.minY / thumbnailScale, width: rectangle.width / thumbnailScale, height: rectangle.height / thumbnailScale)
        //transform to cropBox coordination
        return PageVisibleContentValue(
            bounds: CGRect(
                x: CGFloat(leading.0) / thumbnailScale - boundsForCropBox.minX,
                y: CGFloat(top.0) / thumbnailScale - (boundsForMediaBox.maxY - boundsForCropBox.maxY),
                width: rectangle.width / thumbnailScale,
                height: rectangle.height / thumbnailScale
            ),
            thumbImage: newImage
        )
    }
    
    /*
     from top to bottom
     */
    func getBlankBorderWidth(size: CGSize, padding: Int, numberOfComponents: Int, orientation: CGImagePropertyOrientation, data: UnsafePointer<UInt8>, ratio: Double = 1.0) -> (Int, Int) {
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
        var border = lineNumMax/2
        let pixelNumInRow = Int(size.width) + padding
        var nonWhiteLineFirst = 0
        var nonWhiteLines = 0
        var whiteLines = 0
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
                print("nonWhiteDensity h=\(line) density=\(nonWhiteDensity) orientation=\(orientation.rawValue)")
            }
            
            if nonWhiteDensity > 0,
               nonWhiteDensity / Double(pixelNumMax) * ratio * 20.0 > pdfOptions.hMarginDetectStrength {
                nonWhiteLines += 1
                if nonWhiteLineFirst == 0 {
                    nonWhiteLineFirst = line
                }
            } else {
                whiteLines += 1
                nonWhiteLines = 0
                nonWhiteLineFirst = 0
            }
            
                //print("isWhite h=\(h) \(isWhite)")
            if nonWhiteLines > 2,
               nonWhiteLineFirst < lineNumMax / 4,
               border == lineNumMax / 2 {
                border = nonWhiteLineFirst
            }
        }
        
        if border == lineNumMax/2 {
            border = 1
        }
        
        switch(orientation) {
        case .up, .upMirrored, .right, .rightMirrored:
            return (border, whiteLines)     //top to bottom & left to right
        case .down, .downMirrored, .left, .leftMirrored:
            return (lineNumMax - border - 1, whiteLines)
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
        
        
        if r < 200 && g < 200 && b < 200 {
            return Double(UInt(255-r) + UInt(255-g) + UInt(255-b)) / 3 / 255.0
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
            
            let bounds = pageVisibleContentBounds[
                PageVisibleContentKey(
                    pageNumber: page.pageRef?.pageNumber ?? -1,
                    readingDirection: pdfOptions.readingDirection,
                    hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
                    vMarginDetectStrength: pdfOptions.vMarginDetectStrength
                )
            ]?.bounds ?? .zero
            
            let thumbImage = page.thumbnailWithBackground(of: pdfView.frame.size, for: .cropBox, by: bounds)
            blankView.image = thumbImage
        }
        
        blankView.tintColor = backgroundColor
        blankView.backgroundColor = backgroundColor
        blankView.frame.size = pdfView.frame.size
        
        blankActivityView.frame = CGRect(x: pdfView.frame.width/2, y: pdfView.frame.height/2, width: 50, height: 50)
        blankActivityView.style = .large
        blankActivityView.backgroundColor = .clear
        blankActivityView.startAnimating()
        
        clearBlankSubView()
    }
    
    func clearBlankSubView() {
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(400))) {
            self.blankView.frame.size = .zero
            self.blankActivityView.stopAnimating()
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
        updatePageViewPositionHistory()

        updateReadingProgress()
        
        self.dismiss(animated: true, completion: nil)
    }
    
    func updateReadingProgress() {
        var position = [String : Any]()
        
        guard let curPageNum = pdfView.page(for: .zero, nearest: true)?.pageRef?.pageNumber,
              let curPagePos = getPageViewPositionHistory(curPageNum)
        else { return }
        
        position["pageNumber"] = curPageNum
        position["pageOffsetX"] = curPagePos.point.x
        position["pageOffsetY"] = curPagePos.point.y
        
        let bookProgress = 100.0 * Double(position["pageNumber"] as? Int ?? 0) / Double(pdfView.document?.pageCount ?? 1)
        
        var chapterProgress = 0.0
        let chapterName = titleInfoButton.currentTitle ?? "Unknown Title"
        if let firstIndex = tocList.lastIndex(where: { $0.0 == chapterName && $0.1 <= curPageNum }) {
            let curIndex = firstIndex.advanced(by: 0)
            let nextIndex = firstIndex.advanced(by: 1)
            let chapterStartPageNum = tocList[curIndex].1
            let chapterEndPageNum = nextIndex < tocList.count ?
                tocList[nextIndex].1 + 1 : (pdfView.document?.pageCount ?? 1) + 1
            if chapterEndPageNum > chapterStartPageNum {
                chapterProgress = 100.0 * Double(curPageNum - chapterStartPageNum) / Double(chapterEndPageNum - chapterStartPageNum)
            }
        }
        
        if var updatedReadingPosition = yabrPDFMetaSource?.yabrPDFReadPosition(pdfView) {
            updatedReadingPosition.lastPosition[0] = curPageNum
            updatedReadingPosition.lastPosition[1] = Int(curPagePos.point.x.rounded())
            updatedReadingPosition.lastPosition[2] = Int((curPagePos.point.y).rounded())
            updatedReadingPosition.maxPage = self.pdfView.document?.pageCount ?? 1
            updatedReadingPosition.lastReadPage = curPageNum
            updatedReadingPosition.lastChapterProgress = chapterProgress
            updatedReadingPosition.lastProgress = bookProgress
            updatedReadingPosition.lastReadChapter = chapterName
            updatedReadingPosition.lastReadBook = pdfView.document?.title ?? "Unknown Title"
            updatedReadingPosition.readerName = ReaderType.YabrPDF.rawValue
            updatedReadingPosition.epoch = Date().timeIntervalSince1970
            
            yabrPDFMetaSource?.yabrPDFReadPosition(pdfView, update: updatedReadingPosition)
            
            print("\(#function) updatedReadingPosition=\(updatedReadingPosition)")
        }
            
        yabrPDFMetaSource?.yabrPDFOptions(pdfView, update: pdfOptions)
    }
    
//    @objc func lookupStarDict() {
//        if let s = pdfView.currentSelection?.string {
//            print(s)
//            starDictView.word = s
//            self.present(starDictView, animated: true, completion: nil)
//        }
//    }
    @objc func dictViewerAction() {
        guard let s = pdfView.currentSelection?.string,
              let dictViewer = yabrPDFMetaSource?.yabrPDFDictViewer(pdfView) else { return }
        
        print("\(#function) word=\(s)")
        dictViewer.1.title = s
        
        let nav = UINavigationController(rootViewController: dictViewer.1)
        nav.setNavigationBarHidden(false, animated: false)
        nav.setToolbarHidden(false, animated: false)
        
        self.present(nav, animated: true, completion: nil)
    }
    
    func updatePageViewPositionHistory() {
        guard let pagePoint = getPagePoint() else { return }
        
        pageViewPositionHistory[pagePoint.0] = pagePoint.1
        print("updatePageViewPositionHistory \(pagePoint)")
    }
    
    func getPagePoint() -> (Int, PageViewPosition)? {
        guard let curDest = pdfView.currentDestination,
              let curDestPage = curDest.page,
              let curPage = pdfView.page(for: .zero, nearest: true),
              let curPageNum = curPage.pageRef?.pageNumber
              else { return nil }
        
        var curDestPoint = curDest.point
        if curPage != curDestPage {
//            CGPoint(x: curDest.point.x, y: curDest.point.y - curDestPage.bounds(for: .cropBox).height)
            //translate curDest point to curPage point
            let curDestPointInView = pdfView.convert(curDestPoint, from: curDestPage)
            let curDestPointInCurPage = pdfView.convert(curDestPointInView, to: curPage)
            curDestPoint = curDestPointInCurPage
        }
        
        let viewFrameInPDF = pdfView.convert(pdfView.frame, to: curPage)
        let navBarFrame = self.navigationController?.navigationBar.frame ?? CGRect()
        let navBarFrameInPDF = pdfView.convert(navBarFrame, to:curPage)
    
        let pointUpperLeft = CGPoint(
            x: curDestPoint.x,
            y: curDestPoint.y + navBarFrameInPDF.height + viewFrameInPDF.height
        )
        
        return (
            curPageNum,
            PageViewPosition(
                scaler: pdfView.scaleFactor,
                point: pointUpperLeft,
                viewSize: pdfView.frame.size
            )
        )
    }
    
    func getPageViewPositionHistory(_ pageNum: Int) -> PageViewPosition? {
        return self.pageViewPositionHistory[pageNum]
    }
}

extension YabrPDFViewController: PDFDocumentDelegate {
    func classForPage() -> AnyClass {
        return PDFPageWithBackground.self
    }
    
    
}

protocol YabrPDFMetaSource {
    func yabrPDFURL(_ view: YabrPDFView?) -> URL?
    
    func yabrPDFDocument(_ view: YabrPDFView?) -> PDFDocument?
    
    func yabrPDFNavigate(_ view: YabrPDFView?, pageNumber: Int, offset: CGPoint)
    
    func yabrPDFNavigate(_ view: YabrPDFView?, destination: PDFDestination)

    func yabrPDFOutline(_ view: YabrPDFView?, for page: Int) -> PDFOutline?
    
    func yabrPDFReadPosition(_ view: YabrPDFView?) -> BookDeviceReadingPosition?
    
    func yabrPDFReadPosition(_ view: YabrPDFView?, update readPosition: BookDeviceReadingPosition)
    
    func yabrPDFOptions(_ view: YabrPDFView?) -> PDFOptions?
    
    func yabrPDFOptions(_ view: YabrPDFView?, update options: PDFOptions)
    
    func yabrPDFDictViewer(_ view: YabrPDFView?) -> (String, UIViewController)?
    
    func yabrPDFBookmarks(_ view: YabrPDFView?) -> [PDFBookmark]
    
    func yabrPDFBookmarks(_ view: YabrPDFView?, update bookmark: PDFBookmark)
    
    func yabrPDFBookmarks(_ view: YabrPDFView?, remove bookmark: PDFBookmark)
    
    func yabrPDFHighlights(_ view: YabrPDFView?) -> [PDFHighlight]
    
    func yabrPDFHighlights(_ view: YabrPDFView?, update highlight: PDFHighlight)
    
    func yabrPDFReferenceText(_ view: YabrPDFView?) -> String?

    func yabrPDFReferenceText(_ view: YabrPDFView?, set refText: String?)
    
    func yabrPDFOptionsIsNight<T>(_ view: YabrPDFView?, _ f: T, _ l: T) -> T
}
