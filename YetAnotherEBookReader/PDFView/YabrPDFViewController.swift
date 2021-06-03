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
class YabrPDFViewController: UIViewController, PDFViewDelegate, PDFDocumentDelegate {
    var modelData: ModelData?
    var pdfView: PDFView?
    var mDictView = MDictViewContainer()
    var lastScale = CGFloat(-1.0)
    
    let logger = Logger()
    
    var historyMenu = UIMenu(title: "History", children: [])
    
    var pageSlider = UISlider()
    var pageIndicator = UIButton()
    var pageNextButton = UIButton()
    var pagePrevButton = UIButton()
    
    let titleInfoButton = UIButton()
    var tocList = [(String, Int)]()
    
    let thumbImageView = UIImageView()
    let thumbController = UIViewController()
    
    var pdfOptions = PDFOptions()
        
    var bookTitle: String!

    func open(pdfURL: URL) {
        self.bookTitle = modelData?.readingBook?.title
        
        pdfView = PDFView()
        
        pdfView!.displayMode = PDFDisplayMode.singlePage
        pdfView!.displayDirection = PDFDisplayDirection.horizontal
        pdfView!.interpolationQuality = PDFInterpolationQuality.high
        
        // pdfView!.usePageViewController(true, withViewOptions: nil)
        
//        setToolbarItems(
//            [   UIBarButtonItem.flexibleSpace(),
//                UIBarButtonItem(title: "0 / 0", style: .plain, target: self, action: nil),
//                UIBarButtonItem.flexibleSpace()
//            ], animated: true)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageChange(notification:)), name: .PDFViewPageChanged, object: pdfView!)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScaleChange(_:)), name: .PDFViewScaleChanged, object: pdfView!)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDisplayBoxChange(_:)), name: .PDFViewDisplayBoxChanged, object: pdfView!)
        
        
        logger.info("pdfURL: \(pdfURL.absoluteString)")
        logger.info("Exist: \(FileManager.default.fileExists(atPath: pdfURL.path))")
        
        let pdfDoc = PDFDocument(url: pdfURL)
        pdfDoc?.delegate = self
        logger.info("pdfDoc: \(pdfDoc?.majorVersion ?? -1) \(pdfDoc?.minorVersion ?? -1)")
        
        pdfView!.document = pdfDoc
        pdfView!.autoScales = false

        pageIndicator.setTitle("0 / 0", for: .normal)
        pageIndicator.setTitleColor(.label, for: .normal)
        pageIndicator.addAction(UIAction(handler: { (action) in
            self.present(self.thumbController, animated: true, completion: nil)
        }), for: .primaryActionTriggered)
        
        pageSlider.minimumValue = 1
        pageSlider.maximumValue = Float(pdfView!.document!.pageCount)
        //pageSlider.frame = CGRect(x:0, y:0, width: 200, height: 40);
        pageSlider.isContinuous = true
        pageSlider.addAction(UIAction(handler: { (action) in
            if let destPage = self.pdfView!.document!.page(at: Int(self.pageSlider.value.rounded())) {
                self.pdfView!.go(to: destPage)
            }
        }), for: .valueChanged)

        pagePrevButton.setImage(UIImage(systemName: "arrow.left"), for: .normal)
        pagePrevButton.addAction(UIAction(handler: { (action) in
            if self.pdfView!.displaysRTL {
                self.pdfView!.goToNextPage(self.pagePrevButton)
            } else {
                self.pdfView!.goToPreviousPage(self.pagePrevButton)
            }
        }), for: .primaryActionTriggered)
        pageNextButton.setImage(UIImage(systemName: "arrow.right"), for: .normal)
        pageNextButton.addAction(UIAction(handler: { (action) in
            if self.pdfView!.displaysRTL {
                self.pdfView!.goToPreviousPage(self.pagePrevButton)
            } else {
                self.pdfView!.goToNextPage(self.pagePrevButton)
            }
        }), for: .primaryActionTriggered)
        
        
        navigationItem.setLeftBarButtonItems([
            UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), style: .done, target: self, action: #selector(finishReading(sender:))),
            UIBarButtonItem(title: "Zoom Out", image: UIImage(systemName: "minus.magnifyingglass"), primaryAction: UIAction(handler: { (UIAction) in
                self.pdfView?.scaleFactor = (self.pdfView?.scaleFactor ?? 1.0) / 1.1
            })),
            UIBarButtonItem(title: "Zoom In", image: UIImage(systemName: "plus.magnifyingglass"), primaryAction: UIAction(handler: { (UIAction) in
                self.pdfView?.scaleFactor = (self.pdfView?.scaleFactor ?? 1.0) * 1.1
            })),
        ], animated: true)
        
        navigationItem.setRightBarButtonItems(
            [
                UIBarButtonItem(image: UIImage(systemName: "clock"), menu: historyMenu),
                UIBarButtonItem(
                    title: "Options",
                    image: UIImage(systemName: "doc.badge.gearshape"),
                    primaryAction:
                        UIAction(
                            handler: { (UIAction) in
                                //self.present(self.optionMenu, animated: true, completion: nil)
                                let optionView = PDFOptionView(pdfViewController: self)
                                
                                let optionViewController = UIHostingController(rootView: optionView.fixedSize())
                                //optionViewController.preferredContentSize = CGSize(width:340, height:450)
                                optionViewController.modalPresentationStyle = .popover
                                optionViewController.popoverPresentationController!.barButtonItem = self.navigationItem.rightBarButtonItems![1]
                                
                                self.present(
                                    optionViewController,
                                    animated: true, completion: nil)
                                
                            }
                        )
                ),
                
                
                
        ], animated: true)
        
        var tableOfContents = [UIMenuElement]()
        
        if var outlineRoot = pdfDoc?.outlineRoot {
            while outlineRoot.numberOfChildren == 1 {
                outlineRoot = outlineRoot.child(at: 0)!
            }
            for i in (0..<outlineRoot.numberOfChildren) {
                tocList.append((outlineRoot.child(at: i)?.label ?? "Label at \(i)", outlineRoot.child(at: i)?.destination?.page?.pageRef?.pageNumber ?? 1))
                tableOfContents.append(UIAction(title: outlineRoot.child(at: i)?.label ?? "Label at \(i)") { (action) in
                    if let dest = outlineRoot.child(at: i)?.destination {
                        if let curPage = self.pdfView?.currentPage {
                            
                            var historyItems = self.historyMenu.children
                            var lastHistoryLabel = "Page \(curPage.pageRef!.pageNumber)"
                            if let curPageSelection = curPage.selection(for: curPage.bounds(for: .mediaBox)) {
                                if let curPageSelectionText = curPageSelection.string, curPageSelectionText.count > 5 {
                                    print("\(curPageSelectionText)")
                                    if var curPageOutlineItem = pdfDoc?.outlineItem(for: curPageSelection) {
                                        while( curPageOutlineItem.parent != nil && curPageOutlineItem.parent != outlineRoot) {
                                            curPageOutlineItem = curPageOutlineItem.parent!
                                        }
                                        lastHistoryLabel += " of \(curPageOutlineItem.label!)"
                                    }
                                }
                            }
                            historyItems.append(UIAction(title: lastHistoryLabel) { (action) in
                                var children = self.historyMenu.children
                                if let index = children.firstIndex(of: action) {
                                    children.removeLast(children.count - index)
                                    self.historyMenu = self.historyMenu.replacingChildren(children)
                                    if var rightBarButtonItems = self.navigationItem.rightBarButtonItems {
                                        rightBarButtonItems[0] = UIBarButtonItem(image: UIImage(systemName: "clock"), menu: self.historyMenu)
                                        self.navigationItem.setRightBarButtonItems(rightBarButtonItems, animated: true)
                                    }
                                }
                                self.pdfView!.go(to: curPage)
                            })
                            self.historyMenu = self.historyMenu.replacingChildren(historyItems)
                            if var rightBarButtonItems = self.navigationItem.rightBarButtonItems {
                                rightBarButtonItems[0] = UIBarButtonItem(image: UIImage(systemName: "clock"), menu: self.historyMenu)
                                self.navigationItem.setRightBarButtonItems(rightBarButtonItems, animated: true)
                            }
                            
                        }
                        self.pdfView!.go(to: dest)
                    }
                })
                
            }
        }
        
        let navContentsMenu = UIMenu(title: "Contents", children: tableOfContents)
        
        //navigationItem.setRightBarButton(UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        //navigationItem.setRightBarButtonItems([UIBarButtonItem(image: UIImage(systemName: "list.bullet"), menu: navContentsMenu)], animated: true)
        
        titleInfoButton.setTitle("Title", for: .normal)
        titleInfoButton.setTitleColor(.label, for: .normal)
        titleInfoButton.contentHorizontalAlignment = .center
        titleInfoButton.showsMenuAsPrimaryAction = true
        titleInfoButton.menu = navContentsMenu
        titleInfoButton.frame = CGRect(x:0, y:0, width: navigationController?.navigationBar.frame.width ?? 600 / 2, height: 40)
        
        navigationItem.titleView = titleInfoButton
        
        thumbController.view = thumbImageView
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tappedGesture(sender:)))
        tapGestureRecognizer.numberOfTapsRequired = 2
        
        pdfView!.addGestureRecognizer(tapGestureRecognizer)
        
        self.view = pdfView
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.viewSafeAreaInsetsDidChange()
        self.viewLayoutMarginsDidChange()
        
//        UIMenuController.shared.menuItems = [UIMenuItem(title: "StarDict", action: #selector(lookupStarDict))]
        UIMenuController.shared.menuItems = [UIMenuItem(title: "MDict", action: #selector(lookupMDict))]
//        starDictView.loadViewIfNeeded()
        mDictView.loadViewIfNeeded()
        
        let realm = try! Realm(configuration: Realm.Configuration(schemaVersion: 2))
        let pdfOptionsRealmResult = realm.objects(PDFOptionsRealm.self).filter(
            NSPredicate(format: "id = %@ AND libraryName = %@", NSNumber(value: modelData!.readingBook!.id), modelData!.readingBook!.library.name)
        )
        if let pdfOptionsRealm = pdfOptionsRealmResult.first {
            pdfOptions.selectedAutoScaler = PDFAutoScaler.init(rawValue: pdfOptionsRealm.selectedAutoScaler) ?? .Width
            pdfOptions.readingDirection = PDFReadDirection.init(rawValue: pdfOptionsRealm.readingDirection) ?? .LtR_TtB
            pdfOptions.hMarginAutoScaler = pdfOptionsRealm.hMarginAutoScaler
            pdfOptions.vMarginAutoScaler = pdfOptionsRealm.vMarginAutoScaler
            pdfOptions.hMarginDetectStrength = pdfOptionsRealm.hMarginDetectStrength
            pdfOptions.vMarginDetectStrength = pdfOptionsRealm.vMarginDetectStrength
            pdfOptions.lastScale = pdfOptionsRealm.lastScale
            pdfOptions.rememberInPagePosition = pdfOptionsRealm.rememberInPagePosition
        }
        
        var destPageNum = (modelData?.updatedReadingPosition.lastPosition[0] ?? 1) - 1
        if destPageNum < 0 {
            destPageNum = 0
        }
        
        if let page = pdfView?.document?.page(at: destPageNum) {
            pdfView?.go(to: page)
        }
        
        if destPageNum == 0 {
            self.handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        updateReadingProgress()
        
        super.viewDidDisappear(animated)
    }
    
    class PDFPageWithBackground : PDFPage {
        override func draw(with box: PDFDisplayBox, to context: CGContext) {
            // Draw rotated overlay string
//            UIGraphicsPushContext(context)
//            context.saveGState()
//
//            context.setFillColor(red: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
//
//            let rect = self.bounds(for: box)
//
//            context.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
//
//            context.restoreGState()
//            UIGraphicsPopContext()
            
            // Draw original content
            super.draw(with: box, to: context)
            
            UIGraphicsPushContext(context)
            context.saveGState()
            context.setBlendMode(.darken)
            context.setFillColor(red: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
            let rect = self.bounds(for: box)
            context.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            context.restoreGState()
            UIGraphicsPopContext()
            // print("context \(box.rawValue) \(context.height) \(context.width)")
            
            return
        }
        
        override func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> UIImage {
            let uiImage = super.thumbnail(of: size, for: box)
            
            return uiImage
        }
    }
    
    func classForPage() -> AnyClass {
        return PDFPageWithBackground.self
    }
    
    @objc private func tappedGesture(sender: UITapGestureRecognizer) {
        print("tappedGesture \(sender.state.rawValue)")
        
        if sender.state == .ended {
            let frameRect = self.pdfView!.frame
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
                
                self.pdfView?.scaleFactor = (self.pdfView?.scaleFactor ?? 1.0) * 1.2
            }
        }
    }
    
    @objc private func handlePageChange(notification: Notification)
    {
        var titleLabel = self.bookTitle
        if var outlineRoot = pdfView?.document?.outlineRoot {
            while outlineRoot.numberOfChildren == 1 {
                outlineRoot = outlineRoot.child(at: 0)!
            }
            if let curPage = self.pdfView?.currentPage {
                if let curPageSelection = curPage.selection(for: curPage.bounds(for: .mediaBox)) {
                    if !curPageSelection.selectionsByLine().isEmpty, var curPageOutlineItem = pdfView?.document?.outlineItem(for: curPageSelection) {
                        while( curPageOutlineItem.parent != nil && curPageOutlineItem.parent != outlineRoot) {
                            curPageOutlineItem = curPageOutlineItem.parent!
                        }
                        if curPageOutlineItem.label != nil && !curPageOutlineItem.label!.isEmpty {
                            titleLabel = curPageOutlineItem.label
                        }
                    }
                }
            }
        }
        self.titleInfoButton.setTitle(titleLabel, for: .normal)
        
        let curPageNum = pdfView?.currentPage?.pageRef?.pageNumber ?? 1
        pageIndicator.setTitle("\(curPageNum) / \(pdfView?.document?.pageCount ?? 1)", for: .normal)
        pageSlider.setValue(Float(curPageNum), animated: true)
        
        if pdfOptions.readingDirection.rawValue.contains("LtR") {
            pageSlider.semanticContentAttribute = .forceLeftToRight
            pdfView!.displaysRTL = false
        }
        if pdfOptions.readingDirection.rawValue.contains("RtL") {
            pageSlider.semanticContentAttribute = .forceRightToLeft
            pdfView!.displaysRTL = true
        }
        
        print("handlePageChange \(pageIndicator.title(for: .normal)) \(pageSlider.value)")
        
        if pdfView!.frame.width < 1.0 {
            // have not been populated, cannot fit content
            return
        }
        

        if let page = pdfView?.currentPage {
            let boundForVisibleContent = getVisibleContentsBound(pdfPage: page)
            let boundsForCropBox = page.bounds(for: .cropBox)
            if let curScale = pdfView?.scaleFactor, curScale > 0 {
                
                let visibleWidthRatio = 1.0 * Double(boundForVisibleContent.width + 1) / Double(boundsForCropBox.width)
                let visibleHeightRatio = 1.0 * Double(boundForVisibleContent.height + 1) / Double(boundsForCropBox.height)
                print("curScale \(curScale) \(visibleWidthRatio) \(visibleHeightRatio) \(pdfView!.scaleFactorForSizeToFit)")
                
                let curPoint = pdfView!.currentDestination!.point
                
                let newDestX = Double(boundForVisibleContent.minX) + 1
                let newDestY = Double(boundsForCropBox.height) - Double(boundForVisibleContent.minY)
                
                let visibleRectInView = pdfView!.convert(
                    CGRect(x: newDestX,
                           y: newDestY,
                           width: Double(boundsForCropBox.width) * visibleWidthRatio,
                           height: Double(boundsForCropBox.height) * visibleHeightRatio),
                    from: page)
                
                print("pdfView frame \(pdfView!.frame)")
                
                print("initialRect \(visibleRectInView)")
                
                // let insetsScaleFactor = 0.9
                let insetsHorizontalScaleFactor = 1.0 - (pdfOptions.hMarginAutoScaler * 2.0) / 100.0
                let insetsVerticalScaleFactor = 1.0 - (pdfOptions.vMarginAutoScaler * 2.0) / 100.0
                if self.lastScale < 0 || pdfOptions.selectedAutoScaler != PDFAutoScaler.Custom {
                    switch pdfOptions.selectedAutoScaler {
                    case .Width:
                        self.lastScale = pdfView!.scaleFactor * pdfView!.frame.width / visibleRectInView.width * CGFloat(insetsHorizontalScaleFactor)
                    case .Height:
                        self.lastScale = pdfView!.scaleFactor * (pdfView!.frame.height - self.navigationController!.navigationBar.frame.height) / visibleRectInView.height * CGFloat(insetsVerticalScaleFactor)
                    default:    // including .Page
                        self.lastScale = min(
                            pdfView!.scaleFactor * pdfView!.frame.width / visibleRectInView.width * CGFloat(insetsHorizontalScaleFactor),
                            pdfView!.scaleFactor * pdfView!.frame.height / visibleRectInView.height * CGFloat(insetsVerticalScaleFactor)
                        )
                    }
                    
                }
                pdfView!.scaleFactor = self.lastScale
                print("scaleFactor \(self.lastScale)")
                
                let navBarFrame = self.navigationController!.navigationBar.frame
                let navBarFrameHeightInPDF = pdfView!.convert(navBarFrame, to:page).height
                
                let viewFrameInPDF = pdfView!.convert(pdfView!.frame, to: page)
                
                let newDest = PDFDestination(
                    page: page,
                    at: CGPoint(
                        x: newDestX - (1.0 - insetsHorizontalScaleFactor) / 2 * Double(boundsForCropBox.width) + Double(boundsForCropBox.minX),
                        y: newDestY + Double(navBarFrameHeightInPDF) + Double(boundsForCropBox.minY) + (1.0 - insetsVerticalScaleFactor) / 2 * Double(viewFrameInPDF.height)
                    )
                )
                
                let bottomRight = PDFDestination(
                    page: page,
                    at: CGPoint(x: newDestX + Double(boundsForCropBox.width), y: newDestY + Double(boundsForCropBox.height)))
                
                print("BEFORE POINT curPoint=\(curPoint) newDestPoint=\(newDest.point) \(boundsForCropBox)")
                
                if pdfOptions.rememberInPagePosition && notification.object != nil, let lastPosition = modelData?.updatedReadingPosition.lastPosition, page.pageRef?.pageNumber == lastPosition[0] {
                    let lastDest = PDFDestination(
                        page: page,
                        at: CGPoint(
                            x: lastPosition[1],
                            y: lastPosition[2]
                        )
                    )
                    print("BEFORE POINT lastDestPoint=\(lastDest.point) \(boundsForCropBox)")
                    pdfView!.go(to: bottomRight)
                    pdfView!.go(to: lastDest)
                } else {
                    pdfView!.go(to: bottomRight)
                    pdfView!.go(to: newDest)
                }
                
                print("AFTER POINT curDestPoint=\(pdfView!.currentDestination!.point) \(boundsForCropBox)")

            }
        }

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
    
    func getPixelGreyLevel(pixelIndex: Int, data: UnsafePointer<UInt8>) -> Double {
        let r = data[pixelIndex]
        let g = data[pixelIndex + 1]
        let b = data[pixelIndex + 2]
        // let a = data[pixelIndex + 3]
        // print("\(h) \(w) \(r) \(g) \(b) \(a)")
        
        if r < 250 && g < 250 && b < 250 {
            return Double(UInt(255-r) + UInt(255-g) + UInt(255-b) / 3) / 255.0
            //print("top=\(h) w=\(w) \(r) \(g) \(b) \(a)")
            //isWhite = false
            //break
        } else {
            return 0.0
        }
    }
    
    func getVisibleContentsBound(pdfPage: PDFPage) -> CGRect{
        print("pageNumber \(pdfPage.pageRef?.pageNumber)")
        
        let boundsForCropBox = pdfPage.bounds(for: .cropBox)
        let sizeForThumbnailImage = getThumbnailImageSize(boundsForCropBox: boundsForCropBox)
        
        let image = pdfPage.thumbnail(of: sizeForThumbnailImage, for: .cropBox)
        
        let cgimage = image.cgImage
        let provider = cgimage!.dataProvider
        let providerData = provider!.data
        let data = CFDataGetBytePtr(providerData)
        
        let numberOfComponents = 4
        
        var top = 0
        var bottom = 0
        var leading = 0
        var trailing = 0
        
        print("bounds cropBox=\(boundsForCropBox) mediaBox=\(pdfPage.bounds(for: .mediaBox)) artBox=\(pdfPage.bounds(for: .artBox)) bleedBox=\(pdfPage.bounds(for: .bleedBox)) trimBox=\(pdfPage.bounds(for: .trimBox))")
        print("sizeForThumbnailImage \(sizeForThumbnailImage)")
        print("cgimage width=\(cgimage!.width) height=\(cgimage!.height)")
        
        let align = 8
        let padding = (align - cgimage!.width % align) % align
        print("CGIMAGE PADDING \(padding)")
        
        //TOP
        var isWhite = true
        for h in (0..<(cgimage!.height/4)) {
            var nonWhiteDensity = 0.0
            for w in (0..<cgimage!.width) {
                let pixelIndex = ((Int(cgimage!.width + padding) * h) + w) * numberOfComponents
                
                nonWhiteDensity += getPixelGreyLevel(pixelIndex: pixelIndex, data: data!)
            }
            if nonWhiteDensity > 0 {
                print("nonWhiteDensity h=\(h) density=\(nonWhiteDensity)")
                if Double(nonWhiteDensity) / Double(cgimage!.width) > pdfOptions.hMarginDetectStrength / 20.0 {
                    isWhite = false
                }
            }
            //print("isWhite h=\(h) \(isWhite)")
            if !isWhite {
                top = h
                break
            }
        }
        if isWhite {
            top = cgimage!.height/4
        }
        
        //BOTTOM
        isWhite = true
        for h in (0..<(cgimage!.height/4)) {
            var nonWhiteDensity = 0.0
            for w in (0..<cgimage!.width) {
                let pixelIndex = ((Int(cgimage!.width + padding) * (cgimage!.height - h - 1)) + w) * numberOfComponents
                
                nonWhiteDensity += getPixelGreyLevel(pixelIndex: pixelIndex, data: data!)
            }
            if nonWhiteDensity > 0 {
                print("nonWhiteDensity h=\(h) density=\(nonWhiteDensity)")
                if Double(nonWhiteDensity) / Double(cgimage!.width) > pdfOptions.hMarginDetectStrength / 20.0 {
                    isWhite = false
                }
            }
            //print("isWhite h=\(h) \(isWhite)")
            if !isWhite {
                bottom = cgimage!.height - h - 1
                break
            }
        }
        if isWhite {
            bottom = cgimage!.height - cgimage!.height/4 - 1
        }
        
        //LEADING
        isWhite = true
        for w in (0..<(cgimage!.width/4)) {
            var nonWhiteDensity = 0.0
            for h in (0..<(cgimage!.height)){
                let pixelIndex = ((Int(cgimage!.width + padding) * (h)) + w) * numberOfComponents
                
                nonWhiteDensity += getPixelGreyLevel(pixelIndex: pixelIndex, data: data!)
            }
            if nonWhiteDensity > 0 {
                print("nonWhiteDensity w=\(w) density=\(nonWhiteDensity)")
                if Double(nonWhiteDensity) / Double(cgimage!.width) > pdfOptions.vMarginDetectStrength / 20.0 {
                    isWhite = false
                }
            }
            //print("isWhite w=\(w) \(isWhite)")
            if !isWhite {
                leading = w
                break
            }
        }
        if isWhite {
            leading = cgimage!.width/4
        }
        
        //TRAILING
        isWhite = true
        for w in (0..<(cgimage!.width/4)) {
            var nonWhiteDensity = 0.0
            for h in (0..<(cgimage!.height)){
                let pixelIndex = ((Int(cgimage!.width + padding) * (h)) + (cgimage!.width - w - 1)) * numberOfComponents
                
                nonWhiteDensity += getPixelGreyLevel(pixelIndex: pixelIndex, data: data!)
            }
            if nonWhiteDensity > 0 {
                print("nonWhiteDensity w=\(w) density=\(nonWhiteDensity)")
                if Double(nonWhiteDensity) / Double(cgimage!.width) > pdfOptions.vMarginDetectStrength / 20.0 {
                    isWhite = false
                }
            }
            //print("isWhite w=\(w) \(isWhite)")
            if !isWhite {
                trailing = cgimage!.width - w - 1
                break
            }
        }
        if isWhite {
            trailing = cgimage!.width - cgimage!.width/4 - 1
        }
        
        
        let imageSize = image.size
        UIGraphicsBeginImageContextWithOptions(imageSize, false, CGFloat.zero)
        image.draw(at: CGPoint.zero)
        let rectangle = CGRect(x: leading, y: top, width: trailing - leading + 2, height: bottom - top + 1)
        UIColor.black.setFill()
        //UIRectFill(rectangle)
        UIRectFrame(rectangle)
        
        UIColor.red.setStroke()
        let thumbnailScale = sizeForThumbnailImage.width / boundsForCropBox.width
        let drawBounds = CGRect(x: boundsForCropBox.minX * thumbnailScale,
                                y: boundsForCropBox.minY * thumbnailScale,
                                width: sizeForThumbnailImage.width,
                                height: sizeForThumbnailImage.height)
        UIRectFrame(drawBounds)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        self.thumbImageView.image = newImage
        
        return CGRect(x: rectangle.minX / thumbnailScale, y: rectangle.minY / thumbnailScale, width: rectangle.width / thumbnailScale, height: rectangle.height / thumbnailScale)
    }
    
    func handleOptionsChange(pdfOptions: PDFOptions) {
        print(pdfOptions)
        if self.pdfOptions != pdfOptions {
            self.pdfOptions = pdfOptions
            handlePageChange(notification: Notification(name: .PDFViewScaleChanged))
        }
    }
    
    func handleAutoScalerChange(autoScaler: PDFAutoScaler, hMarginAutoScaler: Double, vMarginAutoScaler: Double) {
        
    }
    
    @objc func handleScaleChange(_ sender: Any?)
    {
        self.lastScale = pdfView!.scaleFactor
        print("handleScaleChange: \(self.lastScale)")
    }
    
    @objc func handleDisplayBoxChange(_ sender: Any?)
    {
        print("handleDisplayBoxChange: \(self.pdfView!.currentDestination!)")
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        updateReadingProgress()
        
        self.dismiss(animated: true, completion: nil)
    }
    
    func updateReadingProgress() {
        var position = [String : Any]()
        if let curDest = pdfView?.currentDestination {
            let pageNum = curDest.page!.pageRef?.pageNumber ?? 1
            position["pageNumber"] = pageNum
            position["pageOffsetX"] = curDest.point.x
            let viewFrameInPDF = pdfView!.convert(pdfView!.frame, to: curDest.page!)
            let navFrameInPDF = pdfView!.convert(navigationController!.navigationBar.frame, to: curDest.page!)
            print("viewFrameInPDF=\(viewFrameInPDF) navFrameInPDF=\(navFrameInPDF) curDestY=\(curDest.point.y)")
            position["pageOffsetY"] = curDest.point.y + viewFrameInPDF.height + navFrameInPDF.height
            
            let bookProgress = 100.0 * Double(position["pageNumber"]! as! Int) / Double(pdfView!.document!.pageCount)
            
            var chapterProgress = 0.0
            let chapterName = titleInfoButton.currentTitle ?? "Unknown Title"
            if let firstIndex = tocList.lastIndex(where: { $0.0 == chapterName && $0.1 <= pageNum }) {
                let curIndex = firstIndex.advanced(by: 0)
                let nextIndex = firstIndex.advanced(by: 1)
                let chapterStartPageNum = tocList[curIndex].1
                let chapterEndPageNum = nextIndex < tocList.count ?
                    tocList[nextIndex].1 + 1 : pdfView!.document!.pageCount + 1
                if chapterEndPageNum > chapterStartPageNum {
                    chapterProgress = 100.0 * Double(pageNum - chapterStartPageNum) / Double(chapterEndPageNum - chapterStartPageNum)
                }
            }
            
            modelData?.updatedReadingPosition.lastPosition[0] = curDest.page!.pageRef?.pageNumber ?? 1
            modelData?.updatedReadingPosition.lastPosition[1] = Int(curDest.point.x.rounded())
            modelData?.updatedReadingPosition.lastPosition[2] = Int((curDest.point.y + viewFrameInPDF.height + navFrameInPDF.height).rounded())
            modelData?.updatedReadingPosition.lastReadPage = curDest.page!.pageRef?.pageNumber ?? 1
            modelData?.updatedReadingPosition.lastChapterProgress = chapterProgress
            modelData?.updatedReadingPosition.lastProgress = bookProgress
            modelData?.updatedReadingPosition.lastReadChapter = chapterName
            modelData?.updatedReadingPosition.readerName = "YabrPDFView"
            
//            modelData?.updateCurrentPosition(progress: progress, position: position)
        }
        
        let realm = try! Realm(configuration: Realm.Configuration(schemaVersion: 2))
        let pdfOptionsRealm = PDFOptionsRealm()
        pdfOptionsRealm.id = modelData!.readingBook!.id
        pdfOptionsRealm.libraryName = modelData!.readingBook!.library.name
        pdfOptionsRealm.selectedAutoScaler = pdfOptions.selectedAutoScaler.rawValue
        pdfOptionsRealm.readingDirection = pdfOptions.readingDirection.rawValue
        pdfOptionsRealm.hMarginAutoScaler = pdfOptions.hMarginAutoScaler
        pdfOptionsRealm.vMarginAutoScaler = pdfOptions.vMarginAutoScaler
        pdfOptionsRealm.hMarginDetectStrength = pdfOptions.hMarginDetectStrength
        pdfOptionsRealm.vMarginDetectStrength = pdfOptions.vMarginDetectStrength
        pdfOptionsRealm.lastScale = pdfOptions.lastScale
        pdfOptionsRealm.rememberInPagePosition = pdfOptions.rememberInPagePosition
        
        let pdfOptionsRealmResult = realm.objects(PDFOptionsRealm.self).filter(
            NSPredicate(format: "id = %@ AND libraryName = %@", NSNumber(value: pdfOptionsRealm.id), pdfOptionsRealm.libraryName)
        )
        try! realm.write {
            realm.delete(pdfOptionsRealmResult)
            realm.add(pdfOptionsRealm)
        }
    }
    
//    @objc func lookupStarDict() {
//        if let s = pdfView?.currentSelection?.string {
//            print(s)
//            starDictView.word = s
//            self.present(starDictView, animated: true, completion: nil)
//        }
//    }
    @objc func lookupMDict() {
        if let s = pdfView?.currentSelection?.string {
            print(s)
            mDictView.word = s
            self.present(mDictView, animated: true, completion: nil)
        }
    }
}

class PDFOptionsRealm: Object {
    @objc dynamic var id: Int32 = 0
    @objc dynamic var libraryName = ""
    @objc dynamic var selectedAutoScaler = PDFAutoScaler.Width.rawValue
    @objc dynamic var readingDirection = PDFReadDirection.LtR_TtB.rawValue
    @objc dynamic var hMarginAutoScaler = 5.0
    @objc dynamic var vMarginAutoScaler = 5.0
    @objc dynamic var hMarginDetectStrength = 2.0
    @objc dynamic var vMarginDetectStrength = 2.0
    @objc dynamic var lastScale = -1.0
    @objc dynamic var rememberInPagePosition = true
}
